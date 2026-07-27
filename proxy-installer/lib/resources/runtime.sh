#!/usr/bin/env bash
# Atomic runtime-file writer; adapters supply already-built content.

set -o pipefail

runtime_write() {
  local candidate_file="$1" target_file="$2" dry_run="${3:-false}"
  [ -f "${candidate_file}" ] || return 1
  [ "${dry_run}" = true ] && return 0
  local target_dir temporary
  target_dir="$(dirname "${target_file}")"
  mkdir -p "${target_dir}" || return 1
  temporary="${target_dir}/.$(basename "${target_file}").tmp.$$"
  cp "${candidate_file}" "${temporary}" || return 1
  chmod 600 "${temporary}" || { rm -f "${temporary}"; return 1; }
  mv -f "${temporary}" "${target_file}" || { rm -f "${temporary}"; return 1; }
}

runtime_restore() {
  local snapshot_file="$1" target_file="$2" dry_run="${3:-false}"
  runtime_write "${snapshot_file}" "${target_file}" "${dry_run}"
}
