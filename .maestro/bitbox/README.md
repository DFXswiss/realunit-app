# Tier-3 BitBox Maestro flows

This directory holds the seven canonical Tier-3 hardware flows (M-1 ... M-7)
that exercise the BitBox 02 Nova against the realunit-app on a real phone
on a self-hosted Apple Silicon runner. Tier-3 is defined in `docs/testing.md`
under the five-tier model; the canonical reference is
`audit-bitbox-2026-05-23/OPUS_BITBOX_MANDATE.md` §5.3 and Appendix B.

Unlike the handbook flows in `.maestro/handbook/`, these flows DO NOT run
on `macos-latest` GitHub-hosted runners — the macOS image's USB / BLE stack
cannot reach a physical BitBox dongle, and per realunit-app#487 the macos
runner image is only 41 % green on Maestro 2.5.x. They MUST run on the
self-hosted Apple-Silicon runner described in `RUNNER.md`, with the
hardware physically attached to (or in BLE range of) the runner.

## Why Tier-3 exists at all

Three contracts cannot be verified at any tier below Tier-3:

| Contract                                  | Only Tier-3 verifier |
|-------------------------------------------|----------------------|
| BLE init-frame retransmit dedup           | M-3                  |
| Channel-hash mismatch detection on pair   | M-5                  |
| Static-pubkey mismatch after factory-reset| M-6                  |

The audit's Top-10 #1 (BLE dedup), #4 (channel-hash), and #8 (factory-reset)
findings are pinned by these three flows respectively. There is no Tier-2
substitute — the simulator cannot model a real radio link drop, two phones
racing the same handshake, or a real firmware-side keypair regenerate.

The other four flows (M-1, M-2, M-4, M-7) are end-to-end smoke / soak
coverage: they make sure the everyday paths (pair, sign, reconnect, long
idle) still work on real hardware after every change to the BLE / framing
/ pipeline layers.

## The seven flows

| Flow | Slug                                      | Hardware required                       | Runtime  | Gate            | Pins audit Top-10 |
|------|-------------------------------------------|------------------------------------------|----------|-----------------|-------------------|
| M-1  | `M-1-happy-path.yaml`                     | BitBox 02 Nova + iOS device              | ~2 min   | PR gate         | smoke             |
| M-2  | `M-2-multi-page-sign-stable-ble.yaml`     | BitBox 02 Nova + iOS device              | ~5 min   | scheduled-daily | #1 (stable side)  |
| M-3  | `M-3-multi-page-sign-with-ble-toggle.yaml`| BitBox 02 Nova + iOS device              | ~8 min   | PR gate         | #1 (CANONICAL)    |
| M-4  | `M-4-disconnect-mid-sign.yaml`            | BitBox 02 Nova + iOS device              | ~6 min   | scheduled-daily | lifecycle         |
| M-5  | `M-5-channel-hash-mismatch.yaml`          | BitBox 02 Nova + 2x iOS devices          | ~4 min   | PR gate         | #4 (CANONICAL)    |
| M-6  | `M-6-factory-reset-detection.yaml`        | BitBox 02 Nova + iOS device              | ~5 min   | PR gate         | #8 (CANONICAL)    |
| M-7  | `M-7-slow-confirm-long-idle.yaml`         | BitBox 02 Nova + Android device          | ~10 min  | scheduled-daily | Android 60s       |

PR-gate flows (M-1 / M-3 / M-5 / M-6) run on every PR against `develop`,
parallelised but serialised on the physical hardware mutex
(`bitbox-hardware-pool`). Scheduled-daily flows (M-2 / M-4 / M-7) run
once per night at 02:00 UTC.

Each flow has its own one-line docblock at the top describing what it
proves AND what it deliberately does not prove. Treat that docblock
as authoritative.

## Tier-2 ↔ Tier-3 pairing

These flows close the explicit "what this scenario does NOT cover" carve-outs
in the Tier-2 scenarios under `bitbox-testkit/go/bitbox/scenarios/`. The
pairing is:

| Tier-2 scenario                       | Tier-3 flow covering the carve-out |
|---------------------------------------|-------------------------------------|
| `ble_init_frame_dedup`                | M-3                                 |
| `multi_page_state_machine`            | M-2 (happy) + M-3 (with drop)       |
| `pair_verify_channel_hash`            | M-5                                 |
| `static_pubkey_mismatch`              | M-6                                 |
| `eth_sign_envelope`                   | M-1                                 |
| `read_timeout_60s_extension`          | M-7                                 |
| `disconnect_recovery`                 | M-4                                 |

Coverage-Honesty CI (see `bitbox-testkit/.github/workflows/coverage-honesty.yaml`)
enforces this table machine-readably; any drift fails the build.

## Hardware required

Every flow needs at least one BitBox 02 Nova in a known firmware state.
The runner machine MUST document the device serial (last 4 chars only;
never log the full serial) and the firmware version before every run.

Wipe + re-initialise the BitBox between sessions where the flow's docblock
says so. M-6 in particular REQUIRES that the BitBox be factory-reset
between its two sub-sessions. Without that physical step the flow fails
preconditions and the run is invalid (not a pass).

