#!/usr/bin/env bash
# Snapshot a controlled file target and restore either its prior contents or absence.

set -o pipefail

snapshot_capture_file() {
  local target="$1" snapshot="$2" dry_run="${3:-false}"
  [ -n "${target}" ] && [ -n "${snapshot}" ] || return 1
  [ "${dry_run}" = true ] && return 0
  mkdir -p "$(dirname "${snapshot}")" || return 1
  if [ -e "${target}" ]; then
    [ -f "${target}" ] || return 1
    cp "${target}" "${snapshot}.tmp.$$" || return 1
    chmod 600 "${snapshot}.tmp.$$" || { rm -f "${snapshot}.tmp.$$"; return 1; }
    mv -f "${snapshot}.tmp.$$" "${snapshot}" || return 1
    printf '%s\n' present > "${snapshot}.state"
  else
    rm -f "${snapshot}"
    printf '%s\n' absent > "${snapshot}.state"
  fi
  chmod 600 "${snapshot}.state"
}

snapshot_was_present() { [ -f "${1}.state" ] && [ "$(cat "${1}.state")" = present ]; }

snapshot_restore_file() {
  local target="$1" snapshot="$2" dry_run="${3:-false}" temporary
  [ -f "${snapshot}.state" ] || return 1
  [ "${dry_run}" = true ] && return 0
  if snapshot_was_present "${snapshot}"; then
    [ -f "${snapshot}" ] || return 1
    mkdir -p "$(dirname "${target}")" || return 1
    temporary="$(dirname "${target}")/.$(basename "${target}").restore.$$"
    cp "${snapshot}" "${temporary}" && chmod 600 "${temporary}" && mv -f "${temporary}" "${target}" || { rm -f "${temporary}"; return 1; }
  else
    [ ! -e "${target}" ] || [ -f "${target}" ] || return 1
    rm -f "${target}"
  fi
}
