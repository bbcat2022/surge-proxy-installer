#!/usr/bin/env bash
# Verified GitHub Release installer. It installs this manager, not proxy protocols.

set -euo pipefail

INSTALL_ROOT="${INSTALL_ROOT:-/opt/proxy-installer}"
CONFIG_ROOT="${CONFIG_ROOT:-/etc/proxy-installer}"
BIN_PATH="${BIN_PATH:-/usr/local/sbin/proxy-installer}"
APT_BIN="${APT_BIN:-apt-get}"
CURL_BIN="${CURL_BIN:-curl}"
TAR_BIN="${TAR_BIN:-tar}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
INSTALL_EUID="${INSTALL_EUID:-${EUID}}"
SKIP_DEPENDENCIES=false
RELEASE_URL=""
EXPECTED_SHA256=""
RELEASE_VERSION=""

usage() {
  printf '%s\n' \
    'usage: install.sh --release-url <https-url> --sha256 <64-hex> [--version <tag>] [--skip-dependencies]' \
    'This bootstrap verifies the release archive, installs the manager, and initializes an empty configuration.'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --release-url) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; RELEASE_URL="$2"; shift 2 ;;
    --sha256) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; EXPECTED_SHA256="$2"; shift 2 ;;
    --version) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; RELEASE_VERSION="$2"; shift 2 ;;
    --skip-dependencies) SKIP_DEPENDENCIES=true; shift ;;
    *) usage >&2; exit 2 ;;
  esac
done

[ "${INSTALL_EUID}" -eq 0 ] || { printf '%s\n' 'failed=root-required' >&2; exit 1; }
[[ "${RELEASE_URL}" =~ ^https:// ]] || { printf '%s\n' 'failed=https-release-url-required' >&2; exit 2; }
[[ "${EXPECTED_SHA256}" =~ ^[A-Fa-f0-9]{64}$ ]] || { printf '%s\n' 'failed=sha256-required' >&2; exit 2; }
[ ! -e "${INSTALL_ROOT}" ] || { printf '%s\n' 'failed=install-root-already-exists; use the manager update workflow' >&2; exit 1; }

if [ "${SKIP_DEPENDENCIES}" = false ]; then
  "${APT_BIN}" update
  "${APT_BIN}" install -y \
    ca-certificates curl tar unzip python3 python3-yaml qrencode \
    openssl iproute2 nftables socat acme.sh
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT
archive="${work_dir}/release.tar.gz"
"${CURL_BIN}" --fail --location --silent --show-error --output "${archive}" "${RELEASE_URL}"
actual_sha256="$(sha256sum "${archive}" | awk '{print $1}')"
expected_sha256="$(printf '%s' "${EXPECTED_SHA256}" | tr '[:upper:]' '[:lower:]')"
[ "${actual_sha256}" = "${expected_sha256}" ] || { printf '%s\n' 'failed=release-checksum-mismatch' >&2; exit 1; }
"${TAR_BIN}" -tzf "${archive}" | grep -Fx 'proxy-installer/bin/proxy-installer.sh' >/dev/null || { printf '%s\n' 'failed=release-layout-invalid' >&2; exit 1; }
"${TAR_BIN}" -C "${work_dir}" -xzf "${archive}"

mkdir -p "$(dirname "${INSTALL_ROOT}")" "${CONFIG_ROOT}" "$(dirname "${BIN_PATH}")"
chmod 700 "${CONFIG_ROOT}"
mv "${work_dir}/proxy-installer" "${INSTALL_ROOT}"
chmod 755 "${INSTALL_ROOT}/bin/proxy-installer.sh"
"${PYTHON_BIN}" "${INSTALL_ROOT}/tools/config_tool.py" --config "${CONFIG_ROOT}/config.yaml" init >/dev/null
temporary_bin="$(dirname "${BIN_PATH}")/.$(basename "${BIN_PATH}").tmp.$$"
printf '%s\n' '#!/usr/bin/env bash' "export PROXY_INSTALLER_CONFIG=\"${CONFIG_ROOT}/config.yaml\"" "exec \"${INSTALL_ROOT}/bin/proxy-installer.sh\" \"\$@\"" > "${temporary_bin}"
chmod 755 "${temporary_bin}"
mv -f "${temporary_bin}" "${BIN_PATH}"
printf '%s\n' "version=${RELEASE_VERSION:-unknown}" "release_url=${RELEASE_URL}" > "${INSTALL_ROOT}/INSTALL-MANIFEST"
chmod 600 "${INSTALL_ROOT}/INSTALL-MANIFEST"
printf '%s\n' 'success=manager-installed' "command=${BIN_PATH}" "config=${CONFIG_ROOT}/config.yaml"
