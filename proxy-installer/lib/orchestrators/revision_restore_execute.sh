#!/usr/bin/env bash
set -o pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "${DIR}/../.." && pwd)"
source "${ROOT}/lib/transaction/transaction.sh"
source "${ROOT}/lib/config/state.sh"

revision_tx_apply_config() { state_tool --config "${REV_CONFIG}" restore --from "${REV_TARGET}"; }
revision_tx_rollback_config() { state_tool --config "${REV_CONFIG}" restore --from "${REV_CURRENT}"; }
revision_restore_execute() {
  # lock op config current-snapshot target-revision snapshot health commit export history
  [ "$#" -eq 10 ] || return 2
  REV_CONFIG="$3"; REV_CURRENT="$4"; REV_TARGET="$5"
  transaction_reset "$2" "$1"
  transaction_add_step config revision_tx_apply_config revision_tx_rollback_config || return 1
  transaction_run "$6" "$7" "$8" "${9}" "${10}"
}
