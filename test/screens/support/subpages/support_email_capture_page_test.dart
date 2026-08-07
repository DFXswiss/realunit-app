import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_widget_service.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_registration_service.dart';
import 'package:realunit_wallet/screens/home/bloc/home_bloc.dart';
import 'package:realunit_wallet/screens/kyc/steps/email/subpages/kyc_email_verification_page.dart';
import 'package:realunit_wallet/screens/support/cubits/support_email_capture/support_email_capture_cubit.dart';
import 'package:realunit_wallet/screens/support/subpages/support_email_capture_page.dart';
import 'package:realunit_wallet/widgets/form/labeled_text_field.dart';

class _MockSupportEmailCaptureCubit extends MockCubit<SupportEmailCaptureState>
    implements SupportEmailCaptureCubit {}

class _MockRegistrationService extends Mock implements RealUnitRegistrationService {}

class _MockDfxWidgetService extends Mock implements DfxWidgetService {}

class _MockHomeBloc extends MockBloc<HomeEvent, HomeState> implements HomeBloc {}

/// Pops the second pushed sub-route with [value]. The merge branch pushes the
/// shared [KycEmailVerificationPage] on top of the capture page; this lets a
/// test simulate the user confirming (`true`) — or backing out (`null`) — of
/// that page without fully driving it. The root/home route
/// (`previousRoute == null`) and the first sub-route (the capture page) are
/// skipped; the pop happens on the next microtask so the verification route
/// mounts first, matching a real user tapping "I've confirmed".
class _AutoPopVerificationObserver extends NavigatorObserver {
  _AutoPopVerificationObserver({this.value});

  final Object? value;
  int _subPushes = 0;
  bool _popped = false;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (previousRoute == null) return; // root/home route
    _subPushes++;
    if (_subPushes == 2 && !_popped) {
      _popped = true;
      Future.microtask(() => route.navigator?.pop<bool>(value as bool?));
    }
  }
}

