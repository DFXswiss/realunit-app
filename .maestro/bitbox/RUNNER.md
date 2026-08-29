# Tier-3 self-hosted Apple Silicon runner

This document is the canonical provisioning guide for the self-hosted
GitHub Actions runner that drives the `.maestro/bitbox/` flows against
real BitBox 02 Nova hardware. The mandate §5.3.3 Group H requires this
file to be the single source of truth for the runner's hardware,
software, and operational state.

Tier-3 will NOT run on a GitHub-hosted `macos-latest` runner. Two reasons:

1. The hosted runner cannot reach a physical BitBox dongle — neither USB
   nor BLE is exposed inside the ephemeral macOS VM.
2. Per realunit-app#487 the hosted-runner Maestro flow stack is only
   ~41 % green on Apple Silicon + iOS 26.x (see the `tier3-handbook.yaml`
   workflow header for the upstream tracking link).

A dedicated, physical, Apple-Silicon Mac mini owned by DFXswiss is
mandatory.

## Hardware

| Component                | Specification                                   |
|--------------------------|--------------------------------------------------|
| Runner machine           | Apple M-series Mac mini (M2 or newer), 16 GB+ RAM, 256 GB+ SSD |
| Test iPhone (primary)    | iPhone 17 (iOS 26.x) — cabled to runner via USB-C |
| Test iPhone (secondary)  | iPhone 15 or 17 (iOS 26.x) — for M-5 only        |
| Test Android (M-7)       | Pixel 8 or newer (Android 14+), USB-cabled       |
| BitBox 02 Nova           | Firmware 9.21.0 or later                         |
| Power                    | Mac mini + phones on uninterruptible power; BitBox on its USB-C cable |

The two iPhones for M-5 must be physically close to the BitBox 02 Nova
(< 1 m) so both phones can race the pairing handshake against the same
device. Document this physical layout in the per-run journal.

## Software baseline

The runner machine must hold the following versions. Each upgrade is
landed on a separate PR with a journal entry per mandate §10.

| Software         | Version             | Source of truth      |
|------------------|---------------------|----------------------|
| macOS            | Sequoia 15.4 or later | `sw_vers`           |
| Xcode            | 26.1 or later       | `xcodebuild -version`|
| Flutter          | matches `pubspec.yaml` toolchain version | `flutter --version` |
| Maestro CLI      | pinned via `.maestro-version` (today: 2.0.10) | `maestro --version` |
| Java (for Android in M-7) | OpenJDK 17  | `java -version`      |
| Android SDK      | Platform 34 or later | `sdkmanager --list`  |
| `ios-deploy`     | latest stable       | `ios-deploy --version`|

