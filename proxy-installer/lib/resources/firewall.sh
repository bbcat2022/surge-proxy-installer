#!/usr/bin/env bash
# Firewall resource primitive. It consumes explicit transport plans only.

set -o pipefail

UFW_BIN="${UFW_BIN:-ufw}"
NFT_BIN="${NFT_BIN:-nft}"

firewall_validate_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

firewall_validate_rule() {
  local kind="$1" value="$2" first last
  case "${kind}" in
    tcp|udp) firewall_validate_port "${value}" ;;
    udp-range)
      [[ "${value}" =~ ^[0-9]+-[0-9]+$ ]] || return 1
      first="${value%-*}"; last="${value#*-}"
      firewall_validate_port "${first}" && firewall_validate_port "${last}" && [ "${first}" -le "${last}" ]
      ;;
    *) return 1 ;;
  esac
}

firewall_parse_rule() {
  local rule="$1"
  FIREWALL_RULE_KIND="${rule%%:*}"
  FIREWALL_RULE_VALUE="${rule#*:}"
  [ "${FIREWALL_RULE_KIND}" != "${rule}" ] && firewall_validate_rule "${FIREWALL_RULE_KIND}" "${FIREWALL_RULE_VALUE}"
}

firewall_render_manual() {
  local rule
  for rule in "$@"; do
    firewall_parse_rule "${rule}" || return 1
    printf 'allow %s %s\n' "${FIREWALL_RULE_KIND}" "${FIREWALL_RULE_VALUE}"
  done
  printf '%s\n' 'cloud-security-group: confirm these same rules separately'
}

firewall_detect_tool() {
  if [ -n "${FIREWALL_TOOL_OVERRIDE:-}" ]; then
    printf '%s\n' "${FIREWALL_TOOL_OVERRIDE}"
  elif command -v "${UFW_BIN}" >/dev/null 2>&1; then
    printf '%s\n' 'ufw'
  elif command -v "${NFT_BIN}" >/dev/null 2>&1; then
    printf '%s\n' 'nftables'
  else
    printf '%s\n' 'manual'
  fi
}

firewall_apply_ufw_rule() {
  local kind="$1" value="$2"
  case "${kind}" in
    tcp|udp) "${UFW_BIN}" allow "${value}/${kind}" ;;
    udp-range) "${UFW_BIN}" allow "${value}/udp" ;;
  esac
}

firewall_apply_nft_rule() {
  local kind="$1" value="$2"
  case "${kind}" in
    tcp|udp) "${NFT_BIN}" add rule inet filter input "${kind}" dport "${value}" accept ;;
    udp-range) "${NFT_BIN}" add rule inet filter input udp dport "${value}" accept ;;
  esac
}

firewall_apply() {
  local mode="$1" tool="$2" dry_run="$3"
  shift 3
  local rule
  for rule in "$@"; do firewall_parse_rule "${rule}" || return 1; done
  if [ "${mode}" = "manual" ] || [ "${tool}" = "manual" ]; then
    firewall_render_manual "$@"
    return 0
  fi
  [ "${mode}" = "auto" ] || return 1
  case "${tool}" in ufw|nftables) ;; *) return 1 ;; esac
  [ "${dry_run}" = "true" ] && { firewall_render_manual "$@"; return 0; }
  for rule in "$@"; do
    firewall_parse_rule "${rule}" || return 1
    if [ "${tool}" = "ufw" ]; then
      firewall_apply_ufw_rule "${FIREWALL_RULE_KIND}" "${FIREWALL_RULE_VALUE}" || return 1
    else
      firewall_apply_nft_rule "${FIREWALL_RULE_KIND}" "${FIREWALL_RULE_VALUE}" || return 1
    fi
  done
}
