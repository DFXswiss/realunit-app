#!/usr/bin/env bash
#
# Tier-3 navigation smoke for the 26 .maestro/handbook/*.yaml flows.
#
# For each flow (alphabetical order):
#   1. run the Maestro flow — navigates the real built app to the target
#      screen and asserts the expected UI state is reachable
#   2. take a diagnostic screenshot via `xcrun simctl io booted screenshot`,
#      written to build/handbook-captures/ so CI can attach it as an
#      artifact for forensic inspection on assertion failures
#
# NOT the source of `handbook.realunit.app` screenshots — those are the
# visual-regression Golden baselines under test/goldens/screens/, mapped
# by scripts/assemble-handbook-screenshots.sh. See docs/handbook/README.md.
#
# Why xcrun rather than Maestro's built-in `takeScreenshot`?
#   Maestro screenshots go through XCUITest, which renders the view-hierarchy
#   bitmap. Flutter screens that use `BackdropFilter` (e.g. SeedBlurCard on
#   the seed-backup pages) live on a GPU layer outside that bitmap and come
#   out as solid black PNGs. `xcrun simctl io booted screenshot` uses the
#   simulator's compositor and captures the actual final frame.
#
# Required:
#   * iOS Simulator booted with Runner.app installed (`flutter build ios
#     --simulator --debug` then `xcrun simctl install booted ...Runner.app`)
#   * maestro CLI on PATH (or at $HOME/.maestro/bin/maestro)
#
# Locale:
#   The booted simulator's locale is pinned to de_CH because the handbook
#   flows assert on German UI strings (e.g. "Digitale Wallet", "Erstellen
#   Sie Ihre PIN", "Einstellungen"). Local devs running this script will
#   have their simulator locale temporarily overridden; `simctl erase` on
#   the next run brings it back to defaults. CI runners default to en_US
#   without this pin and would fail the first German-string assertion.
#
# Retry strategy:
#   The Maestro version is pinned by `.maestro-version` (read by the
#   workflow's install step). Historically Maestro 2.3.x–2.5.x had
#   intermittent driver-hang AND silent-tap-loss issues on Apple
#   Silicon + iOS 26.x (see mobile-dev-inc/maestro#3137); the pin
#   targets a known-good release. The retry remains as a safety net
#   for residual Apple-XCTest crashes (~10 % per the #3137 thread):
#   each flow is retried up to MAESTRO_MAX_ATTEMPTS times (default 3)
#   when the CLI tee-log or `--debug-output` maestro.log matches the
#   driver hang/death class. `IOSDriverTimeoutException` matches
#   anywhere in the file. ConnectException / `Failed to connect to
#   /127.0.0.1:7001` / `Connection refused` / `Connection reset` only
#   count from the first `Running flow ` line onward (inclusive) —
#   every iOS start logs those strings during the XCTest installer
#   status-check *before* the flow. If `Running flow ` is absent the
#   whole file is searched (driver never came up). Maestro often
#   disguises XCUITest-driver death as a later assertion failure on
#   stdout while the ConnectException lives only in the debug log.
#   Assertion failures without those patterns are NEVER retried —
#   those are real regressions and must surface as red CI checks.
#
# Usage:
#   scripts/run-handbook-flows.sh                    # run ALL handbook flows
#   scripts/run-handbook-flows.sh 25-restore-wallet  # run only matching flows
#   scripts/run-handbook-flows.sh '2*' 12-settings   # multiple glob patterns
#
#   With no arguments every flow in .maestro/handbook/*.yaml runs (the
#   default, full-suite behaviour). With one or more positional arguments,
#   each argument is a bash glob pattern matched against the flow basename
#   (filename without the `.yaml` extension); only flows whose basename
#   matches AT LEAST ONE pattern are run, in the same deterministic sorted
#   order. If arguments are given but match zero flows the script exits 1.
#
# WARNING — handbook flows are a sequential CHAIN sharing app state:
#   The numbered flows are designed to run in order, each one continuing
#   from the app state the previous flow left behind. Running a mid-chain
#   flow in isolation will fail because it expects state set up by the
#   flows before it. Only flows that begin with their own `launchApp`
#   re-establish a known starting point and are therefore safe to run
#   alone — every other flow must be run together with its predecessors.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAESTRO="${MAESTRO:-$HOME/.maestro/bin/maestro}"
FLOWS_DIR="$REPO_ROOT/.maestro/handbook"
CAPTURES_DIR="$REPO_ROOT/build/handbook-captures"

