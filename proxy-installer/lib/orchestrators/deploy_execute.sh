#!/usr/bin/env bash
# Transaction wiring for already-approved deployment materials in isolated or real paths.

set -o pipefail

DEPLOY_EXEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${DEPLOY_EXEC_DIR}/../.." && pwd)"
source "${PROJECT_ROOT}/lib/transaction/transaction.sh"
source "${PROJECT_ROOT}/lib/resources/runtime.sh"
source "${PROJECT_ROOT}/lib/resources/systemd.sh"
source "${PROJECT_ROOT}/lib/export/surge.sh"

deploy_tx_apply_runtime() { runtime_write "${DEPLOY_RUNTIME_CANDIDATE}" "${DEPLOY_RUNTIME_TARGET}" false; }
deploy_tx_rollback_runtime() { runtime_restore "${DEPLOY_RUNTIME_BACKUP}" "${DEPLOY_RUNTIME_TARGET}" false; }
deploy_tx_apply_unit() { systemd_write_unit "${DEPLOY_UNIT_DIR}" "${DEPLOY_UNIT_NAME}" "${DEPLOY_UNIT_CANDIDATE}" false && systemd_action "${DEPLOY_UNIT_NAME}" daemon-reload false && systemd_action "${DEPLOY_UNIT_NAME}" restart false; }
deploy_tx_rollback_unit() { systemd_restore_unit "${DEPLOY_UNIT_DIR}" "${DEPLOY_UNIT_NAME}" "${DEPLOY_UNIT_BACKUP}" false && systemd_action "${DEPLOY_UNIT_NAME}" daemon-reload false && systemd_action "${DEPLOY_UNIT_NAME}" restart false; }
deploy_tx_export() { surge_export_fragment "${DEPLOY_EXPORT_TARGET}" false "${DEPLOY_ENTRY_FILE}"; }

deploy_execute_materials() {
  # lock, op, runtime candidate/target/backup, unit dir/name/candidate/backup, export target/entry, snapshot/health/commit/history callbacks
  [ "$#" -eq 15 ] || return 2
  local lock="$1" op="$2" snapshot="${13}" health="${14}" commit="${15}" history="${DEPLOY_HISTORY_CALLBACK:-deploy_tx_history_noop}"
  DEPLOY_RUNTIME_CANDIDATE="$3"; DEPLOY_RUNTIME_TARGET="$4"; DEPLOY_RUNTIME_BACKUP="$5"
  DEPLOY_UNIT_DIR="$6"; DEPLOY_UNIT_NAME="$7"; DEPLOY_UNIT_CANDIDATE="$8"; DEPLOY_UNIT_BACKUP="$9"
  DEPLOY_EXPORT_TARGET="${10}"; DEPLOY_ENTRY_FILE="${11}"
  transaction_reset "${op}" "${lock}"
  transaction_add_step runtime deploy_tx_apply_runtime deploy_tx_rollback_runtime || return 1
  transaction_add_step unit deploy_tx_apply_unit deploy_tx_rollback_unit || return 1
  if [ -n "${DEPLOY_FIREWALL_APPLY:-}" ] || [ -n "${DEPLOY_FIREWALL_ROLLBACK:-}" ]; then
    [ -n "${DEPLOY_FIREWALL_APPLY:-}" ] && [ -n "${DEPLOY_FIREWALL_ROLLBACK:-}" ] || return 2
    transaction_add_step firewall "${DEPLOY_FIREWALL_APPLY}" "${DEPLOY_FIREWALL_ROLLBACK}" || return 1
  fi
  transaction_run "${snapshot}" "${health}" "${commit}" deploy_tx_export "${history}"
}
deploy_tx_history_noop() { return 0; }
