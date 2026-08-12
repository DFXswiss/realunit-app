import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/screens/migrate_bitbox/cubits/migrate_bitbox/migrate_bitbox_cubit.dart';
import 'package:realunit_wallet/screens/migrate_bitbox/widgets/migrate_result_views.dart';
import 'package:realunit_wallet/setup/routing/routes/app_routes.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

class _MockMigrateBitboxCubit extends MockCubit<MigrateBitboxState>
    implements MigrateBitboxCubit {}

void main() {
  late _MockMigrateBitboxCubit cubit;

  setUp(() {
    cubit = _MockMigrateBitboxCubit();
    when(() => cubit.state).thenReturn(
      const MigrateBitboxFailure(MigrateBitboxFailureReason.generic),
    );
    whenListen(
      cubit,
      const Stream<MigrateBitboxState>.empty(),
      initialState: const MigrateBitboxFailure(
        MigrateBitboxFailureReason.generic,
      ),
    );
    when(() => cubit.retry()).thenAnswer((_) async {});
  });

  Future<void> pumpSurface(WidgetTester tester, Widget surface) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('host')),
        ),
        GoRoute(
          path: '/surface',
          builder: (_, _) => BlocProvider<MigrateBitboxCubit>.value(
            value: cubit,
            child: surface,
          ),
        ),
        GoRoute(
          name: AppRoutes.dashboard,
          path: '/dashboard',
          builder: (_, _) => const Scaffold(body: Text('dashboard')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
      ),
    );
    router.push('/surface');
    await tester.pumpAndSettle();
  }

  testWidgets('RegistrationPending close returns to the previous route', (
    tester,
  ) async {
    await pumpSurface(
      tester,
      const MigrateBitboxRegistrationPendingPage(),
    );

    expect(
      find.text(S.current.migrateBitboxRegistrationPendingInfo),
      findsOneWidget,
    );
    await tester.tap(find.byType(AppFilledButton));
    await tester.pumpAndSettle();

    expect(find.text('host'), findsOneWidget);
  });

  testWidgets('Success shows its copy and goes to dashboard', (tester) async {
    await pumpSurface(tester, const MigrateBitboxSuccessPage());

    expect(find.text(S.current.migrateBitboxSuccessTitle), findsOneWidget);
    expect(find.text(S.current.migrateBitboxSuccessDescription), findsOneWidget);
    await tester.tap(find.byType(AppFilledButton));
    await tester.pumpAndSettle();

    expect(find.text('dashboard'), findsOneWidget);
  });

  final failureCases = <(MigrateBitboxFailureReason, String)>[
    (
      MigrateBitboxFailureReason.addressAlreadyLinked,
      'addressAlreadyLinked',
    ),
    (
      MigrateBitboxFailureReason.registrationMissing,
      'registrationMissing',
    ),
    (
      MigrateBitboxFailureReason.signatureCancelled,
      'signatureCancelled',
    ),
    (
      MigrateBitboxFailureReason.bitboxNotConnected,
      'bitboxNotConnected',
    ),
    (MigrateBitboxFailureReason.generic, 'generic'),
  ];

  for (final (reason, label) in failureCases) {
    testWidgets('Failure $label resolves localized copy and closes', (
      tester,
    ) async {
      await pumpSurface(
        tester,
        MigrateBitboxFailurePage(reason: reason, canRetry: false),
      );

      final expected = switch (reason) {
        MigrateBitboxFailureReason.addressAlreadyLinked =>
          S.current.migrateBitboxAlreadyLinkedError,
        MigrateBitboxFailureReason.registrationMissing =>
          S.current.migrateBitboxRegistrationMissingError,
        MigrateBitboxFailureReason.signatureCancelled =>
          S.current.sendFailureSignatureCancelled,
        MigrateBitboxFailureReason.bitboxNotConnected =>
          S.current.connectBitboxFailed,
        MigrateBitboxFailureReason.generic => S.current.connectBitboxFailed,
      };
      expect(find.text(expected), findsOneWidget);
      expect(find.text(S.current.retry), findsNothing);
      expect(find.byType(AppFilledButton), findsOneWidget);

      await tester.tap(find.byType(AppFilledButton));
      await tester.pumpAndSettle();
      expect(find.text('host'), findsOneWidget);
    });
  }

  testWidgets('retryable Failure shows Retry and dispatches retry', (tester) async {
    await pumpSurface(
      tester,
      const MigrateBitboxFailurePage(
        reason: MigrateBitboxFailureReason.generic,
        canRetry: true,
      ),
    );

    expect(find.byType(AppFilledButton), findsNWidgets(2));
    await tester.tap(find.text(S.current.retry));

    verify(() => cubit.retry()).called(1);
  });
}
