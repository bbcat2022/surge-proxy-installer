#!/usr/bin/env bash
# Prepare all private candidates and descriptors before a mutating transaction.
set -o pipefail
DEPLOY_STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; PROJECT_ROOT="$(cd "${DEPLOY_STAGE_DIR}/../.." && pwd)"
source "${PROJECT_ROOT}/lib/orchestrators/deploy_materials.sh"
source "${PROJECT_ROOT}/lib/orchestrators/deploy_binaries.sh"
source "${PROJECT_ROOT}/lib/orchestrators/deploy_binary_descriptor.sh"
source "${PROJECT_ROOT}/lib/orchestrators/deploy_descriptor.sh"
source "${PROJECT_ROOT}/lib/orchestrators/deploy_firewall_descriptor.sh"
source "${PROJECT_ROOT}/lib/orchestrators/deploy_certificates.sh"

deploy_stage_clear_certificate_inputs() {
  unset DEPLOY_CERTIFICATE_CANDIDATE_CERT DEPLOY_CERTIFICATE_CANDIDATE_KEY
  unset DEPLOY_CERTIFICATE_ACTIVE_DIR DEPLOY_CERTIFICATE_SNAPSHOT_DIR
  unset DEPLOY_STAGE_CERTIFICATE_DOMAIN
}

deploy_stage_prepare_contents() {
  [ "$#" -eq 8 ] || return 2
  local config="$1" manifests="$2" work="$3" runtime="$4" binary="$5" certificates="$6" units="$7" backup="$8" protocol
  [[ "${work}" = /* ]] && [ -d "${work}" ] && [ ! -L "${work}" ] || return 1
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

deploy_stage_prepare() {
  # config manifest-dir work runtime binary certificate unit backup
  [ "$#" -eq 8 ] || return 2
  local work="$3"
  deploy_stage_clear_certificate_inputs
  [[ "${work}" = /* ]] && [ ! -e "${work}" ] || return 1
  mkdir -p "${work}" && chmod 700 "${work}" || return 1
  deploy_stage_prepare_contents "$@"
}

deploy_stage_set_certificate_inputs() {
  # config work active-certificate-dir backup-dir
  [ "$#" -eq 4 ] || return 2
  local config="$1" work="$2" active_dir="$3" backup_dir="$4" domain
  domain="$(deploy_certificates_domains "${config}")" || return 1
  [ -n "${domain}" ] || return 0
  DEPLOY_STAGE_CERTIFICATE_DOMAIN="${domain}"
  DEPLOY_CERTIFICATE_CANDIDATE_CERT="${work}/certificates/${domain}/cert.pem"
  DEPLOY_CERTIFICATE_CANDIDATE_KEY="${work}/certificates/${domain}/key.pem"
  DEPLOY_CERTIFICATE_ACTIVE_DIR="${active_dir}"
  DEPLOY_CERTIFICATE_SNAPSHOT_DIR="${backup_dir}/certificate"
}

deploy_stage_prepare_complete() {
  # config public-ip manifest-dir work runtime binary certificate unit backup
  [ "$#" -eq 9 ] || return 2
  local config="$1" public_ip="$2" manifests="$3" work="$4" runtime="$5" binary="$6" certificates="$7" units="$8" backup="$9"
  deploy_stage_clear_certificate_inputs
  [[ "${work}" = /* ]] && [ ! -e "${work}" ] || return 1
  mkdir -p "${work}" && chmod 700 "${work}" || return 1
  deploy_certificates_prepare_candidates "${config}" "${public_ip}" "${work}/certificates" false || return 1
  deploy_stage_prepare_contents "${config}" "${manifests}" "${work}" "${runtime}" "${binary}" "${certificates}" "${units}" "${backup}" || return 1
  deploy_stage_set_certificate_inputs "${config}" "${work}" "${certificates}" "${backup}" || return 1
  if [ -n "${DEPLOY_STAGE_CERTIFICATE_DOMAIN:-}" ]; then
    printf '%s\n' 'stage-certificate=prepared'
  else
    printf '%s\n' 'stage-certificate=not-required'
  fi
}
