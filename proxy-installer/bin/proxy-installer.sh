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
source "${ROOT}/lib/orchestrators/deploy_validate.sh"
source "${ROOT}/lib/orchestrators/deploy_confirmation.sh"
source "${ROOT}/lib/orchestrators/deploy_run.sh"
source "${ROOT}/lib/orchestrators/certificate_renew.sh"
source "${ROOT}/lib/config/state.sh"
source "${ROOT}/lib/adapters/snell.sh"
source "${ROOT}/lib/adapters/anytls.sh"
source "${ROOT}/lib/adapters/hysteria2.sh"
source "${ROOT}/lib/resources/binary.sh"

CONFIG_PATH="${PROXY_INSTALLER_CONFIG:-/etc/proxy-installer/config.yaml}"
MANIFEST_DIR="${ROOT}/manifests"

usage() {
  printf '%s\n' 'Usage:' '  proxy-installer.sh' '  proxy-installer.sh --status' '  proxy-installer.sh --binary-candidates <snell|anytls|hysteria2>' '  proxy-installer.sh --configure-snell <port> <psk> <ip|domain> <address>' '  proxy-installer.sh --configure-anytls <port> <password> <domain> <tfo> <reuse>' '  proxy-installer.sh --configure-hysteria2 <port> <password> <domain> <hop-range-or-empty> <hop-interval> <gecko> <gecko-password-or-empty> <download-bandwidth>' '  proxy-installer.sh --plan-deploy <protocols> <snell-port> <anytls-port> <hy2-port> <hy2-range-or-empty>' '  proxy-installer.sh --deploy-preflight' '  proxy-installer.sh --validate-deploy <server-public-ip>' '  proxy-installer.sh --deploy <server-public-ip> --confirm' '  proxy-installer.sh --renew-certificate' '  proxy-installer.sh --certificate-preflight <server-public-ip>' '  proxy-installer.sh --prepare-certificates <server-public-ip> <candidate-root> <true|false>' '  proxy-installer.sh --prepare-deploy <candidate-dir> <runtime-dir> <binary-dir> <certificate-dir>' '  proxy-installer.sh --build-service-descriptor <candidate-dir> <runtime-dir> <unit-dir> <backup-dir> <descriptor-file>' '  proxy-installer.sh --preacceptance [report-path]'
}

formal_deploy_execute() {
  [ "$#" -eq 2 ] || return 2
  local public_ip="$1" confirmation="$2" operation_id runtime_dir binary_dir certificate_dir unit_dir state_root export_target
  deploy_confirmation_require "${public_ip}" "${confirmation}" || return $?
  "${DEPLOY_ENVIRONMENT_EXECUTOR:-environment_check}" || return 1
  "${DEPLOY_TOOL_CHECK_EXECUTOR:-environment_check_deploy_tools}" || return 1
  "${DEPLOY_VALIDATE_EXECUTOR:-deploy_validate_run}" "${CONFIG_PATH}" "${public_ip}" "${MANIFEST_DIR}" || return 1
  deploy_paths_load_defaults
  operation_id="${PROXY_INSTALLER_OPERATION_ID:-deploy-$("${DEPLOY_DATE_BIN:-date}" -u '+%Y%m%dT%H%M%SZ')-$$}"
  runtime_dir="${PROXY_INSTALLER_RUNTIME_DIR:-${DEPLOY_RUNTIME_DIR}}"
  binary_dir="${PROXY_INSTALLER_BINARY_DIR:-${DEPLOY_BINARY_DIR}}"
  certificate_dir="${PROXY_INSTALLER_CERTIFICATE_DIR:-${DEPLOY_CERTIFICATE_DIR}}"
  unit_dir="${PROXY_INSTALLER_UNIT_DIR:-${DEPLOY_UNIT_DIR}}"
  state_root="${PROXY_INSTALLER_STATE_ROOT:-${DEPLOY_STATE_ROOT}}"
  export_target="${PROXY_INSTALLER_EXPORT_TARGET:-${state_root}/exports/surge.conf}"
  "${DEPLOY_RUN_EXECUTOR:-deploy_run_execute}" \
    "${CONFIG_PATH}" "${public_ip}" "${MANIFEST_DIR}" "${operation_id}" \
    "${runtime_dir}" "${binary_dir}" "${certificate_dir}" "${unit_dir}" \
    "${state_root}" "${export_target}" \
    "${PROXY_INSTALLER_FIREWALL_MODE:-auto}" "${PROXY_INSTALLER_FIREWALL_TOOL:-ufw}"
}

