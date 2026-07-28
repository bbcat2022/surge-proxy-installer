#!/usr/bin/env bash
# Coordinate binary and service transactions, restoring binaries if services fail.

set -o pipefail

DEPLOY_COORDINATOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${DEPLOY_COORDINATOR_DIR}/../.." && pwd)"
source "${PROJECT_ROOT}/lib/orchestrators/deploy_binaries_execute.sh"
source "${PROJECT_ROOT}/lib/orchestrators/deploy_services_execute.sh"

deploy_coordinator_noop() { return 0; }

deploy_coordinator_restore_binaries() {
  local descriptor="$1"
  deploy_binaries_load_descriptor "${descriptor}" || return 1
  deploy_binaries_restore
}

deploy_coordinator_validate_service_inputs() {
  local service_descriptor="$1"
  deploy_services_load_descriptor "${service_descriptor}" || return 1
  deploy_services_validate_firewall_inputs || return $?
  deploy_services_validate_certificate_inputs || return $?
}

deploy_coordinator_execute() {
  # binary-lock service-lock op binary-desc service-desc export entries-file bin-snapshot/health/commit/history svc-snapshot/health/commit/history
  [ "$#" -eq 15 ] || return 2
  local binary_lock="$1" service_lock="$2" op="$3" binary_descriptor="$4" service_descriptor="$5" export_target="$6" entries_file="$7"
  local -a entries=()
  [ -f "${entries_file}" ] || return 1
  while IFS= read -r entry; do [ -z "${entry}" ] || entries+=("${entry}"); done < "${entries_file}"
  [ "${#entries[@]}" -gt 0 ] || return 1
  deploy_coordinator_validate_service_inputs "${service_descriptor}" || return $?
  deploy_binaries_execute "${binary_lock}" "${op}-binaries" "${binary_descriptor}" "$8" "$9" "${10}" "${11}" || return 1
  if ! deploy_services_execute "${service_lock}" "${op}-services" "${service_descriptor}" "${export_target}" "${entries[@]}" -- "${12}" "${13}" "${14}" "${15}"; then
    deploy_coordinator_restore_binaries "${binary_descriptor}" || return 1
    return 1
  fi
}

deploy_coordinator_capture_all() {
  DEPLOY_BINARY_EXTERNAL_SNAPSHOT=deploy_coordinator_noop
  deploy_binaries_capture || return 1
  DEPLOY_SERVICE_EXTERNAL_SNAPSHOT="${DEPLOY_COORDINATOR_EXTERNAL_SNAPSHOT}"
  deploy_services_capture_backups
}

deploy_coordinator_verify_restored() {
  local failed=0
  deploy_binaries_verify_restored || failed=1
  deploy_services_verify_restored || failed=1
  [ "${failed}" -eq 0 ]
}

deploy_coordinator_execute_unified() {
  # lock op binary-descriptor service-descriptor export-target entries-file snapshot health commit history
  [ "$#" -eq 10 ] || return 2
  local lock="$1" op="$2" binary_descriptor="$3" service_descriptor="$4" export_target="$5" entries_file="$6"
  local snapshot="$7" health="$8" commit="$9" history="${10}" entry
  local -a entries=()
  [ -f "${entries_file}" ] || return 1
  while IFS= read -r entry; do [ -z "${entry}" ] || entries+=("${entry}"); done < "${entries_file}"
  [ "${#entries[@]}" -gt 0 ] || return 1
  deploy_binaries_load_descriptor "${binary_descriptor}" || return 1
  deploy_coordinator_validate_service_inputs "${service_descriptor}" || return $?
  DEPLOY_SERVICE_EXPORT_TARGET="${export_target}"
  DEPLOY_SERVICE_ENTRIES=("${entries[@]}")
  DEPLOY_COORDINATOR_EXTERNAL_SNAPSHOT="${snapshot}"
  transaction_reset "${op}" "${lock}"
  [ -z "${DEPLOY_COORDINATOR_RESULT_CALLBACK:-}" ] ||
    transaction_set_result_callback "${DEPLOY_COORDINATOR_RESULT_CALLBACK}" || return 1
  transaction_set_restore_verify_callback deploy_coordinator_verify_restored || return 1
  transaction_add_step binaries deploy_binaries_apply deploy_binaries_restore || return 1
  transaction_add_step runtimes deploy_services_apply_runtime deploy_services_restore_runtime || return 1
  transaction_add_step units deploy_services_apply_units deploy_services_restore_units || return 1
  if [ "${DEPLOY_SERVICE_FIREWALL_INPUTS}" -eq 4 ]; then
    transaction_add_step firewall deploy_services_apply_firewall deploy_services_restore_firewall || return 1
  fi
  transaction_run deploy_coordinator_capture_all "${health}" "${commit}" deploy_services_export "${history}"
}
