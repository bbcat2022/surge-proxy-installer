#!/usr/bin/env bash
# Atomically install prepared protocol binaries with snapshot-backed rollback.

set -o pipefail

DEPLOY_BIN_EXEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${DEPLOY_BIN_EXEC_DIR}/../.." && pwd)"
source "${PROJECT_ROOT}/lib/transaction/transaction.sh"
source "${PROJECT_ROOT}/lib/resources/snapshot.sh"
source "${PROJECT_ROOT}/lib/orchestrators/deploy_binaries.sh"

deploy_binaries_load_descriptor() {
  # protocol|candidate-work-dir|active-path|backup-path
  local descriptor="$1" protocol work active backup
  [ -f "${descriptor}" ] || return 1
  DEPLOY_BINARY_PROTOCOLS=(); DEPLOY_BINARY_WORK_DIRS=(); DEPLOY_BINARY_ACTIVE_PATHS=(); DEPLOY_BINARY_BACKUPS=()
  while IFS='|' read -r protocol work active backup; do
    [ -n "${protocol}" ] || continue
    [[ "${protocol}" =~ ^(snell|anytls|hysteria2)$ ]] || return 1
    [ -x "${work}/candidate" ] && [[ "${active}" = /* ]] && [[ "${backup}" = /* ]] || return 1
    DEPLOY_BINARY_PROTOCOLS+=("${protocol}"); DEPLOY_BINARY_WORK_DIRS+=("${work}"); DEPLOY_BINARY_ACTIVE_PATHS+=("${active}"); DEPLOY_BINARY_BACKUPS+=("${backup}")
  done < "${descriptor}"
  [ "${#DEPLOY_BINARY_PROTOCOLS[@]}" -gt 0 ]
}

deploy_binaries_capture() {
  local index
  for index in "${!DEPLOY_BINARY_PROTOCOLS[@]}"; do snapshot_capture_file "${DEPLOY_BINARY_ACTIVE_PATHS[${index}]}" "${DEPLOY_BINARY_BACKUPS[${index}]}" false || return 1; done
  "${DEPLOY_BINARY_EXTERNAL_SNAPSHOT}"
}

deploy_binaries_apply() {
  local index restored
  DEPLOY_BINARY_APPLIED=()
  for index in "${!DEPLOY_BINARY_PROTOCOLS[@]}"; do
    if ! deploy_binary_install_prepared "${DEPLOY_BINARY_PROTOCOLS[${index}]}" "${DEPLOY_BINARY_WORK_DIRS[${index}]}" "${DEPLOY_BINARY_ACTIVE_PATHS[${index}]}" false; then
      for ((restored=${#DEPLOY_BINARY_APPLIED[@]} - 1; restored >= 0; restored--)); do
        index="${DEPLOY_BINARY_APPLIED[${restored}]}"
        snapshot_restore_file "${DEPLOY_BINARY_ACTIVE_PATHS[${index}]}" "${DEPLOY_BINARY_BACKUPS[${index}]}" false || return 1
      done
      return 1
    fi
    DEPLOY_BINARY_APPLIED+=("${index}")
  done
}

deploy_binaries_restore() {
  local index
  for ((index=${#DEPLOY_BINARY_PROTOCOLS[@]} - 1; index >= 0; index--)); do snapshot_restore_file "${DEPLOY_BINARY_ACTIVE_PATHS[${index}]}" "${DEPLOY_BINARY_BACKUPS[${index}]}" false || return 1; done
}

deploy_binaries_noop() { return 0; }

deploy_binaries_execute() {
  # lock op descriptor snapshot health commit history
  [ "$#" -eq 7 ] || return 2
  deploy_binaries_load_descriptor "$3" || return 1
  DEPLOY_BINARY_EXTERNAL_SNAPSHOT="$4"
  transaction_reset "$2" "$1"
  transaction_add_step binaries deploy_binaries_apply deploy_binaries_restore || return 1
  transaction_run deploy_binaries_capture "$5" "$6" deploy_binaries_noop "$7"
}
