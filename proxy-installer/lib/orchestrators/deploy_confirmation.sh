#!/usr/bin/env bash
# Explicit confirmation gate for the future mutating deployment transaction.

set -o pipefail

deploy_confirmation_require() {
  # public-ip confirmation-token
  [ "$#" -eq 2 ] || return 2
  local public_ip="$1" part
  [[ "${public_ip}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS='.' read -r -a parts <<< "${public_ip}"
  for part in "${parts[@]}"; do [ "${part}" -le 255 ] || return 1; done
  [ "$2" = --confirm ] || { printf '%s\n' 'confirmation=required' 'hint=rerun-with---confirm'; return 1; }
  printf '%s\n' 'confirmation=accepted'
}
