#!/usr/bin/env bash
# Convert verified binary candidates into a descriptor consumed by deploy_binaries_execute.

set -o pipefail

DEPLOY_BINARY_DESCRIPTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${DEPLOY_BINARY_DESCRIPTOR_DIR}/../.." && pwd)"
source "${PROJECT_ROOT}/lib/resources/binary.sh"
source "${PROJECT_ROOT}/lib/registry/protocols.sh"

deploy_binary_descriptor_absolute_dir() { [[ "$1" = /* ]] && [ -n "$1" ]; }

deploy_binary_descriptor_target() {
  local protocol="$1" binary_dir="$2"
  case "${protocol}" in
    snell) printf '%s\n' "${binary_dir}/snell-server" ;;
    anytls) printf '%s\n' "${binary_dir}/sing-box" ;;
    hysteria2) printf '%s\n' "${binary_dir}/hysteria" ;;
    *) return 1 ;;
  esac
}

deploy_binary_descriptor_metadata_target() {
  local protocol="$1" binary_dir="$2" binary_id
  binary_id="$(protocol_registry_get "${protocol}" binary_id)" || return 1
  printf '%s\n' "${binary_dir}/.metadata/${binary_id}.metadata"
}

deploy_binary_descriptor_build() {
  # candidate-root binary-dir backup-dir descriptor-file comma-separated-protocols
  [ "$#" -eq 5 ] || return 2
  local candidate_root="$1" binary_dir="$2" backup_dir="$3" descriptor="$4" protocols="$5"
  [ -d "${candidate_root}" ] || return 1
  deploy_binary_descriptor_absolute_dir "${binary_dir}" && deploy_binary_descriptor_absolute_dir "${backup_dir}" && [[ "${descriptor}" = /* ]] || return 1
  local temporary protocol target metadata_target binary_id
  temporary="$(dirname "${descriptor}")/.$(basename "${descriptor}").tmp.$$"
  mkdir -p "$(dirname "${descriptor}")" || return 1
  : > "${temporary}" || return 1
  chmod 600 "${temporary}" || { rm -f "${temporary}"; return 1; }
  local -a selected=()
  IFS=',' read -r -a selected <<< "${protocols}"
  [ "${#selected[@]}" -gt 0 ] || { rm -f "${temporary}"; return 1; }
  for protocol in "${selected[@]}"; do
    [[ "${protocol}" =~ ^(snell|anytls|hysteria2)$ ]] || { rm -f "${temporary}"; return 1; }
    [ -x "${candidate_root}/${protocol}/candidate" ] || { rm -f "${temporary}"; return 1; }
    binary_id="$(protocol_registry_get "${protocol}" binary_id)" || { rm -f "${temporary}"; return 1; }
    binary_validate_metadata "${candidate_root}/${protocol}/metadata" "${binary_id}" || { rm -f "${temporary}"; return 1; }
    target="$(deploy_binary_descriptor_target "${protocol}" "${binary_dir}")" || { rm -f "${temporary}"; return 1; }
    metadata_target="$(deploy_binary_descriptor_metadata_target "${protocol}" "${binary_dir}")" || { rm -f "${temporary}"; return 1; }
    printf '%s|%s|%s|%s|%s|%s\n' \
      "${protocol}" "${candidate_root}/${protocol}" "${target}" "${backup_dir}/binary-${binary_id}" \
      "${metadata_target}" "${backup_dir}/metadata-${binary_id}" >> "${temporary}" ||
      { rm -f "${temporary}"; return 1; }
  done
  mv -f "${temporary}" "${descriptor}"
}
