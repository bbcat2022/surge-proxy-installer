#!/usr/bin/env bash
# Scheduled certificate refresh with transactional activation and service health checks.

set -o pipefail

CERT_RENEW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${CERT_RENEW_DIR}/../.." && pwd)"
source "${PROJECT_ROOT}/lib/config/state.sh"
source "${PROJECT_ROOT}/lib/orchestrators/deploy_paths.sh"
source "${PROJECT_ROOT}/lib/orchestrators/deploy_health.sh"
source "${PROJECT_ROOT}/lib/orchestrators/certificate_execute.sh"

certificate_renew_load_config() {
  local config="$1" temporary
  temporary="$(mktemp "${TMPDIR:-/tmp}/proxy-installer-renew.XXXXXX")" || return 1
  chmod 600 "${temporary}" || { rm -f -- "${temporary}"; return 1; }
  state_certificate_renewal_env "${config}" > "${temporary}" || { rm -f -- "${temporary}"; return 1; }
  # shellcheck disable=SC1090
  source "${temporary}" || { rm -f -- "${temporary}"; return 1; }
  rm -f -- "${temporary}"
}

certificate_renew_snapshot() {
  state_create_transaction_snapshot \
    "${CERT_RENEW_STATE_ROOT}" "${CERT_RENEW_CONFIG}" "${CERT_RENEW_OPERATION_ID}" \
    "${CERT_RENEW_ACTIVE_DIR}/cert.pem" "${CERT_RENEW_ACTIVE_DIR}/key.pem"
}

certificate_renew_health() {
  deploy_health_verify_all "${CERT_RENEW_CONFIG}" "${CERT_RENEW_BINARY_DIR}" "${CERT_RENEW_LOG_LINES}"
}

certificate_renew_commit() { return 0; }

certificate_renew_history() {
  state_save_success_revision \
    "${CERT_RENEW_STATE_ROOT}" "${CERT_RENEW_CONFIG}" "${CERT_RENEW_OPERATION_ID}" certificate \
    "TLS certificate renewed" "${CERT_RENEW_ACTIVE_DIR}/cert.pem" "${CERT_RENEW_ACTIVE_DIR}/key.pem"
}

certificate_renew_discard_unchanged() {
  local candidate_dir="$1" operation_root="$2"
  rm -f -- "${candidate_dir}/cert.pem" "${candidate_dir}/key.pem"
  rmdir "${candidate_dir}" 2>/dev/null || true
  rmdir "$(dirname "${candidate_dir}")" 2>/dev/null || true
  rmdir "${operation_root}" 2>/dev/null || true
}

certificate_renew_execute() {
  # config binary-dir active-certificate-dir state-root operation-id recent-log-lines
  [ "$#" -eq 6 ] || return 2
  local config="$1" binary_dir="$2" active_dir="$3" state_root="$4" operation_id="$5" log_lines="$6"
  [[ "${config}" = /* ]] && [[ "${binary_dir}" = /* ]] && [[ "${active_dir}" = /* ]] && [[ "${state_root}" = /* ]] || return 2
  [[ "${operation_id}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || return 2
  [[ "${log_lines}" =~ ^[0-9]+$ ]] && [ "${log_lines}" -le 100 ] || return 2
  certificate_renew_load_config "${config}" || return 1
  if [ "${CERTIFICATE_RENEWAL_REQUIRED}" = false ]; then
    printf '%s\n' 'certificate-renewal=not-required'
    return 0
  fi
  [ "${CERTIFICATE_RENEWAL_REQUIRED}" = true ] || return 1
  certificate_pair_state "${active_dir}" | grep -Fx present >/dev/null || return 1
  local operation_root candidate_dir snapshot_dir
  operation_root="$(deploy_paths_prepare_workdir "${state_root}" "${operation_id}")" || return 1
  candidate_dir="${operation_root}/candidate/${CERTIFICATE_RENEWAL_DOMAIN}"
  snapshot_dir="${operation_root}/backups/certificate"
  certificate_refresh_candidate "${CERTIFICATE_RENEWAL_DOMAIN}" "${candidate_dir}" false || return 1
  if cmp -s "${candidate_dir}/cert.pem" "${active_dir}/cert.pem" &&
      cmp -s "${candidate_dir}/key.pem" "${active_dir}/key.pem"; then
    certificate_renew_discard_unchanged "${candidate_dir}" "${operation_root}"
    printf '%s\n' 'certificate-renewal=not-due'
    return 0
  fi
  CERT_RENEW_CONFIG="${config}"
  CERT_RENEW_BINARY_DIR="${binary_dir}"
  CERT_RENEW_ACTIVE_DIR="${active_dir}"
  CERT_RENEW_STATE_ROOT="${state_root}"
  CERT_RENEW_OPERATION_ID="${operation_id}"
  CERT_RENEW_LOG_LINES="${log_lines}"
  state_configure_transaction_recording "${config}" certificate || return 1
  CERT_RESULT_CALLBACK=state_record_transaction_result
  CERT_HISTORY_CALLBACK=certificate_renew_history
  if certificate_execute_install \
      "${state_root}/operation.lock" "${operation_id}" \
      "${candidate_dir}/cert.pem" "${candidate_dir}/key.pem" \
      "${active_dir}" "${snapshot_dir}" "${CERTIFICATE_RENEWAL_UNITS}" \
      certificate_renew_snapshot certificate_renew_health certificate_renew_commit certificate_renew_commit; then
    printf '%s\n' 'certificate-renewal=success'
    return 0
  fi
  printf 'certificate-renewal=%s\n' "${TX_RESULT:-failed}" >&2
  return 1
}
