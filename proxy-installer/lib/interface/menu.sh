#!/usr/bin/env bash
# Menu rendering and input helpers. They do not modify configuration or invoke system commands.

set -o pipefail

menu_render_main() {
  printf '%s\n' \
    '1) 配置并部署代理服务' \
    '2) 查看当前状态' \
    '3) 查看 Surge 配置' \
    '4) 检查并更新 TLS 证书' \
    '5) 退出'
}
menu_parse_main() { case "$1" in 1) printf deploy;; 2) printf status;; 3) printf export;; 4) printf certificate;; 5) printf exit;; *) return 1;; esac; }
menu_confirm() { case "$1" in 1) return 0;; 2) return 1;; *) return 2;; esac; }

menu_render_protocol_selection() {
  printf '%s\n' \
    '请选择要部署的协议（可多选，例如 1,2,3）：' \
    '1) Snell v6 Beta' \
    '2) AnyTLS' \
    '3) Hysteria2' \
    '4) 返回主菜单'
}

menu_parse_protocol_selection() {
  local raw="${1// /}" item
  local selected_snell=false selected_anytls=false selected_hy2=false
  [ -n "${raw}" ] || return 1
  [ "${raw}" != 4 ] || { printf '%s\n' back; return 0; }
  IFS=',' read -r -a protocol_choices <<< "${raw}"
  for item in "${protocol_choices[@]}"; do
    case "${item}" in
      1) selected_snell=true ;;
      2) selected_anytls=true ;;
      3) selected_hy2=true ;;
      *) return 1 ;;
    esac
  done
  local result=()
  [ "${selected_snell}" = false ] || result+=(snell)
  [ "${selected_anytls}" = false ] || result+=(anytls)
  [ "${selected_hy2}" = false ] || result+=(hysteria2)
  [ "${#result[@]}" -gt 0 ] || return 1
  (IFS=,; printf '%s\n' "${result[*]}")
}

menu_prompt_value() {
  # label default secret(true|false)
  local label="$1" default_value="$2" secret="${3:-false}" value
  if [ "${secret}" = true ] && [ -n "${default_value}" ]; then printf '%s [直接回车自动生成]：' "${label}" >&2
  elif [ -n "${default_value}" ]; then printf '%s [%s]：' "${label}" "${default_value}" >&2
  else printf '%s：' "${label}" >&2
  fi
  if [ "${secret}" = true ]; then
    IFS= read -r -s value || return 1
    printf '\n' >&2
  else
    IFS= read -r value || return 1
  fi
  MENU_VALUE="${value:-${default_value}}"
}

menu_prompt_yes_no() {
  # label default(true|false)
  local label="$1" default_value="$2" hint answer
  [ "${default_value}" = true ] && hint=Y/n || hint=y/N
  printf '%s [%s]：' "${label}" "${hint}" >&2
  IFS= read -r answer || return 1
  case "${answer}" in
    '') MENU_BOOLEAN="${default_value}" ;;
    y|Y|yes|YES|Yes) MENU_BOOLEAN=true ;;
    n|N|no|NO|No) MENU_BOOLEAN=false ;;
    *) printf '%s\n' '请输入 y 或 n。' >&2; return 2 ;;
  esac
}

menu_pause() {
  printf '%s' '按回车键返回主菜单。' >&2
  IFS= read -r _ || true
}