interactive_set_protocol_enabled() {
  local protocol="$1" enabled="$2"
  [ "${enabled}" = true ] && return 0
  state_patch "${CONFIG_PATH}" "{\"desired\":{\"protocols\":{\"${protocol}\":{\"enabled\":false}}}}" >/dev/null
}

interactive_guided_deploy() {
  local public_ip domain enabled_snell enabled_anytls enabled_hy2
  local snell_port snell_psk snell_patch anytls_port anytls_password anytls_patch
  local hy2_port hy2_password hy2_range hy2_interval hy2_gecko hy2_gecko_password hy2_bandwidth hy2_patch confirmation
  printf '%s\n' '' '配置向导将安装 Snell v6 Beta、AnyTLS 和 Hysteria2。直接按回车可采用推荐值。'
  menu_prompt_value '服务器公网 IPv4 地址' '' false || return 1; public_ip="${MENU_VALUE}"
  deploy_confirmation_require "${public_ip}" --confirm >/dev/null || { printf '%s\n' '公网 IPv4 地址格式不正确。' >&2; return 1; }
  menu_prompt_value '已解析到本机的域名' '' false || return 1; domain="${MENU_VALUE}"

  menu_prompt_yes_no '启用 Snell v6 Beta' true || return 1; enabled_snell="${MENU_BOOLEAN}"
  if [ "${enabled_snell}" = true ]; then
    menu_prompt_value 'Snell 端口' 443 false || return 1; snell_port="${MENU_VALUE}"
    menu_prompt_value 'Snell PSK（8–128 位）' '' true || return 1; snell_psk="${MENU_VALUE}"
    snell_patch="$(snell_build_config_patch "${snell_port}" "${snell_psk}" domain "${domain}" default)" ||
      { printf '%s\n' 'Snell 参数不符合要求。密码只能使用字母、数字和 ._~+/=-。' >&2; return 1; }
  fi

  menu_prompt_yes_no '启用 AnyTLS' true || return 1; enabled_anytls="${MENU_BOOLEAN}"
  if [ "${enabled_anytls}" = true ]; then
    menu_prompt_value 'AnyTLS 端口' 8443 false || return 1; anytls_port="${MENU_VALUE}"
    menu_prompt_value 'AnyTLS 密码（8–128 位）' '' true || return 1; anytls_password="${MENU_VALUE}"
    anytls_patch="$(anytls_build_config_patch "${anytls_port}" "${anytls_password}" "${domain}" true false)" ||
      { printf '%s\n' 'AnyTLS 参数不符合要求。密码只能使用字母、数字和 ._~+/=-。' >&2; return 1; }
  fi

  menu_prompt_yes_no '启用 Hysteria2' true || return 1; enabled_hy2="${MENU_BOOLEAN}"
  if [ "${enabled_hy2}" = true ]; then
    menu_prompt_value 'Hysteria2 端口' 9000 false || return 1; hy2_port="${MENU_VALUE}"
    menu_prompt_value 'Hysteria2 主密码（8–128 位）' '' true || return 1; hy2_password="${MENU_VALUE}"
    menu_prompt_value '端口跳跃范围' 20000-20100 false || return 1; hy2_range="${MENU_VALUE}"
    menu_prompt_value '端口跳跃间隔（秒）' 10 false || return 1; hy2_interval="${MENU_VALUE}"
    menu_prompt_yes_no '启用 Gecko' true || return 1; hy2_gecko="${MENU_BOOLEAN}"
    hy2_gecko_password=''
    if [ "${hy2_gecko}" = true ]; then
      menu_prompt_value '独立 Gecko 密码（8–128 位）' '' true || return 1; hy2_gecko_password="${MENU_VALUE}"
    fi
    menu_prompt_value '客户端下行带宽（Mbps）' 100 false || return 1; hy2_bandwidth="${MENU_VALUE}"
    hy2_patch="$(hy2_build_config_patch "${hy2_port}" "${hy2_password}" "${domain}" "${hy2_range}" "${hy2_interval}" "${hy2_gecko}" "${hy2_gecko_password}" "${hy2_bandwidth}")" ||
      { printf '%s\n' 'Hysteria2 参数不符合要求，请检查端口、范围和密码。' >&2; return 1; }
  fi

  if [ "${enabled_snell}" = false ] && [ "${enabled_anytls}" = false ] && [ "${enabled_hy2}" = false ]; then
    printf '%s\n' '至少需要启用一种协议。' >&2
    return 1
  fi
  printf '\n将部署：%s%s%s\n' \
    "$([ "${enabled_snell}" = true ] && printf 'Snell ')" \
    "$([ "${enabled_anytls}" = true ] && printf 'AnyTLS ')" \
    "$([ "${enabled_hy2}" = true ] && printf 'Hysteria2（Gecko=%s，包大小 512–1200）' "${hy2_gecko}")"
  printf '域名：%s\n公网 IP：%s\n' "${domain}" "${public_ip}"
  menu_prompt_value '输入 DEPLOY 确认部署' '' false || return 1; confirmation="${MENU_VALUE}"
  [ "${confirmation}" = DEPLOY ] || { printf '%s\n' '已取消部署。'; return 0; }

  interactive_set_protocol_enabled snell "${enabled_snell}" || return 1
  interactive_set_protocol_enabled anytls "${enabled_anytls}" || return 1
  interactive_set_protocol_enabled hysteria2 "${enabled_hy2}" || return 1
  [ "${enabled_snell}" = false ] || state_patch "${CONFIG_PATH}" "${snell_patch}" >/dev/null || return 1
  [ "${enabled_anytls}" = false ] || state_patch "${CONFIG_PATH}" "${anytls_patch}" >/dev/null || return 1
  [ "${enabled_hy2}" = false ] || state_patch "${CONFIG_PATH}" "${hy2_patch}" >/dev/null || return 1
  formal_deploy_execute "${public_ip}" --confirm
}

