#!/usr/bin/env bash
# Apply multiple prepared runtime and systemd materials as one transaction.

set -o pipefail

DEPLOY_SERVICES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${DEPLOY_SERVICES_DIR}/../.." && pwd)"
source "${PROJECT_ROOT}/lib/transaction/transaction.sh"
source "${PROJECT_ROOT}/lib/resources/runtime.sh"
source "${PROJECT_ROOT}/lib/resources/systemd.sh"
source "${PROJECT_ROOT}/lib/resources/snapshot.sh"
source "${PROJECT_ROOT}/lib/resources/certificate.sh"
source "${PROJECT_ROOT}/lib/export/surge.sh"
source "${PROJECT_ROOT}/lib/orchestrators/deploy_firewall_descriptor.sh"

deploy_services_load_descriptor() {
  # protocol|runtime-candidate|runtime-target|runtime-backup|unit-dir|unit-name|unit-candidate|unit-backup
  local descriptor="$1" line protocol runtime_candidate runtime_target runtime_backup unit_dir unit_name unit_candidate unit_backup
  [ -f "${descriptor}" ] || return 1
  DEPLOY_SERVICE_PROTOCOLS=(); DEPLOY_SERVICE_RUNTIME_CANDIDATES=(); DEPLOY_SERVICE_RUNTIME_TARGETS=(); DEPLOY_SERVICE_RUNTIME_BACKUPS=()
  DEPLOY_SERVICE_UNIT_DIRS=(); DEPLOY_SERVICE_UNIT_NAMES=(); DEPLOY_SERVICE_UNIT_CANDIDATES=(); DEPLOY_SERVICE_UNIT_BACKUPS=()
  DEPLOY_SERVICE_STATE_BACKUPS=()
  while IFS='|' read -r protocol runtime_candidate runtime_target runtime_backup unit_dir unit_name unit_candidate unit_backup; do
    [ -n "${protocol}" ] || continue
    [ -n "${unit_backup:-}" ] || return 1
    [[ "${protocol}" =~ ^(snell|anytls|hysteria2|hysteria2-port-hop)$ ]] || return 1
    [ -f "${runtime_candidate}" ] && [ -f "${unit_candidate}" ] || return 1
    systemd_validate_unit_name "${unit_name}" || return 1
    DEPLOY_SERVICE_PROTOCOLS+=("${protocol}"); DEPLOY_SERVICE_RUNTIME_CANDIDATES+=("${runtime_candidate}"); DEPLOY_SERVICE_RUNTIME_TARGETS+=("${runtime_target}"); DEPLOY_SERVICE_RUNTIME_BACKUPS+=("${runtime_backup}")
    DEPLOY_SERVICE_UNIT_DIRS+=("${unit_dir}"); DEPLOY_SERVICE_UNIT_NAMES+=("${unit_name}"); DEPLOY_SERVICE_UNIT_CANDIDATES+=("${unit_candidate}"); DEPLOY_SERVICE_UNIT_BACKUPS+=("${unit_backup}")
    DEPLOY_SERVICE_STATE_BACKUPS+=("${unit_backup}.service-state")
  done < "${descriptor}"
  [ "${#DEPLOY_SERVICE_PROTOCOLS[@]}" -gt 0 ]
}

deploy_services_apply_runtime() {
  local index
  for index in "${!DEPLOY_SERVICE_PROTOCOLS[@]}"; do runtime_write "${DEPLOY_SERVICE_RUNTIME_CANDIDATES[${index}]}" "${DEPLOY_SERVICE_RUNTIME_TARGETS[${index}]}" false || return 1; done
}

