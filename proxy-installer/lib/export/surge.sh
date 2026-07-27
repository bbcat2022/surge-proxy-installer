#!/usr/bin/env bash
# Surge export collector. It receives adapter entries and writes a private fragment.

set -o pipefail

QRENCODE_BIN="${QRENCODE_BIN:-qrencode}"

surge_export_fragment() {
  local target_file="$1" dry_run="$2"
  shift 2
  [ "$#" -gt 0 ] || return 1
  local entry_file
  for entry_file in "$@"; do [ -f "${entry_file}" ] || return 1; done
  [ "${dry_run}" = true ] && return 0
  local target_dir temporary
  target_dir="$(dirname "${target_file}")"
  mkdir -p "${target_dir}" || return 1
  temporary="${target_dir}/.$(basename "${target_file}").tmp.$$"
  {
    printf '%s\n' '[Proxy]'
    for entry_file in "$@"; do cat "${entry_file}"; done
  } > "${temporary}" || { rm -f "${temporary}"; return 1; }
  chmod 600 "${temporary}" || { rm -f "${temporary}"; return 1; }
  mv -f "${temporary}" "${target_file}" || { rm -f "${temporary}"; return 1; }
}

surge_export_qr() {
  # QR content is the exact exported fragment and is generated only after it exists.
  local fragment_file="$1" target_file="$2" dry_run="${3:-false}"
  [ -f "${fragment_file}" ] || return 1
  [ "${dry_run}" = true ] && return 0
  local target_dir temporary
  target_dir="$(dirname "${target_file}")"; mkdir -p "${target_dir}" || return 1
  temporary="${target_dir}/.$(basename "${target_file}").tmp.$$"
  "${QRENCODE_BIN}" -t PNG -o "${temporary}" < "${fragment_file}" || { rm -f "${temporary}"; return 1; }
  [ -s "${temporary}" ] || { rm -f "${temporary}"; return 1; }
  chmod 600 "${temporary}" || { rm -f "${temporary}"; return 1; }
  mv -f "${temporary}" "${target_file}" || { rm -f "${temporary}"; return 1; }
}
