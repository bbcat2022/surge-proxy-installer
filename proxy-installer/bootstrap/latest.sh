#!/usr/bin/env bash
# Install the newest published proxy-installer release from its fixed GitHub location.

set -euo pipefail

REPOSITORY="${PROXY_INSTALLER_REPOSITORY:-bbcat2022/surge-proxy-installer}"
RAW_REF="${PROXY_INSTALLER_RAW_REF:-main}"
CURL_BIN="${CURL_BIN:-curl}"
BASH_BIN="${BASH_BIN:-bash}"
RELEASE_URL="${PROXY_INSTALLER_RELEASE_URL:-https://github.com/${REPOSITORY}/releases/latest/download/proxy-installer-local.tar.gz}"
CHECKSUM_URL="${PROXY_INSTALLER_CHECKSUM_URL:-${RELEASE_URL}.sha256}"
INSTALLER_URL="${PROXY_INSTALLER_BOOTSTRAP_URL:-https://raw.githubusercontent.com/${REPOSITORY}/${RAW_REF}/proxy-installer/bootstrap/install.sh}"

case "${REPOSITORY}" in
  *[!A-Za-z0-9._/-]*|/*|*/|*//*|*/*/*) printf '%s\n' 'failed=repository-invalid' >&2; exit 2 ;;
esac
[[ "${RELEASE_URL}" =~ ^https:// ]] || { printf '%s\n' 'failed=https-release-url-required' >&2; exit 2; }
[[ "${CHECKSUM_URL}" =~ ^https:// ]] || { printf '%s\n' 'failed=https-checksum-url-required' >&2; exit 2; }
[[ "${INSTALLER_URL}" =~ ^https:// ]] || { printf '%s\n' 'failed=https-bootstrap-url-required' >&2; exit 2; }

work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT
checksum_file="${work_dir}/release.sha256"
installer_file="${work_dir}/install.sh"
"${CURL_BIN}" --fail --location --silent --show-error --output "${checksum_file}" "${CHECKSUM_URL}"
expected_sha256="$(awk 'NR == 1 { print $1 }' "${checksum_file}")"
[[ "${expected_sha256}" =~ ^[A-Fa-f0-9]{64}$ ]] || { printf '%s\n' 'failed=release-checksum-invalid' >&2; exit 1; }
"${CURL_BIN}" --fail --location --silent --show-error --output "${installer_file}" "${INSTALLER_URL}"
chmod 700 "${installer_file}"
"${BASH_BIN}" "${installer_file}" \
  --release-url "${RELEASE_URL}" \
  --sha256 "${expected_sha256}" \
  --version latest \
  --upgrade \
  --start-menu
