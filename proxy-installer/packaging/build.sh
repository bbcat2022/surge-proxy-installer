#!/usr/bin/env bash
# Build a self-contained source package without local dependencies or test artifacts.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-${ROOT}/dist}"
NAME="proxy-installer-local.tar.gz"
mkdir -p "${OUT_DIR}"
tar -C "$(dirname "${ROOT}")" --exclude='proxy-installer/.python-packages' --exclude='proxy-installer/__pycache__' --exclude='proxy-installer/dist' -czf "${OUT_DIR}/${NAME}" proxy-installer/bin proxy-installer/lib proxy-installer/tools proxy-installer/docs proxy-installer/bootstrap proxy-installer/manifests proxy-installer/requirements-dev.txt proxy-installer/README.md proxy-installer/AGENTS.md
printf '%s\n' "${OUT_DIR}/${NAME}"
