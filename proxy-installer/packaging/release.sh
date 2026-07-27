#!/usr/bin/env bash
# Produces the two GitHub Release assets: the archive and its SHA-256 file.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-${ROOT}/dist}"
archive="$(bash "${ROOT}/packaging/build.sh" "${OUT_DIR}")"
checksum_file="${archive}.sha256"
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "${archive}" > "${checksum_file}"
else
  shasum -a 256 "${archive}" > "${checksum_file}"
fi
chmod 644 "${checksum_file}"
printf '%s\n' "${archive}" "${checksum_file}"
