#!/usr/bin/env bash
# Reversible file removal for transaction use; never deletes directly.

set -o pipefail

file_stage_remove() {
  local target="$1" stash_dir="$2" dry_run="${3:-false}"
  [ -f "${target}" ] || return 1
  [ "${dry_run}" = true ] && return 0
  mkdir -p "${stash_dir}" || return 1
  local staged="${stash_dir}/$(basename "${target}")"
  [ ! -e "${staged}" ] || return 1
  mv "${target}" "${staged}"
}
file_restore_staged() {
  local staged="$1" target="$2" dry_run="${3:-false}"
  [ -f "${staged}" ] || return 1
  [ "${dry_run}" = true ] && return 0
  mkdir -p "$(dirname "${target}")" && mv "${staged}" "${target}"
}
