#!/usr/bin/env bash
# Transaction wiring for a verified binary update.

set -o pipefail

UPDATE_EXEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${UPDATE_EXEC_DIR}/../.." && pwd)"
source "${PROJECT_ROOT}/lib/transaction/transaction.sh"
source "${PROJECT_ROOT}/lib/resources/binary.sh"

update_tx_apply_binary() { binary_install_candidate "${UPDATE_CANDIDATE}" "${UPDATE_ACTIVE}" "${UPDATE_VERSION_ARG}" false; }
update_tx_rollback_binary() { binary_restore "${UPDATE_BACKUP}" "${UPDATE_ACTIVE}" false; }

update_execute_binary() {
  # lock op candidate active backup version-arg snapshot health commit export history
  [ "$#" -eq 10 ] || return 2
  UPDATE_CANDIDATE="$3"; UPDATE_ACTIVE="$4"; UPDATE_BACKUP="$5"; UPDATE_VERSION_ARG="$6"
  transaction_reset "$2" "$1"
  transaction_add_step binary update_tx_apply_binary update_tx_rollback_binary || return 1
  transaction_run "$7" "$8" "$9" "${10}" "${UPDATE_HISTORY_CALLBACK:-update_tx_history_noop}"
}
update_tx_history_noop() { return 0; }
