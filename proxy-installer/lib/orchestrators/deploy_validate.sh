#!/usr/bin/env bash
# Full read-only validation gate before a real deployment transaction.

set -o pipefail

DEPLOY_VALIDATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${DEPLOY_VALIDATE_DIR}/../.." && pwd)"
source "${PROJECT_ROOT}/lib/orchestrators/deploy.sh"
source "${PROJECT_ROOT}/lib/orchestrators/deploy_materials.sh"
source "${PROJECT_ROOT}/lib/orchestrators/deploy_binaries.sh"
source "${PROJECT_ROOT}/lib/orchestrators/deploy_certificates.sh"
source "${PROJECT_ROOT}/lib/orchestrators/deploy_descriptor.sh"

deploy_validate_run() {
  # config-path, server-public-ip, manifest-dir
  [ "$#" -eq 3 ] || return 2
  local config_path="$1" public_ip="$2" manifest_dir="$3" work protocol manifest
  deploy_preflight_from_config "${config_path}" || return 1
  deploy_certificates_preflight "${config_path}" "${public_ip}" || return 1
  deploy_materials_load_config "${config_path}" || return 1
  IFS=',' read -r -a validate_protocols <<< "${DEPLOY_SELECTED_PROTOCOLS}"
  for protocol in "${validate_protocols[@]}"; do
    manifest="$(deploy_binary_manifest_path "${protocol}" "${manifest_dir}")" || return 1
    deploy_binary_read_pinned_candidate "${manifest}" || return 1
    printf 'binary-plan=%s:%s\n' "${protocol}" "${DEPLOY_BINARY_VERSION}"
  done
  work="$(mktemp -d "${TMPDIR:-/tmp}/proxy-installer-validate.XXXXXX")" || return 1
  chmod 700 "${work}" || { rm -rf -- "${work}"; return 1; }
  if ! deploy_materials_prepare "${config_path}" "${work}/candidates" /etc/proxy-installer/runtime /opt/proxy-installer/bin /etc/proxy-installer/certificates ||
     ! deploy_descriptor_build "${work}/candidates" /etc/proxy-installer/runtime /etc/systemd/system "${work}/backups" "${work}/services.descriptor"; then
    rm -rf -- "${work}"
    return 1
  fi
  local count
  count="$(wc -l < "${work}/services.descriptor" | tr -d ' ')"
  rm -rf -- "${work}"
  printf '%s\n' "service-plan-count=${count}" 'deploy-validation=passed' 'confirmation=required'
}
