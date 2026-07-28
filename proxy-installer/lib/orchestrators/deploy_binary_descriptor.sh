#!/usr/bin/env bash
# Convert verified binary candidates into a descriptor consumed by deploy_binaries_execute.

set -o pipefail

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

deploy_binary_descriptor_build() {
  # candidate-root binary-dir backup-dir descriptor-file comma-separated-protocols
  [ "$#" -eq 5 ] || return 2
  local candidate_root="$1" binary_dir="$2" backup_dir="$3" descriptor="$4" protocols="$5"
  [ -d "${candidate_root}" ] || return 1
  deploy_binary_descriptor_absolute_dir "${binary_dir}" && deploy_binary_descriptor_absolute_dir "${backup_dir}" && [[ "${descriptor}" = /* ]] || return 1
  local temporary protocol target
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
    target="$(deploy_binary_descriptor_target "${protocol}" "${binary_dir}")" || { rm -f "${temporary}"; return 1; }
    printf '%s|%s|%s|%s\n' "${protocol}" "${candidate_root}/${protocol}" "${target}" "${backup_dir}/binary-${protocol}" >> "${temporary}" || { rm -f "${temporary}"; return 1; }
  done
  mv -f "${temporary}" "${descriptor}"
}
