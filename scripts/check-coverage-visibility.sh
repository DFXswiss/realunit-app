#!/usr/bin/env bash
#
# Coverage visibility gate — closes the "never-loaded in-scope file" blind spot.
#
# `flutter test --coverage` only records libraries that were actually LOADED
# during the run. An in-scope .dart file that no test ever imports contributes
# 0/0 to lcov and is therefore INVISIBLE to the scoped line-coverage summary:
# the floor gate stays green at "100 %" while the file is entirely untested.
# The scoped % says nothing about it because it is in neither the numerator nor
# the denominator. This check enumerates the on-disk activated surface and fails
# when a file that should carry coverage produced no `SF:` record in the scoped
# tracefile.
#
# Files that legitimately produce no coverable lines — pure abstract interfaces
# / ports, export-only barrels, const/enum-only declarations — are listed in the
# committed allowlist. The set is a ratchet: a NEW invisible in-scope file fails
# the build until it is either tested (preferred) or, only if it genuinely has
# no coverable lines, added to the allowlist in the same PR with a reason.
#
# Usage: check-coverage-visibility.sh <scoped-lcov.info> <allowlist-file>
set -euo pipefail

TRACEFILE="${1:?usage: check-coverage-visibility.sh <scoped-lcov.info> <allowlist>}"
ALLOWLIST="${2:?usage: check-coverage-visibility.sh <scoped-lcov.info> <allowlist>}"

if [ ! -f "$TRACEFILE" ]; then
  echo "::error::scoped tracefile '$TRACEFILE' not found"
  exit 1
fi
if [ ! -f "$ALLOWLIST" ]; then
  echo "::error::coverage visibility allowlist '$ALLOWLIST' not found"
  exit 1
fi

# Byte collation so the sort order the `comm` calls below rely on is identical
# regardless of the runner's locale.
export LC_ALL=C

ondisk="$(mktemp)"
loaded="$(mktemp)"
invisible="$(mktemp)"
allow="$(mktemp)"
trap 'rm -f "$ondisk" "$loaded" "$invisible" "$allow"' EXIT

# On-disk activated surface. The `case` patterns are the exact lcov --extract
# patterns from the "Filter coverage to README scope" step in
# pull-request.yaml; shell `case` globbing lets `*` span `/`, matching lcov's
# fnmatch. `*.g.dart` is excluded to mirror the `lcov --remove '*.g.dart'` that
# follows the extract. Keep these patterns in lockstep with that step.
{
  find lib -name '*.dart' -type f | while IFS= read -r f; do
    case "$f" in
      *.g.dart) continue ;;
    esac
    case "$f" in
      lib/packages/*|lib/screens/*/cubit/*|lib/screens/*/cubits/*|lib/screens/*/bloc/*)
        printf '%s\n' "$f"
        ;;
    esac
  done
} | sort -u > "$ondisk"

# SF: paths from the scoped tracefile, normalised to repo-relative `lib/…`. The
# `|| true` keeps a tracefile with no SF: record (an upstream failure the floor
# gate already reds) from aborting the pipeline under `pipefail` with no
# diagnostic — it instead flows through as every in-scope file being reported.
# The sed only rewrites ABSOLUTE paths (leading `/`); Flutter emits relative
# `lib/…` paths, which pass through untouched.
{ grep '^SF:' "$TRACEFILE" || true; } | sed 's/^SF://' | sed -E 's#^/.*/lib/#lib/#' | sort -u > "$loaded"

# Invisible = in-scope on disk but absent from the tracefile (never loaded, or
# loaded with no coverable line — either way it contributes no coverage signal).
comm -23 "$ondisk" "$loaded" > "$invisible"

# Allowlist, minus comment/blank lines. The `|| true` is load-bearing: once
# every entry has been tested and pruned, an all-comment allowlist makes `grep`
# exit 1, which under `pipefail` would abort the whole gate with a cryptic
# non-zero exactly in the "everything covered" state where it must stay green.
{ grep -vE '^[[:space:]]*(#|$)' "$ALLOWLIST" || true; } | sort -u > "$allow"

# Stale allowlist entries (now covered, or deleted from the tree) — surfaced so
# the ratchet does not rot. Informational, never a failure.
stale="$(comm -13 "$invisible" "$allow" || true)"
if [ -n "$stale" ]; then
  echo "::warning::coverage visibility allowlist has stale entries (now covered or removed) — prune them from $ALLOWLIST:"
  printf '%s\n' "$stale" | sed 's/^/::warning::  /'
fi

# Fail on any invisible file that is not allow-listed.
offenders="$(comm -23 "$invisible" "$allow" || true)"
if [ -n "$offenders" ]; then
  echo "::error::in-scope file(s) never exercised by any test — invisible to the coverage gate (0/0, not counted in the scoped %):"
  printf '%s\n' "$offenders" | sed 's/^/::error::  /'
  echo "::error::Fix: add a test that imports and exercises the file (preferred). Only if it genuinely has no coverable lines, add it to $ALLOWLIST with a one-line reason."
  exit 1
fi

echo "coverage visibility OK: $(wc -l < "$ondisk" | tr -d ' ') in-scope file(s), $(wc -l < "$invisible" | tr -d ' ') lineless/allow-listed, 0 unexpected blind spots"
