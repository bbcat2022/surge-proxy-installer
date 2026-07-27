#!/usr/bin/env bash
# Revision restore plan builder; actual restoration must run in N3 transaction.

set -o pipefail

revision_restore_plan() {
  local state_root="$1" revision_id="$2"
  [[ "${revision_id}" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
  local revision_dir="${state_root}/revisions/${revision_id}"
  [ -d "${revision_dir}" ] && [ -f "${revision_dir}/config.yaml" ] || return 1
  printf '%s\n' 'operation=revision-restore' "target-revision=${revision_id}" 'preview=required' 'confirmation=strong-required' 'snapshot-current=true' 'restore-config=true' 'restore-derived-resources=true' 'restore-binary-version=required' 'restore-certificate-state=required' 'restore-firewall-state=required' 'health-verification=required' 'commit-new-revision=true' 'execution=transaction-required'
}
