#!/usr/bin/env bash
# Certificate resource primitive: validate, atomically install, and restore local files.

set -o pipefail

OPENSSL_BIN="${OPENSSL_BIN:-openssl}"
GETENT_BIN="${GETENT_BIN:-getent}"
SS_BIN="${SS_BIN:-ss}"
ACME_BIN="${ACME_BIN:-acme.sh}"

certificate_validate_domain() {
  [ "${#1}" -le 253 ] && [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]
}

certificate_validate_ipv4() {
  local ip="$1" part
  [[ "${ip}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS='.' read -r -a parts <<< "${ip}"
  for part in "${parts[@]}"; do [ "${part}" -le 255 ] || return 1; done
}

certificate_precheck_dns() {
  local domain="$1" expected_ipv4="$2" addresses
  certificate_validate_domain "${domain}" || return 1
  certificate_validate_ipv4 "${expected_ipv4}" || return 1
  addresses="$("${GETENT_BIN}" ahostsv4 "${domain}" 2>/dev/null | awk '{print $1}' | sort -u)" || return 1
  [ -n "${addresses}" ] || return 1
  printf 'dns-domain=%s\ndns-addresses=%s\n' "${domain}" "$(tr '\n' ',' <<< "${addresses}" | sed 's/,$//')"
  grep -Fx "${expected_ipv4}" <<< "${addresses}" >/dev/null || return 1
  printf '%s\n' 'dns-match=true'
}

certificate_observe_tcp80() {
  local listeners
  listeners="$("${SS_BIN}" -ltn 2>/dev/null | awk '{print $4}' | grep -E '[:.]80$' || true)"
  if [ -n "${listeners}" ]; then
    printf 'tcp-80-listener=present\ntcp-80-addresses=%s\n' "$(tr '\n' ',' <<< "${listeners}" | sed 's/,$//')"
  else
    printf '%s\n' 'tcp-80-listener=none'
  fi
}

certificate_issue_candidate() {
  # HTTP-01 ownership and DNS checks are intentionally performed by the caller first.
  local domain="$1" candidate_dir="$2" dry_run="${3:-false}"
  certificate_validate_domain "${domain}" || return 1
  [ "${dry_run}" = true ] && return 0
  mkdir -p "${candidate_dir}" || return 1
  chmod 700 "${candidate_dir}" || return 1
  "${ACME_BIN}" --issue --standalone -d "${domain}" || return 1
  "${ACME_BIN}" --install-cert -d "${domain}" --fullchain-file "${candidate_dir}/cert.pem" --key-file "${candidate_dir}/key.pem" || return 1
  certificate_validate_candidate "${candidate_dir}/cert.pem" "${candidate_dir}/key.pem"
}

certificate_build_renew_timer() {
  local service_unit="$1" renew_command="$2"
  [[ "${service_unit}" =~ ^[A-Za-z0-9][A-Za-z0-9_.@-]*\.service$ ]] || return 1
  [ -n "${renew_command}" ] || return 1
  printf '%s\n' '[Unit]' 'Description=proxy-installer certificate renewal' '' '[Timer]' 'OnCalendar=daily' 'Persistent=true' '' '[Install]' 'WantedBy=timers.target' '' '[Service]' 'Type=oneshot' "ExecStart=${renew_command}" "# reload-target=${service_unit}"
}

certificate_validate_candidate() {
  local certificate_file="$1" key_file="$2"
  [ -f "${certificate_file}" ] && [ -f "${key_file}" ] || return 1
  "${OPENSSL_BIN}" x509 -in "${certificate_file}" -noout >/dev/null 2>&1 || return 1
  "${OPENSSL_BIN}" pkey -in "${key_file}" -noout >/dev/null 2>&1
}

certificate_install_candidate() {
  local certificate_file="$1" key_file="$2" active_dir="$3" dry_run="${4:-false}"
  certificate_validate_candidate "${certificate_file}" "${key_file}" || return 1
  [ "${dry_run}" = true ] && return 0
  mkdir -p "${active_dir}" || return 1
  local cert_tmp="${active_dir}/.cert.pem.tmp.$$" key_tmp="${active_dir}/.key.pem.tmp.$$"
  cp "${certificate_file}" "${cert_tmp}" && cp "${key_file}" "${key_tmp}" || { rm -f "${cert_tmp}" "${key_tmp}"; return 1; }
  chmod 600 "${cert_tmp}" "${key_tmp}" || { rm -f "${cert_tmp}" "${key_tmp}"; return 1; }
  mv -f "${cert_tmp}" "${active_dir}/cert.pem" && mv -f "${key_tmp}" "${active_dir}/key.pem" || { rm -f "${cert_tmp}" "${key_tmp}"; return 1; }
}

certificate_restore() {
  local snapshot_dir="$1" active_dir="$2" dry_run="${3:-false}"
  certificate_install_candidate "${snapshot_dir}/cert.pem" "${snapshot_dir}/key.pem" "${active_dir}" "${dry_run}"
}