void main() {
  late SupportEmailCaptureCubit cubit;
  late HomeBloc homeBloc;

  setUpAll(() {
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<RealUnitRegistrationService>()) {
      getIt.registerSingleton<RealUnitRegistrationService>(
        _MockRegistrationService(),
      );
    }
    // The merge branch routes to KycEmailVerificationPage, which resolves its
    // cubit's DFXAuthService from getIt<DfxWidgetService>.
    if (!getIt.isRegistered<DfxWidgetService>()) {
      getIt.registerSingleton<DfxWidgetService>(_MockDfxWidgetService());
    }
  });

  setUp(() {
    cubit = _MockSupportEmailCaptureCubit();
    when(() => cubit.state).thenReturn(const SupportEmailCaptureInitial());
    homeBloc = _MockHomeBloc();
    when(() => homeBloc.state).thenReturn(const HomeState());
  });

  Widget pumpView() {
    return MaterialApp(
      localizationsDelegates: [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
      ],
      supportedLocales: S.delegate.supportedLocales,
      home: BlocProvider<SupportEmailCaptureCubit>.value(
        value: cubit,
        child: const SupportEmailCaptureView(),
      ),
    );
  }

  // Hosts the capture page under a Navigator so the merge branch's
  // Navigator.push (and the capture page's own pop) are observable, with
  // HomeBloc provided above MaterialApp so the pushed verification page can
  // read it.
  Widget mergeHarness({
    required List<NavigatorObserver> observers,
    required Future<void> Function(BuildContext) onLaunch,
  }) {
    return BlocProvider<HomeBloc>.value(
      value: homeBloc,
      child: MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        navigatorObservers: observers,
        home: _LauncherPage(onLaunch: onLaunch),
      ),
    );
  }

  Widget captureRoute() => BlocProvider<SupportEmailCaptureCubit>.value(
        value: cubit,
        child: const SupportEmailCaptureView(),
      );

  group('$SupportEmailCapturePage', () {
    testWidgets('builds the view via BlocProvider create', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          home: const SupportEmailCapturePage(),
        ),
      );

      expect(find.byType(SupportEmailCaptureView), findsOne);
    });
  });

  group('$SupportEmailCaptureView form', () {
    testWidgets('renders title, description, email field, and continue button', (tester) async {
      await tester.pumpWidget(pumpView());

      expect(find.text(S.current.supportEmailCaptureTitle), findsOne);
      expect(find.text(S.current.supportEmailCaptureDescription), findsOne);
      expect(find.byType(LabeledTextField), findsOne);
      expect(find.text(S.current.supportEmailCaptureContinue), findsOne);
    });

    testWidgets('empty email shows the required validator message', (tester) async {
      await tester.pumpWidget(pumpView());

      await tester.tap(find.text(S.current.supportEmailCaptureContinue));
      await tester.pumpAndSettle();

      expect(find.text(S.current.registerEmailRequired), findsOne);
      verifyNever(() => cubit.submit(any()));
    });

    testWidgets('invalid email shows the invalid validator message', (tester) async {
      await tester.pumpWidget(pumpView());

      await tester.enterText(find.byType(TextFormField), 'not-an-email');
      await tester.tap(find.text(S.current.supportEmailCaptureContinue));
      await tester.pumpAndSettle();

      expect(find.text(S.current.registerEmailInvalid), findsOne);
      verifyNever(() => cubit.submit(any()));
    });

    testWidgets('valid email submits to the cubit', (tester) async {
      when(() => cubit.submit(any())).thenAnswer((_) async {});

      await tester.pumpWidget(pumpView());

      await tester.enterText(find.byType(TextFormField), 'a@b.com');
      await tester.tap(find.text(S.current.supportEmailCaptureContinue));
      await tester.pumpAndSettle();

      verify(() => cubit.submit('a@b.com')).called(1);
    });

    testWidgets('Loading state renders the activity indicator', (tester) async {
      when(() => cubit.state).thenReturn(const SupportEmailCaptureLoading());

      await tester.pumpWidget(pumpView());

      expect(find.byType(CupertinoActivityIndicator), findsOne);
    });

    testWidgets('tapping the form background unfocuses the email field', (tester) async {
      await tester.pumpWidget(pumpView());

      await tester.tap(find.byType(TextFormField));
      await tester.pump();
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.focusNode.hasFocus, isTrue);

      // The GestureDetector wrapping the form dismisses the keyboard.
      await tester.tap(find.text(S.current.supportEmailCaptureDescription));
      await tester.pump();

      expect(field.focusNode.hasFocus, isFalse);
    });
  });

  group('$SupportEmailCaptureView navigation & snackbar behavior', () {
    testWidgets('Success state pops the route with true', (tester) async {
      // Wire the view inside a GoRouter so the page's
      // `Navigator.pop(true)` is observable via the parent
      // recording the result.
      Object? popResult;
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => _LauncherPage(
              onLaunch: (ctx) async {
                popResult = await ctx.push('/capture');
              },
            ),
          ),
          GoRoute(
            path: '/capture',
            builder: (_, _) => BlocProvider<SupportEmailCaptureCubit>.value(
              value: cubit,
              child: const SupportEmailCaptureView(),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      whenListen(
        cubit,
        Stream.fromIterable(const [SupportEmailCaptureSuccess()]),
        initialState: const SupportEmailCaptureInitial(),
      );

      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
        ),
      );
      await tester.pumpAndSettle();

      // Trigger the navigation that pushes the capture page.
      await tester.tap(find.text('LAUNCH'));
      await tester.pumpAndSettle();

      expect(popResult, isTrue);
    });

    testWidgets('MergeRequested routes to the email-verification page', (tester) async {
      whenListen(
        cubit,
        Stream.fromIterable(const [SupportEmailCaptureMergeRequested()]),
        initialState: const SupportEmailCaptureInitial(),
      );

      await tester.pumpWidget(
        BlocProvider<HomeBloc>.value(
          value: homeBloc,
          child: MaterialApp(
            localizationsDelegates: const [
              S.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: S.delegate.supportedLocales,
            home: captureRoute(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The merge branch pushes the shared verification flow, not a red error.
      expect(find.byType(KycEmailVerificationPage), findsOne);
    });

    testWidgets('MergeRequested + confirmation pops the capture route with true', (tester) async {
      whenListen(
        cubit,
        Stream.fromIterable(const [SupportEmailCaptureMergeRequested()]),
        initialState: const SupportEmailCaptureInitial(),
      );
      Object? popResult;

      await tester.pumpWidget(
        mergeHarness(
          observers: [_AutoPopVerificationObserver(value: true)],
          onLaunch: (ctx) async {
            popResult = await Navigator.of(ctx).push<bool>(
              MaterialPageRoute<bool>(builder: (_) => captureRoute()),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('LAUNCH'));
      await tester.pumpAndSettle();

      expect(popResult, isTrue);
    });

    testWidgets('MergeRequested + back-out keeps the form and does not pop', (tester) async {
      whenListen(
        cubit,
        Stream.fromIterable(const [SupportEmailCaptureMergeRequested()]),
        initialState: const SupportEmailCaptureInitial(),
      );
      var capturePopped = false;

      await tester.pumpWidget(
        mergeHarness(
          observers: [_AutoPopVerificationObserver(value: null)],
          onLaunch: (ctx) async {
            await Navigator.of(ctx).push<bool>(
              MaterialPageRoute<bool>(builder: (_) => captureRoute()),
            );
            capturePopped = true; // only runs once the capture route pops
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('LAUNCH'));
      await tester.pumpAndSettle();

      // Verification was dismissed without confirmation (await returned null),
      // so the confirm guard's false branch ran and the capture route did NOT
      // pop — it stays on the stack (offstage beneath nothing now).
      expect(find.byType(KycEmailVerificationPage), findsNothing);
      expect(capturePopped, isFalse);
      expect(find.byType(SupportEmailCaptureView, skipOffstage: false), findsOne);
    });

    testWidgets('Failure state shows the raw error message', (tester) async {
      whenListen(
        cubit,
        Stream.fromIterable(const [
          SupportEmailCaptureFailure('something broke'),
        ]),
        initialState: const SupportEmailCaptureInitial(),
      );

      await tester.pumpWidget(pumpView());
      await tester.pump();
      await tester.pump();

      expect(find.text('something broke'), findsOne);
    });
  });
}

/// Helper page that lets a test trigger a navigation push and capture
/// the result of `pop()`.
class _LauncherPage extends StatelessWidget {
  final Future<void> Function(BuildContext) onLaunch;
  const _LauncherPage({required this.onLaunch});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => onLaunch(context),
          child: const Text('LAUNCH'),
        ),
      ),
    );
  }
}
