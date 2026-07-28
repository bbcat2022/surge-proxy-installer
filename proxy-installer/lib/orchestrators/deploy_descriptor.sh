#!/usr/bin/env bash
# Convert prepared candidates into a descriptor consumed by deploy_services_execute.

set -o pipefail

deploy_descriptor_absolute_dir() { [[ "$1" = /* ]] && [ -n "$1" ]; }

deploy_descriptor_build() {
  # candidate-dir runtime-dir unit-dir backup-dir descriptor-file
  [ "$#" -eq 5 ] || return 2
  local candidate="$1" runtime="$2" unit_dir="$3" backup="$4" descriptor="$5"
  [ -d "${candidate}" ] || return 1
  deploy_descriptor_absolute_dir "${runtime}" && deploy_descriptor_absolute_dir "${unit_dir}" && deploy_descriptor_absolute_dir "${backup}" && [[ "${descriptor}" = /* ]] || return 1
  local temporary protocol runtime_candidate runtime_target unit_name unit_candidate
  temporary="$(dirname "${descriptor}")/.$(basename "${descriptor}").tmp.$$"
  mkdir -p "$(dirname "${descriptor}")" || return 1
  : > "${temporary}" || return 1
  chmod 600 "${temporary}" || { rm -f "${temporary}"; return 1; }
  for protocol in snell anytls hysteria2 hysteria2-port-hop; do
    case "${protocol}" in
      snell) runtime_candidate="${candidate}/snell.conf"; runtime_target="${runtime}/snell.conf"; unit_name=proxy-installer-snell.service; unit_candidate="${candidate}/${unit_name}" ;;
      anytls) runtime_candidate="${candidate}/anytls.json"; runtime_target="${runtime}/anytls.json"; unit_name=proxy-installer-anytls.service; unit_candidate="${candidate}/${unit_name}" ;;
      hysteria2) runtime_candidate="${candidate}/hysteria2.yaml"; runtime_target="${runtime}/hysteria2.yaml"; unit_name=proxy-installer-hysteria2.service; unit_candidate="${candidate}/${unit_name}" ;;
      hysteria2-port-hop) runtime_candidate="${candidate}/hysteria2-port-hop.nft"; runtime_target="${runtime}/hysteria2-port-hop.nft"; unit_name=proxy-installer-hysteria2-port-hop.service; unit_candidate="${candidate}/${unit_name}" ;;
    esac
    [ -f "${runtime_candidate}" ] || continue
    [ -f "${unit_candidate}" ] || { rm -f "${temporary}"; return 1; }
    printf '%s|%s|%s|%s|%s|%s|%s|%s\n' "${protocol}" "${runtime_candidate}" "${runtime_target}" "${backup}/runtime-${protocol}" "${unit_dir}" "${unit_name}" "${unit_candidate}" "${backup}/unit-${unit_name}" >> "${temporary}" || { rm -f "${temporary}"; return 1; }
  done
  [ -s "${temporary}" ] || { rm -f "${temporary}"; return 1; }
  mv -f "${temporary}" "${descriptor}"
}

deploy_descriptor_entries() {
  local candidate="$1" entry
  [ -d "${candidate}" ] || return 1
  for entry in snell.surge anytls.surge hysteria2.surge; do [ ! -e "${candidate}/${entry}" ] || printf '%s\n' "${candidate}/${entry}"; done
  return 0
}
