# RealUnit App — Contributing Guidelines

## Build & Test Commands

```bash
flutter pub get
dart run tool/generate_localization.dart   # generate i18n from ARB files
dart run tool/generate_release_info.dart   # generate release_info.dart (writes the `dev` sentinel locally)
flutter pub run build_runner build          # generate code (drift, etc.)
flutter test                                # run all tests
flutter analyze                             # lint check
```

After changing ARB files, always regenerate: `dart run tool/generate_localization.dart`

## Responsive UI & sticky CTAs — CRITICAL

The app must stay fully usable on every **standard phone** we support (smallest iPhone SE / compact Android → largest Pro Max / large Android) and at every **system text scale** from smaller than default through extreme accessibility (`textScale` 0.85–3.0).

**Layout rule**

- Flows with long content + bottom actions (bottom sheets, onboarding, confirmations) use [`ScrollableActionsLayout`](lib/widgets/scrollable_actions_layout.dart): scrollable body, **CTAs fixed outside** the scroll view.
- Never rely on `Spacer()` + fixed sheet height alone — that is how the BitBox pairing `Bestätigen` button became untappable on iOS.
- `Spacer()` inside the body is illegal (unbounded main axis in the scroll view → RenderFlex crash). Use `centerBody: true` to vertically center content that still fits.
- Host must provide **bounded height** (bottom sheet, `Expanded`, or fixed `SizedBox`); unbounded height throws `FlutterError` in every build mode.

**Test rule (gate for this bug class)**

- Matrix: [`test/helper/responsive_matrix.dart`](test/helper/responsive_matrix.dart) × [`layout_assertions.dart`](test/helper/layout_assertions.dart) (`expectNoLayoutOverflow`, `expectFullyTappable`).
- Catalog: sticky-CTA surfaces listed in [`responsive_surface_catalog.dart`](test/helper/responsive_surface_catalog.dart) have a matrix test path and a production path; the catalog self-test fails if either file is missing or the production file no longer references `ScrollableActionsLayout`. Listing every sticky-CTA surface is a review responsibility.
- Prefer real `tester.tap` / `expectFullyTappable` over `onPressed?.call()`.
- Details and PR checklist: [`docs/testing.md`](docs/testing.md) § *Responsive layout / sticky CTAs*.

New sticky-CTA UI without `ScrollableActionsLayout` + matrix entry is a **blocking** review finding.

## Branch Flow

Three branches participate in the release lane:

- `staging` — integration branch. **All feature PRs target `staging`**, not `develop`. Same protections as `develop`: 1 approval + `Analyze & Test` + `Visual Regression` + `Coverage Floor Gate`.
- `develop` — pre-release. Receives changes via [`auto-staging-pr.yaml`](.github/workflows/auto-staging-pr.yaml), which opens a `staging → develop` PR on every push to `staging`.
- `main` — production. Receives changes via [`auto-release-pr.yaml`](.github/workflows/auto-release-pr.yaml), which opens a `develop → main` PR on every push to `develop`.

```
feature/* ──(PR)──> staging ──(auto-PR)──> develop ──(auto-PR)──> main
```

The auto-opened promotion PRs are idempotent — only one is open per branch pair at any time. Each one waits for the same review + CI gates as the underlying branch. Tagged releases (`v*`) trigger after the relevant branch receives the commit; see the Release Versioning workflow table in the README for details.

## API Access — CRITICAL

