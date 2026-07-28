#!/usr/bin/env bash
# TLS preflight and candidate issuance for enabled AnyTLS/Hysteria2 domains.

set -o pipefail

DEPLOY_CERT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${DEPLOY_CERT_DIR}/../.." && pwd)"
source "${PROJECT_ROOT}/lib/config/state.sh"
source "${PROJECT_ROOT}/lib/resources/certificate.sh"

deploy_certificates_domains() {
  local config_path="$1" domains count
  domains="$(state_deployment_domains "${config_path}")" || return 1
  count="$(awk 'NF { count++ } END { print count + 0 }' <<< "${domains}")" || return 1
  if [ "${count}" -gt 1 ]; then
    printf '%s\n' 'AnyTLS 和 Hysteria2 必须使用同一个域名，因为它们共用同一套证书。' >&2
    return 1
  fi
  [ -z "${domains}" ] || printf '%s\n' "${domains}"
}

deploy_certificates_preflight() {
  # config-path, server-public-ip
  [ "$#" -eq 2 ] || return 2
  local config_path="$1" public_ip="$2" domains domain tcp80
  certificate_validate_ipv4 "${public_ip}" || return 1
  domains="$(deploy_certificates_domains "${config_path}")" || return 1
  if [ -z "${domains}" ]; then printf '%s\n' 'tls=not-required'; return 0; fi
  tcp80="$(certificate_observe_tcp80)" || return 1
  printf '%s\n' "${tcp80}"
  grep -Fx 'tcp-80-listener=none' <<< "${tcp80}" >/dev/null || return 1
  while IFS= read -r domain; do [ -z "${domain}" ] || certificate_precheck_dns "${domain}" "${public_ip}" || return 1; done <<< "${domains}"
  printf '%s\n' 'certificate-preflight=passed'
}

deploy_certificates_prepare_candidates() {
  # config-path, server-public-ip, candidate-root, dry-run
  [ "$#" -eq 4 ] || return 2
  local config_path="$1" public_ip="$2" candidate_root="$3" dry_run="$4" domain domains
  [[ "${dry_run}" =~ ^(true|false)$ ]] || return 2
  deploy_certificates_preflight "${config_path}" "${public_ip}" || return 1
  domains="$(deploy_certificates_domains "${config_path}")" || return 1
  [ -z "${domains}" ] && return 0
  [[ "${candidate_root}" = /* ]] || return 1
  while IFS= read -r domain; do
    [ -z "${domain}" ] || certificate_issue_candidate "${domain}" "${candidate_root}/${domain}" "${dry_run}" || return 1
    [ -z "${domain}" ] || printf 'certificate-candidate=%s/%s\n' "${candidate_root}" "${domain}"
  done <<< "${domains}"
}
