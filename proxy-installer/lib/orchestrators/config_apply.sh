#!/usr/bin/env bash
# Field-level impact planner for a single configuration-apply transaction.

set -o pipefail

config_apply_plan() {
  local protocol="$1" field="$2"
  case "${protocol}:${field}" in
    anytls:tfo|anytls:reuse)
      printf '%s\n' 'runtime=false' 'service-restart=false' 'surge-export=true' 'firewall=false'
      ;;
    anytls:port|anytls:password)
      printf '%s\n' 'runtime=true' 'service-restart=true' 'surge-export=true' 'firewall=true'
      ;;
    hysteria2:port|hysteria2:port_hopping_range|hysteria2:hop_interval|hysteria2:password|hysteria2:gecko|hysteria2:gecko_password)
      printf '%s\n' 'runtime=true' 'service-restart=true' 'surge-export=true' 'firewall=true'
      ;;
    hysteria2:download_bandwidth)
      printf '%s\n' 'runtime=false' 'service-restart=false' 'surge-export=true' 'firewall=false'
      ;;
    snell:port|snell:psk)
      printf '%s\n' 'runtime=true' 'service-restart=true' 'surge-export=true' 'firewall=true'
      ;;
    snell:client_address_type|snell:client_address|snell:mode)
      printf '%s\n' 'runtime=false' 'service-restart=false' 'surge-export=true' 'firewall=false'
      ;;
    global:main_domain)
      printf '%s\n' 'runtime=true' 'service-restart=true' 'surge-export=true' 'firewall=true' 'certificate=candidate-required'
      ;;
    *) return 1 ;;
  esac
}
