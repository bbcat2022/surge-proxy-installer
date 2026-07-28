#!/usr/bin/env bash
# systemd resource primitive; business decisions belong to orchestrators.

set -o pipefail

SYSTEMCTL_BIN="${SYSTEMCTL_BIN:-systemctl}"
JOURNALCTL_BIN="${JOURNALCTL_BIN:-journalctl}"
SYSTEMD_CP_BIN="${SYSTEMD_CP_BIN:-cp}"

systemd_validate_unit_name() {
  [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.@-]*\.(service|timer)$ ]]
}

systemd_validate_dry_run() { [[ "$1" =~ ^(true|false)$ ]]; }
systemd_validate_unit_dir() { [[ "$1" = /* ]] && [ "$1" != / ] && [ ! -L "$1" ]; }

systemd_write_unit() {
  local unit_dir="$1" unit_name="$2" candidate_file="$3" dry_run="${4:-false}"
  systemd_validate_unit_name "${unit_name}" || return 1
  systemd_validate_unit_dir "${unit_dir}" && systemd_validate_dry_run "${dry_run}" || return 1
  [ -f "${candidate_file}" ] && [ ! -L "${candidate_file}" ] || return 1
  [ ! -e "${unit_dir}/${unit_name}" ] || { [ -f "${unit_dir}/${unit_name}" ] && [ ! -L "${unit_dir}/${unit_name}" ]; } || return 1
  [ "${dry_run}" = "true" ] && return 0
  mkdir -p "${unit_dir}" || return 1
  local temporary="${unit_dir}/.${unit_name}.tmp.$$"
  [ ! -e "${temporary}" ] && [ ! -L "${temporary}" ] || return 1
  "${SYSTEMD_CP_BIN}" "${candidate_file}" "${temporary}" || { rm -f -- "${temporary}"; return 1; }
  chmod 600 "${temporary}" || { rm -f "${temporary}"; return 1; }
  mv -f "${temporary}" "${unit_dir}/${unit_name}" || { rm -f "${temporary}"; return 1; }
}

systemd_restore_unit() {
  local unit_dir="$1" unit_name="$2" snapshot_file="$3" dry_run="${4:-false}"
  systemd_validate_unit_name "${unit_name}" || return 1
  [ -f "${snapshot_file}" ] || return 1
  systemd_write_unit "${unit_dir}" "${unit_name}" "${snapshot_file}" "${dry_run}"
}

systemd_action() {
  local unit_name="$1" action="$2" dry_run="${3:-false}"
  systemd_validate_unit_name "${unit_name}" || return 1
  systemd_validate_dry_run "${dry_run}" || return 1
  case "${action}" in start|stop|restart|enable|disable|daemon-reload) ;; *) return 1 ;; esac
  [ "${dry_run}" = "true" ] && return 0
  if [ "${action}" = "daemon-reload" ]; then
    "${SYSTEMCTL_BIN}" daemon-reload
  else
    "${SYSTEMCTL_BIN}" "${action}" "${unit_name}"
  fi
}

systemd_observe() {
  local unit_name="$1" dry_run="${2:-false}"
  systemd_validate_unit_name "${unit_name}" || return 1
  systemd_validate_dry_run "${dry_run}" || return 1
  if [ "${dry_run}" = "true" ]; then
    printf '%s\n' 'active=unknown' 'enabled=unknown' 'dry_run=true'
    return 0
  fi
  local active enabled active_exit enabled_exit
  active="$("${SYSTEMCTL_BIN}" is-active "${unit_name}" 2>/dev/null)"; active_exit=$?
  enabled="$("${SYSTEMCTL_BIN}" is-enabled "${unit_name}" 2>/dev/null)"; enabled_exit=$?
  case "${active}" in active|inactive|failed|activating|deactivating|reloading|maintenance) ;; *) active=unknown ;; esac
  case "${enabled}" in enabled|disabled|static|indirect|masked|generated|transient|linked|linked-runtime|alias|not-found) ;; *) enabled=unknown ;; esac
  printf 'active=%s\nenabled=%s\nactive_query_exit=%s\nenabled_query_exit=%s\n' "${active}" "${enabled}" "${active_exit}" "${enabled_exit}"
}

systemd_capture_state() {
  local unit_name="$1" snapshot_file="$2" dry_run="${3:-false}" observation active enabled temporary
  systemd_validate_unit_name "${unit_name}" || return 1
  systemd_validate_dry_run "${dry_run}" || return 1
  [[ "${snapshot_file}" = /* ]] && [ "${snapshot_file}" != / ] && [ ! -L "${snapshot_file}" ] || return 1
  [ "${dry_run}" = "true" ] && return 0
  observation="$(systemd_observe "${unit_name}" false)" || return 1
  active="$(printf '%s\n' "${observation}" | awk -F= '$1 == "active" { print $2 }')"
  enabled="$(printf '%s\n' "${observation}" | awk -F= '$1 == "enabled" { print $2 }')"
  [ -n "${active}" ] && [ "${active}" != unknown ] && [ -n "${enabled}" ] && [ "${enabled}" != unknown ] || return 1
  mkdir -p "$(dirname "${snapshot_file}")" || return 1
  temporary="$(dirname "${snapshot_file}")/.$(basename "${snapshot_file}").tmp.$$"
  [ ! -e "${temporary}" ] && [ ! -L "${temporary}" ] || return 1
  printf 'active=%s\nenabled=%s\n' "${active}" "${enabled}" > "${temporary}" &&
    chmod 600 "${temporary}" &&
    mv -f "${temporary}" "${snapshot_file}" || { rm -f "${temporary}"; return 1; }
}

systemd_read_captured_state() {
  local snapshot_file="$1" key="$2" value count
  [ -f "${snapshot_file}" ] && [ ! -L "${snapshot_file}" ] || return 1
  case "${key}" in active|enabled) ;; *) return 1 ;; esac
  count="$(awk -F= -v key="${key}" '$1 == key { count++ } END { print count + 0 }' "${snapshot_file}")"
  [ "${count}" -eq 1 ] || return 1
  value="$(awk -F= -v key="${key}" '$1 == key { print $2 }' "${snapshot_file}")"
  case "${key}:${value}" in
    active:active|active:inactive|active:failed|active:activating|active:deactivating|active:reloading|active:maintenance) ;;
    enabled:enabled|enabled:disabled|enabled:static|enabled:indirect|enabled:masked|enabled:generated|enabled:transient|enabled:linked|enabled:linked-runtime|enabled:alias|enabled:not-found) ;;
    *) return 1 ;;
  esac
  printf '%s\n' "${value}"
}

systemd_restore_state() {
  local unit_name="$1" snapshot_file="$2" dry_run="${3:-false}" active enabled failed=0
  systemd_validate_unit_name "${unit_name}" || return 1
  systemd_validate_dry_run "${dry_run}" || return 1
  active="$(systemd_read_captured_state "${snapshot_file}" active)" || return 1
  enabled="$(systemd_read_captured_state "${snapshot_file}" enabled)" || return 1
  if [ "${enabled}" = enabled ]; then
    systemd_action "${unit_name}" enable "${dry_run}" || failed=1
  elif [ "${enabled}" = disabled ]; then
    systemd_action "${unit_name}" disable "${dry_run}" || failed=1
  fi
  if [ "${active}" = active ]; then
    systemd_action "${unit_name}" start "${dry_run}" || failed=1
  else
    systemd_action "${unit_name}" stop "${dry_run}" || failed=1
  fi
  [ "${failed}" -eq 0 ]
}

systemd_verify_captured_state() {
  local unit_name="$1" snapshot_file="$2" observation expected_active expected_enabled actual_active actual_enabled
  expected_active="$(systemd_read_captured_state "${snapshot_file}" active)" || return 1
  expected_enabled="$(systemd_read_captured_state "${snapshot_file}" enabled)" || return 1
  observation="$(systemd_observe "${unit_name}" false)" || return 1
  actual_active="$(printf '%s\n' "${observation}" | awk -F= '$1 == "active" { print $2 }')"
  actual_enabled="$(printf '%s\n' "${observation}" | awk -F= '$1 == "enabled" { print $2 }')"
  if [ "${expected_active}" = active ]; then [ "${actual_active}" = active ] || return 1
  else [ "${actual_active}" != active ] && [ "${actual_active}" != unknown ] || return 1
  fi
  case "${expected_enabled}" in
    enabled|disabled) [ "${actual_enabled}" = "${expected_enabled}" ] || return 1 ;;
    *) [ "${actual_enabled}" = "${expected_enabled}" ] || return 1 ;;
  esac
}

systemd_logs() {
  local unit_name="$1" lines="$2" dry_run="${3:-false}"
  systemd_validate_unit_name "${unit_name}" || return 1
  systemd_validate_dry_run "${dry_run}" || return 1
  [[ "${lines}" =~ ^[0-9]+$ ]] && [ "${lines}" -ge 1 ] && [ "${lines}" -le 100 ] || return 1
  [ "${dry_run}" = "true" ] && return 0
  "${JOURNALCTL_BIN}" --no-pager -u "${unit_name}" -n "${lines}" |
    awk -v limit="${lines}" 'NR <= limit'
}
