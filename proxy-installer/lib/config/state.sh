#!/usr/bin/env bash
# Config/state facade. It delegates all main-YAML access to config_tool.py.

set -o pipefail

STATE_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${STATE_MODULE_DIR}/../.." && pwd)"
CONFIG_TOOL="${CONFIG_TOOL:-${PROJECT_ROOT}/tools/config_tool.py}"
PYTHON_BIN="${PYTHON_BIN:-python3}"

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
  # config-path operation-id operation-type status non-sensitive-summary
  [ "$#" -eq 5 ] || return 2
  state_tool --config "$1" record-operation --operation-id "$2" --operation-type "$3" --status "$4" --summary "$5"
}

state_create_transaction_snapshot() {
  local state_root="$1"
  local config_path="$2"
  local operation_id="$3"
  shift 3
  local snapshot_dir="${state_root}/transactions/${operation_id}"
  local resources_dir="${snapshot_dir}/resources"
  mkdir -p "${resources_dir}" || return 1
  chmod 700 "${snapshot_dir}" "${resources_dir}" || return 1
  cp "${config_path}" "${snapshot_dir}/config.yaml" || return 1
  chmod 600 "${snapshot_dir}/config.yaml" || return 1
  local resource
  for resource in "$@"; do
    [ -f "${resource}" ] || return 1
    cp "${resource}" "${resources_dir}/$(basename "${resource}")" || return 1
    chmod 600 "${resources_dir}/$(basename "${resource}")" || return 1
  done
}

state_save_success_revision() {
  local state_root="$1"
  local config_path="$2"
  local revision_id="$3"
  local operation_summary="$4"
  shift 4
  local revisions_dir="${state_root}/revisions"
  local revision_dir="${revisions_dir}/${revision_id}"
  local resources_dir="${revision_dir}/resources"
  [ ! -e "${revision_dir}" ] || return 1
  mkdir -p "${resources_dir}" || return 1
  chmod 700 "${revision_dir}" "${resources_dir}" || return 1
  cp "${config_path}" "${revision_dir}/config.yaml" || return 1
  chmod 600 "${revision_dir}/config.yaml" || return 1
  printf '%s\n' "${operation_summary}" > "${revision_dir}/operation-summary.txt" || return 1
  chmod 600 "${revision_dir}/operation-summary.txt" || return 1
  local resource
  for resource in "$@"; do
    [ -f "${resource}" ] || return 1
    cp "${resource}" "${resources_dir}/$(basename "${resource}")" || return 1
    chmod 600 "${resources_dir}/$(basename "${resource}")" || return 1
  done
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