mkdir -p "$CAPTURES_DIR"

if [ ! -x "$MAESTRO" ] && ! command -v maestro >/dev/null 2>&1; then
  echo "error: maestro CLI not found (expected at $MAESTRO or on PATH)" >&2
  exit 1
fi

if ! xcrun simctl list devices booted 2>/dev/null | grep -q Booted; then
  echo "error: no booted iOS simulator. Boot one and install Runner.app first." >&2
  exit 1
fi

# Maestro's `clearState` clears NSUserDefaults but does NOT clear the iOS
# Keychain. The app stores the wallet seed and PIN in Keychain, so without
# a full uninstall/reinstall the next run boots straight to the app-lock
# screen instead of the welcome flow. Reinstall to guarantee a clean start.
APP_ID="swiss.realunit.app"
APP_BUNDLE="${APP_BUNDLE:-$REPO_ROOT/build/ios/iphonesimulator/Runner.app}"

if [ ! -d "$APP_BUNDLE" ]; then
  echo "error: $APP_BUNDLE not found. Run:" >&2
  echo "  flutter build ios --simulator --debug" >&2
  exit 1
fi

# iOS Keychain on the simulator survives both `clearState` and a reinstall.
# The wallet + PIN are stored in Keychain, so a stale device boots straight
# to the app-lock screen instead of the onboarding flow. The reliable way to
# get a clean state is `simctl erase`, which wipes the device.
UDID="$(xcrun simctl list devices booted -j | /usr/bin/python3 -c "
import json, sys
for r, devs in json.load(sys.stdin)['devices'].items():
    for d in devs:
        if d.get('state') == 'Booted':
            print(d['udid']); sys.exit(0)
")"
if [ -z "$UDID" ]; then
  echo "error: could not resolve booted device UDID" >&2
  exit 1
fi

echo "Resetting simulator $UDID for a clean Keychain"
xcrun simctl shutdown "$UDID"
xcrun simctl erase "$UDID"
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b >/dev/null

# Pin simulator locale to de_CH. The handbook flows assert on German UI
# strings (e.g. "Digitale Wallet", "Erstellen Sie Ihre PIN", "Einstellungen")
# because the app's default locale is de_CH. CI runners boot iOS simulators
# in en_US by default, which would fail every German-string assertion on
# the very first flow that has one. Local developers usually have their
# simulator in de_CH already, so re-captures locally and on CI now match.
# Run after `bootstatus -b` so the device is guaranteed ready for
# `simctl spawn`, and use `spawn` so the defaults land in the booted
# device's domain, not the host's NSGlobalDomain.
echo "Pinning simulator locale to de_CH"
xcrun simctl spawn "$UDID" defaults write -g AppleLanguages -array de_CH
xcrun simctl spawn "$UDID" defaults write -g AppleLocale -string de_CH

echo "Installing $APP_ID from $APP_BUNDLE"
xcrun simctl install "$UDID" "$APP_BUNDLE"

