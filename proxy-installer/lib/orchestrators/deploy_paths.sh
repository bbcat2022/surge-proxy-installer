#!/usr/bin/env bash
# Canonical private paths for a confirmed deployment transaction.

set -o pipefail

deploy_paths_absolute() { [[ "$1" = /* ]] && [ -n "$1" ]; }

deploy_paths_prepare_workdir() {
  # state-root operation-id; prints a private, newly-created transaction directory.
  [ "$#" -eq 2 ] || return 2
  local state_root="$1" operation_id="$2" work
  deploy_paths_absolute "${state_root}" || return 1
  [[ "${operation_id}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || return 1
  work="${state_root}/work/${operation_id}"
  [ ! -e "${work}" ] || return 1
  mkdir -p "${work}" || return 1
  chmod 700 "${state_root}" "${state_root}/work" "${work}" || return 1
  printf '%s\n' "${work}"
}

deploy_paths_defaults() {
  printf '%s\n' \
    'runtime-dir=/etc/proxy-installer/runtime' \
    'binary-dir=/opt/proxy-installer/bin' \
    'certificate-dir=/etc/proxy-installer/certificates' \
    'unit-dir=/etc/systemd/system' \
    'state-root=/var/lib/proxy-installer'
}

deploy_paths_load_defaults() {
  DEPLOY_RUNTIME_DIR=/etc/proxy-installer/runtime
  DEPLOY_BINARY_DIR=/opt/proxy-installer/bin
  DEPLOY_CERTIFICATE_DIR=/etc/proxy-installer/certificates
  DEPLOY_UNIT_DIR=/etc/systemd/system
  DEPLOY_STATE_ROOT=/var/lib/proxy-installer
}
