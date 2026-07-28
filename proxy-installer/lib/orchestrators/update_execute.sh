#!/usr/bin/env bash
# Transaction wiring for a verified binary update.

set -o pipefail

UPDATE_EXEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${UPDATE_EXEC_DIR}/../.." && pwd)"
source "${PROJECT_ROOT}/lib/transaction/transaction.sh"
source "${PROJECT_ROOT}/lib/resources/binary.sh"

update_tx_apply_binary() {
  binary_install_candidate "${UPDATE_CANDIDATE}" "${UPDATE_ACTIVE}" "${UPDATE_VERSION_ARG}" false "${UPDATE_EXPECTED_VERSION}" &&
    binary_install_metadata "${UPDATE_METADATA_CANDIDATE}" "${UPDATE_METADATA_ACTIVE}" false
}
update_tx_rollback_binary() {
  local failed=0
  binary_restore "${UPDATE_BACKUP}" "${UPDATE_ACTIVE}" false || failed=1
  binary_install_metadata "${UPDATE_METADATA_BACKUP}" "${UPDATE_METADATA_ACTIVE}" false || failed=1
  [ "${failed}" -eq 0 ]
}

update_execute_binary() {
  # lock op candidate active backup version-arg expected-version candidate-metadata active-metadata metadata-backup snapshot health commit export
  [ "$#" -eq 14 ] || return 2
  UPDATE_CANDIDATE="$3"; UPDATE_ACTIVE="$4"; UPDATE_BACKUP="$5"; UPDATE_VERSION_ARG="$6"; UPDATE_EXPECTED_VERSION="$7"
  UPDATE_METADATA_CANDIDATE="$8"; UPDATE_METADATA_ACTIVE="$9"; UPDATE_METADATA_BACKUP="${10}"
  local candidate_binary_id active_binary_id candidate_version
  candidate_binary_id="$(binary_metadata_get "${UPDATE_METADATA_CANDIDATE}" binary_id)" || return 1
  active_binary_id="$(binary_metadata_get "${UPDATE_METADATA_ACTIVE}" binary_id)" || return 1
  candidate_version="$(binary_metadata_get "${UPDATE_METADATA_CANDIDATE}" version)" || return 1
  [ "${candidate_binary_id}" = "${active_binary_id}" ] && [ "${candidate_version}" = "${UPDATE_EXPECTED_VERSION}" ] || return 1
  transaction_reset "$2" "$1"
  transaction_add_step binary update_tx_apply_binary update_tx_rollback_binary || return 1
  transaction_run "${11}" "${12}" "${13}" "${14}" "${UPDATE_HISTORY_CALLBACK:-update_tx_history_noop}"
}
update_tx_history_noop() { return 0; }
