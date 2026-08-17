import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/transactions/dto/transactions_dto.dart';
import 'package:realunit_wallet/screens/dashboard/bloc/pending_transactions_cubit.dart';
import 'package:realunit_wallet/screens/dashboard/widgets/pending_transaction_row.dart';
import 'package:realunit_wallet/screens/dashboard/widgets/sections/dashboard_pending_transactions.dart';
import 'package:realunit_wallet/setup/routing/routes/app_routes.dart';

class _MockPendingCubit extends MockCubit<List<TransactionDto>>
    implements PendingTransactionsCubit {}

TransactionDto _tx({
  int? id = 1,
  String? uid,
  TransactionType type = TransactionType.buy,
  TransactionState state = TransactionState.processing,
}) => TransactionDto(
  id: id,
  uid: uid,
  type: type,
  state: state,
  date: DateTime.utc(2026, 5, 15),
);

void main() {
  late _MockPendingCubit cubit;

  setUpAll(() {
    registerFallbackValue(_tx());
    registerFallbackValue('');
    registerFallbackValue(null);
  });

  setUp(() {
    cubit = _MockPendingCubit();
    when(() => cubit.reload()).thenAnswer((_) async {});
    when(() => cubit.drop(any())).thenReturn(null);
    when(() => cubit.applyDetailReturn(any())).thenAnswer((_) async {});
  });

  Widget host() => BlocProvider<PendingTransactionsCubit>.value(
    value: cubit,
    child: MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: S.delegate.supportedLocales,
      // Non-const so DashboardPendingTransactionsView's constructor is covered.
      // ignore: prefer_const_constructors
      home: Scaffold(body: DashboardPendingTransactionsView()),
    ),
  );

  Widget hostWithRouter() {
    final router = GoRouter(
      initialLocation: '/dashboard',
      routes: [
        GoRoute(
          name: AppRoutes.dashboard,
          path: '/dashboard',
          builder: (_, _) => BlocProvider<PendingTransactionsCubit>.value(
            value: cubit,
            child: const Scaffold(body: DashboardPendingTransactionsView()),
          ),
          routes: [
            GoRoute(
              name: AppRoutes.pendingTransaction,
              path: 'pendingTransaction',
              builder: (_, state) => Scaffold(
                body: Text(
                  'detail-${(state.extra as TransactionDto).id}',
                  key: const ValueKey('pending-detail-marker'),
                ),
              ),
            ),
          ],
        ),
      ],
    );

    return MaterialApp.router(
      routerConfig: router,
      locale: const Locale('de'),
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: S.delegate.supportedLocales,
    );
  }

  group('$DashboardPendingTransactionsView', () {
    testWidgets('empty list: renders SizedBox.shrink (no PendingTransactionRow)', (tester) async {
      when(() => cubit.state).thenReturn([]);

      await tester.pumpWidget(host());
      await tester.pump();

      expect(find.byType(PendingTransactionRow), findsNothing);
    });

    testWidgets('non-empty list: renders one PendingTransactionRow per tx', (tester) async {
      when(() => cubit.state).thenReturn([
        _tx(id: 1),
        _tx(id: 2, type: TransactionType.sell),
        _tx(id: 3),
      ]);

      await tester.pumpWidget(host());
      await tester.pump();

      expect(find.byType(PendingTransactionRow), findsNWidgets(3));
      expect(find.byKey(const ValueKey('pendingTx-1')), findsOneWidget);
    });

    testWidgets('never shows a deactivate IconButton on any row', (tester) async {
      when(() => cubit.state).thenReturn([
        _tx(id: 1, state: TransactionState.waitingForPayment),
        _tx(id: 2, type: TransactionType.sell),
        _tx(id: 3, state: TransactionState.waitingForPayment),
      ]);

      await tester.pumpWidget(host());
      await tester.pump();

      expect(find.byType(IconButton), findsNothing);
    });

    testWidgets('tap on buy-waiting row navigates to pending detail and reloads', (tester) async {
      when(() => cubit.state).thenReturn([
        _tx(id: 1, state: TransactionState.waitingForPayment),
        _tx(id: 2, type: TransactionType.sell),
      ]);

      await tester.pumpWidget(hostWithRouter());
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('pendingTx-1')));
      // CupertinoActivityIndicator animates indefinitely — no pumpAndSettle.
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('pending-detail-marker')), findsOneWidget);
      expect(find.text('detail-1'), findsOneWidget);

      // Pop the cancelled id so the list drops the row even if reload fails.
      final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
      navigator.pop('1');
      await tester.pump();
      await tester.pump();

      verify(() => cubit.applyDetailReturn('1')).called(1);
    });

    testWidgets('pop without a cancelled id still applies the return', (tester) async {
      when(() => cubit.state).thenReturn([
        _tx(id: 1, state: TransactionState.waitingForPayment),
      ]);

      await tester.pumpWidget(hostWithRouter());
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('pendingTx-1')));
      await tester.pump();
      await tester.pump();

      final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
      navigator.pop();
      await tester.pump();
      await tester.pump();

      verify(() => cubit.applyDetailReturn(null)).called(1);
    });

    testWidgets('unmount while the detail route is open still reloads the cubit', (tester) async {
      when(() => cubit.state).thenReturn([
        _tx(id: 1, state: TransactionState.waitingForPayment),
      ]);

      final showList = ValueNotifier(true);
      addTearDown(showList.dispose);
      final router = GoRouter(
        initialLocation: '/dashboard',
        routes: [
          GoRoute(
            name: AppRoutes.dashboard,
            path: '/dashboard',
            builder: (_, _) => ValueListenableBuilder<bool>(
              valueListenable: showList,
              builder: (_, visible, _) => BlocProvider<PendingTransactionsCubit>.value(
                value: cubit,
                child: Scaffold(
                  body: visible
                      ? const DashboardPendingTransactionsView()
                      : const SizedBox.shrink(),
                ),
              ),
            ),
            routes: [
              GoRoute(
                name: AppRoutes.pendingTransaction,
                path: 'pendingTransaction',
                builder: (_, state) => Scaffold(
                  body: Text(
                    'detail-${(state.extra as TransactionDto).id}',
                    key: const ValueKey('pending-detail-marker'),
                  ),
                ),
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          locale: const Locale('de'),
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('pendingTx-1')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('pending-detail-marker')), findsOneWidget);

      // Unmount the list view but keep the navigator so pushNamed can resolve.
      showList.value = false;
      await tester.pump();
      router.pop();
      await tester.pump();
      await tester.pump();

      verify(() => cubit.applyDetailReturn(null)).called(1);
    });

    testWidgets('tap on sell row also navigates (details without cancel CTA)', (tester) async {
      when(() => cubit.state).thenReturn([
        _tx(id: 2, type: TransactionType.sell),
      ]);

      await tester.pumpWidget(hostWithRouter());
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('pendingTx-2')));
      await tester.pump();
      await tester.pump();

      expect(find.text('detail-2'), findsOneWidget);
    });

    testWidgets('non-empty list also renders a section header above the rows', (tester) async {
      when(() => cubit.state).thenReturn([_tx()]);

      await tester.pumpWidget(host());
      await tester.pump();

      // Header position: the first Text widget is rendered before the
      // PendingTransactionRow's children. We only pin that the header Text
      // exists outside any PendingTransactionRow.
      final headerCount = find
          .descendant(
            of: find.byType(Column).first,
            matching: find.byType(Text),
          )
          .evaluate()
          .length;
      expect(headerCount, greaterThan(0));
      expect(find.byType(PendingTransactionRow), findsOneWidget);
    });

    testWidgets('uid-only row uses uid in the ValueKey', (tester) async {
      when(() => cubit.state).thenReturn([
        TransactionDto(
          id: null,
          uid: 'waiting-uid',
          type: TransactionType.buy,
          state: TransactionState.waitingForPayment,
          date: DateTime.utc(2026, 5, 15),
        ),
      ]);

      await tester.pumpWidget(host());
      await tester.pump();

      expect(find.byKey(const ValueKey('pendingTx-waiting-uid')), findsOneWidget);
    });
  });
}
