# Real Unit App

A Flutter wallet for Real Unit investors. Multi-chain, BitBox-ready, KYC-aware.

> **Status:** Early development. APIs, flows and UI are still moving.

## Contributing

**New PRs may only merge into `develop` if test coverage is 100% on the activated surface.** Concretely:

- `flutter test --coverage` must report 100% lines / functions / branches on every file in the activated surface (see Coverage scope below). CI will fail the build below threshold.
- Defensive code that genuinely cannot be reached in `flutter_test` (platform channels without a test override, native plugin entry points, BLE callbacks) is exempted by an inline `// coverage:ignore-line` annotation with a one-line reason.
- The branch is protected on GitHub: a PR cannot be merged while CI is red.

**Coverage scope:** `lib/packages/**` (services, repositories, signers, utils) and the `cubits/` + `bloc/` directories under each `lib/screens/<feature>/`. Widget files (`lib/screens/<feature>/<feature>_page.dart` and `lib/widgets/**`) are exercised via `testWidgets` specs and excluded from the line-coverage gate — widget tests count as `widget` coverage in the feature matrix, not as line %. Generated files (`*.g.dart` from `build_runner` / Drift) are also stripped after the scope extract — they are tool output, not developer code, and would otherwise drag the scoped line % down for free.

The five-tier testing model (Tier 0 Cubit unit · Tier 1 FakeBitbox integration · Tier 2 firmware simulator · Tier 3 Maestro flows (handbook simulator + deferred BitBox02 hardware) · Tier 4 BLE VCR/replay stretch) is tracked in [#314](https://github.com/RealUnitCH/app/issues/314). See [`docs/testing.md`](docs/testing.md) for the full tier picker. New BitBox-touching PRs are expected to add tests at the appropriate tier(s).

## Coverage infrastructure roadmap

The 100% rule above is the target state. Until the items below land, it is aspirational and not yet CI-enforced:

- [x] `flutter test --coverage` step in `.github/workflows/pull-request.yaml`
- [x] lcov filter narrowed to the activated surface (`lib/packages/**` + `lib/screens/**/cubit(s)/**` + `lib/screens/**/bloc/**`) and a per-run summary posted to the workflow step summary
- [x] lcov threshold check failing the build below a committed floor on the scope above
- [x] Floor gate lives in its own CI job (`Coverage Floor Gate`), wired up as a required status check on `develop` + `main`
- [x] GitHub branch protection on `develop` requiring the `Coverage Floor Gate` check (ruleset `PRs` / id `11317379`)
- [x] Inline `// coverage:ignore-*` annotations on truly unreachable paths, each with a one-line reason — applied to Drift schema getters across `lib/packages/storage/`, defensive `assert(false) → throw StateError` fallthroughs in `wallet.dart`, the platform-channel forwarders in `PathProviderAdapter` and `BiometricServiceAdapter`, the Android-only telemetry-kill file write in `fuck_firebase.dart`, and the `_localTesting` dev-only `Uri.http` branch in `api_config.dart`. `BitboxCredentials`' synchronous web3dart entry points used to be listed here too; they now carry `throwsA(isA<UnimplementedError>())` tests instead of an ignore, matching the tested `_DebugCredentials` stubs in `wallet.dart`
- [x] Visibility gate closing the "never-loaded file" blind spot — `flutter test --coverage` only records libraries a test actually imports, so an in-scope file no test loads is absent from `lcov.info` entirely and sits in neither the numerator nor the denominator: the scoped % stays 100 % while the file is wholly untested. The `Coverage Floor Gate` job runs [`scripts/check-coverage-visibility.sh`](scripts/check-coverage-visibility.sh), which enumerates the on-disk activated surface (same globs as the scope filter) and fails when a file produced no `SF:` record. Files that genuinely have no coverable lines — pure abstract interfaces / ports, export-only barrels, const/enum-only declarations — are ratcheted in `.coverage-visibility-allowlist`; a new blind spot fails the build until it is tested (preferred) or, only if truly lineless, allow-listed in the same PR with a reason

**Ratchet protocol.** The committed floor lives in two flat files at the repo root: `.coverage-floor-lines` and `.coverage-floor-functions` (integer percent, no `%` suffix). CI fails the build when scoped coverage drops below either value. Raising the floor is encouraged on every PR that raises measured coverage — bump the file in the same commit and the gate moves up. Lowering the floor requires explicit reviewer sign-off; PR convention is the `coverage:lower-floor` label so the regression is visible in the PR list rather than smuggled in. The functions floor is parked at a placeholder today because `flutter test --coverage` does not emit `FN` records — the gate warns instead of failing on that metric until upstream adds support.

> **Before first use:** two PR labels are referenced by this tooling but are not auto-created. Run `gh label create tier3:full` once on the repo to enable per-PR opt-in for the Tier 3 handbook workflow — without the label the workflow's `if:` gate never matches and the job silently skips on PRs. Run `gh label create coverage:lower-floor` once to make floor-lowering PRs grep-able; the coverage floor gate itself runs unconditionally on every PR, this label is a review-convention marker only and is not read by any workflow.

Three PRs have closed the largest gaps for KYC + BitBox logic: [#319](https://github.com/RealUnitCH/app/pull/319) (Tier 0 cubit tests), [#320](https://github.com/RealUnitCH/app/pull/320) (Tier 1 FakeBitbox integration), [#321](https://github.com/RealUnitCH/app/pull/321) (dashboard buy actions + auth service tests).

## Features

User-facing functions, their activation status, and the tests that cover them. It is the source of truth for "what does this wallet actually do" — keep it in sync when adding or removing a flow.

**Status legend:** `always` = ships on every build · `hardware` = needs a BitBox hardware wallet (see [Supported hardware wallets](#supported-hardware-wallets) below) · `planned` = surface exists but flow not yet implemented.

**Triage legend** (MVP testing decision): `mvp` = in MVP scope, must reach full test coverage before launch · `defer` = ships but does not block MVP coverage (coverage required eventually, no hard deadline) · `planned` = not in scope for MVP.

**Tests legend:** `widget` = `testWidgets` spec under `test/screens/**` · `golden` = visual-regression spec under `test/goldens/**` (pixel-exact baseline rendered on the self-hosted runner, see [`docs/visual-regression-tests.md`](docs/visual-regression-tests.md)) · `unit` = pure-Dart `test/packages/**` spec · `cubit` = `bloc_test`-style spec for a Bloc/Cubit · `integration` = `test/integration/**` spec crossing ≥ 2 production layers with `FakeBitboxCredentials` · `e2e` = Maestro YAML flow on real hardware · `—` = no test exists.

> Per-feature line-coverage % is not surfaced in this table. The repo-wide scoped coverage is enforced by the `Coverage Floor Gate` CI job against `.coverage-floor-lines` / `.coverage-floor-functions`; the lcov artifact attached to every PR run holds the per-file breakdown.

### Supported hardware wallets

`hardware`-status flows require a BitBox device. Platform availability depends on the model:

| Device | Android | iOS |
| --- | --- | --- |
| BitBox 02 | yes | no |
| BitBox 02 Nova | yes | yes |

The transport is USB on Android and Bluetooth on iOS; the original BitBox 02 has no Bluetooth, so iOS support requires a BitBox 02 Nova.

### Onboarding & authentication

| Feature | Status | Triage | Tests |
| --- | --- | --- | --- |
| Welcome screen | always | mvp | widget (`welcome_page_test.dart`, `welcome/widgets/welcome_card_test.dart`) + golden (`welcome/welcome_golden_test.dart`) |
| Create wallet — software (generate seed) | always | mvp | widget (`create_wallet/create_wallet_page_test.dart`) + golden (`create_wallet/create_wallet_golden_test.dart`); no cubit/service test |
| Create wallet — BitBox (hardware connect) | hardware | mvp | golden (`hardware_connect_bitbox/connect_bitbox_golden_test.dart`); integration test added via [#320](https://github.com/RealUnitCH/app/pull/320) |
| Restore wallet — software seed phrase | always | mvp | widget (`restore_wallet/restore_wallet_page_test.dart`) + golden (`restore_wallet/restore_wallet_golden_test.dart`) |
| Verify seed phrase (3-word challenge) | always | mvp | widget (`verify_seed/verify_seed_page_test.dart`) + golden (`verify_seed/verify_seed_golden_test.dart`) |
| Setup PIN | always | mvp | widget (`pin/setup_pin_page_test.dart`) + golden (`pin/setup_pin_golden_test.dart`) |
| Verify PIN (unlock) | always | mvp | widget (`pin/verify_pin_page_test.dart`) + golden (`pin/verify_pin_golden_test.dart`) |
| Biometric unlock (Face ID / Touch ID / fingerprint) | always | mvp | cubit (`pin/verify_pin_cubit_test.dart`) + widget (`pin/verify_pin_page_test.dart`) |
| Legal disclaimer (post-onboarding gate) | always | mvp | golden (`legal/legal_disclaimer_golden_test.dart`, `legal/legal_document_golden_test.dart`); cubit transition covered in [#319](https://github.com/RealUnitCH/app/pull/319) |
| Onboarding completion | always | mvp | widget (`onboarding/onboarding_completed_page_test.dart`) + golden (`onboarding/onboarding_completed_golden_test.dart`) |

### Wallet actions

| Feature | Status | Triage | Tests |
| --- | --- | --- | --- |
| Dashboard — asset list + total balance | always | mvp | cubit/bloc (`dashboard/dashboard_bloc_test.dart`, `dashboard/balance_cubit_test.dart`, `dashboard/portfolio_chart_cubit_test.dart`, `dashboard/price_chart_cubit_test.dart`, `dashboard/pending_transactions_cubit_test.dart`, `dashboard/dashboard_transaction_history_cubit_test.dart`) + widget (`dashboard/widgets/**`) + golden (`dashboard/dashboard_golden_test.dart`) |
| Receive — address + QR code | always | mvp | widget (`receive/widgets/qr_address_widget_test.dart`) + golden (`receive/receive_golden_test.dart`) |
| Transaction history | always | mvp | widget (`transaction_history/transaction_history_page_test.dart`) + golden (`transaction_history/transaction_history_golden_test.dart`) |
| Sell to BitBox (on-chain transfer) | hardware | defer | golden (`sell_bitbox/sell_bitbox_golden_test.dart`) |

### DFX backend integration

| Feature | Status | Triage | Tests |
| --- | --- | --- | --- |
| Buy — DFX fiat on-ramp (SEPA) | always | mvp | widget (`buy/buy_page_test.dart`) + golden (`buy/buy_golden_test.dart`) + unit (`real_unit_buy_payment_info_service_test.dart`); added via [#321](https://github.com/RealUnitCH/app/pull/321) |
| Sell — DFX fiat off-ramp (IBAN) | always | mvp | widget (`sell/sell_page_test.dart`) + golden (`sell/sell_golden_test.dart`, `sell/sell_bank_account_selection_golden_test.dart`); added via [#321](https://github.com/RealUnitCH/app/pull/321) |
| KYC: Email + 2FA gate | always | mvp | widget (`kyc_email_page_test.dart`, `kyc_2fa_page_test.dart`) + golden (`kyc/kyc_email_golden_test.dart`, `kyc/kyc_email_verification_golden_test.dart`, `kyc/kyc_2fa_golden_test.dart`); cubit added via [#319](https://github.com/RealUnitCH/app/pull/319) |
| KYC: Registration + BitBox EIP-712 sign | always | mvp | widget (`kyc_registration_page_test.dart`) + golden (`kyc/kyc_registration_golden_test.dart`) + unit (`eip712_signer_test.dart`); cubit / `registration_submit` / sign-flow integration tests added via [#319](https://github.com/RealUnitCH/app/pull/319) + [#320](https://github.com/RealUnitCH/app/pull/320) |
| KYC: Personal data (correction after an ident data mismatch) | always | mvp | widget (`kyc_personal_data_page_test.dart`) + golden (`kyc/kyc_personal_data_golden_test.dart`) + cubit (`kyc_personal_data_cubit_test.dart`) |
| KYC: Nationality | always | mvp | widget (`kyc_nationality_page_test.dart`) + golden (`kyc/kyc_nationality_golden_test.dart`) |
| KYC: Financial data | always | mvp | widget (`kyc_financial_data_page_test.dart`) + golden (`kyc/kyc_financial_data_golden_test.dart`, `kyc/kyc_financial_data_failure_golden_test.dart`, `kyc/kyc_financial_data_loading_golden_test.dart`, `kyc/kyc_financial_data_questions_golden_test.dart`) |
| KYC: Ident | always | mvp | widget (`kyc_ident_page_test.dart`) + golden (`kyc/kyc_ident_golden_test.dart`) |
| KYC: Pending / Completed / Failure | always | mvp | widget (`kyc/subpages/kyc_*_page_test.dart`) + golden (`kyc/kyc_pending_golden_test.dart`, `kyc/kyc_completed_golden_test.dart`, `kyc/kyc_failure_golden_test.dart`, `kyc/kyc_loading_golden_test.dart`) |
| KYC: AccountMergeRequested / UnsupportedStepFailure | always | mvp | widget (`kyc/subpages/kyc_unsupported_step_page_test.dart`) + golden (`kyc/kyc_account_merge_golden_test.dart`, `kyc/kyc_unsupported_step_golden_test.dart`); cubit paths added via [#319](https://github.com/RealUnitCH/app/pull/319) |
| `DFXAuthService` (lazy auth + 401 retry) | always | mvp | — (unit tests added via [#319](https://github.com/RealUnitCH/app/pull/319) + [#321](https://github.com/RealUnitCH/app/pull/321)) |
| `balance_service` (balance fetch + cache) | always | mvp | unit (`balance_service_test.dart`) |
| `format_fixed` / `parse_fixed` (decimal helpers) | always | mvp | unit (`format_fixed_test.dart`, `parse_fixed_test.dart`) |
| `ApiException` mapping | always | mvp | unit (`exceptions/api_exception_test.dart`) |
| `ApiConfig` parsing | always | mvp | unit (`api_config_test.dart`) |

### Settings

| Feature | Status | Triage | Tests |
| --- | --- | --- | --- |
| Settings — root (sections list) | always | defer | golden (`settings/settings_golden_test.dart`) |
| Wallet address (export) | always | defer | widget (`settings_wallet_address/settings_wallet_address_page_test.dart`) + golden (`settings_wallet_address/settings_wallet_address_golden_test.dart`) |
| User data — overview | always | defer | widget (`settings_user_data/settings_user_data_page_test.dart`) + golden (`settings_user_data/settings_user_data_golden_test.dart`) |
| User data — edit name / address / phone | always | defer | widget (3 subpage specs under `settings_user_data/subpages/`) + golden (`settings_user_data/settings_edit_name_golden_test.dart`, `settings_user_data/settings_edit_address_golden_test.dart`, `settings_user_data/settings_edit_phone_number_golden_test.dart`, `settings_user_data/settings_edit_loading_golden_test.dart`, `settings_user_data/settings_edit_failure_golden_test.dart`, `settings_user_data/settings_edit_pending_golden_test.dart`) |
| Show seed phrase | always | defer | widget (`settings_seed/settings_seed_page_test.dart`) + golden (`settings_seed/settings_seed_golden_test.dart`) |
| Legal documents | always | defer | widget (`settings_legal_documents/settings_legal_documents_page_test.dart`) + golden (`settings_legal_documents/settings_legal_documents_golden_test.dart`, `settings_legal_documents/settings_aktionariat_documents_golden_test.dart`, `settings_legal_documents/settings_dfx_documents_golden_test.dart`) |
| Currencies / Languages / Network | always | defer | golden (`settings_currencies/settings_currencies_golden_test.dart`, `settings_languages/settings_languages_golden_test.dart`, `settings_network/settings_network_golden_test.dart`) |
| Tax report | always | defer | golden (`settings_tax_report/settings_tax_report_golden_test.dart`) |
| Contact | always | defer | golden (`settings_contact/settings_contact_golden_test.dart`) |
| Security — change PIN | always | defer | widget (`settings_security/settings_security_page_test.dart`) |
| Security — biometric unlock toggle | always | defer | cubit (`settings_security/cubits/settings_security_cubit_test.dart`) + widget (`settings_security/settings_security_page_test.dart`) + golden (`settings_security/settings_security_golden_test.dart`) |

### Support

| Feature | Status | Triage | Tests |
| --- | --- | --- | --- |
| Support — root (chat / create / list buttons) | always | defer | golden (`support/support_golden_test.dart`) |
| Support — chat | always | defer | widget (`support/support_chat_page_test.dart`) + golden (`support/support_chat_golden_test.dart`) |
| Support — create ticket | always | defer | widget (`support/support_create_ticket_page_test.dart`) + golden (`support/support_create_ticket_golden_test.dart`) |
| Support — tickets list | always | defer | widget (`support/support_tickets_page_test.dart`) + golden (`support/support_tickets_golden_test.dart`) |

## Triage gaps

The activated surface (see "Coverage scope" above) is at **100 % scoped line coverage**. Every file under `lib/packages/**`, `lib/screens/**/cubit(s)/**`, and `lib/screens/**/bloc/**` either ships with tests or carries an `// coverage:ignore-*` annotation with a documented reason. The previous bullet list of partially-covered services, KYC cubits, biometric unlock, and DFX backend services has been retired — those gaps are closed.

Out of scope of the gate and tracked elsewhere:

- **Widget render paths** — measured separately via `testWidgets` specs, not in the line-coverage gate (deliberate; see `docs/testing.md` "Tier 0" rationale).
- **Visual regression (goldens)** — every `lib/screens/**/*_page.dart` has a `test/goldens/**/*_golden_test.dart` companion, validated pixel-exact on the self-hosted runner by the `Visual Regression` CI job. Not folded into the line-coverage gate. The one exception is `lib/screens/web_view/web_view_page.dart` — `InAppWebView` is a platform-view that has no headless render in `flutter_test`, the spec is committed with `skip: true`. See [`docs/visual-regression-tests.md`](docs/visual-regression-tests.md).
- **Tier 2 (firmware simulator)** — runs in `bitbox-simulator.yml`, not folded into the scoped coverage number.
- **Tier 3 (Maestro handbook flows)** — runs in `tier3-handbook.yaml`, not folded in.
- **`lib/widgets/chain_asset_icon.dart`** and **`lib/widgets/image_picker_sheet.dart`** — `Image.asset` / `ImagePicker` platform-channel paths, see "Surface that needs infra work" in `docs/testing.md`.

## Testing tiers

[#314](https://github.com/RealUnitCH/app/issues/314) defines a 5-tier model for BitBox-touching code:

- **Tier 0 — Cubit unit tests** (`bloc_test` + `mocktail`). Fast, no platform, no BitBox. Covers every state transition.
- **Tier 1 — FakeBitbox integration tests** (`FakeBitboxCredentials` at the BitBox boundary, runs under `flutter test --coverage`). Drives multi-layer flows without hardware. Specs live under `test/integration/`.
- **Tier 2 — Firmware simulator** (TCP transport + Docker `bitbox02-firmware/simulator`). End-to-end with real crypto, no hardware. Planned.
- **Tier 3 — Maestro flows** (`.maestro/handbook/*.yaml` for software-only flows; the BitBox02-hardware variant is deferred and has no flow files committed yet). The handbook flows run on a fresh iOS Simulator, automated via [`tier3-handbook.yaml`](.github/workflows/tier3-handbook.yaml) — opt-in on PRs via the `tier3:full` label, always runs on push to `develop`. An upstream Maestro driver-hang regression on `macos-latest` runners makes intermittent first-attempt failures expected; `scripts/run-handbook-flows.sh` retries the driver-hang class up to 3× per flow (CI-hardening work originally tracked in [#487](https://github.com/RealUnitCH/app/issues/487), now closed). The hardware variant remains manually triggered before each release until Phase 3 of [#314](https://github.com/RealUnitCH/app/issues/314) lands.
- **Tier 4 — BLE VCR / replay** (capture on hardware once, replay deterministically). Stretch — most of its value is covered by Tier 2 + Tier 3 in tandem.

Non-BitBox code only needs Tier 0 + widget tests; Tier 1+ are reserved for hardware-coupled paths.

## Tests

| Stack    | Command                   | What it covers                                                                                                                                                                                            |
| -------- | ------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Flutter  | `flutter test`            | Unit + widget specs under `test/**` (pure-Dart `test` and `testWidgets`)                                                                                                                                  |
| Coverage | `flutter test --coverage` | Writes `coverage/lcov.info`. CI narrows it to the activated surface and hard-fails when scoped coverage drops below the floor in `.coverage-floor-lines` / `.coverage-floor-functions`. See "Coverage infrastructure roadmap" above for the ratchet protocol. |
| Analyzer | `flutter analyze`         | Dart static analysis per `analysis_options.yaml`                                                                                                                                                          |

Tier 1 specs live under `test/integration/**` and run inside the same `flutter test --coverage` invocation as Tier 0 — no separate `integration_test/` harness today (that Flutter-convention directory is reserved for on-device runs that are not yet wired up). Tier 3 handbook flows (iOS Simulator) are wired via [`tier3-handbook.yaml`](.github/workflows/tier3-handbook.yaml); the BitBox02 hardware variant remains deferred.

## CI/CD

| Workflow                     | Trigger                                                       | Action                                                                                  |
| ---------------------------- | ------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| `pull-request.yaml`          | Any PR except PRs to `main` · push `develop` · manual         | Runs `flutter analyze` + `flutter test --coverage --exclude-tags golden`, enforces scoped coverage, validates Goldens on the self-hosted runner, and uploads diagnostics. Jobs: `Analyze & Test`, `Coverage Floor Gate`, `Visual Regression`, `BitBox quirks audit`. |
| `staging-ci-fallback.yaml`   | Push `staging` · manual                                       | Routes staging CI without cross-event cancellation: a ready `staging → develop` PR owns canonical CI; otherwise it dispatches `pull-request.yaml` on `staging` as a fail-safe. |
| `tier3-handbook.yaml`        | Any PR except PRs to `main`, with label `tier3:full` · push `develop` · manual | Tier-3 navigation/tap-routing smoke: runs every `.maestro/handbook/*.yaml` flow on a fresh `iPhone 17` simulator and uploads diagnostic captures (`build/handbook-captures/`) as a build artifact. Pixel drift on the page renders is owned by `Visual Regression` in `pull-request.yaml`, not this job. |
| `bitbox-simulator.yml`       | Any PR except PRs to `main` touching `lib/packages/hardware_wallet/**`, `lib/packages/wallet/**`, `lib/screens/hardware_connect_bitbox/**`, their test mirrors, `pubspec.yaml`, or the workflow itself · manual | Runs the BitBox02 firmware simulator with `bitbox-testkit` baselines (Tier 2)           |
| `bitbox-simulator-slash.yml` | `/bitbox-simulator` comment on any PR                         | Same engine as above, on-demand per PR (variants: default / `ref=main`)                 |
| `auto-staging-pr.yaml`       | Push `staging` · manual                                       | Opens Staging PR `staging` → `develop`                                                  |
| `auto-release-pr.yaml`       | Push `develop` · manual                                       | Opens Release PR `develop` → `main`                                                     |
| `auto-tag.yaml`              | Push `develop`                                                | Creates the next `vX.Y.Z` patch tag (PATCH = previous + 1, MINOR/MAJOR from pubspec floor) |
| `release.yaml`               | Tag `v*` · manual                                             | Single store-release pipeline. Guard job routes by PATCH: `vX.Y.0` → production candidate (GitHub release, prerelease: false); `vX.Y.Z` (Z >= 1) → internal release (GitHub pre-release). Both lanes deploy Android + iOS to Play Internal + TestFlight; production promotion stays manual in the store backends. |
| `store-metadata.yaml`        | Push `main` under `*/fastlane/metadata/**` or `ios/fastlane/screenshots/**` · manual `workflow_dispatch` | Sync App Store + Play Store listing text + screenshots without rebuilding the app. A `preflight` gate rejects `FIXME-` placeholders and over-length text fields before either store upload runs. |
| `handbook-deploy.yaml`       | Push `staging` · manual                                       | Builds the handbook image from `staging` and deploys it to PRD via the reusable `handbook.yaml` (`:latest`, handbook.realunit.app). Content is pre-gated by `handbook-build-check.yaml` (screenshot-assembly, store-listing sync, legal-sync, and image build + container smoke); this workflow alone exercises the deploy WIRING (SSH, secrets, rollout) |
| `handbook.yaml`              | Called by `handbook-deploy.yaml` (`workflow_call`)            | Reusable build → Docker Hub push → server pull/recreate → smoke check, parameterised per environment |

## Release versioning

Tags follow plain SemVer: `vMAJOR.MINOR.PATCH`. There is no pre-release suffix — the previous `vX.Y.Z-beta.N` schema has been retired.

| Component | When does it bump? | Workflow | Distribution |
| --- | --- | --- | --- |
| `PATCH` (`v1.0.X` with X >= 1) | Automatically on every push to `develop` (see `auto-tag.yaml`). | `release.yaml` (internal lane) | TestFlight + Play Internal. |
| `MINOR` (`v1.X.0`) | Manual tag push (App-Store-update marker). | `release.yaml` (production-candidate lane) | TestFlight + Play Internal. Production promotion is done manually in the store backends. |
| `MAJOR` (`vX.0.0`) | Manual tag push. | `release.yaml` (production-candidate lane) | TestFlight + Play Internal. Production promotion is done manually in the store backends. |

A single release workflow (`release.yaml`) listens on the `v*` tag pattern and uses a guard job to route based on the PATCH component: patch tags go through the internal lane (`prerelease: true` on GitHub), MAJOR/MINOR tags through the production-candidate lane (`prerelease: false`). Either way the build lands in the Test tracks first — the App Store / Play Store production track is never updated by a tag push.

Both `beta` lanes push the store **listing** (Fastlane metadata + screenshots) alongside the binary on every tag-driven release, so the listings stay in sync with the build. Android `supply` writes the (global) Play listing with the AAB. iOS `deliver` runs with `skip_app_version_update: false`, so it creates or selects the editable App Store version itself and stages the listing there — the Deliverfile's `submit_for_review false` + `automatic_release false` keep it staged for a human to submit; deliver never auto-submits or releases. The iOS `deliver` is **best-effort** (`deliver_best_effort` in `ios/fastlane/Fastfile`): until the app's first App Store version is created once in App Store Connect, Apple rejects creating it via the API ("cannot create a new version of the App in the current state"), so the push is logged loudly and skipped without failing the release (the TestFlight binary already shipped). After that one-time bootstrap, every release syncs the listing automatically. The same surface can also be synced without a binary via the `store_metadata` lane / `store-metadata.yaml`. Either way, `release.yaml` runs the same `scripts/check-store-metadata.sh` preflight (FIXME placeholders + character/URL limits) as `store-metadata.yaml` in a gating `store-metadata-preflight` job before either deploy lane runs — a tag can never ship a `FIXME-` placeholder or an oversize field to the live consoles. Production promotion / final submit stay manual.

The build number is derived deterministically from the tag by `tool/generate_release_info.dart` using `MAJOR * 10_000_000 + MINOR * 100_000 + PATCH * 1_000 + 999`. The fixed `+999` suffix keeps every new build strictly above the legacy beta build codes; the first new build `v1.0.15` lands at `10_015_999`, comfortably above the highest published legacy beta `v1.0.0-beta.14` at `10_000_014`.

`pubspec.yaml`'s `version:` field has two roles:

- The `+0` build-number sentinel is for local builds — CI always overrides `--build-name` / `--build-number` from the tag. Don't bump the `+N` part manually.
- The `X.Y.Z` part is a **floor** for MAJOR / MINOR jumps. Patch increments come from the latest tag; pubspec is only consulted to trigger jumps. To start a new MINOR / MAJOR train (e.g. `v1.1.0`), bump pubspec on `develop` and the next auto-tag will pick it up.

Typical patch flow: PR merges into `staging` → `auto-staging-pr.yaml` opens the `staging → develop` PR → after that PR merges, `auto-tag.yaml` creates `v1.0.X` on `develop` → `release.yaml` (internal lane) ships the build to TestFlight + Play Internal.

## Getting started

Before getting started, please make sure you have Flutter version 3.41.6 and the latest version of golang and gomobile installed.

```shell
go install golang.org/x/mobile/cmd/gomobile@latest
gomobile init
```

### 1. Generate translations

```shell
dart run tool/generate_localization.dart
```

### 2. Generate Drift files

```shell
dart run build_runner build --delete-conflicting-outputs
```

### 3. Get dependencies

```shell
flutter pub get
```

### 4. Start the app

```shell
flutter run
```