deploy_services_restore_runtime() {
  local index failed=0
  for ((index=${#DEPLOY_SERVICE_PROTOCOLS[@]} - 1; index >= 0; index--)); do
    snapshot_restore_file "${DEPLOY_SERVICE_RUNTIME_TARGETS[${index}]}" "${DEPLOY_SERVICE_RUNTIME_BACKUPS[${index}]}" false || failed=1
  done
  [ "${failed}" -eq 0 ]
}

deploy_services_capture_backups() {
  local index
  for index in "${!DEPLOY_SERVICE_PROTOCOLS[@]}"; do
    snapshot_capture_file "${DEPLOY_SERVICE_RUNTIME_TARGETS[${index}]}" "${DEPLOY_SERVICE_RUNTIME_BACKUPS[${index}]}" false || return 1
    snapshot_capture_file "${DEPLOY_SERVICE_UNIT_DIRS[${index}]}/${DEPLOY_SERVICE_UNIT_NAMES[${index}]}" "${DEPLOY_SERVICE_UNIT_BACKUPS[${index}]}" false || return 1
    systemd_capture_state "${DEPLOY_SERVICE_UNIT_NAMES[${index}]}" "${DEPLOY_SERVICE_STATE_BACKUPS[${index}]}" false || return 1
  done
  if [ "${DEPLOY_SERVICE_CERTIFICATE_INPUTS}" -eq 4 ]; then
    snapshot_capture_file "${DEPLOY_CERTIFICATE_ACTIVE_DIR}/cert.pem" "${DEPLOY_CERTIFICATE_SNAPSHOT_DIR}/cert.pem" false || return 1
    snapshot_capture_file "${DEPLOY_CERTIFICATE_ACTIVE_DIR}/key.pem" "${DEPLOY_CERTIFICATE_SNAPSHOT_DIR}/key.pem" false || return 1
  fi
  "${DEPLOY_SERVICE_EXTERNAL_SNAPSHOT}"
}

deploy_services_apply_units() {
  local index
  if [ "${DEPLOY_SERVICE_CERTIFICATE_INPUTS}" -eq 4 ]; then
    certificate_install_candidate "${DEPLOY_CERTIFICATE_CANDIDATE_CERT}" "${DEPLOY_CERTIFICATE_CANDIDATE_KEY}" "${DEPLOY_CERTIFICATE_ACTIVE_DIR}" false || return 1
  fi
  for index in "${!DEPLOY_SERVICE_PROTOCOLS[@]}"; do systemd_write_unit "${DEPLOY_SERVICE_UNIT_DIRS[${index}]}" "${DEPLOY_SERVICE_UNIT_NAMES[${index}]}" "${DEPLOY_SERVICE_UNIT_CANDIDATES[${index}]}" false || return 1; done
  systemd_action ignored.service daemon-reload false || return 1
  for index in "${!DEPLOY_SERVICE_PROTOCOLS[@]}"; do
    systemd_action "${DEPLOY_SERVICE_UNIT_NAMES[${index}]}" enable false || return 1
    systemd_action "${DEPLOY_SERVICE_UNIT_NAMES[${index}]}" restart false || return 1
  done
}

deploy_services_restore_units() {
  local index failed=0 previous_enabled
  if [ "${DEPLOY_SERVICE_CERTIFICATE_INPUTS}" -eq 4 ]; then
    snapshot_restore_file "${DEPLOY_CERTIFICATE_ACTIVE_DIR}/key.pem" "${DEPLOY_CERTIFICATE_SNAPSHOT_DIR}/key.pem" false || failed=1
    snapshot_restore_file "${DEPLOY_CERTIFICATE_ACTIVE_DIR}/cert.pem" "${DEPLOY_CERTIFICATE_SNAPSHOT_DIR}/cert.pem" false || failed=1
  fi
  for ((index=${#DEPLOY_SERVICE_PROTOCOLS[@]} - 1; index >= 0; index--)); do
    previous_enabled="$(systemd_read_captured_state "${DEPLOY_SERVICE_STATE_BACKUPS[${index}]}" enabled)" || { failed=1; continue; }
    if [ "${previous_enabled}" = not-found ]; then
      systemd_action "${DEPLOY_SERVICE_UNIT_NAMES[${index}]}" stop false || failed=1
      systemd_action "${DEPLOY_SERVICE_UNIT_NAMES[${index}]}" disable false || failed=1
    fi
  done
  for ((index=${#DEPLOY_SERVICE_PROTOCOLS[@]} - 1; index >= 0; index--)); do
    snapshot_restore_file "${DEPLOY_SERVICE_UNIT_DIRS[${index}]}/${DEPLOY_SERVICE_UNIT_NAMES[${index}]}" "${DEPLOY_SERVICE_UNIT_BACKUPS[${index}]}" false || failed=1
  done
  systemd_action ignored.service daemon-reload false || failed=1
  for ((index=${#DEPLOY_SERVICE_PROTOCOLS[@]} - 1; index >= 0; index--)); do
    previous_enabled="$(systemd_read_captured_state "${DEPLOY_SERVICE_STATE_BACKUPS[${index}]}" enabled)" || { failed=1; continue; }
    if [ "${previous_enabled}" != not-found ]; then
      systemd_restore_state "${DEPLOY_SERVICE_UNIT_NAMES[${index}]}" "${DEPLOY_SERVICE_STATE_BACKUPS[${index}]}" false || failed=1
    fi
  done
  [ "${failed}" -eq 0 ]
}

deploy_services_verify_restored() {
  local index failed=0
  for index in "${!DEPLOY_SERVICE_PROTOCOLS[@]}"; do
    snapshot_verify_file "${DEPLOY_SERVICE_RUNTIME_TARGETS[${index}]}" "${DEPLOY_SERVICE_RUNTIME_BACKUPS[${index}]}" || failed=1
    snapshot_verify_file "${DEPLOY_SERVICE_UNIT_DIRS[${index}]}/${DEPLOY_SERVICE_UNIT_NAMES[${index}]}" "${DEPLOY_SERVICE_UNIT_BACKUPS[${index}]}" || failed=1
    systemd_verify_captured_state "${DEPLOY_SERVICE_UNIT_NAMES[${index}]}" "${DEPLOY_SERVICE_STATE_BACKUPS[${index}]}" || failed=1
  done
  if [ "${DEPLOY_SERVICE_CERTIFICATE_INPUTS}" -eq 4 ]; then
    snapshot_verify_file "${DEPLOY_CERTIFICATE_ACTIVE_DIR}/cert.pem" "${DEPLOY_CERTIFICATE_SNAPSHOT_DIR}/cert.pem" || failed=1
    snapshot_verify_file "${DEPLOY_CERTIFICATE_ACTIVE_DIR}/key.pem" "${DEPLOY_CERTIFICATE_SNAPSHOT_DIR}/key.pem" || failed=1
  fi
  [ "${failed}" -eq 0 ]
}

deploy_services_export() { surge_export_fragment "${DEPLOY_SERVICE_EXPORT_TARGET}" false "${DEPLOY_SERVICE_ENTRIES[@]}"; }
deploy_services_apply_firewall() { firewall_apply_with_context "${DEPLOY_FIREWALL_CONTEXT}" "${DEPLOY_FIREWALL_MODE}" "${DEPLOY_FIREWALL_EFFECTIVE_TOOL}" false "${DEPLOY_FIREWALL_RULES[@]}"; }
deploy_services_restore_firewall() { firewall_rollback_from_context "${DEPLOY_FIREWALL_CONTEXT}"; }

deploy_services_validate_firewall_inputs() {
  DEPLOY_SERVICE_FIREWALL_INPUTS=0
  [ -z "${DEPLOY_FIREWALL_DESCRIPTOR:-}" ] || DEPLOY_SERVICE_FIREWALL_INPUTS=$((DEPLOY_SERVICE_FIREWALL_INPUTS + 1))
  [ -z "${DEPLOY_FIREWALL_CONTEXT:-}" ] || DEPLOY_SERVICE_FIREWALL_INPUTS=$((DEPLOY_SERVICE_FIREWALL_INPUTS + 1))
  [ -z "${DEPLOY_FIREWALL_MODE:-}" ] || DEPLOY_SERVICE_FIREWALL_INPUTS=$((DEPLOY_SERVICE_FIREWALL_INPUTS + 1))
  [ -z "${DEPLOY_FIREWALL_TOOL:-}" ] || DEPLOY_SERVICE_FIREWALL_INPUTS=$((DEPLOY_SERVICE_FIREWALL_INPUTS + 1))
  [ "${DEPLOY_SERVICE_FIREWALL_INPUTS}" -eq 0 ] || [ "${DEPLOY_SERVICE_FIREWALL_INPUTS}" -eq 4 ] || return 2
  if [ "${DEPLOY_SERVICE_FIREWALL_INPUTS}" -eq 4 ]; then
    case "${DEPLOY_FIREWALL_MODE}" in manual|auto) ;; *) return 2 ;; esac
    case "${DEPLOY_FIREWALL_TOOL}" in manual|ufw|nftables) ;; *) return 2 ;; esac
    [[ "${DEPLOY_FIREWALL_CONTEXT}" = /* ]] || return 2
    deploy_firewall_descriptor_load "${DEPLOY_FIREWALL_DESCRIPTOR}" || return 1
    firewall_resolve_tool "${DEPLOY_FIREWALL_MODE}" "${DEPLOY_FIREWALL_TOOL}" >/dev/null || return 1
    DEPLOY_FIREWALL_EFFECTIVE_TOOL="${FIREWALL_EFFECTIVE_TOOL}"
  fi
}

deploy_services_validate_certificate_inputs() {
  local protocol tls_service=false
  DEPLOY_SERVICE_CERTIFICATE_INPUTS=0
  [ -z "${DEPLOY_CERTIFICATE_CANDIDATE_CERT:-}" ] || DEPLOY_SERVICE_CERTIFICATE_INPUTS=$((DEPLOY_SERVICE_CERTIFICATE_INPUTS + 1))
  [ -z "${DEPLOY_CERTIFICATE_CANDIDATE_KEY:-}" ] || DEPLOY_SERVICE_CERTIFICATE_INPUTS=$((DEPLOY_SERVICE_CERTIFICATE_INPUTS + 1))
  [ -z "${DEPLOY_CERTIFICATE_ACTIVE_DIR:-}" ] || DEPLOY_SERVICE_CERTIFICATE_INPUTS=$((DEPLOY_SERVICE_CERTIFICATE_INPUTS + 1))
  [ -z "${DEPLOY_CERTIFICATE_SNAPSHOT_DIR:-}" ] || DEPLOY_SERVICE_CERTIFICATE_INPUTS=$((DEPLOY_SERVICE_CERTIFICATE_INPUTS + 1))
  [ "${DEPLOY_SERVICE_CERTIFICATE_INPUTS}" -eq 0 ] || [ "${DEPLOY_SERVICE_CERTIFICATE_INPUTS}" -eq 4 ] || return 2
  [ "${DEPLOY_SERVICE_CERTIFICATE_INPUTS}" -eq 4 ] || return 0
  for protocol in "${DEPLOY_SERVICE_PROTOCOLS[@]}"; do
    case "${protocol}" in anytls|hysteria2) tls_service=true ;; esac
  done
  [ "${tls_service}" = true ] || return 2
  [[ "${DEPLOY_CERTIFICATE_ACTIVE_DIR}" = /* ]] && [ "${DEPLOY_CERTIFICATE_ACTIVE_DIR}" != / ] || return 2
  [[ "${DEPLOY_CERTIFICATE_SNAPSHOT_DIR}" = /* ]] && [ "${DEPLOY_CERTIFICATE_SNAPSHOT_DIR}" != / ] || return 2
  [ ! -L "${DEPLOY_CERTIFICATE_SNAPSHOT_DIR}" ] || return 2
  [ ! -e "${DEPLOY_CERTIFICATE_SNAPSHOT_DIR}" ] || [ -d "${DEPLOY_CERTIFICATE_SNAPSHOT_DIR}" ] || return 2
  case "${DEPLOY_CERTIFICATE_SNAPSHOT_DIR}/" in "${DEPLOY_CERTIFICATE_ACTIVE_DIR}/"*) return 2 ;; esac
  case "${DEPLOY_CERTIFICATE_ACTIVE_DIR}/" in "${DEPLOY_CERTIFICATE_SNAPSHOT_DIR}/"*) return 2 ;; esac
  certificate_pair_state "${DEPLOY_CERTIFICATE_ACTIVE_DIR}" >/dev/null || return 1
  certificate_validate_candidate "${DEPLOY_CERTIFICATE_CANDIDATE_CERT}" "${DEPLOY_CERTIFICATE_CANDIDATE_KEY}" || return 1
}

deploy_services_execute() {
  # lock op descriptor export-target entry-files... -- snapshot health commit history
  [ "$#" -ge 9 ] || return 2
  local lock="$1" op="$2" descriptor="$3" export_target="$4" separator=0 item snapshot='' health='' commit='' history='' entries=()
  shift 4
  for item in "$@"; do
    if [ "${item}" = -- ]; then separator=1; continue; fi
    if [ "${separator}" -eq 0 ]; then entries+=("${item}"); else
      if [ -z "${snapshot}" ]; then snapshot="${item}"; elif [ -z "${health}" ]; then health="${item}"; elif [ -z "${commit}" ]; then commit="${item}"; elif [ -z "${history}" ]; then history="${item}"; else return 2; fi
    fi
  done
  [ "${separator}" -eq 1 ] && [ "${#entries[@]}" -gt 0 ] && [ -n "${snapshot}" ] && [ -n "${health}" ] && [ -n "${commit}" ] && [ -n "${history}" ] || return 2
  deploy_services_load_descriptor "${descriptor}" || return 1
  deploy_services_validate_firewall_inputs || return $?
  deploy_services_validate_certificate_inputs || return $?
  DEPLOY_SERVICE_EXPORT_TARGET="${export_target}"; DEPLOY_SERVICE_ENTRIES=("${entries[@]}")
  DEPLOY_SERVICE_EXTERNAL_SNAPSHOT="${snapshot}"
  transaction_reset "${op}" "${lock}"
  transaction_set_restore_verify_callback deploy_services_verify_restored || return 1
  transaction_add_step runtimes deploy_services_apply_runtime deploy_services_restore_runtime || return 1
  transaction_add_step units deploy_services_apply_units deploy_services_restore_units || return 1
  if [ "${DEPLOY_SERVICE_FIREWALL_INPUTS}" -eq 4 ]; then
    transaction_add_step firewall deploy_services_apply_firewall deploy_services_restore_firewall || return 1
  fi
  transaction_run deploy_services_capture_backups "${health}" "${commit}" deploy_services_export "${history}"
}
