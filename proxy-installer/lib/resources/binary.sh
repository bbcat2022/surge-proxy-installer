#!/usr/bin/env bash
# Binary resource primitive. A caller supplies a verified, official manifest.

set -o pipefail

CURL_BIN="${CURL_BIN:-curl}"
SHA256_BIN="${SHA256_BIN:-shasum}"
UNZIP_BIN="${UNZIP_BIN:-unzip}"
TAR_BIN="${TAR_BIN:-tar}"

binary_validate_manifest_line() {
  local version="$1" date="$2" url="$3" checksum="$4" archive="$5" executable="$6"
  [[ "${version}" =~ ^v[0-9]+(\.[0-9]+){1,3}$ ]] && [[ "${date}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && [[ "${url}" =~ ^https:// ]] && [[ "${checksum}" =~ ^[a-fA-F0-9]{64}$ ]] && [[ "${archive}" =~ ^(zip|tar.gz|raw)$ ]] && [ -n "${executable}" ]
}

binary_list_candidates() {
  local manifest="$1" count=0 line version date url checksum archive executable
  [ -f "${manifest}" ] || return 1
  while IFS='|' read -r version date url checksum archive executable; do
    [ -n "${version}" ] || continue
    binary_validate_manifest_line "${version}" "${date}" "${url}" "${checksum}" "${archive}" "${executable}" || return 1
    printf '%s|%s|%s|%s|%s|%s\n' "${version}" "${date}" "${url}" "${checksum}" "${archive}" "${executable}"
    count=$((count + 1)); [ "${count}" -le 3 ] || return 1
  done < "${manifest}"
  [ "${count}" -gt 0 ]
}

binary_verify_checksum() {
  local file="$1" expected="$2" actual
  actual="$("${SHA256_BIN}" -a 256 "${file}" | awk '{print $1}')" || return 1
  [ "${actual}" = "${expected}" ]
}

binary_prepare() {
  local url="$1" checksum="$2" archive="$3" executable="$4" work_dir="$5" dry_run="$6"
  [ "${dry_run}" = true ] && return 0
  mkdir -p "${work_dir}" || return 1
  local download="${work_dir}/download" candidate="${work_dir}/candidate"
  "${CURL_BIN}" --fail --location --silent --show-error --output "${download}" "${url}" || return 1
  binary_verify_checksum "${download}" "${checksum}" || return 1
  case "${archive}" in
    raw) cp "${download}" "${candidate}" ;;
    zip) "${UNZIP_BIN}" -p "${download}" "${executable}" > "${candidate}" || { rm -f "${candidate}"; return 1; } ;;
    tar.gz) "${TAR_BIN}" -xOzf "${download}" "${executable}" > "${candidate}" || { rm -f "${candidate}"; return 1; } ;;
  esac
  chmod 700 "${candidate}" || return 1
  [ -x "${candidate}" ]
}

binary_install_candidate() {
  local candidate="$1" active_path="$2" version_command="$3" dry_run="$4"
  [ -x "${candidate}" ] || return 1
  [ "${dry_run}" = true ] && return 0
  "${candidate}" ${version_command} >/dev/null 2>&1 || return 1
  mkdir -p "$(dirname "${active_path}")" || return 1
  local temporary="${active_path}.candidate.$$"
  cp "${candidate}" "${temporary}" || return 1
  chmod 700 "${temporary}" || return 1
  mv -f "${temporary}" "${active_path}"
}

binary_restore() {
  local backup="$1" active_path="$2" dry_run="$3"
  [ -x "${backup}" ] || return 1
  [ "${dry_run}" = true ] && return 0
  cp "${backup}" "${active_path}.restore.$$" && mv -f "${active_path}.restore.$$" "${active_path}"
}
