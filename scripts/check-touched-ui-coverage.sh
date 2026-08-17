#!/usr/bin/env bash
#
# Enforce 100% line coverage on every UI file touched by the PR.
#
# Scope: paths under lib/screens/** or lib/widgets/** that are not cubit/bloc
# folders and not generated *.g.dart. Measured against the FULL lcov.info
# (before the packages/cubits/blocs scope extract). The existing floor gate on
# packages/cubits/blocs is unchanged and is NOT widened to the whole widget tree.
#
# Usage: check-touched-ui-coverage.sh <full-lcov.info> <base-ref>
#
# Exit codes:
#   0 — no touched UI files, or every touched UI file has LH==LF and LF>0
#   1 — a touched UI file is missing from lcov or has uncovered lines
set -euo pipefail

TRACEFILE="${1:?usage: check-touched-ui-coverage.sh <full-lcov.info> <base-ref>}"
BASE="${2:?usage: check-touched-ui-coverage.sh <full-lcov.info> <base-ref>}"

if [ ! -f "$TRACEFILE" ]; then
  echo "error: lcov file '$TRACEFILE' not found" >&2
  exit 1
fi

export LC_ALL=C

# Collect touched UI files relative to the merge base. Triple-dot uses the
# merge-base of BASE and HEAD so the set matches the PR diff.
touched="$(mktemp)"
trap 'rm -f "$touched"' EXIT

git diff --name-only "${BASE}...HEAD" | while IFS= read -r f; do
  case "$f" in
    lib/screens/*|lib/widgets/*) ;;
    *) continue ;;
  esac
  case "$f" in
    *.g.dart) continue ;;
    */cubit/*|*/cubits/*|*/bloc/*) continue ;;
  esac
  case "$f" in
    *.dart) printf '%s\n' "$f" ;;
  esac
done | sort -u > "$touched"

if [ ! -s "$touched" ]; then
  echo "No touched UI files under lib/screens/** or lib/widgets/** — OK"
  exit 0
fi

failed=0

while IFS= read -r file; do
  # Normalise SF: paths the same way as check-coverage-visibility.sh:
  # absolute .../lib/foo → lib/foo; relative lib/foo passes through.
  section="$(
    awk -v target="$file" '
      BEGIN { capturing = 0; block = "" }
      /^SF:/ {
        path = substr($0, 4)
        sub(/^\/.*\/lib\//, "lib/", path)
        if (path == target) {
          capturing = 1
          block = $0 "\n"
        } else {
          capturing = 0
        }
        next
      }
      capturing {
        block = block $0 "\n"
        if ($0 == "end_of_record") {
          printf "%s", block
          exit 0
        }
      }
    ' "$TRACEFILE"
  )"

  if [ -z "$section" ]; then
    echo "error: touched UI file missing from lcov: $file" >&2
    failed=1
    continue
  fi

  lh="$(printf '%s' "$section" | sed -nE 's/^LH:([0-9]+).*/\1/p' | head -n1)"
  lf="$(printf '%s' "$section" | sed -nE 's/^LF:([0-9]+).*/\1/p' | head -n1)"

  if [ -z "${lh:-}" ] || [ -z "${lf:-}" ]; then
    echo "error: could not parse LH/LF for $file" >&2
    failed=1
    continue
  fi

  if [ "$lf" -eq 0 ]; then
    echo "error: $file has LF=0 (no instrumented lines) in lcov" >&2
    failed=1
    continue
  fi

  if [ "$lh" -ne "$lf" ]; then
    echo "error: $file line coverage ${lh}/${lf} is below 100%" >&2
    failed=1
    continue
  fi

  echo "OK: $file ${lh}/${lf}"
done < "$touched"

if [ "$failed" -ne 0 ]; then
  echo "error: one or more touched UI files lack 100% line coverage" >&2
  exit 1
fi

echo "All touched UI files have 100% line coverage"
exit 0
