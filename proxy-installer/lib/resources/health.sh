#!/usr/bin/env bash
# Strict service health verification for transaction commit gates.

set -o pipefail

SS_BIN="${SS_BIN:-ss}"

health_verify() {
  local unit="$1" transport="$2" port="$3" binary="$4" version_arg="$5" log_lines="${6:-0}"
  [[ "${transport}" =~ ^(tcp|udp)$ ]] && [[ "${port}" =~ ^[0-9]+$ ]] || return 1
  [[ "${log_lines}" =~ ^[0-9]+$ ]] || return 1
  "${SYSTEMCTL_BIN:-systemctl}" is-active --quiet "${unit}" || return 1
  "${binary}" "${version_arg}" >/dev/null 2>&1 || return 1
  case "${transport}" in
    tcp) "${SS_BIN}" -ltn | awk '{print $4}' | grep -Eq "[:.]${port}$" || return 1 ;;
    udp) "${SS_BIN}" -lun | awk '{print $4}' | grep -Eq "[:.]${port}$" || return 1 ;;
  esac
  [ "${log_lines}" -eq 0 ] || "${JOURNALCTL_BIN:-journalctl}" --no-pager -u "${unit}" -n "${log_lines}" >/dev/null 2>&1 || return 1
  return 0
}
