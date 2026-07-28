#!/usr/bin/env bash
# Formal local CLI shell. High-impact menu actions remain transaction-gated.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT}/lib/core/environment.sh"
source "${ROOT}/lib/core/result.sh"
source "${ROOT}/lib/interface/menu.sh"
source "${ROOT}/lib/orchestrators/deploy.sh"
source "${ROOT}/lib/orchestrators/deploy_materials.sh"
source "${ROOT}/lib/orchestrators/deploy_certificates.sh"
source "${ROOT}/lib/orchestrators/deploy_descriptor.sh"
source "${ROOT}/lib/config/state.sh"
source "${ROOT}/lib/adapters/snell.sh"
source "${ROOT}/lib/adapters/anytls.sh"
source "${ROOT}/lib/adapters/hysteria2.sh"
source "${ROOT}/lib/resources/binary.sh"

CONFIG_PATH="${PROXY_INSTALLER_CONFIG:-/etc/proxy-installer/config.yaml}"
MANIFEST_DIR="${ROOT}/manifests"

usage() {
  printf '%s\n' 'Usage:' '  proxy-installer.sh' '  proxy-installer.sh --status' '  proxy-installer.sh --binary-candidates <snell|anytls|hysteria2>' '  proxy-installer.sh --configure-snell <port> <psk> <ip|domain> <address>' '  proxy-installer.sh --configure-anytls <port> <password> <domain> <tfo> <reuse>' '  proxy-installer.sh --configure-hysteria2 <port> <password> <domain> <hop-range-or-empty> <hop-interval> <gecko> <gecko-password-or-empty> <download-bandwidth>' '  proxy-installer.sh --plan-deploy <protocols> <snell-port> <anytls-port> <hy2-port> <hy2-range-or-empty>' '  proxy-installer.sh --deploy-preflight' '  proxy-installer.sh --certificate-preflight <server-public-ip>' '  proxy-installer.sh --prepare-certificates <server-public-ip> <candidate-root> <true|false>' '  proxy-installer.sh --prepare-deploy <candidate-dir> <runtime-dir> <binary-dir> <certificate-dir>' '  proxy-installer.sh --build-service-descriptor <candidate-dir> <runtime-dir> <unit-dir> <backup-dir> <descriptor-file>' '  proxy-installer.sh --preacceptance [report-path]'
}

if [ "${1:-}" = "--status" ]; then
  [ "$#" -eq 1 ] || { usage >&2; exit 2; }
  state_read "${CONFIG_PATH}"
  exit $?
fi

if [ "${1:-}" = "--binary-candidates" ]; then
  [ "$#" -eq 2 ] || { usage >&2; exit 2; }
  case "$2" in
    snell) printf '%s\n' 'protocol=snell-v6-beta' 'server-artifact=v5.0.1'; binary_list_candidates "${MANIFEST_DIR}/snell-amd64.txt" ;;
    anytls) binary_list_candidates "${MANIFEST_DIR}/sing-box-amd64.txt" ;;
    hysteria2) binary_list_candidates "${MANIFEST_DIR}/hysteria2-amd64.txt" ;;
    *) usage >&2; exit 2 ;;
  esac
  exit $?
fi

if [ "${1:-}" = "--configure-snell" ]; then
  [ "$#" -eq 5 ] || { usage >&2; exit 2; }
  state_patch "${CONFIG_PATH}" "$(snell_build_config_patch "$2" "$3" "$4" "$5" default)"
  exit $?
fi

if [ "${1:-}" = "--configure-anytls" ]; then
  [ "$#" -eq 6 ] || { usage >&2; exit 2; }
  state_patch "${CONFIG_PATH}" "$(anytls_build_config_patch "$2" "$3" "$4" "$5" "$6")"
  exit $?
fi

if [ "${1:-}" = "--configure-hysteria2" ]; then
  [ "$#" -eq 9 ] || { usage >&2; exit 2; }
  state_patch "${CONFIG_PATH}" "$(hy2_build_config_patch "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9")"
  exit $?
fi

if [ "${1:-}" = "--plan-deploy" ]; then
  [ "$#" -eq 6 ] || { usage >&2; exit 2; }
  deploy_build_plan "$2" "$3" "$4" "$5" "$6"
  exit $?
fi

if [ "${1:-}" = "--deploy-preflight" ]; then
  [ "$#" -eq 1 ] || { usage >&2; exit 2; }
  environment_check || exit 1
  deploy_preflight_from_config "${CONFIG_PATH}"
  exit $?
fi

if [ "${1:-}" = "--certificate-preflight" ]; then
  [ "$#" -eq 2 ] || { usage >&2; exit 2; }
  deploy_certificates_preflight "${CONFIG_PATH}" "$2"
  exit $?
fi

if [ "${1:-}" = "--prepare-certificates" ]; then
  [ "$#" -eq 4 ] || { usage >&2; exit 2; }
  deploy_certificates_prepare_candidates "${CONFIG_PATH}" "$2" "$3" "$4"
  exit $?
fi

if [ "${1:-}" = "--prepare-deploy" ]; then
  [ "$#" -eq 5 ] || { usage >&2; exit 2; }
  deploy_materials_prepare "${CONFIG_PATH}" "$2" "$3" "$4" "$5"
  exit $?
fi

if [ "${1:-}" = "--build-service-descriptor" ]; then
  [ "$#" -eq 6 ] || { usage >&2; exit 2; }
  deploy_descriptor_build "$2" "$3" "$4" "$5" "$6"
  exit $?
fi

if [ "${1:-}" = "--preacceptance" ]; then
  shift
  if [ "$#" -eq 0 ]; then exec bash "${ROOT}/bin/preacceptance.sh" --verify; fi
  [ "$#" -eq 1 ] || { usage >&2; exit 2; }
  exec bash "${ROOT}/bin/preacceptance.sh" --verify --report "$1"
fi

[ "$#" -eq 0 ] || { usage >&2; exit 2; }

main() {
  environment_check || { result_render failed 'environment check failed' 'env-check'; return 1; }
  while true; do
    menu_render_main
    printf '%s' '请选择：'
    IFS= read -r choice || return 0
    local action
    action="$(menu_parse_main "${choice}")" || { printf '%s\n' '输入无效，请重试。'; continue; }
    [ "${action}" = exit ] && { result_render skipped 'user exited the script' 'exit'; return 0; }
    result_render skipped "${action} menu is ready; execution requires a confirmed transaction plan" "menu-${action}"
  done
}

main "$@"
