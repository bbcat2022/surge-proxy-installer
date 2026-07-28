#!/usr/bin/env bash
# Firewall resource primitive. It consumes explicit transport plans only.

set -o pipefail

UFW_BIN="${UFW_BIN:-ufw}"
NFT_BIN="${NFT_BIN:-nft}"
FIREWALL_NORMALIZED_RULES=()
FIREWALL_APPLIED_RULES=()
FIREWALL_TOOL_REASON=explicit
FIREWALL_EFFECTIVE_TOOL=manual

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

firewall_normalize_rules() {
  local rule existing duplicate
  [ "$#" -gt 0 ] || return 1
  FIREWALL_NORMALIZED_RULES=()
  for rule in "$@"; do
    firewall_parse_rule "${rule}" || return 1
    duplicate=false
    for existing in "${FIREWALL_NORMALIZED_RULES[@]}"; do
      [ "${existing}" != "${rule}" ] || { duplicate=true; break; }
    done
    [ "${duplicate}" = true ] || FIREWALL_NORMALIZED_RULES+=("${rule}")
  done
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
    case "${FIREWALL_TOOL_OVERRIDE}" in
      ufw|nftables|manual) printf '%s\n' "${FIREWALL_TOOL_OVERRIDE}" ;;
      *) printf '%s\n' manual ;;
    esac
  elif command -v "${UFW_BIN}" >/dev/null 2>&1; then
    printf '%s\n' 'ufw'
  elif command -v "${NFT_BIN}" >/dev/null 2>&1; then
    printf '%s\n' 'nftables'
  else
    printf '%s\n' 'manual'
  fi
}

