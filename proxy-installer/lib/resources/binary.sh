#!/usr/bin/env bash
# Binary resource primitive. A caller supplies a verified, official manifest.

set -o pipefail

CURL_BIN="${CURL_BIN:-curl}"
SHA256_BIN="${SHA256_BIN:-shasum}"
UNZIP_BIN="${UNZIP_BIN:-unzip}"
TAR_BIN="${TAR_BIN:-tar}"

binary_validate_manifest_line() {
  local version="$1" date="$2" url="$3" checksum="$4" archive="$5" executable="$6"
  [[ "${version}" =~ ^v[0-9]+(\.[0-9]+){1,3}$ ]] &&
    [[ "${date}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] &&
    [[ "${url}" =~ ^https://[^[:space:]]+$ ]] &&
    [[ "${checksum}" =~ ^[a-fA-F0-9]{64}$ ]] &&
    [[ "${archive}" =~ ^(zip|tar.gz|raw)$ ]] &&
    [[ "${executable}" =~ ^[A-Za-z0-9._+-]+(/[A-Za-z0-9._+-]+)*$ ]] &&
    [[ "/${executable}/" != */../* ]]
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
  actual="$("${SHA256_BIN}" -a 256 "${file}" | awk '{print $1}' | tr 'A-F' 'a-f')" || return 1
  expected="$(printf '%s' "${expected}" | tr 'A-F' 'a-f')" || return 1
  [ "${actual}" = "${expected}" ]
}

binary_prepare() {
  local url="$1" checksum="$2" archive="$3" executable="$4" work_dir="$5" dry_run="$6"
  [[ "${dry_run}" =~ ^(true|false)$ ]] || return 2
  binary_validate_manifest_line v1.0 1970-01-01 "${url}" "${checksum}" "${archive}" "${executable}" || return 1
  [[ "${work_dir}" = /* ]] && [ "${work_dir}" != / ] && [ ! -e "${work_dir}" ] && [ ! -L "${work_dir}" ] || return 1
  [ "${dry_run}" = true ] && return 0
  local parent staging download candidate
  parent="$(dirname "${work_dir}")"
  staging="${parent}/.$(basename "${work_dir}").prepare.$$"
  [ ! -e "${staging}" ] && [ ! -L "${staging}" ] || return 1
  mkdir -p "${parent}" && mkdir "${staging}" || return 1
  chmod 700 "${staging}" || { rm -rf -- "${staging}"; return 1; }
  download="${staging}/download"
  candidate="${staging}/candidate"
  "${CURL_BIN}" --fail --location --silent --show-error --output "${download}" "${url}" ||
    { rm -rf -- "${staging}"; return 1; }
  binary_verify_checksum "${download}" "${checksum}" ||
    { rm -rf -- "${staging}"; return 1; }
  case "${archive}" in
    raw) cp "${download}" "${candidate}" || { rm -rf -- "${staging}"; return 1; } ;;
    zip) "${UNZIP_BIN}" -p "${download}" "${executable}" > "${candidate}" || { rm -rf -- "${staging}"; return 1; } ;;
    tar.gz) "${TAR_BIN}" -xOzf "${download}" "${executable}" > "${candidate}" || { rm -rf -- "${staging}"; return 1; } ;;
  esac
  [ -f "${candidate}" ] && [ ! -L "${candidate}" ] && chmod 700 "${candidate}" ||
    { rm -rf -- "${staging}"; return 1; }
  rm -f "${download}" || { rm -rf -- "${staging}"; return 1; }
  mv "${staging}" "${work_dir}" || { rm -rf -- "${staging}"; return 1; }
  [ -x "${work_dir}/candidate" ]
}

binary_validate_version_argument() {
  case "$1" in --version|version) return 0 ;; *) return 1 ;; esac
}

binary_install_candidate() {
  local candidate="$1" active_path="$2" version_command="$3" dry_run="$4"
  [[ "${dry_run}" =~ ^(true|false)$ ]] || return 2
  [ -f "${candidate}" ] && [ ! -L "${candidate}" ] && [ -x "${candidate}" ] || return 1
  [[ "${active_path}" = /* ]] && [ "${active_path}" != / ] || return 1
  [ ! -e "${active_path}" ] || { [ -f "${active_path}" ] && [ ! -L "${active_path}" ]; } || return 1
  binary_validate_version_argument "${version_command}" || return 1
  [ "${dry_run}" = true ] && return 0
  "${candidate}" "${version_command}" >/dev/null 2>&1 || return 1
  mkdir -p "$(dirname "${active_path}")" || return 1
  local temporary="$(dirname "${active_path}")/.$(basename "${active_path}").candidate.$$"
  [ ! -e "${temporary}" ] && cp "${candidate}" "${temporary}" &&
    chmod 700 "${temporary}" && mv -f "${temporary}" "${active_path}" ||
    { rm -f -- "${temporary}"; return 1; }
}

binary_restore() {
  local backup="$1" active_path="$2" dry_run="$3"
  [[ "${dry_run}" =~ ^(true|false)$ ]] || return 2
  [ -f "${backup}" ] && [ ! -L "${backup}" ] || return 1
  [[ "${active_path}" = /* ]] && [ "${active_path}" != / ] || return 1
  [ ! -e "${active_path}" ] || { [ -f "${active_path}" ] && [ ! -L "${active_path}" ]; } || return 1
  [ "${dry_run}" = true ] && return 0
  mkdir -p "$(dirname "${active_path}")" || return 1
  local temporary="$(dirname "${active_path}")/.$(basename "${active_path}").restore.$$"
  [ ! -e "${temporary}" ] && cp "${backup}" "${temporary}" &&
    chmod 700 "${temporary}" && mv -f "${temporary}" "${active_path}" ||
    { rm -f -- "${temporary}"; return 1; }
}
