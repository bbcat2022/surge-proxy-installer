#!/usr/bin/env bash
# Executes an approved field-level configuration change as one transaction.

set -o pipefail

CONFIG_EXEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${CONFIG_EXEC_DIR}/../.." && pwd)"
source "${PROJECT_ROOT}/lib/transaction/transaction.sh"
source "${PROJECT_ROOT}/lib/resources/runtime.sh"
source "${PROJECT_ROOT}/lib/resources/systemd.sh"
source "${PROJECT_ROOT}/lib/export/surge.sh"

config_tx_apply_runtime() { runtime_write "${CONFIG_RUNTIME_CANDIDATE}" "${CONFIG_RUNTIME_TARGET}" false; }
config_tx_rollback_runtime() { runtime_restore "${CONFIG_RUNTIME_BACKUP}" "${CONFIG_RUNTIME_TARGET}" false; }
config_tx_apply_unit() { systemd_write_unit "${CONFIG_UNIT_DIR}" "${CONFIG_UNIT_NAME}" "${CONFIG_UNIT_CANDIDATE}" false && systemd_action "${CONFIG_UNIT_NAME}" daemon-reload false && systemd_action "${CONFIG_UNIT_NAME}" restart false; }
config_tx_rollback_unit() { systemd_restore_unit "${CONFIG_UNIT_DIR}" "${CONFIG_UNIT_NAME}" "${CONFIG_UNIT_BACKUP}" false && systemd_action "${CONFIG_UNIT_NAME}" daemon-reload false && systemd_action "${CONFIG_UNIT_NAME}" restart false; }
config_tx_export() { surge_export_fragment "${CONFIG_EXPORT_TARGET}" false "${CONFIG_ENTRY_FILE}"; }

config_apply_execute() {
  # lock op runtime_changed runtime candidate/target/backup unit dir/name/candidate/backup export/entry snapshot health commit history
  [ "$#" -eq 17 ] || return 2
  local lock="$1" op="$2" runtime_changed="$3" snapshot="${15}" health="${16}" commit="${17}" history="${CONFIG_HISTORY_CALLBACK:-config_tx_history_noop}"
  CONFIG_RUNTIME_CANDIDATE="$4"; CONFIG_RUNTIME_TARGET="$5"; CONFIG_RUNTIME_BACKUP="$6"
  CONFIG_UNIT_DIR="$7"; CONFIG_UNIT_NAME="$8"; CONFIG_UNIT_CANDIDATE="$9"; CONFIG_UNIT_BACKUP="${10}"
  CONFIG_EXPORT_TARGET="${11}"; CONFIG_ENTRY_FILE="${12}"
  [[ "${runtime_changed}" =~ ^(true|false)$ ]] || return 2
  transaction_reset "${op}" "${lock}"
  if [ "${runtime_changed}" = true ]; then
    transaction_add_step runtime config_tx_apply_runtime config_tx_rollback_runtime || return 1
    transaction_add_step unit config_tx_apply_unit config_tx_rollback_unit || return 1
    if [ -n "${CONFIG_FIREWALL_APPLY:-}" ] || [ -n "${CONFIG_FIREWALL_ROLLBACK:-}" ]; then
      [ -n "${CONFIG_FIREWALL_APPLY:-}" ] && [ -n "${CONFIG_FIREWALL_ROLLBACK:-}" ] || return 2
      transaction_add_step firewall "${CONFIG_FIREWALL_APPLY}" "${CONFIG_FIREWALL_ROLLBACK}" || return 1
    fi
  else
    # Client-only changes still run through the transaction gate, but alter no server material.
    transaction_add_step client-only config_tx_noop config_tx_noop || return 1
  fi
  transaction_run "${snapshot}" "${health}" "${commit}" config_tx_export "${history}"
}

config_tx_noop() { return 0; }
config_tx_history_noop() { return 0; }
