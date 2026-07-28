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

menu_prompt_value() {
  # label default secret(true|false)
  local label="$1" default_value="$2" secret="${3:-false}" value
  if [ -n "${default_value}" ]; then printf '%s [%s]：' "${label}" "${default_value}" >&2
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
