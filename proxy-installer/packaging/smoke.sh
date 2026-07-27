#!/usr/bin/env bash
set -euo pipefail
PACKAGE="$1"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
tar -C "${WORK}" -xzf "${PACKAGE}"
test -x "${WORK}/proxy-installer/bin/proxy-installer.sh"
test -f "${WORK}/proxy-installer/tools/config_tool.py"
test -f "${WORK}/proxy-installer/lib/transaction/transaction.sh"
test -f "${WORK}/proxy-installer/docs/debian13-acceptance-record-template.md"
test -f "${WORK}/proxy-installer/docs/local-preacceptance-coverage.md"
test -x "${WORK}/proxy-installer/bootstrap/install.sh"
test -f "${WORK}/proxy-installer/manifests/snell-amd64.txt"
printf '%s\n' 'package-smoke=success'
