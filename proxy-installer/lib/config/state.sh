#!/usr/bin/env bash
# Config/state facade. It delegates all main-YAML access to config_tool.py.

set -o pipefail

STATE_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${STATE_MODULE_DIR}/../.." && pwd)"
CONFIG_TOOL="${CONFIG_TOOL:-${PROJECT_ROOT}/tools/config_tool.py}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
STATE_DATE_BIN="${STATE_DATE_BIN:-date}"
STATE_TRANSACTION_CONFIG_PATH=""
STATE_TRANSACTION_OPERATION_TYPE=""

state_tool() {
  "${PYTHON_BIN}" "${CONFIG_TOOL}" "$@"
}

state_initialize() {
  local config_path="$1"
  state_tool --config "${config_path}" init
}

state_read() {
  local config_path="$1"
  state_tool --config "${config_path}" read
}

state_deployment_plan() {
  local config_path="$1"
  state_tool --config "${config_path}" deployment-plan
}

state_deployment_env() {
  local config_path="$1"
  state_tool --config "${config_path}" deployment-env
}

state_deployment_domains() {
  local config_path="$1"
  state_tool --config "${config_path}" deployment-domains
}

state_certificate_renewal_env() {
  local config_path="$1"
  state_tool --config "${config_path}" certificate-renewal-env
}

state_commit_deployment() {
  local config_path="$1" operation_id="$2"
  state_tool --config "${config_path}" commit-deployment --operation-id "${operation_id}"
}

state_patch() {
  local config_path="$1"
  local patch_json="$2"
  state_tool --config "${config_path}" patch --patch "${patch_json}"
}

state_record_observed() {
  local config_path="$1"
  local observed_patch="$2"
  state_patch "${config_path}" "{\"observed\":${observed_patch}}"
}

state_commit_applied() {
  local config_path="$1"
  local applied_patch="$2"
  state_patch "${config_path}" "{\"applied\":${applied_patch}}"
}

state_record_operation() {
  # config-path operation-id operation-type status non-sensitive-summary [failed-stage repair-advice]
  [ "$#" -eq 5 ] || [ "$#" -eq 7 ] || return 2
  local command=(--config "$1" record-operation --operation-id "$2" --operation-type "$3" --status "$4" --summary "$5")
  if [ "$#" -eq 7 ]; then
    command+=(--failed-stage "$6" --repair-advice "$7")
  fi
  state_tool "${command[@]}"
}

state_configure_transaction_recording() {
  # Bind a config and controlled operation type before registering
  # state_record_transaction_result as a transaction result callback.
  [ "$#" -eq 2 ] && [ -n "$1" ] || return 2
  case "$2" in deploy|config-apply|update|uninstall|certificate|revision-restore) ;; *) return 2 ;; esac
  STATE_TRANSACTION_CONFIG_PATH="$1"
  STATE_TRANSACTION_OPERATION_TYPE="$2"
}

state_record_transaction_result() {
  # callback args: operation-id result failed-stage summary repair-advice
  [ "$#" -eq 5 ] && [ -n "${STATE_TRANSACTION_CONFIG_PATH}" ] && [ -n "${STATE_TRANSACTION_OPERATION_TYPE}" ] || return 2
  state_record_operation \
    "${STATE_TRANSACTION_CONFIG_PATH}" "$1" "${STATE_TRANSACTION_OPERATION_TYPE}" "$2" "$4" "$3" "$5" >/dev/null
}

