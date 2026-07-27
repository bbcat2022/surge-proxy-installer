#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PYTHONPATH="${ROOT}/../.python-packages${PYTHONPATH:+:${PYTHONPATH}}"
python3 -m unittest discover -s "${ROOT}/tests" -v
