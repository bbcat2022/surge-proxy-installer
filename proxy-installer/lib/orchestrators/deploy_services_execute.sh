#!/usr/bin/env bash
# Apply multiple prepared runtime and systemd materials as one transaction.

set -o pipefail

DEPLOY_SERVICES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${DEPLOY_SERVICES_DIR}/../.." && pwd)"
source "${PROJECT_ROOT}/lib/transaction/transaction.sh"
source "${PROJECT_ROOT}/lib/resources/runtime.sh"
source "${PROJECT_ROOT}/lib/resources/systemd.sh"
source "${PROJECT_ROOT}/lib/resources/snapshot.sh"
source "${PROJECT_ROOT}/lib/export/surge.sh"

deploy_services_load_descriptor() {
  # protocol|runtime-candidate|runtime-target|runtime-backup|unit-dir|unit-name|unit-candidate|unit-backup
  local descriptor="$1" line protocol runtime_candidate runtime_target runtime_backup unit_dir unit_name unit_candidate unit_backup
  [ -f "${descriptor}" ] || return 1
  DEPLOY_SERVICE_PROTOCOLS=(); DEPLOY_SERVICE_RUNTIME_CANDIDATES=(); DEPLOY_SERVICE_RUNTIME_TARGETS=(); DEPLOY_SERVICE_RUNTIME_BACKUPS=()
  DEPLOY_SERVICE_UNIT_DIRS=(); DEPLOY_SERVICE_UNIT_NAMES=(); DEPLOY_SERVICE_UNIT_CANDIDATES=(); DEPLOY_SERVICE_UNIT_BACKUPS=()
  while IFS='|' read -r protocol runtime_candidate runtime_target runtime_backup unit_dir unit_name unit_candidate unit_backup; do
    [ -n "${protocol}" ] || continue
    [ -n "${unit_backup:-}" ] || return 1
    [[ "${protocol}" =~ ^(snell|anytls|hysteria2)$ ]] || return 1
    [ -f "${runtime_candidate}" ] && [ -f "${unit_candidate}" ] || return 1
    systemd_validate_unit_name "${unit_name}" || return 1
    DEPLOY_SERVICE_PROTOCOLS+=("${protocol}"); DEPLOY_SERVICE_RUNTIME_CANDIDATES+=("${runtime_candidate}"); DEPLOY_SERVICE_RUNTIME_TARGETS+=("${runtime_target}"); DEPLOY_SERVICE_RUNTIME_BACKUPS+=("${runtime_backup}")
    DEPLOY_SERVICE_UNIT_DIRS+=("${unit_dir}"); DEPLOY_SERVICE_UNIT_NAMES+=("${unit_name}"); DEPLOY_SERVICE_UNIT_CANDIDATES+=("${unit_candidate}"); DEPLOY_SERVICE_UNIT_BACKUPS+=("${unit_backup}")
  done < "${descriptor}"
  [ "${#DEPLOY_SERVICE_PROTOCOLS[@]}" -gt 0 ]
}

deploy_services_apply_runtime() {
  local index
  for index in "${!DEPLOY_SERVICE_PROTOCOLS[@]}"; do runtime_write "${DEPLOY_SERVICE_RUNTIME_CANDIDATES[${index}]}" "${DEPLOY_SERVICE_RUNTIME_TARGETS[${index}]}" false || return 1; done
}

deploy_services_restore_runtime() {
  local index
  for ((index=${#DEPLOY_SERVICE_PROTOCOLS[@]} - 1; index >= 0; index--)); do snapshot_restore_file "${DEPLOY_SERVICE_RUNTIME_TARGETS[${index}]}" "${DEPLOY_SERVICE_RUNTIME_BACKUPS[${index}]}" false || return 1; done
}

deploy_services_capture_backups() {
  local index
  for index in "${!DEPLOY_SERVICE_PROTOCOLS[@]}"; do
    snapshot_capture_file "${DEPLOY_SERVICE_RUNTIME_TARGETS[${index}]}" "${DEPLOY_SERVICE_RUNTIME_BACKUPS[${index}]}" false || return 1
    snapshot_capture_file "${DEPLOY_SERVICE_UNIT_DIRS[${index}]}/${DEPLOY_SERVICE_UNIT_NAMES[${index}]}" "${DEPLOY_SERVICE_UNIT_BACKUPS[${index}]}" false || return 1
  done
  "${DEPLOY_SERVICE_EXTERNAL_SNAPSHOT}"
}

deploy_services_apply_units() {
  local index
  for index in "${!DEPLOY_SERVICE_PROTOCOLS[@]}"; do systemd_write_unit "${DEPLOY_SERVICE_UNIT_DIRS[${index}]}" "${DEPLOY_SERVICE_UNIT_NAMES[${index}]}" "${DEPLOY_SERVICE_UNIT_CANDIDATES[${index}]}" false || return 1; done
  systemd_action ignored.service daemon-reload false || return 1
  for index in "${!DEPLOY_SERVICE_PROTOCOLS[@]}"; do
    systemd_action "${DEPLOY_SERVICE_UNIT_NAMES[${index}]}" enable false || return 1
    systemd_action "${DEPLOY_SERVICE_UNIT_NAMES[${index}]}" restart false || return 1
  done
}

deploy_services_restore_units() {
  local index
  for ((index=${#DEPLOY_SERVICE_PROTOCOLS[@]} - 1; index >= 0; index--)); do snapshot_restore_file "${DEPLOY_SERVICE_UNIT_DIRS[${index}]}/${DEPLOY_SERVICE_UNIT_NAMES[${index}]}" "${DEPLOY_SERVICE_UNIT_BACKUPS[${index}]}" false || return 1; done
  systemd_action ignored.service daemon-reload false || return 1
  for ((index=${#DEPLOY_SERVICE_PROTOCOLS[@]} - 1; index >= 0; index--)); do
    if snapshot_was_present "${DEPLOY_SERVICE_UNIT_BACKUPS[${index}]}"; then systemd_action "${DEPLOY_SERVICE_UNIT_NAMES[${index}]}" restart false || return 1
    else systemd_action "${DEPLOY_SERVICE_UNIT_NAMES[${index}]}" stop false || return 1; systemd_action "${DEPLOY_SERVICE_UNIT_NAMES[${index}]}" disable false || return 1; fi
  done
}

deploy_services_export() { surge_export_fragment "${DEPLOY_SERVICE_EXPORT_TARGET}" false "${DEPLOY_SERVICE_ENTRIES[@]}"; }

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
  DEPLOY_SERVICE_EXPORT_TARGET="${export_target}"; DEPLOY_SERVICE_ENTRIES=("${entries[@]}")
  DEPLOY_SERVICE_EXTERNAL_SNAPSHOT="${snapshot}"
  transaction_reset "${op}" "${lock}"
  transaction_add_step runtimes deploy_services_apply_runtime deploy_services_restore_runtime || return 1
  transaction_add_step units deploy_services_apply_units deploy_services_restore_units || return 1
  transaction_run deploy_services_capture_backups "${health}" "${commit}" deploy_services_export "${history}"
}
