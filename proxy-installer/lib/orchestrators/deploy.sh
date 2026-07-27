#!/usr/bin/env bash
# Deploy-plan builder. Execution is intentionally delegated to the transaction layer.

set -o pipefail

DEPLOY_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${DEPLOY_MODULE_DIR}/../.." && pwd)"
source "${PROJECT_ROOT}/lib/resources/firewall.sh"
source "${PROJECT_ROOT}/lib/config/state.sh"

deploy_normalize_protocols() {
  local raw="$1" item existing duplicate
  DEPLOY_PROTOCOLS=()
  IFS=',' read -r -a items <<< "${raw}"
  for item in "${items[@]}"; do
    item="${item// /}"
    case "${item}" in snell|anytls|hysteria2) ;; *) return 1 ;; esac
    duplicate=false
    for existing in "${DEPLOY_PROTOCOLS[@]:-}"; do [ "${existing}" != "${item}" ] || duplicate=true; done
    [ "${duplicate}" = true ] || DEPLOY_PROTOCOLS+=("${item}")
  done
  [ "${#DEPLOY_PROTOCOLS[@]}" -gt 0 ]
}

deploy_build_plan() {
  local selected="$1" snell_port="$2" anytls_port="$3" hy2_port="$4" hy2_range="$5"
  deploy_normalize_protocols "${selected}" || return 1
  local protocol tls_required=false tcp_ports=() udp_rules=() item
  for protocol in "${DEPLOY_PROTOCOLS[@]}"; do
    case "${protocol}" in
      snell) firewall_validate_rule tcp "${snell_port}" || return 1; tcp_ports+=("${snell_port}") ;;
      anytls) firewall_validate_rule tcp "${anytls_port}" || return 1; tcp_ports+=("${anytls_port}"); tls_required=true ;;
      hysteria2)
        firewall_validate_rule udp "${hy2_port}" || return 1; udp_rules+=("udp:${hy2_port}"); tls_required=true
        if [ -n "${hy2_range}" ]; then firewall_validate_rule udp-range "${hy2_range}" || return 1; local first="${hy2_range%-*}" last="${hy2_range#*-}"; [ "${hy2_port}" -lt "${first}" ] || [ "${hy2_port}" -gt "${last}" ] || return 1; udp_rules+=("udp-range:${hy2_range}"); fi
        ;;
    esac
  done
  local i j
  for ((i=0; i<${#tcp_ports[@]}; i++)); do for ((j=i+1; j<${#tcp_ports[@]}; j++)); do [ "${tcp_ports[i]}" != "${tcp_ports[j]}" ] || return 1; done; done
  printf 'operation=deploy\nprotocols=%s\n' "$(IFS=,; echo "${DEPLOY_PROTOCOLS[*]}")"
  printf 'certificate=%s\n' "$([ "${tls_required}" = true ] && echo shared-main-domain || echo not-required)"
  for item in "${tcp_ports[@]}"; do printf 'network=tcp:%s\n' "${item}"; done
  for item in "${udp_rules[@]}"; do printf 'network=%s\n' "${item}"; done
  printf '%s\n' 'confirmation=required' 'execution=transaction-required'
}

deploy_preflight_from_config() {
  # This is intentionally read-only. The later execution phase must consume
  # credentials only through a dedicated privileged material builder.
  local config_path="$1"
  state_deployment_plan "${config_path}" || return 1
  printf '%s\n' 'operation=deploy-preflight' 'environment=ready-required' 'certificate=http-01-required-for-tls-protocols' 'confirmation=required' 'execution=not-yet-authorized-by-preflight'
}