interactive_show_status() {
  state_read "${CONFIG_PATH}"
  local unit
  for unit in proxy-installer-snell.service proxy-installer-anytls.service proxy-installer-hysteria2.service; do
    printf '%s=' "${unit}"
    "${SYSTEMCTL_BIN:-systemctl}" is-active "${unit}" 2>/dev/null || true
  done
}

interactive_show_export() {
  deploy_paths_load_defaults
  local export_target="${PROXY_INSTALLER_EXPORT_TARGET:-${DEPLOY_STATE_ROOT}/exports/surge.conf}"
  [ -f "${export_target}" ] || { printf '%s\n' '尚未生成 Surge 配置，请先完成部署。'; return 0; }
  printf '%s\n' "Surge 配置文件：${export_target}"
  sed -n '1,200p' "${export_target}"
}

interactive_renew_certificate() {
  deploy_paths_load_defaults
  local operation_id="${PROXY_INSTALLER_OPERATION_ID:-certificate-$("${DEPLOY_DATE_BIN:-date}" -u '+%Y%m%dT%H%M%SZ')-$$}"
  "${CERTIFICATE_RENEW_EXECUTOR:-certificate_renew_execute}" \
    "${CONFIG_PATH}" "${PROXY_INSTALLER_BINARY_DIR:-${DEPLOY_BINARY_DIR}}" \
    "${PROXY_INSTALLER_CERTIFICATE_DIR:-${DEPLOY_CERTIFICATE_DIR}}" \
    "${PROXY_INSTALLER_STATE_ROOT:-${DEPLOY_STATE_ROOT}}" \
    "${operation_id}" "${PROXY_INSTALLER_RENEW_LOG_LINES:-20}"
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

if [ "${1:-}" = "--validate-deploy" ]; then
  [ "$#" -eq 2 ] || { usage >&2; exit 2; }
  environment_check || exit 1
  deploy_validate_run "${CONFIG_PATH}" "$2" "${MANIFEST_DIR}"
  exit $?
fi

if [ "${1:-}" = "--deploy" ]; then
  [ "$#" -eq 3 ] || { usage >&2; exit 2; }
  formal_deploy_execute "$2" "$3"
  exit $?
fi

if [ "${1:-}" = "--certificate-preflight" ]; then
  [ "$#" -eq 2 ] || { usage >&2; exit 2; }
  deploy_certificates_preflight "${CONFIG_PATH}" "$2"
  exit $?
fi

if [ "${1:-}" = "--renew-certificate" ]; then
  [ "$#" -eq 1 ] || { usage >&2; exit 2; }
  interactive_renew_certificate
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
    printf '\n%s\n' 'Surge Proxy Installer'
    menu_render_main
    printf '%s' '请选择：'
    IFS= read -r choice || return 0
    local action
    action="$(menu_parse_main "${choice}")" || { printf '%s\n' '输入无效，请重试。'; continue; }
    [ "${action}" = exit ] && { result_render skipped 'user exited the script' 'exit'; return 0; }
    case "${action}" in
      deploy) interactive_guided_deploy || printf '%s\n' '部署未完成，请根据上方提示检查后重试。' >&2 ;;
      status) interactive_show_status ;;
      export) interactive_show_export ;;
      certificate) interactive_renew_certificate || printf '%s\n' '证书检查未完成。' >&2 ;;
    esac
    menu_pause
  done
}

main "$@"
