#!/usr/bin/env bash
# Snapshot a controlled file target and restore either its prior contents or absence.

set -o pipefail

snapshot_file_mode() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
}

snapshot_capture_file() {
  local target="$1" snapshot="$2" dry_run="${3:-false}"
  [ -n "${target}" ] && [ -n "${snapshot}" ] || return 1
  [ "${dry_run}" = true ] && return 0
  mkdir -p "$(dirname "${snapshot}")" || return 1
  local mode
  if [ -e "${target}" ]; then
    [ -f "${target}" ] || return 1
    mode="$(snapshot_file_mode "${target}")" || return 1
    cp "${target}" "${snapshot}.tmp.$$" || return 1
    chmod 600 "${snapshot}.tmp.$$" || { rm -f "${snapshot}.tmp.$$"; return 1; }
    mv -f "${snapshot}.tmp.$$" "${snapshot}" || return 1
    printf 'present:%s\n' "${mode}" > "${snapshot}.state"
  else
    rm -f "${snapshot}"
    printf '%s\n' absent > "${snapshot}.state"
  fi
  chmod 600 "${snapshot}.state"
}

snapshot_was_present() { [ -f "${1}.state" ] && [[ "$(cat "${1}.state")" = present:* ]]; }
snapshot_restore_mode() { local state; state="$(cat "${1}.state")"; [[ "${state}" =~ ^present:([0-7]{3,4})$ ]] || return 1; printf '%s\n' "${BASH_REMATCH[1]}"; }

snapshot_restore_file() {
  local target="$1" snapshot="$2" dry_run="${3:-false}" temporary mode
  [ -f "${snapshot}.state" ] || return 1
  [ "${dry_run}" = true ] && return 0
  if snapshot_was_present "${snapshot}"; then
    [ -f "${snapshot}" ] || return 1
    mkdir -p "$(dirname "${target}")" || return 1
    temporary="$(dirname "${target}")/.$(basename "${target}").restore.$$"
    mode="$(snapshot_restore_mode "${snapshot}")" || return 1
    cp "${snapshot}" "${temporary}" && chmod "${mode}" "${temporary}" && mv -f "${temporary}" "${target}" || { rm -f "${temporary}"; return 1; }
  else
    [ ! -e "${target}" ] || [ -f "${target}" ] || return 1
    rm -f "${target}"
  fi
}

snapshot_verify_file() {
  local target="$1" snapshot="$2" expected_mode actual_mode
  [ -f "${snapshot}.state" ] || return 1
  if snapshot_was_present "${snapshot}"; then
    [ -f "${target}" ] && [ ! -L "${target}" ] && [ -f "${snapshot}" ] || return 1
    cmp -s "${target}" "${snapshot}" || return 1
    expected_mode="$(snapshot_restore_mode "${snapshot}")" || return 1
    actual_mode="$(snapshot_file_mode "${target}")" || return 1
    [ "${actual_mode}" = "${expected_mode}" ]
  else
    [ ! -e "${target}" ] && [ ! -L "${target}" ]
  fi
}