The pinning rationale is the same as `.github/workflows/tier3-handbook.yaml`:
Maestro 2.3+–2.5+ has driver-startup hangs and silent tap-loss on iOS 26
(mobile-dev-inc/maestro#3137). 2.0.10 is the last release that passes the
handbook flows reliably.

## One-time runner registration

1. Create the runner on GitHub:
   - Settings → Actions → Runners → New self-hosted runner.
   - Choose "macOS" / "ARM64".
2. Download and configure the runner agent on the Mac mini per GitHub's
   on-screen instructions. Choose `bitbox-tier3` as the runner name.
3. Apply labels: `self-hosted`, `macOS`, `arm64`, `bitbox`,
   `apple-silicon`. The workflow targets the `self-hosted` + `macOS` +
   `arm64` + `bitbox` quadruple to pin scheduling to this specific machine.
4. Install the agent as a launchd service so it survives reboots:
   `sudo ./svc.sh install && sudo ./svc.sh start`.
5. Verify the runner shows "Idle" in Settings → Actions → Runners.

## Runner-token rotation procedure

The registration token expires after 1 hour; the runner agent's
configured token does NOT — it stays valid indefinitely. Rotate when:

- The runner machine is wiped, repaired, or replaced.
- The runner is suspected compromised (any unexplained pause / log
  anomaly).
- Quarterly per security hygiene (calendar reminder owner: operator).

Rotation steps:

1. `sudo ./svc.sh stop && sudo ./svc.sh uninstall`.
2. `./config.sh remove --token <removal-token-from-Settings>`.
3. Generate a new registration token in Settings → Actions → Runners.
4. Re-run the configure step from the one-time setup, above.
5. Restart the launchd service.
6. Verify the workflow's most recent `bitbox-tier3` run succeeded after
   the rotation by re-running it manually via `workflow_dispatch`.

## Per-flow timeout configuration

Each flow's expected runtime is documented in
`.maestro/bitbox/README.md`. The workflow caps each job at 2x the
expected runtime to absorb runner-load variance. If a flow hits its
timeout repeatedly, increase the cap on a tracking PR — do NOT
quietly bump on the spot.

| Flow | Expected runtime | Workflow timeout |
|------|------------------|------------------|
| M-1  | 2 min            | 5 min            |
| M-2  | 5 min            | 12 min           |
| M-3  | 8 min            | 18 min           |
| M-4  | 6 min            | 14 min           |
| M-5  | 4 min            | 10 min           |
| M-6  | 5 min            | 12 min           |
| M-7  | 10 min (incl. 65 s idle) | 22 min   |

## Disk-space + cache hygiene

Maestro stores test artefacts (screenshots, logs, video) under
`~/.maestro/tests/`; a single Tier-3 run can write 100 MB+. The
DerivedData and CocoaPods caches also balloon over time.

A daily `launchd` plist must run at 04:00 UTC (after the scheduled-daily
flows finish) executing:

```bash
#!/usr/bin/env bash
set -euo pipefail
# Keep last 14 days of Maestro artefacts; delete older.
find ~/.maestro/tests -type d -mtime +14 -prune -exec rm -rf {} \;
# Prune Xcode DerivedData on overage; cap at 20 GB.
du -sk ~/Library/Developer/Xcode/DerivedData | awk '$1>20000000 {print "prune"}' | xargs -I{} rm -rf ~/Library/Developer/Xcode/DerivedData/*
# Prune CocoaPods cache if > 5 GB.
du -sk ~/Library/Caches/CocoaPods | awk '$1>5000000 {print "prune"}' | xargs -I{} pod cache clean --all
# Booted simulators: shutdown + erase any non-iPhone-17 device.
xcrun simctl shutdown all || true
```

Operator owns scheduling this via `launchctl load -w` once.

## Known issues + workarounds

- **Maestro 2.5.x driver hang on iOS 26.** Stay on 2.0.10. Tracked
  upstream as mobile-dev-inc/maestro#3137.
- **BLE programmatic toggle.** iOS does not expose a CLI to toggle BLE
  from outside an app. M-3 falls back to `xcrun simctl status_bar set
  bluetooth-state airplane` — this updates the status bar but does NOT
  actually drop the BLE link. M-3 documents this in its docblock and the
  operator may need to airplane-mode the phone manually mid-flow until
  realunit-app ships a DEV toggle.
- **Two-phone hardware reservation for M-5.** The workflow uses a
  GitHub Actions `concurrency` mutex to serialise hardware-bound jobs
  on the runner. Until the second iPhone is wired in (operator pending),
  M-5 fails its precondition step with a clear error and the workflow
  marks the job `skipped` rather than `failed`.
- **Factory-reset on M-6.** The BitBox device's factory-reset is a hold-
  the-button physical action. Until the realunit-app DEV-reset rebuild
  endpoint ships (BL-017 backlog item), M-6 prompts the operator to
  reset the device manually via a `waitForAnimationToEnd` checkpoint
  step the operator must walk through.
- **macos-latest hosted runner.** Do NOT migrate Tier-3 there. Per
  TF #487 the hosted runner is 41 % green on Maestro 2.5.x and cannot
  reach hardware. Tier-3 is self-hosted-only.

## Health check + ping cron

Mandate §5.3.6 calls for a 30-minute health-check cron. Implement as a
separate workflow `.github/workflows/runner-health.yaml` (NOT in scope
for this PR) that does `runs-on: [self-hosted, bitbox]` + `echo "alive
$(date)"` every 30 minutes. If two consecutive runs miss, the operator
is paged via the alert channel.

## Operator quick-start (3-5 steps)

1. Boot the runner Mac mini and unlock; verify the GitHub Actions runner
   service is `running` (`launchctl list | grep actions.runner`).
2. Cable both iPhone(s) and (if running M-7) the Android device to the
   runner; verify they appear in `xcrun simctl list devices booted`
   (iOS) and `adb devices` (Android).
3. Power the BitBox 02 Nova and confirm it is BLE-discoverable from
   the primary iPhone (open Settings → Bluetooth → see "BitBox02-XXXX").
4. Log the firmware version and serial (last 4 chars only) into the
   per-run journal entry.
5. Trigger the desired flow either via PR (PR-gate flows) or
   `workflow_dispatch` on `.github/workflows/maestro-bitbox.yaml`.
