#!/usr/bin/env bash
# Coordinate binary and service transactions, restoring binaries if services fail.

set -o pipefail

DEPLOY_COORDINATOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${DEPLOY_COORDINATOR_DIR}/../.." && pwd)"
source "${PROJECT_ROOT}/lib/orchestrators/deploy_binaries_execute.sh"
source "${PROJECT_ROOT}/lib/orchestrators/deploy_services_execute.sh"

deploy_coordinator_restore_binaries() {
  local descriptor="$1"
  deploy_binaries_load_descriptor "${descriptor}" || return 1
  deploy_binaries_restore
}

deploy_coordinator_execute() {
  # binary-lock service-lock op binary-desc service-desc export entries-file bin-snapshot/health/commit/history svc-snapshot/health/commit/history
  [ "$#" -eq 15 ] || return 2
  local binary_lock="$1" service_lock="$2" op="$3" binary_descriptor="$4" service_descriptor="$5" export_target="$6" entries_file="$7"
  local -a entries=()
  [ -f "${entries_file}" ] || return 1
  while IFS= read -r entry; do [ -z "${entry}" ] || entries+=("${entry}"); done < "${entries_file}"
  [ "${#entries[@]}" -gt 0 ] || return 1
  deploy_services_validate_firewall_inputs || return $?
  deploy_binaries_execute "${binary_lock}" "${op}-binaries" "${binary_descriptor}" "$8" "$9" "${10}" "${11}" || return 1
  if ! deploy_services_execute "${service_lock}" "${op}-services" "${service_descriptor}" "${export_target}" "${entries[@]}" -- "${12}" "${13}" "${14}" "${15}"; then
    deploy_coordinator_restore_binaries "${binary_descriptor}" || return 1
    return 1
  fi
}
