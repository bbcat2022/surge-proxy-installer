#!/usr/bin/env bash
# Uninstall-plan builder. Resource deletion must later run through a transaction.

set -o pipefail

uninstall_plan() {
  local installed_csv="$1" target="$2" item
  IFS=',' read -r -a installed <<< "${installed_csv}"
  local found=false remaining=() tls_remaining=false
  for item in "${installed[@]}"; do
    case "${item}" in snell|anytls|hysteria2) ;; *) return 1 ;; esac
    [ "${item}" = "${target}" ] && found=true || remaining+=("${item}")
  done
  [ "${found}" = true ] || return 1
  for item in "${remaining[@]:-}"; do [[ "${item}" = anytls || "${item}" = hysteria2 ]] && tls_remaining=true; done
  printf '%s\n' 'operation=uninstall' "target=${target}" "stop-service=proxy-installer-${target}.service" 'disable-service=true' 'delete-runtime=true' 'delete-unit=true' 'surge-export=true' 'firewall-cleanup=false'
  case "${target}" in
    snell) printf '%s\n' 'certificate=unchanged' 'certificate-timer=unchanged' ;;
    anytls|hysteria2)
      if [ "${tls_remaining}" = true ]; then printf '%s\n' 'certificate=shared-in-use' 'certificate-timer=unchanged'; else printf '%s\n' 'certificate=retain-manual-cleanup' 'certificate-timer=retain'; fi
      ;;
  esac
  printf '%s\n' 'confirmation=strong-required' 'execution=transaction-required'
}
