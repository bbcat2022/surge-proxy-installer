#!/usr/bin/env bash
# Binary update plan builder; candidate selection and execution remain separate.

set -o pipefail

update_plan() {
  local target="$1" current_version="$2" selected_version="$3" batch="$4"
  case "${target}" in snell|anytls|hysteria2) ;; *) return 1 ;; esac
  [[ "${current_version}" =~ ^v[0-9]+(\.[0-9]+){1,3}$ ]] && [[ "${selected_version}" =~ ^v[0-9]+(\.[0-9]+){1,3}$ ]] || return 1
  [[ "${batch}" =~ ^(true|false)$ ]] || return 1
  printf '%s\n' 'operation=update' "target=${target}" "current-version=${current_version}" "selected-version=${selected_version}" 'candidate-must-be-official=true' 'checksum-required=true' 'backup-binary=true' 'version-check=true' 'health-verification=required' 'rollback-on-failure=true' 'commit-applied-after-success=true' 'execution=transaction-required'
  [ "${batch}" = true ] && printf '%s\n' 'batch=sequential-stop-on-failure'
}
