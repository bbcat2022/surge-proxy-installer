#!/usr/bin/env bash
# Development-only CLI for isolated planning and configuration-tool smoke checks.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PYTHONPATH="${ROOT}/../.python-packages${PYTHONPATH:+:${PYTHONPATH}}"
source "${ROOT}/lib/config/state.sh"
source "${ROOT}/lib/orchestrators/deploy.sh"
source "${ROOT}/lib/orchestrators/config_apply.sh"

usage() {
  printf '%s\n' 'Usage:' '  dev.sh init-config <path>' '  dev.sh plan-deploy <protocols> <snell-port> <anytls-port> <hy2-port> <hy2-range-or-empty>' '  dev.sh plan-config <protocol> <field>'
}

case "${1:-}" in
  init-config) [ "$#" -eq 2 ] || { usage; exit 2; }; state_initialize "$2" ;;
  plan-deploy) [ "$#" -eq 6 ] || { usage; exit 2; }; deploy_build_plan "$2" "$3" "$4" "$5" "$6" ;;
  plan-config) [ "$#" -eq 3 ] || { usage; exit 2; }; config_apply_plan "$2" "$3" ;;
  *) usage; exit 2 ;;
esac
