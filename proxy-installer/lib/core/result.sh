#!/usr/bin/env bash
# Uniform non-sensitive result rendering for high-impact operations.

set -o pipefail

result_render() {
  local status="$1" summary="$2" operation_id="$3"
  case "${status}" in success|partial-success|failed|rollback-success|dirty|skipped) ;; *) return 1 ;; esac
  printf 'operation-id=%s\nstatus=%s\nsummary=%s\n' "${operation_id}" "${status}" "${summary}"
  case "${status}" in
    success) printf '%s\n' 'next=operation-complete' ;;
    partial-success) printf '%s\n' 'next=check-client-export-or-history' ;;
    rollback-success) printf '%s\n' 'next=previous-service-state-restored' ;;
    failed) printf '%s\n' 'next=review-error-and-retry' ;;
    dirty) printf '%s\n' 'next=manual-repair-required' ;;
    skipped) printf '%s\n' 'next=no-system-change-made' ;;
  esac
}
