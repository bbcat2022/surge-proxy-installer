#!/usr/bin/env bash
# Binary resource primitive. A caller supplies a verified, official manifest.

set -o pipefail

CURL_BIN="${CURL_BIN:-curl}"
SHA256_BIN="${SHA256_BIN:-shasum}"
UNZIP_BIN="${UNZIP_BIN:-unzip}"
TAR_BIN="${TAR_BIN:-tar}"

binary_validate_artifact() {
  local url="$1" checksum="$2" archive="$3" executable="$4"
  [[ "${url}" =~ ^https://[^[:space:]]+$ ]] &&
    [[ "${checksum}" =~ ^[a-fA-F0-9]{64}$ ]] &&
    [[ "${archive}" =~ ^(zip|tar.gz|raw)$ ]] &&
    [[ "${executable}" =~ ^[A-Za-z0-9._+-]+(/[A-Za-z0-9._+-]+)*$ ]] &&
    [[ "/${executable}/" != */../* ]]
}

binary_validate_manifest_line() {
  local version="$1" stability="$2" date="$3" platform="$4" consumers="$5" url="$6" checksum="$7" archive="$8" executable="$9"
  [[ "${version}" =~ ^v[0-9]+(\.[0-9]+){1,3}$ ]] &&
    [[ "${stability}" =~ ^(stable|beta)$ ]] &&
    [[ "${date}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] &&
    [[ "${platform}" =~ ^linux-(amd64|arm64)$ ]] &&
    [[ "${consumers}" =~ ^[a-z0-9][a-z0-9-]*(,[a-z0-9][a-z0-9-]*)*$ ]] &&
    binary_validate_artifact "${url}" "${checksum}" "${archive}" "${executable}"
}

binary_consumers_supported() {
  local requested="$1" supported="$2" consumer
  [ -z "${requested}" ] && return 0
  [[ "${requested}" =~ ^[a-z0-9][a-z0-9-]*(,[a-z0-9][a-z0-9-]*)*$ ]] || return 1
  IFS=',' read -r -a requested_consumers <<< "${requested}"
  for consumer in "${requested_consumers[@]}"; do
    [[ ",${supported}," = *",${consumer},"* ]] || return 1
  done
}

binary_list_candidates() {
  local manifest="$1" required_platform="${2:-linux-amd64}" required_consumers="${3:-}"
  local count=0 version stability date platform consumers url checksum archive executable seen="|"
  [ -f "${manifest}" ] || return 1
  [[ "${required_platform}" =~ ^linux-(amd64|arm64)$ ]] || return 1
  while IFS='|' read -r version stability date platform consumers url checksum archive executable; do
    [ -n "${version}" ] || continue
    binary_validate_manifest_line "${version}" "${stability}" "${date}" "${platform}" "${consumers}" "${url}" "${checksum}" "${archive}" "${executable}" || return 1
    [ "${platform}" = "${required_platform}" ] || continue
    binary_consumers_supported "${required_consumers}" "${consumers}" || continue
    [[ "${seen}" != *"|${version}|"* ]] || return 1
    seen="${seen}${version}|"
    printf '%s|%s|%s|%s|%s|%s|%s|%s|%s\n' "${version}" "${stability}" "${date}" "${platform}" "${consumers}" "${url}" "${checksum}" "${archive}" "${executable}"
    count=$((count + 1)); [ "${count}" -le 3 ] || return 1
  done < "${manifest}"
  [ "${count}" -gt 0 ]
}

binary_select_candidate() {
  local manifest="$1" selected_version="$2" required_platform="${3:-linux-amd64}" required_consumers="${4:-}" line found=""
  [[ "${selected_version}" =~ ^v[0-9]+(\.[0-9]+){1,3}$ ]] || return 1
  while IFS= read -r line; do
    [[ "${line}" = "${selected_version}|"* ]] || continue
    [ -z "${found}" ] || return 1
    found="${line}"
  done < <(binary_list_candidates "${manifest}" "${required_platform}" "${required_consumers}") || return 1
  [ -n "${found}" ] || return 1
  printf '%s\n' "${found}"
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
  binary_validate_artifact "${url}" "${checksum}" "${archive}" "${executable}" || return 1
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

binary_probe_version() {
  local candidate="$1" version_command="$2" expected_version="$3" output numeric escaped pattern
  [ -f "${candidate}" ] && [ ! -L "${candidate}" ] && [ -x "${candidate}" ] || return 1
  binary_validate_version_argument "${version_command}" || return 1
  [[ "${expected_version}" =~ ^v[0-9]+(\.[0-9]+){1,3}$ ]] || return 1
  output="$("${candidate}" "${version_command}" 2>&1)" || return 1
  numeric="${expected_version#v}"
  escaped="${numeric//./\\.}"
  pattern="(^|[^0-9])v?${escaped}([^0-9]|$)"
  [[ "${output}" =~ ${pattern} ]]
}

binary_install_candidate() {
  [ "$#" -eq 5 ] || return 2
  local candidate="$1" active_path="$2" version_command="$3" dry_run="$4" expected_version="$5"
  [[ "${dry_run}" =~ ^(true|false)$ ]] || return 2
  [ -f "${candidate}" ] && [ ! -L "${candidate}" ] && [ -x "${candidate}" ] || return 1
  [[ "${active_path}" = /* ]] && [ "${active_path}" != / ] || return 1
  [ ! -e "${active_path}" ] || { [ -f "${active_path}" ] && [ ! -L "${active_path}" ]; } || return 1
  binary_validate_version_argument "${version_command}" && [[ "${expected_version}" =~ ^v[0-9]+(\.[0-9]+){1,3}$ ]] || return 1
  [ "${dry_run}" = true ] && return 0
  binary_probe_version "${candidate}" "${version_command}" "${expected_version}" || return 1
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

binary_write_metadata() {
  # path binary-id version stability release-date platform source sha256 dry-run
  [ "$#" -eq 9 ] || return 2
  local path="$1" binary_id="$2" version="$3" stability="$4" release_date="$5" platform="$6" source="$7" checksum="$8" dry_run="$9"
  [[ "${dry_run}" =~ ^(true|false)$ ]] || return 2
  [[ "${path}" = /* ]] && [ "${path}" != / ] || return 1
  [[ "${binary_id}" =~ ^[a-z0-9][a-z0-9._-]{0,63}$ ]] || return 1
  binary_validate_manifest_line "${version}" "${stability}" "${release_date}" "${platform}" "metadata" "${source}" "${checksum}" raw metadata || return 1
  [ "${dry_run}" = true ] && return 0
  mkdir -p "$(dirname "${path}")" || return 1
  local temporary="$(dirname "${path}")/.$(basename "${path}").tmp.$$"
  [ ! -e "${temporary}" ] || return 1
  printf 'binary_id=%s\nversion=%s\nstability=%s\nrelease_date=%s\nplatform=%s\nsource=%s\nsha256=%s\n' \
    "${binary_id}" "${version}" "${stability}" "${release_date}" "${platform}" "${source}" "${checksum}" > "${temporary}" &&
    chmod 600 "${temporary}" && mv -f "${temporary}" "${path}" ||
    { rm -f -- "${temporary}"; return 1; }
}

binary_validate_metadata() {
  [ "$#" -eq 1 ] || [ "$#" -eq 2 ] || return 2
  local path="$1" expected_binary_id="${2:-}" key value
  local binary_id="" version="" stability="" release_date="" platform="" source="" checksum="" seen="|"
  [ -f "${path}" ] && [ ! -L "${path}" ] || return 1
  while IFS='=' read -r key value; do
    [ -n "${key}" ] && [[ "${seen}" != *"|${key}|"* ]] || return 1
    seen="${seen}${key}|"
    case "${key}" in
      binary_id) binary_id="${value}" ;;
      version) version="${value}" ;;
      stability) stability="${value}" ;;
      release_date) release_date="${value}" ;;
      platform) platform="${value}" ;;
      source) source="${value}" ;;
      sha256) checksum="${value}" ;;
      *) return 1 ;;
    esac
  done < "${path}"
  [[ "${binary_id}" =~ ^[a-z0-9][a-z0-9._-]{0,63}$ ]] &&
    { [ -z "${expected_binary_id}" ] || [ "${binary_id}" = "${expected_binary_id}" ]; } &&
    binary_validate_manifest_line "${version}" "${stability}" "${release_date}" "${platform}" metadata "${source}" "${checksum}" raw metadata
}

binary_metadata_get() {
  [ "$#" -eq 2 ] || return 2
  local path="$1" requested="$2" key value
  binary_validate_metadata "${path}" || return 1
  case "${requested}" in binary_id|version|stability|release_date|platform|source|sha256) ;; *) return 1 ;; esac
  while IFS='=' read -r key value; do
    [ "${key}" = "${requested}" ] || continue
    printf '%s\n' "${value}"
    return 0
  done < "${path}"
  return 1
}

binary_install_metadata() {
  local candidate="$1" active_path="$2" dry_run="$3"
  [[ "${dry_run}" =~ ^(true|false)$ ]] || return 2
  binary_validate_metadata "${candidate}" || return 1
  [[ "${active_path}" = /* ]] && [ "${active_path}" != / ] || return 1
  [ ! -e "${active_path}" ] || { [ -f "${active_path}" ] && [ ! -L "${active_path}" ]; } || return 1
  [ "${dry_run}" = true ] && return 0
  mkdir -p "$(dirname "${active_path}")" || return 1
  local temporary="$(dirname "${active_path}")/.$(basename "${active_path}").candidate.$$"
  [ ! -e "${temporary}" ] && cp "${candidate}" "${temporary}" &&
    chmod 600 "${temporary}" && mv -f "${temporary}" "${active_path}" ||
    { rm -f -- "${temporary}"; return 1; }
}

binary_observe_installed() {
  # active-binary metadata version-argument
  [ "$#" -eq 3 ] || return 2
  local active="$1" metadata="$2" version_argument="$3" binary_id version
  binary_id="$(binary_metadata_get "${metadata}" binary_id)" || return 1
  version="$(binary_metadata_get "${metadata}" version)" || return 1
  binary_probe_version "${active}" "${version_argument}" "${version}" || return 1
  printf 'binary_id=%s\nversion=%s\npath=%s\nmetadata=%s\n' "${binary_id}" "${version}" "${active}" "${metadata}"
}
