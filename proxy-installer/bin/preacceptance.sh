#!/usr/bin/env bash
# Local-only gate for deciding whether a build may enter Debian 13 acceptance.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT=""
VERIFY=false

usage() { printf '%s\n' 'usage: preacceptance.sh [--verify] [--report path]'; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    --verify) VERIFY=true ;;
    --report) shift; [ "$#" -gt 0 ] || { usage >&2; exit 2; }; REPORT="$1" ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done

required=(
  lib/registry/protocols.sh lib/config/state.sh lib/transaction/transaction.sh
  lib/orchestrators/deploy_execute.sh lib/orchestrators/config_apply_execute.sh
  lib/orchestrators/update_execute.sh lib/orchestrators/uninstall_execute.sh
  lib/orchestrators/revision_restore_execute.sh lib/orchestrators/certificate_execute.sh
  docs/debian13-acceptance-record-template.md docs/local-preacceptance-coverage.md packaging/build.sh packaging/smoke.sh
)
missing=0
for relative in "${required[@]}"; do [ -f "${ROOT}/${relative}" ] || { printf 'missing=%s\n' "${relative}" >&2; missing=1; }; done
[ "${missing}" -eq 0 ] || exit 1
if [ "${VERIFY}" = true ]; then
  PYTHONPATH="${ROOT}/../.python-packages${PYTHONPATH:+:${PYTHONPATH}}" python3 -m unittest discover -s "${ROOT}/tests" -q
  "${ROOT}/packaging/build.sh" >/dev/null
  "${ROOT}/packaging/smoke.sh" "${ROOT}/dist/proxy-installer-local.tar.gz" >/dev/null
fi
if [ -n "${REPORT}" ]; then
  report_dir="$(dirname "${REPORT}")"; mkdir -p "${report_dir}"
  printf '%s\n' 'local_preacceptance=pass' "verification_run=${VERIFY}" 'real_acceptance=not-run' 'scope=isolated-local-tests-and-package-smoke' 'next_gate=authorized-debian-13-and-ios-surge-acceptance' > "${REPORT}"
  chmod 600 "${REPORT}"
fi
printf '%s\n' 'preacceptance=pass' 'real_acceptance=not-run'
