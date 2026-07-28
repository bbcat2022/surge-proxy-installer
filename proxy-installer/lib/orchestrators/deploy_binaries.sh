#!/usr/bin/env bash
# Resolve, download and verify one pinned protocol binary. It never installs it.

set -o pipefail

DEPLOY_BINARIES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${DEPLOY_BINARIES_DIR}/../.." && pwd)"
source "${PROJECT_ROOT}/lib/resources/binary.sh"
source "${PROJECT_ROOT}/lib/registry/protocols.sh"

deploy_binary_manifest_path() {
  local protocol="$1" manifest_dir="$2"
  case "${protocol}" in
    snell) printf '%s\n' "${manifest_dir}/snell-amd64.txt" ;;
    anytls) printf '%s\n' "${manifest_dir}/sing-box-amd64.txt" ;;
    hysteria2) printf '%s\n' "${manifest_dir}/hysteria2-amd64.txt" ;;
    *) return 1 ;;
  esac
}

deploy_binary_version_argument() {
  case "$1" in snell) printf '%s\n' --version ;; anytls|hysteria2) printf '%s\n' version ;; *) return 1 ;; esac
}

deploy_binary_read_pinned_candidate() {
  # manifest; exports DEPLOY_BINARY_* from its first validated candidate only.
  local manifest="$1" consumer="${2:-}" line
  line="$(binary_list_candidates "${manifest}" linux-amd64 "${consumer}" | sed -n '1p')" || return 1
  [ -n "${line}" ] || return 1
  IFS='|' read -r DEPLOY_BINARY_VERSION DEPLOY_BINARY_STABILITY DEPLOY_BINARY_DATE DEPLOY_BINARY_PLATFORM DEPLOY_BINARY_CONSUMERS DEPLOY_BINARY_URL DEPLOY_BINARY_SHA256 DEPLOY_BINARY_ARCHIVE DEPLOY_BINARY_MEMBER <<< "${line}"
  binary_validate_manifest_line "${DEPLOY_BINARY_VERSION}" "${DEPLOY_BINARY_STABILITY}" "${DEPLOY_BINARY_DATE}" "${DEPLOY_BINARY_PLATFORM}" "${DEPLOY_BINARY_CONSUMERS}" "${DEPLOY_BINARY_URL}" "${DEPLOY_BINARY_SHA256}" "${DEPLOY_BINARY_ARCHIVE}" "${DEPLOY_BINARY_MEMBER}"
}

deploy_binary_prepare_pinned() {
  # protocol, manifest-dir, work-dir, dry-run
  [ "$#" -eq 4 ] || return 2
  local protocol="$1" manifest_dir="$2" work_dir="$3" dry_run="$4" manifest
  [[ "${dry_run}" =~ ^(true|false)$ ]] || return 2
  manifest="$(deploy_binary_manifest_path "${protocol}" "${manifest_dir}")" || return 1
  deploy_binary_read_pinned_candidate "${manifest}" "${protocol}" || return 1
  binary_prepare "${DEPLOY_BINARY_URL}" "${DEPLOY_BINARY_SHA256}" "${DEPLOY_BINARY_ARCHIVE}" "${DEPLOY_BINARY_MEMBER}" "${work_dir}" "${dry_run}" || return 1
  local binary_id
  binary_id="$(protocol_registry_get "${protocol}" binary_id)" || return 1
  binary_write_metadata "${work_dir}/metadata" "${binary_id}" "${DEPLOY_BINARY_VERSION}" "${DEPLOY_BINARY_STABILITY}" "${DEPLOY_BINARY_DATE}" "${DEPLOY_BINARY_PLATFORM}" "${DEPLOY_BINARY_URL}" "${DEPLOY_BINARY_SHA256}" "${dry_run}" ||
    { [ "${dry_run}" = true ] || rm -rf -- "${work_dir}"; return 1; }
  printf 'protocol=%s\nbinary-id=%s\nversion=%s\nstability=%s\nplatform=%s\nsource=%s\nchecksum=%s\n' "${protocol}" "${binary_id}" "${DEPLOY_BINARY_VERSION}" "${DEPLOY_BINARY_STABILITY}" "${DEPLOY_BINARY_PLATFORM}" "${DEPLOY_BINARY_URL}" "${DEPLOY_BINARY_SHA256}"
}

deploy_binary_install_prepared() {
  # protocol, candidate-work-dir, active-path, dry-run
  [ "$#" -eq 4 ] || return 2
  local protocol="$1" work_dir="$2" active_path="$3" dry_run="$4" version_arg
  [[ "${dry_run}" =~ ^(true|false)$ ]] || return 2
  version_arg="$(deploy_binary_version_argument "${protocol}")" || return 1
  binary_install_candidate "${work_dir}/candidate" "${active_path}" "${version_arg}" "${dry_run}"
}
