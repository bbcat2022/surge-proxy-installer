#!/usr/bin/env bash
set -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "${DIR}/../.." && pwd)"
source "${ROOT}/lib/transaction/transaction.sh"
source "${ROOT}/lib/resources/files.sh"
source "${ROOT}/lib/resources/systemd.sh"

uninstall_tx_apply_runtime() { file_stage_remove "${UN_RUNTIME}" "${UN_STASH}" false; }
uninstall_tx_rollback_runtime() { file_restore_staged "${UN_STASH}/$(basename "${UN_RUNTIME}")" "${UN_RUNTIME}" false; }
uninstall_tx_apply_unit() { systemd_action "${UN_UNIT}" stop false && systemd_action "${UN_UNIT}" disable false && file_stage_remove "${UN_UNIT_FILE}" "${UN_STASH}" false && systemd_action "${UN_UNIT}" daemon-reload false; }
uninstall_tx_rollback_unit() { file_restore_staged "${UN_STASH}/$(basename "${UN_UNIT_FILE}")" "${UN_UNIT_FILE}" false && systemd_action "${UN_UNIT}" daemon-reload false && systemd_action "${UN_UNIT}" enable false && systemd_action "${UN_UNIT}" start false; }

uninstall_execute_materials() {
  # lock op runtime unit-file unit-name stash snapshot health commit export history
  [ "$#" -eq 10 ] || return 2
  UN_RUNTIME="$3"; UN_UNIT_FILE="$4"; UN_UNIT="$5"; UN_STASH="$6"
  transaction_reset "$2" "$1"
  transaction_add_step runtime uninstall_tx_apply_runtime uninstall_tx_rollback_runtime || return 1
  transaction_add_step unit uninstall_tx_apply_unit uninstall_tx_rollback_unit || return 1
  transaction_run "$7" "$8" "$9" "${10}" "${UN_HISTORY_CALLBACK:-uninstall_tx_history_noop}"
}
uninstall_tx_history_noop() { return 0; }
