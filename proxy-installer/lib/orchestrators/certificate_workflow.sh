#!/usr/bin/env bash
# Certificate workflow planner. acme.sh/systemd calls are transaction steps, not here.

set -o pipefail

certificate_workflow_plan() {
  local action="$1" domain="$2" port80_owner="$3" tls_services="$4"
  [[ "${domain}" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]] || return 1
  case "${action}" in issue|renew)
    printf '%s\n' "operation=certificate-${action}" "domain=${domain}" 'precheck=dns,current-ip,tcp-80,firewall' 'candidate-certificate=true' 'validate-candidate=true' 'backup-active-certificate=true' 'atomic-install=true' "reload-services=${tls_services}" 'health-verification=required' 'execution=transaction-required'
    [ "${port80_owner}" = none ] || printf 'port-80-owner=%s\nstop-owner-after-confirmation=true\nrestore-owner=true\n' "${port80_owner}"
    ;;
    timer-enable|timer-disable)
      printf '%s\n' "operation=certificate-${action}" 'certificate-files=unchanged' 'confirmation=required' 'execution=transaction-required'
      ;;
    cleanup)
      [ -z "${tls_services}" ] || return 1
      printf '%s\n' 'operation=certificate-cleanup' 'dependency-check=required' 'confirmation=strong-required' 'execution=transaction-required'
      ;;
    *) return 1 ;;
  esac
}
