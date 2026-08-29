#!/usr/bin/env bash
# Thin wrapper so local/CI can run the matcher without a simulator.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec "$ROOT/scripts/run-handbook-flows.sh" --matcher-self-test