state_create_transaction_snapshot() {
  local state_root="$1"
  local config_path="$2"
  local operation_id="$3"
  shift 3
  [[ "${operation_id}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || return 1
  local snapshot_dir="${state_root}/transactions/${operation_id}"
  local staging_dir="${state_root}/transactions/.${operation_id}.tmp.$$"
  local resources_dir="${staging_dir}/resources"
  [ ! -e "${snapshot_dir}" ] && [ ! -e "${staging_dir}" ] || return 1
  mkdir -p "${resources_dir}" || return 1
  chmod 700 "${staging_dir}" "${resources_dir}" || { rm -rf -- "${staging_dir}"; return 1; }
  cp "${config_path}" "${staging_dir}/config.yaml" || { rm -rf -- "${staging_dir}"; return 1; }
  chmod 600 "${staging_dir}/config.yaml" || { rm -rf -- "${staging_dir}"; return 1; }
  local resource index=0 stored_name resource_manifest="${staging_dir}/resource-manifest.txt"
  : > "${resource_manifest}" || { rm -rf -- "${staging_dir}"; return 1; }
  for resource in "$@"; do
    [ -f "${resource}" ] || { rm -rf -- "${staging_dir}"; return 1; }
    index=$((index + 1))
    printf -v stored_name '%04d-%s' "${index}" "$(basename "${resource}")"
    cp "${resource}" "${resources_dir}/${stored_name}" || { rm -rf -- "${staging_dir}"; return 1; }
    chmod 600 "${resources_dir}/${stored_name}" || { rm -rf -- "${staging_dir}"; return 1; }
    printf '%s|%s|%s\n' "${index}" "${resource}" "${stored_name}" >> "${resource_manifest}" || { rm -rf -- "${staging_dir}"; return 1; }
  done
  printf 'operation_id=%s\nresource_count=%s\n' "${operation_id}" "${index}" > "${staging_dir}/snapshot-manifest.txt" || { rm -rf -- "${staging_dir}"; return 1; }
  chmod 600 "${resource_manifest}" "${staging_dir}/snapshot-manifest.txt" || { rm -rf -- "${staging_dir}"; return 1; }
  mv "${staging_dir}" "${snapshot_dir}" || { rm -rf -- "${staging_dir}"; return 1; }
}

state_save_success_revision() {
  local state_root="$1"
  local config_path="$2"
  local revision_id="$3"
  local operation_type="$4"
  local operation_summary="$5"
  shift 5
  [[ "${revision_id}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || return 1
  case "${operation_type}" in deploy|config-apply|update|uninstall|certificate|revision-restore) ;; *) return 1 ;; esac
  [ -n "${operation_summary}" ] && [ "${#operation_summary}" -le 240 ] && [[ "${operation_summary}" != *$'\n'* ]] && [[ "${operation_summary}" != *$'\r'* ]] || return 1
  local revisions_dir="${state_root}/revisions"
  local revision_dir="${revisions_dir}/${revision_id}"
  local staging_dir="${revisions_dir}/.${revision_id}.tmp.$$"
  local resources_dir="${staging_dir}/resources"
  [ ! -e "${revision_dir}" ] || return 1
  [ ! -e "${staging_dir}" ] || return 1
  mkdir -p "${resources_dir}" || return 1
  chmod 700 "${staging_dir}" "${resources_dir}" || { rm -rf -- "${staging_dir}"; return 1; }
  cp "${config_path}" "${staging_dir}/config.yaml" || { rm -rf -- "${staging_dir}"; return 1; }
  chmod 600 "${staging_dir}/config.yaml" || { rm -rf -- "${staging_dir}"; return 1; }
  printf '%s\n' "${operation_summary}" > "${staging_dir}/operation-summary.txt" || { rm -rf -- "${staging_dir}"; return 1; }
  chmod 600 "${staging_dir}/operation-summary.txt" || { rm -rf -- "${staging_dir}"; return 1; }
  local completed_at resource index=0 stored_name
  completed_at="$("${STATE_DATE_BIN}" -u '+%Y-%m-%dT%H:%M:%SZ')" || { rm -rf -- "${staging_dir}"; return 1; }
  printf 'revision_id=%s\noperation_type=%s\ncompleted_at=%s\nsummary=%s\n' \
    "${revision_id}" "${operation_type}" "${completed_at}" "${operation_summary}" > "${staging_dir}/revision-manifest.txt" || { rm -rf -- "${staging_dir}"; return 1; }
  local resource_manifest="${staging_dir}/resource-manifest.txt"
  : > "${resource_manifest}" || { rm -rf -- "${staging_dir}"; return 1; }
  for resource in "$@"; do
    [ -f "${resource}" ] || { rm -rf -- "${staging_dir}"; return 1; }
    index=$((index + 1))
    printf -v stored_name '%04d-%s' "${index}" "$(basename "${resource}")"
    cp "${resource}" "${resources_dir}/${stored_name}" || { rm -rf -- "${staging_dir}"; return 1; }
    chmod 600 "${resources_dir}/${stored_name}" || { rm -rf -- "${staging_dir}"; return 1; }
    printf '%s|%s|%s\n' "${index}" "${resource}" "${stored_name}" >> "${resource_manifest}" || { rm -rf -- "${staging_dir}"; return 1; }
  done
  printf 'resource_count=%s\n' "${index}" >> "${staging_dir}/revision-manifest.txt" || { rm -rf -- "${staging_dir}"; return 1; }
  chmod 600 "${staging_dir}/revision-manifest.txt" "${resource_manifest}" || { rm -rf -- "${staging_dir}"; return 1; }
  mv "${staging_dir}" "${revision_dir}" || { rm -rf -- "${staging_dir}"; return 1; }
  local revisions=()
  while IFS= read -r revision; do revisions+=("${revision}"); done < <(find "${revisions_dir}" -mindepth 1 -maxdepth 1 -type d -print | sort)
  while [ "${#revisions[@]}" -gt 5 ]; do
    rm -rf "${revisions[0]}" || return 1
    revisions=("${revisions[@]:1}")
  done
}

state_list_success_revisions() {
  local state_root="$1"
  local revisions_dir="${state_root}/revisions"
  [ -d "${revisions_dir}" ] || return 0
  find "${revisions_dir}" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort
}