- The app is **only allowed to talk to the DFX API**: `api.dfx.swiss` (mainnet) and `dev.api.dfx.swiss` (testnet/Sepolia). No other hosts.
- **No third-party APIs**: no direct Ethereum JSON-RPC calls (Infura, Alchemy, public nodes, etc.), no block explorer APIs (Etherscan, …), no price feeds, no analytics endpoints, no third-party SDKs that call out over the network.
- If a feature needs on-chain data (e.g. native ETH balance, transaction status, token balance), add a new endpoint to [`DFXswiss/api`](https://github.com/DFXswiss/api) and let the app call that endpoint. The API is the single gateway.
- All network calls must go through `AppStore.httpClient` with `buildUri(_host, …)` — `_host` resolves to the DFX API host via `ApiConfig`. Do not instantiate `http.Client`/`Dio`/`Web3Client` against other hosts.
- **One scoped exception — crash reporting.** Builds that inject `--dart-define=SENTRY_DSN=...` deliver crash reports to the company-operated crash-reporting service ([`lib/setup/error_handling/crash_reporting.dart`](lib/setup/error_handling/crash_reporting.dart)). This is first-party infrastructure telemetry, not a third-party service: without an injected DSN (all local and test builds) the SDK never starts and produces no network traffic, and the delivered data is limited to error events — no PII, no screenshots, no performance tracing, no session telemetry (the exact pinned option surface lives in `crash_reporting.dart`). Widening what is sent (breadcrumbs with request URLs, user context, attachments) is a review-blocking change, not a config tweak.

## API as Decision Authority — CRITICAL

Network access is one half of the gateway rule. **Business decisions are the other half.** The DFX API is the single source of truth for what the user is allowed to do, what state they are in, and what they should be asked to do next. The realunit-app is a **rendering layer** for what the API says.

### The rule

- **The app does not decide if a flow is allowed.** The API decides. If the API accepts a call, the app must not block it pre-emptively.
- **The app does not interpret status strings into business meaning.** It renders what the API returns as `currentStep` / `nextAction` / `state`.
- **The app does not duplicate backend sets/enums as gating logic.** DTO mirroring for type safety is fine; local `_requiredStepNames`, `actionableStatuses`, `_minLevelForActions`, `_minAmountChf` constants are not.
- **Prompts to the user fire only when the API requests them.** "Please verify yourself" appears only when the API signals a pending KYC step — never because the app inferred something from a level number or expired timestamp.

### The test (Wer entscheidet?)

Before adding an `if` / `switch` / `.filter()` on API data, ask:

1. Does the API already return the answer I'm computing? → use it directly.
2. If I remove this local logic and render the API field 1:1, what breaks? → if "nothing", remove it; if "a missing field", extend the API.
3. When local and API disagree, who wins? → the API. Always.

### What is OK in the app

- UI input validation (format, required field, length) — UI concern
- Display formatting (date, currency, locale) — UI concern
- Local security gates (PIN, wallet lock, BitBox connection) — physical security boundary, cannot be API-driven
- Cryptographic operations (EIP-712 signing, key derivation) — must be local

### What is NOT OK in the app

- Deciding which KYC steps are required (`_requiredStepNames`, `_minLevelForActions`) — **the API decides via `requiredKycSteps()` on its side**
- Deciding which step status is "actionable" or "pending" (`actionableStatuses`, `pendingStatuses`) — **the API returns `currentStep` directly**
- Min/max transaction amounts, fees, supported currencies hardcoded — **must come from `/quote` / `/fiat` / `/asset` endpoints**
- Routing flows based on local conditions (`if isBitbox → sellBitbox`) — **API signals the required workflow**
- Feature visibility based on derived local state (Support link only if `emailSet`, Edit only if `!inReview`) — **API returns capability flags**
- Pre-flight validation duplicating API rules — **call the API, render its error**

### When the API doesn't yet expose what we need

Extend the API, then change the app. **Do not add app-side workarounds.** Open an issue / PR in [`DFXswiss/api`](https://github.com/DFXswiss/api) describing the missing field (e.g. `KycStepDto.isRequired`, `BuyQuoteDto.minAmount`, `SettingsCapabilityDto.canBackup`) and wait for it. Temporary local logic is technical debt that **stays** — every shortcut accumulates as another place the app diverges from the API.

### Audit

Current violations of this rule are tracked internally. New PRs must not add to that list; ideally they reduce it.

### Consuming API capabilities — eight rules

When the API exposes a capability (boolean flag or struct on `UserCapabilitiesDto` / similar), the app's consumer code follows the rules below. The mirror — the rules for how the API exposes capabilities — lives in [`DFXswiss/api:CONTRIBUTING.md`](https://github.com/DFXswiss/api/blob/develop/CONTRIBUTING.md) under "API Capability Design". Both sets were synthesised from the `#3733 → #3761 → #3767(closed) → #3772(merged 2026-05-26)` review sequence with @davidleomay.

1. **Read the capability shape, don't reconstruct it.** If the API ships `canEditName: bool`, the page binds `onPressed` to `canEditName`. If it ships `createSupportTicket: { available, missingPrerequisite? }`, the tap handler routes on the discriminator. Never `if (user.mail == null)` or `if (user.kyc.level >= 30)` as a stand-in.

2. **Tile/button visibility for discoverable actions is unconditional.** Tiles that gate prerequisites (Support, KYC, etc.) stay visible regardless of capability state — the user discovers the action even pre-signin. The capability struct's `available` field controls only the **tap outcome** (push the target page vs. push the prerequisite capture page), not the **visibility**.

3. **Map prerequisite types to UI components, not to business rules.** When the capability says `missingPrerequisite: 'Email'`, the app pushes the email capture page. It does NOT contain a comment like "this means mail is required because support needs it" — the rule is on the backend. The app's switch is a UI dispatch, not domain logic.

4. **Legacy backend tolerance — capability optional, sane fallback.** All new capability fields are nullable in the Dart DTO (`createSupportTicket?: CreateSupportTicketCapabilityDto`). On pre-rollout backends the field is null; the consumer falls back to the unprotected direct-push. The behaviour is identical to today's behaviour (pre-capability), so the user is no worse off — the capability just adds the smarter path when the backend supports it.

5. **No reactive 400-handling for what a capability could pre-tell.** If the backend exposes a pre-tap capability, the app must consume it. Attempting the action and reacting to a typed `BadRequestException` post-submit is a regression — the user loses form data, the error-body parsing is brittle, the navigation choreography is fragile. Reactive errors are only for things the capability can't predict (network failures, transient backend issues, race conditions).

6. **Pair-PR discipline.** App-side capability adoption happens in the same PR that deletes the local logic the capability replaces. PR title: `refactor(<scope>): consume <Capability>`. PR body references the violation it resolves and the API-side commit. The PR is opened **after** the API PR has merged on `develop` — running ahead of the API merge means the consumer sees null forever in DEV and the change effectively dead-codes itself.

7. **Tests pin the contract, not the implementation.** Cubit tests assert that `init()` with `capability == null` emits the legacy-fallback success state; with `available: true` emits the available state; with `available: false, missingPrerequisite: Email` emits the prerequisite-required state. Widget tests assert that taps in each state push the correct route. Don't test "if mail == null, the tile state is unavailable" — that ties the test to the backend rule, exactly what we're trying to decouple.

8. **Push back on capability shape that's over-engineered.** Capabilities should be the minimum dynamic info to fulfil a UX requirement. Endpoint paths, HTTP methods, and i18n strings belong in Swagger / the client respectively. If a proposed API field looks like it duplicates static information, comment on the API PR asking for the minimum surface. Reference template: <https://github.com/DFXswiss/api/pull/3772#issuecomment-4549147861>.

#### Concrete pattern — Support ticket flow

The first capability that follows this design lives end-to-end across these PRs:

- API: [DFXswiss/api#3772](https://github.com/DFXswiss/api/pull/3772) — adds `createSupportTicket: { available, missingPrerequisite? }`.
- App: companion PR on this repo consuming the field — `SettingsContactPage` keeps the tile unconditional, `SettingsContactCubit` hydrates the capability from `/v2/user`, the tap handler in the view routes on `capability.available` / `capability.missingPrerequisite`.

Future capabilities follow the same shape: bool for hide-able, `{ available, missingPrerequisite? }` for discoverable. The closed `MissingPrerequisite` enum grows additively as new prerequisite gates appear server-side.

## Project Architecture

```
lib/
  di.dart                          # GetIt service locator setup
  router.dart                      # GoRouter route definitions
  models/                          # Domain models (extend Equatable)
  packages/
    repository/                    # Data access layer
    service/dfx/
      models/{resource}/dto/       # DTOs with fromJson()
      {resource}_service.dart      # Business logic services
  screens/{screen}/
    bloc/ or cubits/               # State management per screen
    widgets/                       # Screen-specific widgets
  styles/                          # Colors, TextStyles, Themes
  widgets/                         # Shared reusable widgets
```

## Styling — CRITICAL

- **Colors**: Always use `RealUnitColors.*` or `RealUnitColors.basic.white` / `.black`. Avoid using colors from `material.dart` (`Colors.white`, `Colors.black`, `Colors.transparent`, etc.) if possible. NEVER use raw `Color(0x...)` values.
- **Transparent colors**: `RealUnitColors.basic.white.withValues(alpha: 0)` — NEVER `Color(0x00FFFFFF)`.
- **TextStyles**: Always use `Theme.of(context).textTheme.*` (headlineLarge/Medium/Small, bodyLarge/Medium/Small). NEVER hardcode `TextStyle(fontSize: 26, fontWeight: ...)`.
  - Mapping: `headlineLarge` = h1 (30/600), `headlineMedium` = h2 (26/bold), `headlineSmall` = h4 (20/bold), `bodyLarge` = base (16), `bodyMedium` = sm (14), `bodySmall` = xs (12)
  - Any changes to TextStyles should happen via `.copyWith(...)` (e.g., color, fontWeight).
- **Loading indicators**: `CupertinoActivityIndicator` — NEVER `CircularProgressIndicator`.
- **Linter**: Use `analysis_options.yaml` as the linter rule reference.

## Localization (i18n)

- Source files: `assets/languages/strings_de.arb` and `strings_en.arb`
- Generated file: `lib/generated/i18n.dart` (in .gitignore)
- Keys MUST be alphabetically sorted in both ARB files.
- Always update BOTH de and en ARB files.
- Punctuation belongs in the template (`'${s.label}: $value'`), NOT in the ARB value.
- Before adding a new key: search existing keys first — reuse where possible.
- Avoid using `S.current` (no context) in cubits/blocs. Prefer emitting typed states and resolving localization in the UI via `S.of(context)`. When localization is needed in functions, pass `BuildContext` rather than `S`.

## Release Versioning

- Single source of truth for a published build: the git tag. Tags are plain SemVer `vX.Y.Z` — no pre-release suffix. The previous `vX.Y.Z-beta.N` schema has been retired and tags carrying any suffix are rejected by the generator.
- PATCH (`v1.0.X`, X >= 1) is bumped automatically by `.github/workflows/auto-tag.yaml` on every push to `develop`. MINOR / MAJOR are manual tag pushes — they mark an App-Store-update candidate.
- Both release workflows ship to Test tracks only (TestFlight + Play Internal). Production promotion is done manually in the store backends, never by a tag push.
- `tool/generate_release_info.dart` derives the in-app `releaseTag`, the platform-identical `versionCode` and the `marketingVersion` from the tag. Schema: `MAJOR * 10_000_000 + MINOR * 100_000 + PATCH * 1_000 + 999`. The fixed `+999` suffix keeps new build codes strictly above the legacy beta train (highest published was `v1.0.0-beta.14` → `10_000_014`).
- Local builds carry `releaseTag = 'dev'` (versionCode `0`) so the settings footer reads `Version dev` instead of a stale pinned build number.
- `pubspec.yaml`'s `version:` field has two roles:
  - `+0` is a sentinel for local builds — CI always overrides `--build-name` / `--build-number` from the tag. Don't bump the `+N` part manually.
  - The `X.Y.Z` part is consumed by `auto-tag.yaml` as a **floor** for MAJOR / MINOR bumps. Patch increments come from the latest tag; pubspec is only consulted to trigger jumps. To start a new MINOR / MAJOR train (e.g. `1.1.0`), bump the `X.Y.Z` part in `pubspec.yaml` on `develop` and the next auto-tag will pick it up. Patch-level work needs no edit — just push to develop.
- Schema limits: `MAJOR`, `MINOR`, `PATCH` in `0..99`. The generator hard-fails outside these bounds. Before approaching `PATCH = 99` on a given train, bump `pubspec.yaml`'s MINOR (e.g. `1.0.99` → `1.1.0`) so auto-tag starts a new train. There is intentionally no safety net — surprising a CI cap is preferable to silently overflowing the version code.

See the README's "Release versioning" section for the full table and the typical patch flow.

## State Management

- **Bloc**: For complex event-driven flows. Events are `sealed class` extending `Equatable`. States use `final class` — use `copyWith` or distinct state classes (Initial, Loading, Success, Failure) depending on the use case.
- **Cubit**: For simpler state. States extend `Equatable` — use `copyWith` or distinct state classes depending on the use case.
- State files are separate from bloc/cubit files.

## Wallet Modes

The app supports three wallet modes (`software`, `bitbox`, `debug`) with different signing capabilities. Any feature that needs an EIP-712 signature must gate on `getIt<AppStore>().wallet.walletType` and surface a dedicated failure state for modes that cannot sign (today: `debug`). See [`docs/wallet-modes.md`](docs/wallet-modes.md) for the full table and the `KycSignatureUnsupportedFailure` precedent.

## DTOs & Models

- DTOs live in `lib/packages/service/dfx/models/{resource}/dto/`
- Naming: `{Resource}Dto` with `factory fromJson(Map<String, dynamic> json)`
- Type casting: `json['field'] as Type` — no dynamic access.
- NEVER parse JSON inline in services — always create a DTO class.
- Domain models are separate from DTOs and extend `Equatable`.

## Navigation

- Uses GoRouter. Routes defined in `lib/setup/routing/router_config.dart`.
- Route names are defined in typed classes: `AppRoutes`, `SettingsRoutes`, `PinRoutes`, `OnboardingRoutes`, `LegalRoutes`.
- Always use `pushNamed`/`goNamed` with route constants — NEVER hardcode route strings.
- Pages should read their own dependencies from Bloc/DI — avoid passing data via route `extra` when the page can obtain it from context.

## Dependency Injection

- GetIt service locator in `lib/di.dart`.
- Access via `getIt<ServiceType>()` — use inline, don't store in local variables unless used multiple times.

## Testing

- Uses `flutter_test`, `bloc_test`, and `mocktail` (NOT mockito).
- Test structure mirrors `lib/` structure.
- Test helper at `test/helper/` (provides `pumpApp`).
- For BitBox-related code, the layered test strategy (Tier 0–4) is documented in [`docs/testing.md`](docs/testing.md), with concrete patterns for cubit tests, widget tests, service + HTTP tests, and `FakeBitboxCredentials`-backed integration tests.
- [`docs/testing.md`](docs/testing.md) also lists the surface that needs an infra PR first (Drift repositories, `getIt`-coupled pages, `path_provider`-coupled cubits, the Sumsub SDK, plugin-coupled widgets). Don't try to mock around those without changing the injection point.
- Service-lifecycle tests are mandatory for any service with a `Timer`, observer/subscription loop, or platform/MethodChannel dependency: instantiate the real class (no mock of the service itself), swap `BitboxUsbPlatform.instance` in `setUp` and restore in `tearDown`. Tests with periodic-timer or observer behaviour MUST drive time via `package:fake_async` (`fakeAsync` zone + `async.elapse(...)`). Wall-clock `Future.delayed` is not acceptable for time-bound assertions.
  - Why: mocking the service-under-test hides timer leaks, unsubscribed listeners, and double-init bugs; wall-clock delays make tests slow and flaky.
  - See: `test/packages/hardware_wallet/bitbox_service_test.dart`.
- Exception surface tests are mandatory: every typed exception in `lib/` (any class that `implements Exception` or `extends Exception`) MUST override `toString()` so the rendered string does not contain `Instance of` and is non-empty, AND MUST be enumerated in the shared surface test the moment it is introduced. When a new typed exception is added to `lib/`, it MUST be added to the enumeration in `exception_surface_test.dart` in the same PR. The test exists to catch precisely this kind of drift.
  - Why: exceptions surface in logs, Sentry, and user-facing error states — the Dart default `Instance of '...'` is useless for debugging and unfriendly for users.
  - See: `test/packages/service/dfx/exceptions/exception_surface_test.dart`.
- Platform-specific code paths (USB transports, BLE lifecycle, secure storage, biometric prompts, deep links) MUST either ship an `integration_test/` counterpart exercising the real plugin or vendor simulator, OR carry an inline `// @no-integration-test: <reason>` annotation as either a file-level dartdoc comment OR immediately above the function/method declaration.[^integration-test]
  - Why: unit tests with mocked platform channels cannot catch real-device regressions (permission prompts, OS-level lifecycle, transport quirks); the annotation makes the absence of an integration test a deliberate, reviewable decision.
  - See: grep the annotation with
    ```bash
    rg "^//\s*@no-integration-test:" lib/
    ```
- Visual-regression Goldens under `test/goldens/screens/` are also the source of the 26 screenshots served at `handbook.realunit.app`. When you add a handbook page, you MUST add a matching Golden test AND a row in the mapping table at `scripts/assemble-handbook-screenshots.sh` — the handbook will not pick up a Maestro-captured PNG anymore. The `Handbook Build Check` workflow on every PR runs the assembly script and fails loudly if a mapped Golden is missing.
  - Why: single source of truth — a UI regression that breaks a Golden also breaks the handbook image before either ships; eliminates the previous "two pipelines, two truths" problem.
  - See: [`docs/visual-regression-tests.md`](docs/visual-regression-tests.md) section "Handbook screenshots are sourced from Goldens".

[^integration-test]: Activates once an `integration_test/` directory exists in the repo; until then, treat option 1 as N/A and the `// @no-integration-test:` annotation as the documenting form.

## Widget Guidelines

- Prefer `StatelessWidget` unless lifecycle management is truly needed.
- Extract widgets into own files if they can be graphically as well as semantically separated.
- Don't create wrapper widgets that only delegate to a child.
- Prefer `Align` instead of `Positioned`.

## Dependencies

- `pubspec.yaml` dependencies must be alphabetically sorted.
- Imports within files: alphabetically sorted. Order: `dart:` → `package:flutter` → `package:other` → `package:realunit_wallet/`.

## Common Mistakes to Avoid

- Don't leave unused imports after refactoring.
- Don't use default parameter values that contradict business rules (e.g., `amount = '300'` when minimum is 1000).
- Don't add explanatory comments for workarounds — fix the root cause instead.
- Don't add i18n keys without using them — remove unused keys when deleting features.
- Avoid using `SizedBox` for spacing in Column/Row — use the `spacing` property instead:

  ```dart
  // Bad
  Column(children: [Widget1(), SizedBox(height: 16), Widget2()])

  // Good
  Column(spacing: 16, children: [Widget1(), Widget2()])
  ```

- Don't use positional parameters for optional values in state classes — use named parameters:

  ```dart
  // Bad
  const MyState(this.optionalData, {this.otherField});

  // Good
  const MyState({this.optionalData, this.otherField});
  ```

- Follow existing patterns. For multi-step flows (e.g., KYC), each step should have its own Page + Cubit. Don't combine multiple steps into one, pass data through state, or use inline widgets with callbacks when a separate page is the established pattern.
- Follow the separation of concerns principle.
