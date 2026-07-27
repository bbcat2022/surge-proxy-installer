#!/usr/bin/env bash
# Transaction wiring after ACME has produced and validated a candidate certificate.

set -o pipefail

CERT_EXEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${CERT_EXEC_DIR}/../.." && pwd)"
source "${PROJECT_ROOT}/lib/transaction/transaction.sh"
source "${PROJECT_ROOT}/lib/resources/certificate.sh"
source "${PROJECT_ROOT}/lib/resources/systemd.sh"

certificate_tx_apply_files() { certificate_install_candidate "${CERT_CANDIDATE_CERT}" "${CERT_CANDIDATE_KEY}" "${CERT_ACTIVE_DIR}" false; }
certificate_tx_rollback_files() { certificate_restore "${CERT_SNAPSHOT_DIR}" "${CERT_ACTIVE_DIR}" false; }
certificate_tx_reload_services() {
  local unit
  IFS=',' read -r -a units <<< "${CERT_TLS_UNITS}"
  for unit in "${units[@]}"; do systemd_action "${unit}" restart false || return 1; done
}
certificate_tx_restore_services() { certificate_tx_reload_services; }

certificate_execute_install() {
  # lock op candidate-cert candidate-key active-dir snapshot-dir comma-separated-tls-units snapshot health commit export
  [ "$#" -eq 11 ] || return 2
  CERT_CANDIDATE_CERT="$3"; CERT_CANDIDATE_KEY="$4"; CERT_ACTIVE_DIR="$5"; CERT_SNAPSHOT_DIR="$6"; CERT_TLS_UNITS="$7"
  [ -n "${CERT_TLS_UNITS}" ] || return 2
  transaction_reset "$2" "$1"
  transaction_add_step certificate certificate_tx_apply_files certificate_tx_rollback_files || return 1
  transaction_add_step tls-services certificate_tx_reload_services certificate_tx_restore_services || return 1
  transaction_run "$8" "$9" "${10}" "${11}" "${CERT_HISTORY_CALLBACK:-certificate_tx_history_noop}"
}
certificate_tx_history_noop() { return 0; }
