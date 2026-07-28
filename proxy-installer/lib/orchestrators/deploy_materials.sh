#!/usr/bin/env bash
# Build deployment candidates from controlled configuration. No system mutation.

set -o pipefail

DEPLOY_MATERIALS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${DEPLOY_MATERIALS_DIR}/../.." && pwd)"
source "${PROJECT_ROOT}/lib/config/state.sh"
source "${PROJECT_ROOT}/lib/adapters/snell.sh"
source "${PROJECT_ROOT}/lib/adapters/anytls.sh"
source "${PROJECT_ROOT}/lib/adapters/hysteria2.sh"

deploy_materials_load_config() {
  local config_path="$1" temporary
  temporary="$(mktemp "${TMPDIR:-/tmp}/proxy-installer-deploy.XXXXXX")" || return 1
  chmod 600 "${temporary}" || { rm -f "${temporary}"; return 1; }
  state_deployment_env "${config_path}" > "${temporary}" || { rm -f "${temporary}"; return 1; }
  # shellcheck disable=SC1090
  source "${temporary}" || { rm -f "${temporary}"; return 1; }
  rm -f "${temporary}"
}

deploy_materials_require_path() { [[ "$1" = /* ]] && [ -n "$1" ]; }

deploy_materials_prepare() {
  # config-path, candidate-dir, runtime-dir, binary-dir, certificate-dir
  [ "$#" -eq 5 ] || return 2
  local config_path="$1" candidate_dir="$2" runtime_dir="$3" binary_dir="$4" certificate_dir="$5"
  deploy_materials_require_path "${candidate_dir}" || return 1
  deploy_materials_require_path "${runtime_dir}" || return 1
  deploy_materials_require_path "${binary_dir}" || return 1
  deploy_materials_require_path "${certificate_dir}" || return 1
  deploy_materials_load_config "${config_path}" || return 1
  mkdir -p "${candidate_dir}" || return 1
  chmod 700 "${candidate_dir}" || return 1
  DEPLOY_MATERIAL_PROTOCOLS=()
  local protocol
  IFS=',' read -r -a DEPLOY_MATERIAL_PROTOCOLS <<< "${DEPLOY_SELECTED_PROTOCOLS}"
  for protocol in "${DEPLOY_MATERIAL_PROTOCOLS[@]}"; do
    case "${protocol}" in
      snell)
        snell_build_runtime "${SNELL_PORT}" "${SNELL_PSK}" "${SNELL_CLIENT_ADDRESS_TYPE}" "${SNELL_CLIENT_ADDRESS}" "${SNELL_MODE}" > "${candidate_dir}/snell.conf" || return 1
        snell_build_unit "${binary_dir}/snell-server" "${runtime_dir}/snell.conf" > "${candidate_dir}/proxy-installer-snell.service" || return 1
        snell_build_surge_entry Snell-v6 "${SNELL_PORT}" "${SNELL_PSK}" "${SNELL_CLIENT_ADDRESS_TYPE}" "${SNELL_CLIENT_ADDRESS}" "${SNELL_MODE}" > "${candidate_dir}/snell.surge" || return 1
        ;;
      anytls)
        anytls_build_runtime "${ANYTLS_PORT}" "${ANYTLS_PASSWORD}" "${ANYTLS_DOMAIN}" "${certificate_dir}/cert.pem" "${certificate_dir}/key.pem" > "${candidate_dir}/anytls.json" || return 1
        anytls_build_unit "${binary_dir}/sing-box" "${runtime_dir}/anytls.json" > "${candidate_dir}/proxy-installer-anytls.service" || return 1
        anytls_build_surge_entry AnyTLS "${ANYTLS_PORT}" "${ANYTLS_PASSWORD}" "${ANYTLS_DOMAIN}" "${ANYTLS_TFO}" "${ANYTLS_REUSE}" > "${candidate_dir}/anytls.surge" || return 1
        ;;
      hysteria2)
        hy2_build_runtime "${HYSTERIA2_PORT}" "${HYSTERIA2_PASSWORD}" "${HYSTERIA2_DOMAIN}" "${certificate_dir}/cert.pem" "${certificate_dir}/key.pem" "${HYSTERIA2_PORT_HOPPING_RANGE}" "${HYSTERIA2_HOP_INTERVAL}" "${HYSTERIA2_GECKO}" "${HYSTERIA2_GECKO_PASSWORD}" > "${candidate_dir}/hysteria2.yaml" || return 1
        hy2_build_unit "${binary_dir}/hysteria" "${runtime_dir}/hysteria2.yaml" > "${candidate_dir}/proxy-installer-hysteria2.service" || return 1
        hy2_build_surge_entry Hysteria2 "${HYSTERIA2_PORT}" "${HYSTERIA2_PASSWORD}" "${HYSTERIA2_DOMAIN}" "${HYSTERIA2_PORT_HOPPING_RANGE}" "${HYSTERIA2_HOP_INTERVAL}" "${HYSTERIA2_GECKO}" "${HYSTERIA2_GECKO_PASSWORD}" "${HYSTERIA2_DOWNLOAD_BANDWIDTH}" > "${candidate_dir}/hysteria2.surge" || return 1
        if [ -n "${HYSTERIA2_PORT_HOPPING_RANGE}" ]; then
          hy2_build_port_hop_runtime "${HYSTERIA2_PORT_HOPPING_RANGE}" "${HYSTERIA2_PORT}" > "${candidate_dir}/hysteria2-port-hop.nft" || return 1
          hy2_build_port_hop_unit "${runtime_dir}/hysteria2-port-hop.nft" > "${candidate_dir}/proxy-installer-hysteria2-port-hop.service" || return 1
        fi
        ;;
      *) return 1 ;;
    esac
  done
  chmod 600 "${candidate_dir}"/* || return 1
  printf 'operation=prepare-deploy\nprotocols=%s\ncandidate-dir=%s\n' "${DEPLOY_SELECTED_PROTOCOLS}" "${candidate_dir}"
}
