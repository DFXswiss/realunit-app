import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/user/dto/user_dto.dart';
import 'package:realunit_wallet/screens/settings_contact/cubit/settings_contact_cubit.dart';
import 'package:realunit_wallet/screens/settings_contact/settings_contact_page.dart';
import 'package:realunit_wallet/setup/routing/routes/support_routes.dart';
import 'package:realunit_wallet/widgets/outlined_tile.dart';

class _MockSettingsContactCubit extends MockCubit<SettingsContactState>
    implements SettingsContactCubit {}

class _MockDfxKycService extends Mock implements DfxKycService {}

void main() {
  late SettingsContactCubit cubit;
  late List<String> pushedRoutes;
  // Push-result for the `/support/email` capture flow under test. The
  // value the modelled capture page returns drives the re-init →
  // forward path in the page logic; tests flip it per-case.
  bool? emailCaptureResult;
  // Capability returned by the cubit on re-init (after the email
  // capture flow). Most tests don't trigger re-init; the
  // missingPrerequisite branch does.
  CreateSupportTicketCapabilityDto? capabilityAfterReinit;

  setUpAll(() {
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<DfxKycService>()) {
      getIt.registerSingleton<DfxKycService>(_MockDfxKycService());
    }
  });

  setUp(() {
    cubit = _MockSettingsContactCubit();
    when(() => cubit.state).thenReturn(const SettingsContactInitial());
    when(() => cubit.init()).thenAnswer((_) async {
      // Mirror the real cubit: after a successful email capture, the
      // page calls `cubit.init()` and the next state read should
      // surface the refreshed capability. We toggle the stubbed
      // `cubit.state` here so the page's post-`init()` read sees the
      // updated value.
      when(() => cubit.state).thenReturn(
        SettingsContactSuccess(capability: capabilityAfterReinit),
      );
    });
    pushedRoutes = <String>[];
    emailCaptureResult = null;
    capabilityAfterReinit = null;
  });

  GoRouter buildRouter() {
    return GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => BlocProvider<SettingsContactCubit>.value(
            value: cubit,
            child: const SettingsContactView(),
          ),
        ),
        GoRoute(
          name: SupportRoutes.support,
          path: '/support',
          builder: (_, _) {
            pushedRoutes.add(SupportRoutes.support);
            return const Scaffold(body: Text('SUPPORT'));
          },
        ),
        GoRoute(
          name: SupportRoutes.emailCapture,
          path: '/support/email',
          builder: (_, _) {
            pushedRoutes.add(SupportRoutes.emailCapture);
            return _EmailCaptureStub(
              onReady: (popContext) {
                // Pop next frame so the page-under-test sees the
                // capture result via `pushNamed`.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (popContext.mounted) popContext.pop(emailCaptureResult);
                });
              },
            );
          },
        ),
      ],
    );
  }

  Future<void> pumpPage(WidgetTester tester) async {
    final router = buildRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder supportTileFinder() {
    return find.byWidgetPredicate(
      (w) => w is OutlinedTile && w.title == S.current.contactSupport,
    );
  }

  group('$SettingsContactPage', () {
    testWidgets('renders $SettingsContactView and creates a cubit', (tester) async {
      // The page wraps the view in a real BlocProvider that touches DI;
      // we already register a kyc service mock in setUpAll, so this
      // should build without throwing.
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          home: const SettingsContactPage(),
        ),
      );

      expect(find.byType(SettingsContactView), findsOne);
    });
  });

  group('$SettingsContactView tile visibility', () {
    testWidgets('Support tile is visible in Initial state', (tester) async {
      when(() => cubit.state).thenReturn(const SettingsContactInitial());
      await pumpPage(tester);
      expect(supportTileFinder(), findsOne);
    });

    testWidgets('Support tile is visible in Loading state', (tester) async {
      when(() => cubit.state).thenReturn(const SettingsContactLoading());
      await pumpPage(tester);
      expect(supportTileFinder(), findsOne);
    });

    testWidgets('Support tile is visible in Success state', (tester) async {
      when(() => cubit.state).thenReturn(const SettingsContactSuccess());
      await pumpPage(tester);
      expect(supportTileFinder(), findsOne);
    });

    testWidgets('Support tile is visible in Failure state', (tester) async {
      when(() => cubit.state).thenReturn(
        const SettingsContactFailure(message: 'boom'),
      );
      await pumpPage(tester);
      expect(supportTileFinder(), findsOne);
    });
  });

  group('$SettingsContactView routing on Support tile tap', () {
    testWidgets('tap with null capability (legacy backend) pushes Support directly', (
      tester,
    ) async {
      // Pre-PR backends don't ship the capability. The page must
      // still let the user reach Support — the API is the authority.
      when(() => cubit.state).thenReturn(const SettingsContactSuccess());
      await pumpPage(tester);

      await tester.tap(supportTileFinder());
      await tester.pumpAndSettle();

      expect(pushedRoutes, [SupportRoutes.support]);
      verifyNever(() => cubit.init());
    });

    testWidgets('tap in Initial state pushes Support directly', (tester) async {
      // Before init() finishes, the cubit's state has no capability —
      // best-effort fallback is a direct push.
      when(() => cubit.state).thenReturn(const SettingsContactInitial());
      await pumpPage(tester);

      await tester.tap(supportTileFinder());
      await tester.pumpAndSettle();

      expect(pushedRoutes, [SupportRoutes.support]);
    });

    testWidgets('tap in Failure state pushes Support directly', (tester) async {
      // If we failed to load the user, we still let the user reach
      // Support — same best-effort fallback path.
      when(() => cubit.state).thenReturn(
        const SettingsContactFailure(message: 'boom'),
      );
      await pumpPage(tester);

      await tester.tap(supportTileFinder());
      await tester.pumpAndSettle();

      expect(pushedRoutes, [SupportRoutes.support]);
    });

    testWidgets('tap with capability.available=true pushes Support', (tester) async {
      when(() => cubit.state).thenReturn(
        const SettingsContactSuccess(
          capability: CreateSupportTicketCapabilityDto(available: true),
        ),
      );
      await pumpPage(tester);

      await tester.tap(supportTileFinder());
      await tester.pumpAndSettle();

      expect(pushedRoutes, [SupportRoutes.support]);
      verifyNever(() => cubit.init());
    });

    testWidgets(
      'tap with missingPrerequisite=email + capture pop(true) + refreshed capability available → push Support after re-init',
      (tester) async {
        // Happy path of the prerequisite branch: capture page pops
        // with true, cubit re-init reports `available: true`, page
        // forwards to Support.
        when(() => cubit.state).thenReturn(
          const SettingsContactSuccess(
            capability: CreateSupportTicketCapabilityDto(
              available: false,
              missingPrerequisite: MissingPrerequisite.email,
            ),
          ),
        );
        emailCaptureResult = true;
        capabilityAfterReinit = const CreateSupportTicketCapabilityDto(
          available: true,
        );

        await pumpPage(tester);
        await tester.tap(supportTileFinder());
        await tester.pumpAndSettle();

        expect(
          pushedRoutes,
          [SupportRoutes.emailCapture, SupportRoutes.support],
        );
        verify(() => cubit.init()).called(1);
      },
    );

    testWidgets(
      'tap with missingPrerequisite=email + capture pop(false) → NO push to Support, NO re-init',
      (tester) async {
        // User backed out of the capture page. Page must not nudge
        // the user forward or re-fetch.
        when(() => cubit.state).thenReturn(
          const SettingsContactSuccess(
            capability: CreateSupportTicketCapabilityDto(
              available: false,
              missingPrerequisite: MissingPrerequisite.email,
            ),
          ),
        );
        emailCaptureResult = false;

        await pumpPage(tester);
        await tester.tap(supportTileFinder());
        await tester.pumpAndSettle();

        expect(pushedRoutes, [SupportRoutes.emailCapture]);
        verifyNever(() => cubit.init());
      },
    );

    testWidgets(
      'tap with missingPrerequisite=email + capture pop(null) → NO push to Support, NO re-init',
      (tester) async {
        // Same as pop(false): only an explicit success result
        // unlocks forwarding.
        when(() => cubit.state).thenReturn(
          const SettingsContactSuccess(
            capability: CreateSupportTicketCapabilityDto(
              available: false,
              missingPrerequisite: MissingPrerequisite.email,
            ),
          ),
        );
        emailCaptureResult = null;

        await pumpPage(tester);
        await tester.tap(supportTileFinder());
        await tester.pumpAndSettle();

        expect(pushedRoutes, [SupportRoutes.emailCapture]);
        verifyNever(() => cubit.init());
      },
    );

    testWidgets(
      'tap with missingPrerequisite=email + capture pop(true) + refreshed capability still NOT available → NO forward',
      (tester) async {
        // Edge case: the API refresh after a successful capture
        // surfaces a different missing prerequisite (or still
        // `available: false`). We must NOT forward — Support is the
        // last resort and stays gated until the API says yes.
        when(() => cubit.state).thenReturn(
          const SettingsContactSuccess(
            capability: CreateSupportTicketCapabilityDto(
              available: false,
              missingPrerequisite: MissingPrerequisite.email,
            ),
          ),
        );
        emailCaptureResult = true;
        capabilityAfterReinit = const CreateSupportTicketCapabilityDto(
          available: false,
        );

        await pumpPage(tester);
        await tester.tap(supportTileFinder());
        await tester.pumpAndSettle();

        expect(pushedRoutes, [SupportRoutes.emailCapture]);
        verify(() => cubit.init()).called(1);
      },
    );

    testWidgets(
      'tap with available=false and missingPrerequisite null → defensive direct push',
      (tester) async {
        // API said "not available" but didn't name a prerequisite.
        // Defensive fallback: push Support and let the API render the
        // error — never silently swallow the tap.
        when(() => cubit.state).thenReturn(
          const SettingsContactSuccess(
            capability: CreateSupportTicketCapabilityDto(available: false),
          ),
        );

        await pumpPage(tester);
        await tester.tap(supportTileFinder());
        await tester.pumpAndSettle();

        expect(pushedRoutes, [SupportRoutes.support]);
      },
    );

    testWidgets(
      'tap with missingPrerequisite=unknown → defensive direct push',
      (tester) async {
        // Forward-compat: the API ships an additive prerequisite type
        // this app version does not yet recognise. DTO degrades to
        // `unknown`; the page must fall back to a direct Support push
        // so the user is never trapped.
        when(() => cubit.state).thenReturn(
          const SettingsContactSuccess(
            capability: CreateSupportTicketCapabilityDto(
              available: false,
              missingPrerequisite: MissingPrerequisite.unknown,
            ),
          ),
        );

        await pumpPage(tester);
        await tester.tap(supportTileFinder());
        await tester.pumpAndSettle();

        expect(pushedRoutes, [SupportRoutes.support]);
      },
    );
  });
}

/// Minimal capture-page stub that pops with a caller-controlled value
/// on the first post-frame so the page-under-test can read the result
/// via `pushNamed<bool>`.
class _EmailCaptureStub extends StatefulWidget {
  final void Function(BuildContext) onReady;
  const _EmailCaptureStub({required this.onReady});

  @override
  State<_EmailCaptureStub> createState() => _EmailCaptureStubState();
}

class _EmailCaptureStubState extends State<_EmailCaptureStub> {
  @override
  void initState() {
    super.initState();
    widget.onReady(context);
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('CAPTURE'));
}