firewall_command_available() {
  local command_path="$1"
  if [[ "${command_path}" = */* ]]; then
    [ -f "${command_path}" ] && [ -x "${command_path}" ]
  else
    command -v "${command_path}" >/dev/null 2>&1
  fi
}

firewall_resolve_tool() {
  [ "$#" -eq 2 ] || return 2
  local mode="$1" requested="$2" status
  FIREWALL_EFFECTIVE_TOOL=manual
  case "${mode}" in
    manual)
      FIREWALL_TOOL_REASON=requested-manual
      printf '%s\n' manual
      return 0
      ;;
    auto) ;;
    *) return 1 ;;
  esac
  case "${requested}" in
    manual)
      FIREWALL_TOOL_REASON=no-supported-tool
      printf '%s\n' manual
      ;;
    ufw)
      if ! firewall_command_available "${UFW_BIN}"; then
        FIREWALL_TOOL_REASON=ufw-command-missing
        printf '%s\n' manual
        return 0
      fi
      status="$(LC_ALL=C "${UFW_BIN}" status 2>/dev/null)" || {
        FIREWALL_TOOL_REASON=ufw-status-failed
        printf '%s\n' manual
        return 0
      }
      if printf '%s\n' "${status}" | awk '$1 == "Status:" && $2 == "active" { found=1 } END { exit !found }'; then
        FIREWALL_TOOL_REASON=ufw-active-persistent
        FIREWALL_EFFECTIVE_TOOL=ufw
        printf '%s\n' ufw
      else
        FIREWALL_TOOL_REASON=ufw-inactive
        printf '%s\n' manual
      fi
      ;;
    nftables)
      if ! firewall_command_available "${NFT_BIN}"; then
        FIREWALL_TOOL_REASON=nft-command-missing
      elif ! "${NFT_BIN}" list chain inet filter input >/dev/null 2>&1; then
        FIREWALL_TOOL_REASON=nft-input-chain-unavailable
      else
        FIREWALL_TOOL_REASON=nft-persistence-unmanaged
      fi
      printf '%s\n' manual
      ;;
    *) return 1 ;;
  esac
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
  [ "$#" -ge 4 ] || return 2
  local mode="$1" tool="$2" dry_run="$3"
  shift 3
  local rule
  FIREWALL_NORMALIZED_RULES=()
  FIREWALL_APPLIED_RULES=()
  case "${mode}" in manual|auto) ;; *) return 1 ;; esac
  case "${tool}" in ufw|nftables|manual) ;; *) return 1 ;; esac
  [[ "${dry_run}" =~ ^(true|false)$ ]] || return 1
  firewall_normalize_rules "$@" || return 1
  if [ "${mode}" = "manual" ] || [ "${tool}" = "manual" ]; then
    firewall_render_manual "${FIREWALL_NORMALIZED_RULES[@]}"
    return 0
  fi
  [ "${dry_run}" = "true" ] && { firewall_render_manual "${FIREWALL_NORMALIZED_RULES[@]}"; return 0; }
  for rule in "${FIREWALL_NORMALIZED_RULES[@]}"; do
    firewall_parse_rule "${rule}" || return 1
    if [ "${tool}" = "ufw" ]; then
      firewall_apply_ufw_rule "${FIREWALL_RULE_KIND}" "${FIREWALL_RULE_VALUE}" || return 1
    else
      firewall_apply_nft_rule "${FIREWALL_RULE_KIND}" "${FIREWALL_RULE_VALUE}" || return 1
    fi
    FIREWALL_APPLIED_RULES+=("${rule}")
  done
}

firewall_write_context() {
  [ "$#" -ge 5 ] && [ "$#" -le 6 ] || return 2
  local context_file="$1" status="$2" requested_mode="$3" tool="$4" dry_run="$5" failed_rule="${6:-}" temporary rule
  [[ "${context_file}" = /* ]] && [ "${context_file}" != / ] && [ ! -L "${context_file}" ] || return 1
  case "${status}" in success|failed) ;; *) return 1 ;; esac
  case "${requested_mode}" in manual|auto) ;; *) return 1 ;; esac
  case "${tool}" in ufw|nftables|manual) ;; *) return 1 ;; esac
  [[ "${dry_run}" =~ ^(true|false)$ ]] || return 1
  [[ "${FIREWALL_TOOL_REASON:-}" =~ ^[a-z0-9][a-z0-9-]{0,63}$ ]] || return 1
  [ -z "${failed_rule}" ] || firewall_parse_rule "${failed_rule}" || return 1
  temporary="$(dirname "${context_file}")/.$(basename "${context_file}").tmp.$$"
  mkdir -p "$(dirname "${context_file}")" || return 1
  [ ! -e "${temporary}" ] && [ ! -L "${temporary}" ] || return 1
  {
    printf 'status=%s\nrequested_mode=%s\ntool=%s\ntool_resolution=%s\ndry_run=%s\n' "${status}" "${requested_mode}" "${tool}" "${FIREWALL_TOOL_REASON}" "${dry_run}"
    printf '%s\n' 'cloud_security_group=unconfirmed' 'automatic_rollback=false' 'rollback=manual-review-required'
    [ -z "${failed_rule}" ] || printf 'failed_rule=%s\n' "${failed_rule}"
    for rule in "${FIREWALL_NORMALIZED_RULES[@]}"; do printf 'planned_rule=%s\n' "${rule}"; done
    for rule in "${FIREWALL_APPLIED_RULES[@]}"; do printf 'processed_rule=%s\n' "${rule}"; done
  } > "${temporary}" &&
    chmod 600 "${temporary}" &&
    mv -f "${temporary}" "${context_file}" || { rm -f "${temporary}"; return 1; }
}

firewall_apply_with_context() {
  # context-file mode tool dry-run explicit-rules...
  [ "$#" -ge 5 ] || return 2
  local context_file="$1" mode="$2" tool="$3" dry_run="$4" result=0 failed_rule=''
  shift 4
  firewall_apply "${mode}" "${tool}" "${dry_run}" "$@" || result=$?
  if [ "${result}" -ne 0 ]; then
    if [ "${#FIREWALL_APPLIED_RULES[@]}" -lt "${#FIREWALL_NORMALIZED_RULES[@]}" ]; then
      failed_rule="${FIREWALL_NORMALIZED_RULES[${#FIREWALL_APPLIED_RULES[@]}]}"
    fi
    firewall_write_context "${context_file}" failed "${mode}" "${tool}" "${dry_run}" "${failed_rule}" || return 1
    return "${result}"
  fi
  firewall_write_context "${context_file}" success "${mode}" "${tool}" "${dry_run}" || return 1
}

firewall_context_requires_manual_rollback() {
  [ "$#" -eq 1 ] || return 2
  local context_file="$1"
  [ -f "${context_file}" ] && [ ! -L "${context_file}" ] || return 2
  grep -q '^automatic_rollback=false$' "${context_file}" || return 2
  grep -q '^processed_rule=' "${context_file}"
}

firewall_rollback_from_context() {
  [ "$#" -eq 1 ] || return 2
  local context_file="$1" rule check=0
  firewall_context_requires_manual_rollback "${context_file}" || check=$?
  case "${check}" in
    1) return 0 ;;
    2) return 1 ;;
  esac
  while IFS= read -r rule; do
    rule="${rule#processed_rule=}"
    firewall_parse_rule "${rule}" || return 1
    printf 'manual-firewall-review=%s\n' "${rule}" >&2
  done < <(grep '^processed_rule=' "${context_file}")
  return 1
}