shopt -s nullglob
flows=("$FLOWS_DIR"/*.yaml)
if [ "${#flows[@]}" -eq 0 ]; then
  echo "error: no flow files found in $FLOWS_DIR" >&2
  exit 1
fi

# Sort for deterministic ordering — flow filename is the source of truth.
IFS=$'\n' flows=($(printf '%s\n' "${flows[@]}" | sort))
unset IFS

# Optional positional arguments are basename glob patterns. With no
# arguments every flow runs (full suite). With arguments, keep only the
# flows whose basename (filename without `.yaml`) matches at least one
# pattern. Matching uses bash's `[[ == ]]` glob — NEVER `eval` — so
# patterns like `2*` or `25-restore-wallet` work without shell injection.
if [ "$#" -gt 0 ]; then
  patterns=("$@")
  selected=()
  for flow in "${flows[@]}"; do
    base="$(basename "$flow" .yaml)"
    for pat in "${patterns[@]}"; do
      if [[ $base == $pat ]]; then
        selected+=("$flow")
        break
      fi
    done
  done
  if [ "${#selected[@]}" -eq 0 ]; then
    echo "error: no handbook flows match the given pattern(s): ${patterns[*]}" >&2
    exit 1
  fi
  flows=("${selected[@]}")
fi

# xcrun simctl runs inside CoreSimulator which is sandboxed by macOS TCC and
# cannot write to ~/Documents directly. Stage to /tmp and `mv` afterwards.
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Per-attempt retry budget for the upstream driver-hang class. The per-flow
# / per-attempt timing logged below is the data to size the workflow's
# `timeout-minutes` (see tier3-handbook.yaml) and to target a real speed-up.
# Worst-case the entire suite is 3 × 26 × ~1 min plus 3 × ~6 min
# driver-startup-timeout per failed attempt, which still fits inside
# the workflow's 60 min envelope.
MAESTRO_MAX_ATTEMPTS="${MAESTRO_MAX_ATTEMPTS:-3}"

# Maestro's `--debug-output` writes per-attempt view-hierarchy.json +
# screenshot + maestro.log into the given directory. On flow failure
# these are the only forensic data that show what was actually on the
# screen at the assertion point — much more useful than a `simctl io
# screenshot` taken after the flow exited (which captures whatever
# screen the failure left the app on, not the moment of failure).
MAESTRO_DEBUG_ROOT="$TMP_DIR/maestro-debug"
mkdir -p "$MAESTRO_DEBUG_ROOT"

# XCUITest-driver reuse across the per-flow `maestro test` invocations.
#
# Each `maestro test` invocation otherwise pays the full XCUITest-runner
# lifecycle: by default Maestro 2.0.10 *uninstalls* the runner on session
# close, so the next invocation finds nothing alive and has to
# uninstall/install/start it again from scratch — the Maestro log line
# `Restarting XCTest Runner (uninstalling, installing and starting)` + a
# fresh `xcodebuild test-without-building`. Across 26 flows that one-time
# ~5 min build is effectively paid 26×.
#
# `--reinstall-driver=false` (Maestro 2.0.10 TestCommand option, default
# `true`) skips the uninstall step both at session start AND at session
# close. So invocation 1 installs+starts the runner and then *leaves it
# running*; invocations 2-26 hit Maestro's `isChannelAlive()` early-return
# (`UI Test runner already running, returning`) and reuse it — no
# reinstall, no rebuild. The first run on a freshly `simctl erase`-d
# device has nothing to uninstall, so passing the flag there is harmless.
#
# Exception: the driver hang/death retry path below reboots the
# simulator, which kills the running runner. After a reboot the next
# attempt MUST do a full reinstall (a clean driver is exactly the recovery
# the retry exists for), so `reinstall_driver` is flipped back to `true`
# for that one attempt and reset to `false` afterwards.
reinstall_driver=false

# Whole-second duration → `Nm SSs`. Drives the per-attempt / per-flow /
# suite timing lines below — the data for sizing the CI envelope and
# finding which flows to speed up.
fmt_duration() {
  printf '%dm %02ds' $(( $1 / 60 )) $(( $1 % 60 ))
}

# True when $1 is a readable file that matches the XCUITest-driver
# hang/death class. Maestro often disguises driver death as a later
# assertion failure on CLI stdout while the ConnectException lives
# only in `--debug-output` maestro.log — callers must pass both.
# ConnectException-class strings before `Running flow ` are installer
# status-check noise, not driver death; slice them out. Do not pipe
# awk into grep under pipefail (SIGPIPE would false-negative).
is_driver_hang_or_death() {
  local log="$1"
  [ -f "$log" ] || return 1

  if grep -qF 'IOSDriverTimeoutException' "$log"; then
    return 0
  fi

  local haystack="$log"
  local tmp=""
  if grep -qF 'Running flow ' "$log"; then
    tmp="$(mktemp)"
    awk 'p || /Running flow / { p=1; print }' "$log" > "$tmp"
    haystack="$tmp"
  fi

  grep -qF \
    -e 'Failed to connect to /127.0.0.1:7001' \
    -e 'java.net.ConnectException' \
    -e 'Connection refused' \
    -e 'Connection reset' \
    "$haystack"
  local rc=$?
  if [ -n "$tmp" ]; then
    rm -f "$tmp"
  fi
  return "$rc"
}

suite_start=$(date +%s)
timings=()

for flow in "${flows[@]}"; do
  base="$(basename "$flow" .yaml)"
  tmp_png="$TMP_DIR/$base.png"
  png="$CAPTURES_DIR/$base.png"
  echo
  echo "▶ $base"
  flow_start=$(date +%s)

  attempt=0
  while : ; do
    attempt=$((attempt + 1))
    attempt_start=$(date +%s)
    flow_log="$TMP_DIR/$base.attempt-$attempt.log"
    debug_dir="$MAESTRO_DEBUG_ROOT/$base-attempt-$attempt"
    if "$MAESTRO" test --reinstall-driver="$reinstall_driver" \
         --debug-output "$debug_dir" --flatten-debug-output "$flow" 2>&1 | tee "$flow_log"; then
      echo "  attempt $attempt passed in $(fmt_duration $(( $(date +%s) - attempt_start )))"
      # Driver is up after a successful invocation — keep reusing it
      # (a prior retry may have flipped this to true for a reinstall).
      reinstall_driver=false
      break
    fi
    # Only retry the XCUITest-driver hang/death class. Check the CLI
    # tee-log AND `--debug-output` maestro.log: driver death is often
    # reported on stdout as a later assertion failure (`Assert that
    # "Start" is visible`) while ConnectException lives only in the
    # debug log. Assertion failures without these patterns are real
    # regressions and must surface red — never retry them.
    if { is_driver_hang_or_death "$flow_log" || \
         is_driver_hang_or_death "$debug_dir/maestro.log"; } && \
       [ "$attempt" -lt "$MAESTRO_MAX_ATTEMPTS" ]; then
      echo "  driver hang/death on attempt $attempt of $MAESTRO_MAX_ATTEMPTS after $(fmt_duration $(( $(date +%s) - attempt_start ))); restarting simulator and retrying"
      xcrun simctl shutdown "$UDID" || true
      xcrun simctl boot "$UDID"
      xcrun simctl bootstatus "$UDID" -b >/dev/null
      # The reboot killed the XCUITest runner. Force a full reinstall on
      # the retry attempt so it recovers from a clean driver state; the
      # successful-attempt branch above resets this back to false.
      reinstall_driver=true
      continue
    fi
    # Real failure OR retries exhausted: post-mortem + exit.
    echo "--- POST-MORTEM: TCP loopback listeners ---"
    /usr/sbin/lsof -iTCP -sTCP:LISTEN -nP 2>/dev/null | grep -E 'IPv[46]|java|xctest|XCT|maestro' || true
    echo "--- POST-MORTEM: live maestro / XCT / xcodebuild processes ---"
    ps -A 2>/dev/null | grep -E 'maestro|XCT|xcodebuild' | grep -v grep || true
    echo "--- POST-MORTEM: simulator log (last 2 min) ---"
    xcrun simctl spawn "$UDID" log show \
      --predicate 'process == "XCTRunner" OR process CONTAINS "swiss.realunit.app"' \
      --last 2m --style compact 2>/dev/null | tail -200 || true
    echo "--- POST-MORTEM: copy Maestro debug-output for failure to captures dir ---"
    if [ -d "$debug_dir" ]; then
      # Surface the failure screenshot + view hierarchy in the
      # uploaded artifact so a reviewer can see what was on screen
      # at the assertion point without re-running locally.
      cp -R "$debug_dir" "$CAPTURES_DIR/_debug-$base-attempt-$attempt" || true
    fi
    exit 1
  done

  xcrun simctl io booted screenshot "$tmp_png" >/dev/null
  mv "$tmp_png" "$png"
  flow_secs=$(( $(date +%s) - flow_start ))
  timings+=("$base|$flow_secs|$attempt")
  echo "  captured → ${png#"$REPO_ROOT"/}  [flow total $(fmt_duration "$flow_secs"), $attempt attempt(s)]"
done

echo
echo "Done in $(fmt_duration $(( $(date +%s) - suite_start )))."
echo
echo "Per-flow wall-clock (slowest first) — data for sizing tier3-handbook.yaml"
echo "timeout-minutes and for targeting the slow flows:"
printf '%s\n' "${timings[@]}" | sort -t'|' -k2 -rn | while IFS='|' read -r name secs att; do
  printf '  %-34s %9s  (%s attempt(s))\n' "$name" "$(fmt_duration "$secs")" "$att"
done
echo
echo "Captures in $CAPTURES_DIR:"
ls -1 "$CAPTURES_DIR"