## Required widget keys — TODO before flows go green

These flows reference Maestro selectors like `id: "bitbox-pair-confirm"`.
realunit-app today has NO stable widget keys on the BitBox screens — every
selector is text-based and German-locale dependent. Before any of these
flows can run reliably:

1. Add `Key('bitbox-pair-confirm')` (and the other keys listed in the
   per-flow `# REQUIRED-KEYS:` block) to the BitBox widgets in
   `lib/screens/hardware_connect_bitbox/` and the KYC sign widgets in
   `lib/screens/kyc/`.
2. Until those keys ship, each flow falls back to its text-based
   selectors. Text-based selectors break on locale changes and on
   string-revisions — they are NOT a long-term contract. See
   per-flow `# REQUIRED-KEYS:` blocks for the canonical key names.

This is tracked as a follow-up in the audit backlog (BL-017 acceptance).

## Operator setup checklist

Before triggering any flow on the self-hosted runner:

1. Verify the BitBox 02 Nova is powered, paired into the OS BLE stack,
   and reachable via BLE from the iPhone (M-1 ... M-6) or Android device
   (M-7) cabled to the runner.
2. Verify the phone is `simctl boot`ed (iOS) or `adb` reachable (Android).
3. Log the BitBox firmware version + device serial (last 4 chars) into
   the per-run journal at `audit-bitbox-2026-05-23/logs/opus_journal.md`
   per the §10 protocol.
4. For M-5: confirm BOTH iOS devices are awake, on the same Wi-Fi/BLE
   network, AND that the human operator is standing where they can hold
   the BitBox between them in BLE range.
5. For M-6: confirm the operator is physically present to perform the
   manual factory-reset step on the BitBox device (long-hold reset; see
   BitBox 02 Nova hardware documentation). If `BITBOX_DEV_RESET=1` is
   exported AND the realunit-app was built with the dev-reset endpoint
   enabled (currently blocked — see "Dev features required" below), the
   flow performs the reset programmatically.
6. For M-7: confirm the Android device's BLE timeout is the platform
   default (not customised), so the test exercises the real 60 s read
   timeout extension that protects against the Android-default 10 s.

## Running a flow locally

The runner machine must have the `Runner.app` (iOS) or `app-debug.apk`
(Android) for the current branch already installed and launched once.
After that:

```bash
# iOS (M-1 ... M-6)
maestro test .maestro/bitbox/M-1-happy-path.yaml

# iOS — full PR-gate subset
for f in M-1 M-3 M-5 M-6; do
  maestro test .maestro/bitbox/${f}-*.yaml
done

# Android (M-7) — set device target via Maestro env
MAESTRO_DEVICE_ID=<adb-serial> maestro test .maestro/bitbox/M-7-slow-confirm-long-idle.yaml
```

`maestro test --validate <file>.yaml` lints the YAML against the Maestro
schema without executing it. Run this in CI to catch syntax errors
before booking a hardware slot.

## Flake budget

Per audit mandate §5.3.5 + TF realunit-app#487:

- Per-flow target: at least 80 % green on the self-hosted runner over the
  trailing 30 days. Below that, the flow is demoted from PR-gate to
  scheduled-only and a tracking issue is opened.
- Suite-wide target: every PR-gate flow (M-1 / M-3 / M-5 / M-6) green
  on the first attempt OR on the second of three retries. Three retries
  is the workflow ceiling; needing all three is logged as a flake.
- The CI workflow updates `bitbox-testkit/coverage_report.md` with per-flow
  flake rate via a posting step after each run.

## Dev features required (blockers)

Some flows reference DEV-only endpoints that are not yet shipped in
realunit-app. Each flow's YAML has a `# BLOCKED until <feature>` comment
where applicable. Summary:

| Flow | Blocker                                                    | Status |
|------|------------------------------------------------------------|--------|
| M-1  | none                                                       | ready  |
| M-2  | none (uses real KYC registration sign payload)             | ready  |
| M-3  | iOS BLE programmatic toggle (uses `simctl status_bar` proxy + manual airplane-mode fallback) | partial |
| M-4  | none (uses manual unpower; documented in docblock)         | ready  |
| M-5  | two-phone hardware reservation; programmatic phone-B pair-spoof requires DEV `--bitbox-pair-from-test=B` flag NOT YET in app | partial |
| M-6  | factory-reset endpoint: BitBox CLI integration on runner OR DEV `BITBOX_DEV_RESET=1` rebuild path. Manual fallback documented. | partial |
| M-7  | Android build of realunit-app on runner (currently iOS-only CI) | partial |

"Partial" flows still ship as Tier-3 YAML and produce a clear
PRECONDITION-FAILED error pointing the operator at the manual workaround.
They do NOT silently pass when their precondition is missing.

## Reference

- Mandate: `audit-bitbox-2026-05-23/OPUS_BITBOX_MANDATE.md` Appendix B, §5.3, §8.12
- Backlog: `audit-bitbox-2026-05-23/BACKLOG.md` BL-017, BL-052..BL-057
- Maestro docs: https://maestro.mobile.dev/api-reference
