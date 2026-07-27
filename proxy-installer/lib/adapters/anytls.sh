#!/usr/bin/env bash
# AnyTLS/sing-box content builder; no file or system side effects.

set -o pipefail

anytls_validate_port() { [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; }
anytls_validate_domain() { [ "${#1}" -le 253 ] && [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]; }
anytls_validate_password() { [ "${#1}" -ge 8 ] && [ "${#1}" -le 128 ] && [[ "$1" =~ ^[A-Za-z0-9._~+/=-]+$ ]]; }
anytls_validate() { anytls_validate_port "$1" && anytls_validate_password "$2" && anytls_validate_domain "$3" && [ -n "$4" ] && [ -n "$5" ]; }

anytls_build_runtime() {
  local port="$1" password="$2" domain="$3" certificate_path="$4" key_path="$5"
  anytls_validate "${port}" "${password}" "${domain}" "${certificate_path}" "${key_path}" || return 1
  printf '{"inbounds":[{"type":"anytls","tag":"anytls-in","listen":"::","listen_port":%s,"users":[{"name":"default","password":"%s"}],"tls":{"enabled":true,"server_name":"%s","certificate_path":"%s","key_path":"%s"}}]}\n' "${port}" "${password}" "${domain}" "${certificate_path}" "${key_path}"
}

anytls_build_unit() {
  local binary_path="$1" runtime_path="$2"
  [ -n "${binary_path}" ] && [ -n "${runtime_path}" ] || return 1
  printf '%s\n' '[Unit]' 'Description=proxy-installer AnyTLS service' 'After=network-online.target' '' '[Service]' 'Type=simple' "ExecStart=${binary_path} run -c ${runtime_path}" 'Restart=on-failure' '' '[Install]' 'WantedBy=multi-user.target'
}

anytls_build_surge_entry() {
  local name="$1" port="$2" password="$3" domain="$4" tfo="$5" reuse="$6"
  anytls_validate_port "${port}" && anytls_validate_password "${password}" && anytls_validate_domain "${domain}" || return 1
  [[ "${tfo}" =~ ^(true|false)$ ]] && [[ "${reuse}" =~ ^(true|false)$ ]] || return 1
  printf '%s = anytls, %s, %s, password=%s, tfo=%s, reuse=%s\n' "${name}" "${domain}" "${port}" "${password}" "${tfo}" "${reuse}"
}

anytls_build_config_patch() {
  local port="$1" password="$2" domain="$3" tfo="$4" reuse="$5"
  anytls_validate_port "${port}" && anytls_validate_password "${password}" && anytls_validate_domain "${domain}" || return 1
  [[ "${tfo}" =~ ^(true|false)$ ]] && [[ "${reuse}" =~ ^(true|false)$ ]] || return 1
  printf '{"desired":{"protocols":{"anytls":{"enabled":true,"port":%s,"password":"%s","domain":"%s","tfo":%s,"reuse":%s}}}}\n' "${port}" "${password}" "${domain}" "${tfo}" "${reuse}"
}

anytls_resource_requirements() { anytls_validate_port "$1" || return 1; printf '%s\n' 'binary=sing-box' 'service=proxy-installer-anytls.service' "network=tcp:$1" 'certificate=shared-main-domain' 'health=systemd-active,tcp-listen,binary-version'; }
