#!/usr/bin/env bash
# Snell v6 content builder. It deliberately has no file or system side effects.

set -o pipefail

snell_validate_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

snell_validate_psk() {
  [ "${#1}" -ge 12 ] && [ "${#1}" -le 255 ] && [[ "$1" =~ ^[A-Za-z0-9._~+/=-]+$ ]]
}

snell_validate_ipv4() {
  local ip="$1" part
  [[ "${ip}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
  IFS='.' read -r -a parts <<< "${ip}"
  for part in "${parts[@]}"; do [ "${part}" -le 255 ] || return 1; done
}

snell_validate_ipv6() {
  [ "${#1}" -le 45 ] && [[ "$1" =~ ^[0-9A-Fa-f:.]+$ ]] && [[ "$1" == *:* ]]
}

snell_validate_domain() {
  [ "${#1}" -le 253 ] && [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]
}

snell_validate() {
  local port="$1" psk="$2" address_type="$3" address="$4" mode="$5"
  snell_validate_port "${port}" || return 1
  snell_validate_psk "${psk}" || return 1
  [ "${mode}" = "default" ] || return 1
  case "${address_type}" in
    ip) snell_validate_ipv4 "${address}" || snell_validate_ipv6 "${address}" ;;
    domain) snell_validate_domain "${address}" ;;
    *) return 1 ;;
  esac
}

snell_build_runtime() {
  local port="$1" psk="$2" address_type="$3" address="$4" mode="$5"
  snell_validate "${port}" "${psk}" "${address_type}" "${address}" "${mode}" || return 1
  printf '%s\n' '[snell-server]' "listen = 0.0.0.0:${port}" "psk = ${psk}" "mode = ${mode}" 'dns-ip-preference = default'
}

snell_build_unit() {
  local binary_path="$1" runtime_path="$2"
  [ -n "${binary_path}" ] && [ -n "${runtime_path}" ] || return 1
  printf '%s\n' '[Unit]' 'Description=proxy-installer Snell v6 service' 'After=network-online.target' 'Wants=network-online.target' '' '[Service]' 'Type=simple' "ExecStart=${binary_path} -c ${runtime_path}" 'Restart=on-failure' 'RestartSec=3' 'NoNewPrivileges=true' '' '[Install]' 'WantedBy=multi-user.target'
}

snell_build_surge_entry() {
  local name="$1" port="$2" psk="$3" address_type="$4" address="$5" mode="$6"
  [ -n "${name}" ] || return 1
  snell_validate "${port}" "${psk}" "${address_type}" "${address}" "${mode}" || return 1
  printf '%s = snell, %s, %s, psk=%s, version=6\n' "${name}" "${address}" "${port}" "${psk}"
}

snell_resource_requirements() {
  local port="$1"
  snell_validate_port "${port}" || return 1
  printf '%s\n' 'binary=snell-server' 'service=proxy-installer-snell.service' "network=tcp:${port}" 'health=systemd-active,tcp-listen,binary-version'
}

snell_build_config_patch() {
  local port="$1" psk="$2" address_type="$3" address="$4" mode="$5"
  snell_validate "${port}" "${psk}" "${address_type}" "${address}" "${mode}" || return 1
  printf '{"desired":{"protocols":{"snell":{"enabled":true,"port":%s,"psk":"%s","client_address_type":"%s","client_address":"%s","mode":"default"}}}}\n' "${port}" "${psk}" "${address_type}" "${address}"
}
