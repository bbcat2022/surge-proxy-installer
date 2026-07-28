#!/usr/bin/env bash
# Verify every configured proxy service after deployment.

set -o pipefail

DEPLOY_HEALTH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${DEPLOY_HEALTH_DIR}/../.." && pwd)"
source "${PROJECT_ROOT}/lib/orchestrators/deploy_materials.sh"
source "${PROJECT_ROOT}/lib/orchestrators/deploy_binaries.sh"
source "${PROJECT_ROOT}/lib/orchestrators/deploy_binary_descriptor.sh"
source "${PROJECT_ROOT}/lib/registry/protocols.sh"
source "${PROJECT_ROOT}/lib/resources/health.sh"

deploy_health_protocol_port() {
  case "$1" in
    snell) printf '%s\n' "${SNELL_PORT:-}" ;;
    anytls) printf '%s\n' "${ANYTLS_PORT:-}" ;;
    hysteria2) printf '%s\n' "${HYSTERIA2_PORT:-}" ;;
    *) return 1 ;;
  esac
}

deploy_health_protocol_transport() {
  local network
  network="$(protocol_registry_get "$1" network)" || return 1
  printf '%s\n' "${network%%,*}"
}

deploy_health_verify_port_hopping() {
  [ -n "${HYSTERIA2_PORT_HOPPING_RANGE:-}" ] || return 0
  "${SYSTEMCTL_BIN:-systemctl}" is-active --quiet proxy-installer-hysteria2-port-hop.service || return 1
  "${NFT_BIN:-nft}" list table inet proxy_installer_hy2 >/dev/null 2>&1
}

deploy_health_verify_all() {
  # config-path binary-dir recent-log-lines
  [ "$#" -eq 3 ] || return 2
  local config="$1" binary_dir="$2" log_lines="$3" protocol unit transport port binary version_arg failed=0
  [[ "${binary_dir}" = /* ]] && [ "${binary_dir}" != / ] || return 2
  [[ "${log_lines}" =~ ^[0-9]+$ ]] && [ "${log_lines}" -le 100 ] || return 2
  deploy_materials_load_config "${config}" || return 1
  IFS=',' read -r -a health_protocols <<< "${DEPLOY_SELECTED_PROTOCOLS}"
  for protocol in "${health_protocols[@]}"; do
    unit="$(protocol_registry_get "${protocol}" service_name)" || return 1
    transport="$(deploy_health_protocol_transport "${protocol}")" || return 1
    port="$(deploy_health_protocol_port "${protocol}")" || return 1
    binary="$(deploy_binary_descriptor_target "${protocol}" "${binary_dir}")" || return 1
    version_arg="$(deploy_binary_version_argument "${protocol}")" || return 1
    if health_verify "${unit}" "${transport}" "${port}" "${binary}" "${version_arg}" "${log_lines}"; then
      printf 'health=%s:passed\n' "${protocol}"
    else
      printf 'health=%s:failed\n' "${protocol}" >&2
      failed=1
    fi
    if [ "${protocol}" = hysteria2 ] && [ -n "${HYSTERIA2_PORT_HOPPING_RANGE:-}" ]; then
      if deploy_health_verify_port_hopping; then
        printf '%s\n' 'health=hysteria2-port-hopping:passed'
      else
        printf '%s\n' 'health=hysteria2-port-hopping:failed' >&2
        failed=1
      fi
    fi
  done
  [ "${failed}" -eq 0 ]
}
