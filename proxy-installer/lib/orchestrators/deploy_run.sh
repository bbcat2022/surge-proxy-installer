#!/usr/bin/env bash
# Connect preparation, installation, health checks, and state recording.

set -o pipefail

DEPLOY_RUN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${DEPLOY_RUN_DIR}/../.." && pwd)"
source "${PROJECT_ROOT}/lib/config/state.sh"
source "${PROJECT_ROOT}/lib/orchestrators/deploy_paths.sh"
source "${PROJECT_ROOT}/lib/orchestrators/deploy_stage.sh"
source "${PROJECT_ROOT}/lib/orchestrators/deploy_coordinator.sh"
source "${PROJECT_ROOT}/lib/orchestrators/deploy_health.sh"

deploy_run_snapshot() {
  state_create_transaction_snapshot "${DEPLOY_RUN_STATE_ROOT}" "${DEPLOY_RUN_CONFIG}" "${DEPLOY_RUN_OPERATION_ID}"
}

deploy_run_health() {
  deploy_health_verify_all "${DEPLOY_RUN_CONFIG}" "${DEPLOY_RUN_BINARY_DIR}" "${DEPLOY_RUN_LOG_LINES}"
}

deploy_run_commit() {
  state_commit_deployment "${DEPLOY_RUN_CONFIG}" "${DEPLOY_RUN_OPERATION_ID}" >/dev/null
}

deploy_run_history() {
  state_save_success_revision "${DEPLOY_RUN_STATE_ROOT}" "${DEPLOY_RUN_CONFIG}" "${DEPLOY_RUN_OPERATION_ID}" deploy "proxy services deployed"
}

deploy_run_record_prepare_failure() {
  state_record_operation \
    "${DEPLOY_RUN_CONFIG}" "${DEPLOY_RUN_OPERATION_ID}" deploy failed \
    "deployment materials could not be prepared" preparation \
    "review the preparation output before retrying" >/dev/null
}

deploy_run_validate_paths() {
  local path
  for path in "$@"; do [[ "${path}" = /* ]] && [ "${path}" != / ] || return 1; done
}

deploy_run_execute() {
  # config public-ip manifests operation-id runtime binary certificates units state-root export firewall-mode firewall-tool
  [ "$#" -eq 12 ] || return 2
  local config="$1" public_ip="$2" manifests="$3" operation_id="$4" runtime="$5" binary="$6"
  local certificates="$7" units="$8" state_root="$9" export_target="${10}" firewall_mode="${11}" firewall_tool="${12}"
  [[ "${operation_id}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || return 2
  deploy_run_validate_paths "${config}" "${manifests}" "${runtime}" "${binary}" "${certificates}" "${units}" "${state_root}" "${export_target}" || return 2
  case "${firewall_mode}" in manual|auto) ;; *) return 2 ;; esac
  case "${firewall_tool}" in manual|ufw|nftables) ;; *) return 2 ;; esac
  DEPLOY_RUN_CONFIG="${config}"
  DEPLOY_RUN_OPERATION_ID="${operation_id}"
  DEPLOY_RUN_BINARY_DIR="${binary}"
  DEPLOY_RUN_STATE_ROOT="${state_root}"
  DEPLOY_RUN_LOG_LINES="${DEPLOY_RUN_LOG_LINES:-20}"
  local operation_root stage_work backup_dir
  operation_root="$(deploy_paths_prepare_workdir "${state_root}" "${operation_id}")" || return 1
  stage_work="${operation_root}/stage"
  backup_dir="${operation_root}/backups"
  if ! deploy_stage_prepare_complete "${config}" "${public_ip}" "${manifests}" "${stage_work}" "${runtime}" "${binary}" "${certificates}" "${units}" "${backup_dir}"; then
    deploy_run_record_prepare_failure || true
    return 1
  fi
  DEPLOY_FIREWALL_DESCRIPTOR="${stage_work}/firewall.descriptor"
  DEPLOY_FIREWALL_CONTEXT="${operation_root}/firewall.context"
  DEPLOY_FIREWALL_MODE="${firewall_mode}"
  DEPLOY_FIREWALL_TOOL="${firewall_tool}"
  state_configure_transaction_recording "${config}" deploy || return 1
  DEPLOY_COORDINATOR_RESULT_CALLBACK=state_record_transaction_result
  if deploy_coordinator_execute_unified \
      "${state_root}/operation.lock" "${operation_id}" \
      "${stage_work}/binaries.descriptor" "${stage_work}/services.descriptor" \
      "${export_target}" "${stage_work}/surge.entries" \
      deploy_run_snapshot deploy_run_health deploy_run_commit deploy_run_history; then
    printf 'deployment-result=%s\n' "${TX_RESULT:-success}"
    return 0
  fi
  printf 'deployment-result=%s\n' "${TX_RESULT:-failed}" >&2
  return 1
}
