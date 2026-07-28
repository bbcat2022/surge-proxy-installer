#!/usr/bin/env bash
# Transaction wiring after ACME has produced and validated a candidate certificate.

set -o pipefail

CERT_EXEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${CERT_EXEC_DIR}/../.." && pwd)"
source "${PROJECT_ROOT}/lib/transaction/transaction.sh"
source "${PROJECT_ROOT}/lib/resources/certificate.sh"
source "${PROJECT_ROOT}/lib/resources/snapshot.sh"
source "${PROJECT_ROOT}/lib/resources/systemd.sh"

certificate_tx_apply_files() { certificate_install_candidate "${CERT_CANDIDATE_CERT}" "${CERT_CANDIDATE_KEY}" "${CERT_ACTIVE_DIR}" false; }
certificate_tx_rollback_files() {
  local failed=0
  snapshot_restore_file "${CERT_ACTIVE_DIR}/key.pem" "${CERT_SNAPSHOT_DIR}/key.pem" false || failed=1
  snapshot_restore_file "${CERT_ACTIVE_DIR}/cert.pem" "${CERT_SNAPSHOT_DIR}/cert.pem" false || failed=1
  [ "${failed}" -eq 0 ]
}
certificate_tx_capture_files() {
  local unit
  certificate_pair_state "${CERT_ACTIVE_DIR}" >/dev/null || return 1
  snapshot_capture_file "${CERT_ACTIVE_DIR}/cert.pem" "${CERT_SNAPSHOT_DIR}/cert.pem" false || return 1
  snapshot_capture_file "${CERT_ACTIVE_DIR}/key.pem" "${CERT_SNAPSHOT_DIR}/key.pem" false || return 1
  for unit in "${CERT_TLS_UNIT_ARRAY[@]}"; do
    systemd_capture_state "${unit}" "${CERT_SNAPSHOT_DIR}/service-${unit}.state" false || return 1
  done
  "${CERT_EXTERNAL_SNAPSHOT}"
}
certificate_tx_reload_services() {
  local unit active
  for unit in "${CERT_TLS_UNIT_ARRAY[@]}"; do
    active="$(systemd_read_captured_state "${CERT_SNAPSHOT_DIR}/service-${unit}.state" active)" || return 1
    [ "${active}" != active ] || systemd_action "${unit}" restart false || return 1
  done
}
certificate_tx_restore_services() {
  local unit failed=0
  for unit in "${CERT_TLS_UNIT_ARRAY[@]}"; do
    systemd_restore_state "${unit}" "${CERT_SNAPSHOT_DIR}/service-${unit}.state" false || failed=1
  done
  [ "${failed}" -eq 0 ]
}
certificate_tx_apply_switch() {
  certificate_tx_apply_files || return 1
  certificate_tx_reload_services
}
certificate_tx_rollback_switch() {
  local failed=0
  certificate_tx_rollback_files || failed=1
  certificate_tx_restore_services || failed=1
  [ "${failed}" -eq 0 ]
}
certificate_tx_verify_restored() {
  local unit failed=0
  snapshot_verify_file "${CERT_ACTIVE_DIR}/cert.pem" "${CERT_SNAPSHOT_DIR}/cert.pem" || failed=1
  snapshot_verify_file "${CERT_ACTIVE_DIR}/key.pem" "${CERT_SNAPSHOT_DIR}/key.pem" || failed=1
  for unit in "${CERT_TLS_UNIT_ARRAY[@]}"; do
    systemd_verify_captured_state "${unit}" "${CERT_SNAPSHOT_DIR}/service-${unit}.state" || failed=1
  done
  [ "${failed}" -eq 0 ]
}

certificate_execute_install() {
  # lock op candidate-cert candidate-key active-dir snapshot-dir comma-separated-tls-units snapshot health commit export
  [ "$#" -eq 11 ] || return 2
  CERT_CANDIDATE_CERT="$3"; CERT_CANDIDATE_KEY="$4"; CERT_ACTIVE_DIR="$5"; CERT_SNAPSHOT_DIR="$6"; CERT_TLS_UNITS="$7"; CERT_EXTERNAL_SNAPSHOT="$8"
  [ -n "${CERT_TLS_UNITS}" ] || return 2
  local unit existing duplicate
  local -a units=()
  CERT_TLS_UNIT_ARRAY=()
  IFS=',' read -r -a units <<< "${CERT_TLS_UNITS}"
  for unit in "${units[@]}"; do
    systemd_validate_unit_name "${unit}" || return 2
    duplicate=false
    for existing in "${CERT_TLS_UNIT_ARRAY[@]}"; do [ "${existing}" != "${unit}" ] || duplicate=true; done
    [ "${duplicate}" = false ] || return 2
    CERT_TLS_UNIT_ARRAY+=("${unit}")
  done
  certificate_validate_candidate "${CERT_CANDIDATE_CERT}" "${CERT_CANDIDATE_KEY}" || return 1
  transaction_reset "$2" "$1"
  transaction_set_restore_verify_callback certificate_tx_verify_restored || return 1
  transaction_add_step certificate-switch certificate_tx_apply_switch certificate_tx_rollback_switch || return 1
  transaction_run certificate_tx_capture_files "$9" "${10}" "${11}" "${CERT_HISTORY_CALLBACK:-certificate_tx_history_noop}"
}
certificate_tx_history_noop() { return 0; }
