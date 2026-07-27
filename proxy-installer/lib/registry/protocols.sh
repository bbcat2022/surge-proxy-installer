#!/usr/bin/env bash
# Static v1 protocol capability registry. Instance values belong in desired config.

set -o pipefail

protocol_registry_validate() {
  local protocol
  for protocol in snell anytls hysteria2; do
    protocol_registry_get "${protocol}" display_name >/dev/null || return 1
    protocol_registry_get "${protocol}" network >/dev/null || return 1
    protocol_registry_get "${protocol}" tls >/dev/null || return 1
    protocol_registry_get "${protocol}" binary_id >/dev/null || return 1
    protocol_registry_get "${protocol}" service_name >/dev/null || return 1
    protocol_registry_get "${protocol}" runtime_path >/dev/null || return 1
  done
}

protocol_registry_get() {
  local protocol="$1"
  local field="$2"
  case "${protocol}:${field}" in
    snell:display_name) printf '%s\n' 'Snell v6' ;;
    snell:network) printf '%s\n' 'tcp' ;;
    snell:default_port) printf '%s\n' '443' ;;
    snell:tls) printf '%s\n' 'false' ;;
    snell:binary_id) printf '%s\n' 'snell-server' ;;
    snell:service_name) printf '%s\n' 'proxy-installer-snell.service' ;;
    snell:runtime_path) printf '%s\n' '/etc/proxy-installer/runtime/snell.conf' ;;
    snell:health_check) printf '%s\n' 'systemd-active,tcp-listen,binary-version' ;;
    anytls:display_name) printf '%s\n' 'AnyTLS' ;;
    anytls:network) printf '%s\n' 'tcp' ;;
    anytls:default_port) printf '%s\n' '443' ;;
    anytls:tls) printf '%s\n' 'shared-main-domain' ;;
    anytls:binary_id) printf '%s\n' 'sing-box' ;;
    anytls:service_name) printf '%s\n' 'proxy-installer-anytls.service' ;;
    anytls:runtime_path) printf '%s\n' '/etc/proxy-installer/runtime/anytls.json' ;;
    anytls:health_check) printf '%s\n' 'systemd-active,tcp-listen,binary-version' ;;
    hysteria2:display_name) printf '%s\n' 'Hysteria2' ;;
    hysteria2:network) printf '%s\n' 'udp,udp-range' ;;
    hysteria2:default_port) printf '%s\n' '443' ;;
    hysteria2:tls) printf '%s\n' 'shared-main-domain' ;;
    hysteria2:binary_id) printf '%s\n' 'hysteria' ;;
    hysteria2:service_name) printf '%s\n' 'proxy-installer-hysteria2.service' ;;
    hysteria2:runtime_path) printf '%s\n' '/etc/proxy-installer/runtime/hysteria2.yaml' ;;
    hysteria2:health_check) printf '%s\n' 'systemd-active,udp-listen,binary-version' ;;
    *) return 1 ;;
  esac
}

protocol_registry_parameters() {
  local protocol="$1"
  case "${protocol}" in
    snell)
      printf '%s\n' 'port:integer:required:false'
      printf '%s\n' 'psk:string:required:true'
      printf '%s\n' 'client_address_type:enum:required:false'
      printf '%s\n' 'client_address:string:required:true'
      printf '%s\n' 'mode:enum:required:false'
      ;;
    anytls)
      printf '%s\n' 'port:integer:required:false'
      printf '%s\n' 'password:string:required:true'
      printf '%s\n' 'tfo:boolean:optional:false'
      printf '%s\n' 'reuse:boolean:optional:false'
      ;;
    hysteria2)
      printf '%s\n' 'port:integer:required:false'
      printf '%s\n' 'password:string:required:true'
      printf '%s\n' 'port_hopping_range:string:optional:false'
      printf '%s\n' 'hop_interval:integer:optional:false'
      printf '%s\n' 'gecko:string:optional:true'
      printf '%s\n' 'download_bandwidth:integer:optional:false'
      ;;
    *) return 1 ;;
  esac
}
