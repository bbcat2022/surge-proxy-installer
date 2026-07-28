#!/usr/bin/env bash
# Prepare all private candidates and descriptors before a mutating transaction.
set -o pipefail
DEPLOY_STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; PROJECT_ROOT="$(cd "${DEPLOY_STAGE_DIR}/../.." && pwd)"
source "${PROJECT_ROOT}/lib/orchestrators/deploy_materials.sh"
source "${PROJECT_ROOT}/lib/orchestrators/deploy_binaries.sh"
source "${PROJECT_ROOT}/lib/orchestrators/deploy_binary_descriptor.sh"
source "${PROJECT_ROOT}/lib/orchestrators/deploy_descriptor.sh"
source "${PROJECT_ROOT}/lib/orchestrators/deploy_firewall_descriptor.sh"

deploy_stage_prepare() {
  # config manifest-dir work runtime binary certificate unit backup
  [ "$#" -eq 8 ] || return 2
  local config="$1" manifests="$2" work="$3" runtime="$4" binary="$5" certificates="$6" units="$7" backup="$8" protocol
  [[ "${work}" = /* ]] && [ ! -e "${work}" ] || return 1
  mkdir -p "${work}" && chmod 700 "${work}" || return 1
  deploy_materials_prepare "${config}" "${work}/materials" "${runtime}" "${binary}" "${certificates}" || return 1
  deploy_materials_load_config "${config}" || return 1
  IFS=',' read -r -a protocols <<< "${DEPLOY_SELECTED_PROTOCOLS}"
  for protocol in "${protocols[@]}"; do deploy_binary_prepare_pinned "${protocol}" "${manifests}" "${work}/binaries/${protocol}" false || return 1; done
  deploy_binary_descriptor_build "${work}/binaries" "${binary}" "${backup}" "${work}/binaries.descriptor" "${DEPLOY_SELECTED_PROTOCOLS}" || return 1
  deploy_descriptor_build "${work}/materials" "${runtime}" "${units}" "${backup}" "${work}/services.descriptor" || return 1
  deploy_firewall_descriptor_build "${work}/firewall.descriptor" || return 1
  deploy_descriptor_entries "${work}/materials" > "${work}/surge.entries" || return 1
  chmod 600 "${work}"/*.descriptor "${work}/surge.entries" || return 1
  printf '%s\n' "stage-workdir=${work}" 'stage=prepared'
}
