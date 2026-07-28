#!/usr/bin/env bash
# Hysteria2 content builder; port-range redirect is declared for the orchestrator.

set -o pipefail

hy2_port() { [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; }
hy2_secret() { [ "${#1}" -ge 8 ] && [ "${#1}" -le 128 ] && [[ "$1" =~ ^[A-Za-z0-9._~+/=-]+$ ]]; }
hy2_domain() { [ "${#1}" -le 253 ] && [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]; }
hy2_range() { [[ "$1" =~ ^[0-9]+-[0-9]+$ ]] || return 1; local a="${1%-*}" b="${1#*-}"; hy2_port "$a" && hy2_port "$b" && [ "$a" -le "$b" ]; }
hy2_validate() { hy2_port "$1" && hy2_secret "$2" && hy2_domain "$3" && [ -n "$4" ] && [ -n "$5" ] && { [ -z "$6" ] || hy2_range "$6"; } && { [ -z "$6" ] || { [ "$1" -lt "${6%-*}" ] || [ "$1" -gt "${6#*-}" ]; }; } && [[ "$7" =~ ^[0-9]+$ ]] && [ "$7" -ge 5 ] && { [ "$8" = false ] || hy2_secret "$9"; }; }

hy2_build_runtime() {
  local port="$1" password="$2" domain="$3" cert="$4" key="$5" range="$6" interval="$7" gecko="$8" gecko_password="$9"
  hy2_validate "$@" || return 1
  printf 'listen: :%s\ntls:\n  cert: %s\n  key: %s\nauth:\n  type: password\n  password: %s\n' "$port" "$cert" "$key" "$password"
  if [ "$gecko" = true ]; then printf 'obfs:\n  type: gecko\n  gecko:\n    password: %s\n    minPacketSize: 512\n    maxPacketSize: 1200\n' "$gecko_password"; fi
}
hy2_build_unit() { [ -n "$1" ] && [ -n "$2" ] || return 1; printf '%s\n' '[Unit]' 'Description=proxy-installer Hysteria2 service' 'After=network-online.target' '' '[Service]' 'Type=simple' "ExecStart=$1 server -c $2" 'Restart=on-failure' '' '[Install]' 'WantedBy=multi-user.target'; }
hy2_build_port_hop_runtime() {
  local range="$1" listen_port="$2"
  hy2_range "${range}" && hy2_port "${listen_port}" || return 1
  [ "${listen_port}" -lt "${range%-*}" ] || [ "${listen_port}" -gt "${range#*-}" ] || return 1
  printf '%s\n' 'table inet proxy_installer_hy2 {' '  chain prerouting {' '    type nat hook prerouting priority dstnat; policy accept;' "    udp dport ${range} redirect to :${listen_port}" '  }' '}'
}
hy2_build_port_hop_unit() {
  local runtime_path="$1"
  [[ "${runtime_path}" = /* ]] || return 1
  printf '%s\n' '[Unit]' 'Description=proxy-installer Hysteria2 port hopping rules' 'Before=proxy-installer-hysteria2.service' 'After=network-online.target' '' '[Service]' 'Type=oneshot' 'RemainAfterExit=true' 'ExecStartPre=-/usr/sbin/nft delete table inet proxy_installer_hy2' "ExecStart=/usr/sbin/nft -f ${runtime_path}" 'ExecStop=-/usr/sbin/nft delete table inet proxy_installer_hy2' '' '[Install]' 'WantedBy=multi-user.target'
}
hy2_build_surge_entry() {
  local name="$1" port="$2" password="$3" domain="$4" range="$5" interval="$6" gecko="$7" gecko_password="$8" download="$9"
  hy2_port "$port" && hy2_secret "$password" && hy2_domain "$domain" && [[ "$download" =~ ^[0-9]+$ ]] || return 1
  local options="password=${password}, download-bandwidth=${download}"
  [ -z "$range" ] || { hy2_range "$range" && options+=", port-hopping=${range}, port-hopping-interval=${interval}"; }
  [ "$gecko" = false ] || { hy2_secret "$gecko_password" || return 1; options+=", gecko-password=${gecko_password}"; }
  printf '%s = hysteria2, %s, %s, %s\n' "$name" "$domain" "$port" "$options"
}
hy2_build_config_patch() {
  local port="$1" password="$2" domain="$3" range="$4" interval="$5" gecko="$6" gecko_password="$7" download="$8"
  hy2_validate "${port}" "${password}" "${domain}" /candidate/cert.pem /candidate/key.pem "${range}" "${interval}" "${gecko}" "${gecko_password}" || return 1
  [[ "${download}" =~ ^[0-9]+$ ]] || return 1
  printf '{"desired":{"protocols":{"hysteria2":{"enabled":true,"port":%s,"password":"%s","domain":"%s","port_hopping_range":"%s","hop_interval":%s,"gecko":%s,"gecko_password":"%s","download_bandwidth":%s}}}}\n' "${port}" "${password}" "${domain}" "${range}" "${interval}" "${gecko}" "${gecko_password}" "${download}"
}
hy2_resource_requirements() { hy2_port "$1" || return 1; printf '%s\n' 'binary=hysteria' 'service=proxy-installer-hysteria2.service' "network=udp:$1" 'certificate=shared-main-domain' 'health=systemd-active,udp-listen,binary-version'; [ -z "$2" ] || { hy2_range "$2" && printf 'network=udp-range:%s\nport-hop-redirect=required\n' "$2"; }; }
