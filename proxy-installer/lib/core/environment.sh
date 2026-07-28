#!/usr/bin/env bash
# Target-environment capability checks. No packages are installed here.

set -o pipefail

environment_check() {
  local os_release="${ENV_OS_RELEASE:-/etc/os-release}" arch="${ENV_ARCH:-$(uname -m)}" init="${ENV_INIT:-systemd}" python_bin="${ENV_PYTHON_BIN:-python3}"
  [ "${ENV_EUID:-${EUID}}" -eq 0 ] || { printf '%s\n' 'failed=root-required'; return 1; }
  [ -f "${os_release}" ] || { printf '%s\n' 'failed=os-release-missing'; return 1; }
  local os_id version
  os_id="$(awk -F= '$1=="ID" {gsub(/"/,"",$2); print $2}' "${os_release}")"
  version="$(awk -F= '$1=="VERSION_ID" {gsub(/"/,"",$2); print $2}' "${os_release}")"
  [ "${os_id}" = debian ] && [ "${version}" = 13 ] || { printf '%s\n' 'failed=debian-13-required'; return 1; }
  [ "${arch}" = x86_64 ] || { printf '%s\n' 'failed=amd64-required'; return 1; }
  [ "${init}" = systemd ] || { printf '%s\n' 'failed=systemd-required'; return 1; }
  command -v "${python_bin}" >/dev/null 2>&1 || { printf '%s\n' 'failed=python3-required'; return 1; }
  printf '%s\n' 'success=environment-ready' "firewall-mode=${ENV_FIREWALL_MODE:-manual}"
}

environment_check_deploy_tools() {
  local label command failed=0
  while IFS='|' read -r label command; do
    if ! command -v "${command}" >/dev/null 2>&1; then
      printf 'failed=missing-command:%s\n' "${label}"
      failed=1
    fi
  done <<EOF
curl|${CURL_BIN:-curl}
tar|${TAR_BIN:-tar}
unzip|${UNZIP_BIN:-unzip}
openssl|${OPENSSL_BIN:-openssl}
ss|${SS_BIN:-ss}
nft|${NFT_BIN:-nft}
acme.sh|${ACME_BIN:-acme.sh}
systemctl|${SYSTEMCTL_BIN:-systemctl}
EOF
  [ "${failed}" -eq 0 ] || return 1
  printf '%s\n' 'success=deploy-tools-ready'
}
