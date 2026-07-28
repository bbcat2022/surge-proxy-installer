#!/usr/bin/env bash
# Static v1 protocol capability registry. Instance values belong in desired config.

set -o pipefail

protocol_registry_validate() {
  local protocol field value
  for protocol in snell anytls hysteria2; do
    for field in id display_name generation network port_resource default_port tls binary_id binary_sharing service_name runtime_path health_check validate_builder runtime_builder unit_builder client_export_builder config_patch_builder resource_builder; do
      value="$(protocol_registry_get "${protocol}" "${field}")" && [ -n "${value}" ] || return 1
    done
    [ "$(protocol_registry_get "${protocol}" id)" = "${protocol}" ] || return 1
    [[ "$(protocol_registry_get "${protocol}" default_port)" =~ ^[0-9]+$ ]] || return 1
    [[ "$(protocol_registry_get "${protocol}" service_name)" =~ ^[a-z0-9._@-]+\.service$ ]] || return 1
    [[ "$(protocol_registry_get "${protocol}" runtime_path)" = /* ]] || return 1
    protocol_registry_validate_parameters "${protocol}" || return 1
  done
}

protocol_registry_get() {
  local protocol="$1"
  local field="$2"
  case "${protocol}:${field}" in
    snell:id) printf '%s\n' 'snell' ;;
    snell:display_name) printf '%s\n' 'Snell v6' ;;
    snell:generation) printf '%s\n' '6' ;;
    snell:network) printf '%s\n' 'tcp' ;;
    snell:port_resource) printf '%s\n' 'tcp-single' ;;
    snell:default_port) printf '%s\n' '443' ;;
    snell:tls) printf '%s\n' 'false' ;;
    snell:binary_id) printf '%s\n' 'snell-server' ;;
    snell:binary_sharing) printf '%s\n' 'exclusive' ;;
    snell:service_name) printf '%s\n' 'proxy-installer-snell.service' ;;
    snell:runtime_path) printf '%s\n' '/etc/proxy-installer/runtime/snell.conf' ;;
    snell:health_check) printf '%s\n' 'systemd-active,tcp-listen,binary-version' ;;
    snell:validate_builder) printf '%s\n' 'snell_validate' ;;
    snell:runtime_builder) printf '%s\n' 'snell_build_runtime' ;;
    snell:unit_builder) printf '%s\n' 'snell_build_unit' ;;
    snell:client_export_builder) printf '%s\n' 'snell_build_surge_entry' ;;
    snell:config_patch_builder) printf '%s\n' 'snell_build_config_patch' ;;
    snell:resource_builder) printf '%s\n' 'snell_resource_requirements' ;;
    anytls:id) printf '%s\n' 'anytls' ;;
    anytls:display_name) printf '%s\n' 'AnyTLS' ;;
    anytls:generation) printf '%s\n' '1' ;;
    anytls:network) printf '%s\n' 'tcp' ;;
    anytls:port_resource) printf '%s\n' 'tcp-single' ;;
    anytls:default_port) printf '%s\n' '443' ;;
    anytls:tls) printf '%s\n' 'shared-main-domain' ;;
    anytls:binary_id) printf '%s\n' 'sing-box' ;;
    anytls:binary_sharing) printf '%s\n' 'shared-compatible' ;;
    anytls:service_name) printf '%s\n' 'proxy-installer-anytls.service' ;;
    anytls:runtime_path) printf '%s\n' '/etc/proxy-installer/runtime/anytls.json' ;;
    anytls:health_check) printf '%s\n' 'systemd-active,tcp-listen,binary-version' ;;
    anytls:validate_builder) printf '%s\n' 'anytls_validate' ;;
    anytls:runtime_builder) printf '%s\n' 'anytls_build_runtime' ;;
    anytls:unit_builder) printf '%s\n' 'anytls_build_unit' ;;
    anytls:client_export_builder) printf '%s\n' 'anytls_build_surge_entry' ;;
    anytls:config_patch_builder) printf '%s\n' 'anytls_build_config_patch' ;;
    anytls:resource_builder) printf '%s\n' 'anytls_resource_requirements' ;;
    hysteria2:id) printf '%s\n' 'hysteria2' ;;
    hysteria2:display_name) printf '%s\n' 'Hysteria2' ;;
    hysteria2:generation) printf '%s\n' '2' ;;
    hysteria2:network) printf '%s\n' 'udp,udp-range' ;;
    hysteria2:port_resource) printf '%s\n' 'udp-single,udp-range' ;;
    hysteria2:default_port) printf '%s\n' '443' ;;
    hysteria2:tls) printf '%s\n' 'shared-main-domain' ;;
    hysteria2:binary_id) printf '%s\n' 'hysteria' ;;
    hysteria2:binary_sharing) printf '%s\n' 'exclusive' ;;
    hysteria2:service_name) printf '%s\n' 'proxy-installer-hysteria2.service' ;;
    hysteria2:runtime_path) printf '%s\n' '/etc/proxy-installer/runtime/hysteria2.yaml' ;;
    hysteria2:health_check) printf '%s\n' 'systemd-active,udp-listen,binary-version' ;;
    hysteria2:validate_builder) printf '%s\n' 'hy2_validate' ;;
    hysteria2:runtime_builder) printf '%s\n' 'hy2_build_runtime' ;;
    hysteria2:unit_builder) printf '%s\n' 'hy2_build_unit' ;;
    hysteria2:client_export_builder) printf '%s\n' 'hy2_build_surge_entry' ;;
    hysteria2:config_patch_builder) printf '%s\n' 'hy2_build_config_patch' ;;
    hysteria2:resource_builder) printf '%s\n' 'hy2_resource_requirements' ;;
    *) return 1 ;;
  esac
}

protocol_registry_parameters() {
  local protocol="$1"
  case "${protocol}" in
    snell)
      printf '%s\n' 'port:integer:optional:false:443:port:always'
      printf '%s\n' 'psk:string:required:true::secret:always'
      printf '%s\n' 'client_address_type:enum:required:false::address-type:always'
      printf '%s\n' 'client_address:string:required:false::client-address:always'
      printf '%s\n' 'mode:enum:optional:false:default:snell-mode:always'
      ;;
    anytls)
      printf '%s\n' 'port:integer:optional:false:443:port:always'
      printf '%s\n' 'password:string:required:true::secret:always'
      printf '%s\n' 'domain:string:required:false::domain:always'
      printf '%s\n' 'tfo:boolean:optional:false:false:boolean:always'
      printf '%s\n' 'reuse:boolean:optional:false:false:boolean:always'
      ;;
    hysteria2)
      printf '%s\n' 'port:integer:optional:false:443:port:always'
      printf '%s\n' 'password:string:required:true::secret:always'
      printf '%s\n' 'domain:string:required:false::domain:always'
      printf '%s\n' 'port_hopping_range:string:optional:false::udp-range:always'
      printf '%s\n' 'hop_interval:integer:optional:false:10:hop-interval:port-hopping-enabled'
      printf '%s\n' 'gecko:boolean:optional:false:false:boolean:always'
      printf '%s\n' 'gecko_password:string:conditional:true::secret:gecko-enabled'
      printf '%s\n' 'min_packet_size:integer:fixed:false:512:packet-size:gecko-enabled'
      printf '%s\n' 'max_packet_size:integer:fixed:false:1200:packet-size:gecko-enabled'
      printf '%s\n' 'download_bandwidth:integer:optional:false:100:bandwidth:always'
      ;;
    *) return 1 ;;
  esac
}

protocol_registry_parameter_get() {
  [ "$#" -eq 3 ] || return 1
  local protocol="$1" requested_name="$2" requested_field="$3"
  local name type requirement sensitive default_value validator dependency
  while IFS=: read -r name type requirement sensitive default_value validator dependency; do
    [ "${name}" = "${requested_name}" ] || continue
    case "${requested_field}" in
      type) printf '%s\n' "${type}" ;;
      requirement) printf '%s\n' "${requirement}" ;;
      sensitive) printf '%s\n' "${sensitive}" ;;
      default) printf '%s\n' "${default_value}" ;;
      validator) printf '%s\n' "${validator}" ;;
      dependency) printf '%s\n' "${dependency}" ;;
      *) return 1 ;;
    esac
    return 0
  done < <(protocol_registry_parameters "${protocol}") || return 1
  return 1
}

protocol_registry_validate_parameters() {
  local protocol="$1" name type requirement sensitive default_value validator dependency count=0
  while IFS=: read -r name type requirement sensitive default_value validator dependency; do
    count=$((count + 1))
    [[ "${name}" =~ ^[a-z][a-z0-9_]*$ ]] || return 1
    [[ "${type}" =~ ^(string|integer|boolean|enum)$ ]] || return 1
    [[ "${requirement}" =~ ^(required|optional|conditional|fixed)$ ]] || return 1
    [[ "${sensitive}" =~ ^(true|false)$ ]] || return 1
    [[ "${validator}" =~ ^[a-z][a-z0-9-]*$ ]] || return 1
    [[ "${dependency}" =~ ^[a-z][a-z0-9-]*$ ]] || return 1
  done < <(protocol_registry_parameters "${protocol}") || return 1
  [ "${count}" -gt 0 ]
}
