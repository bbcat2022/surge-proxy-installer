#!/usr/bin/env bash
# Pure menu rendering/input helpers. Actions are provided by later orchestrators.

set -o pipefail

menu_render_main() { printf '%s\n' '1) 部署服务' '2) 代理服务管理' '3) 证书管理' '4) 配置管理' '5) 退出'; }
menu_parse_main() { case "$1" in 1) printf deploy;; 2) printf service;; 3) printf certificate;; 4) printf config;; 5) printf exit;; *) return 1;; esac; }
menu_confirm() { case "$1" in 1) return 0;; 2) return 1;; *) return 2;; esac; }
