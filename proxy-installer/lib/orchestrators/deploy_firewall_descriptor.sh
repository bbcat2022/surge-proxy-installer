#!/usr/bin/env bash
# Build and load a secret-free firewall descriptor for a staged deployment.

set -o pipefail

DEPLOY_FIREWALL_DESCRIPTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${DEPLOY_FIREWALL_DESCRIPTOR_DIR}/../.." && pwd)"
source "${PROJECT_ROOT}/lib/resources/firewall.sh"

deploy_firewall_descriptor_build() {
  # descriptor-file; consumes validated DEPLOY_SELECTED_PROTOCOLS and port variables.
  [ "$#" -eq 1 ] || return 2
  local descriptor="$1" protocol temporary first last
  local -a rules=() protocols=()
  [[ "${descriptor}" = /* ]] && [ "${descriptor}" != / ] && [ ! -L "${descriptor}" ] || return 1
  [ -n "${DEPLOY_SELECTED_PROTOCOLS:-}" ] || return 1
  IFS=',' read -r -a protocols <<< "${DEPLOY_SELECTED_PROTOCOLS}"
  for protocol in "${protocols[@]}"; do
    case "${protocol}" in
      snell) rules+=("tcp:${SNELL_PORT:-}") ;;
      anytls) rules+=("tcp:${ANYTLS_PORT:-}") ;;
      hysteria2)
        rules+=("udp:${HYSTERIA2_PORT:-}")
        if [ -n "${HYSTERIA2_PORT_HOPPING_RANGE:-}" ]; then
          first="${HYSTERIA2_PORT_HOPPING_RANGE%-*}"
          last="${HYSTERIA2_PORT_HOPPING_RANGE#*-}"
          firewall_validate_rule udp-range "${HYSTERIA2_PORT_HOPPING_RANGE}" || return 1
          [ "${HYSTERIA2_PORT}" -lt "${first}" ] || [ "${HYSTERIA2_PORT}" -gt "${last}" ] || return 1
          rules+=("udp-range:${HYSTERIA2_PORT_HOPPING_RANGE}")
        fi
        ;;
      *) return 1 ;;
    esac
  done
  firewall_normalize_rules "${rules[@]}" || return 1
  [ "${#FIREWALL_NORMALIZED_RULES[@]}" -eq "${#rules[@]}" ] || return 1
  mkdir -p "$(dirname "${descriptor}")" || return 1
  temporary="$(dirname "${descriptor}")/.$(basename "${descriptor}").tmp.$$"
  [ ! -e "${temporary}" ] && [ ! -L "${temporary}" ] || return 1
  {
    printf '%s\n' 'schema=1'
    for protocol in "${FIREWALL_NORMALIZED_RULES[@]}"; do printf 'rule=%s\n' "${protocol}"; done
  } > "${temporary}" &&
    chmod 600 "${temporary}" &&
    mv -f "${temporary}" "${descriptor}" || { rm -f "${temporary}"; return 1; }
}

deploy_firewall_descriptor_load() {
  [ "$#" -eq 1 ] || return 2
  local descriptor="$1" line schema_count=0 rule
  [ -f "${descriptor}" ] && [ ! -L "${descriptor}" ] || return 1
  DEPLOY_FIREWALL_RULES=()
  while IFS= read -r line; do
    case "${line}" in
      schema=1) schema_count=$((schema_count + 1)) ;;
      rule=*)
        rule="${line#rule=}"
        firewall_parse_rule "${rule}" || return 1
        DEPLOY_FIREWALL_RULES+=("${rule}")
        ;;
      *) return 1 ;;
    esac
  done < "${descriptor}"
  [ "${schema_count}" -eq 1 ] || return 1
  firewall_normalize_rules "${DEPLOY_FIREWALL_RULES[@]}" || return 1
  [ "${#FIREWALL_NORMALIZED_RULES[@]}" -eq "${#DEPLOY_FIREWALL_RULES[@]}" ] || return 1
  DEPLOY_FIREWALL_RULES=("${FIREWALL_NORMALIZED_RULES[@]}")
}
