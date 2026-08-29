#!/usr/bin/env bash
# Unit-test is_driver_hang_or_death without a simulator / Maestro CLI.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
eval "$(sed -n '/^is_driver_hang_or_death()/,/^}$/p' "$ROOT/scripts/run-handbook-flows.sh")"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

printf '%s\n' \
  'Running flow 01-welcome' \
  'Assert that "Start" is visible...Exception in thread "main" UnknownFailure(errorResponse=Request for http://127.0.0.1:7001/deviceInfo failed, code: 500, body: )' \
  > "$tmp"
is_driver_hang_or_death "$tmp" || {
  echo 'expected HTTP 500 deviceInfo after Running flow to match' >&2
  exit 1
}

printf '%s\n' 'Running flow 01-welcome' 'Assert that "Start" is visible' > "$tmp"
if is_driver_hang_or_death "$tmp"; then
  echo 'bare assertion must not match' >&2
  exit 1
fi

printf '%s\n' 'java.net.ConnectException: Connection refused' > "$tmp"
is_driver_hang_or_death "$tmp" || {
  echo 'expected ConnectException without Running flow to match' >&2
  exit 1
}

echo ok
