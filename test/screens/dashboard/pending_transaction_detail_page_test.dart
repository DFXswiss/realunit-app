import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/transactions/dto/transactions_dto.dart';
import 'package:realunit_wallet/screens/dashboard/cubits/pending_transaction_detail/pending_transaction_detail_cubit.dart';
import 'package:realunit_wallet/screens/dashboard/pending_transaction_detail_page.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

class _MockDetailCubit extends MockCubit<PendingTransactionDetailState>
    implements PendingTransactionDetailCubit {}

TransactionDto _tx({
  int? id = 1,
  String? uid,
  TransactionType type = TransactionType.buy,
  TransactionState state = TransactionState.waitingForPayment,
  double? inputAmount = 500,
  String? inputAsset = 'CHF',
  DateTime? date,
}) => TransactionDto(
  id: id,
  uid: uid,
  type: type,
  state: state,
  inputAmount: inputAmount,
  inputAsset: inputAsset,
  date: date ?? DateTime.utc(2026, 5, 21, 8),
);

void main() {
  late _MockDetailCubit cubit;

  setUpAll(() {
    registerFallbackValue(_tx());
  });

  setUp(() {
    cubit = _MockDetailCubit();
    when(() => cubit.state).thenReturn(const PendingTransactionDetailInitial());
    when(() => cubit.deactivate(any())).thenAnswer((_) async {});
  });

  Widget host(TransactionDto tx, {GoRouter? router}) {
    final view = BlocProvider<PendingTransactionDetailCubit>.value(
      value: cubit,
      child: PendingTransactionDetailView(transaction: tx),
    );
    if (router != null) {
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
    return MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: S.delegate.supportedLocales,
      home: view,
    );
  }

  group('$PendingTransactionDetailView', () {
    testWidgets('shows deactivate CTA only for buy + waitingForPayment', (tester) async {
      await tester.pumpWidget(host(_tx()));
      await tester.pump();

      expect(find.text(S.current.pendingTransactionDeactivate), findsOneWidget);
      expect(find.byType(AppFilledButton), findsOneWidget);
      expect(find.byKey(const ValueKey('pendingTxDetailTitle')), findsOneWidget);
      expect(find.byKey(const ValueKey('pendingTxDetailType')), findsOneWidget);
      expect(find.byKey(const ValueKey('pendingTxDetailStatus')), findsOneWidget);
      expect(find.byKey(const ValueKey('pendingTxDetailAmount')), findsOneWidget);
      expect(find.byKey(const ValueKey('pendingTxDetailDate')), findsOneWidget);
      expect(find.byKey(const ValueKey('pendingTxDetailId')), findsOneWidget);
    });

    testWidgets('sell pending has no deactivate button', (tester) async {
      await tester.pumpWidget(
        host(_tx(type: TransactionType.sell, state: TransactionState.processing)),
      );
      await tester.pump();

      expect(find.text(S.current.pendingTransactionDeactivate), findsNothing);
      expect(find.byType(AppFilledButton), findsNothing);
    });

    testWidgets('sell detail title is type-neutral', (tester) async {
      await tester.pumpWidget(
        host(_tx(type: TransactionType.sell, state: TransactionState.processing)),
      );
      await tester.pump();

      final title = tester.widget<Text>(
        find.byKey(const ValueKey('pendingTxDetailTitle')),
      );
      expect(title.data, S.current.pendingTransactionDetailTitle);
    });

    testWidgets('buy + processing has no deactivate button', (tester) async {
      await tester.pumpWidget(
        host(_tx(state: TransactionState.processing)),
      );
      await tester.pump();

      expect(find.text(S.current.pendingTransactionDeactivate), findsNothing);
    });

    testWidgets('sheet cancel does not call deactivate', (tester) async {
      await tester.pumpWidget(host(_tx()));
      await tester.pump();

      await tester.tap(find.text(S.current.pendingTransactionDeactivate));
      await tester.pumpAndSettle();

      expect(find.byType(CancelQuoteConfirmSheet), findsOneWidget);
      expect(find.text(S.current.pendingTransactionDeactivateConfirm), findsOneWidget);

      final sheetCancel = find.descendant(
        of: find.byType(CancelQuoteConfirmSheet),
        matching: find.widgetWithText(AppFilledButton, S.current.cancel),
      );
      await tester.tap(sheetCancel);
      await tester.pumpAndSettle();

      verifyNever(() => cubit.deactivate(any()));
      expect(find.byType(CancelQuoteConfirmSheet), findsNothing);
    });

    testWidgets('sheet confirm calls deactivate once', (tester) async {
      await tester.pumpWidget(host(_tx(id: 42)));
      await tester.pump();

      await tester.tap(find.text(S.current.pendingTransactionDeactivate));
      await tester.pumpAndSettle();

      final sheetConfirm = find.descendant(
        of: find.byType(CancelQuoteConfirmSheet),
        matching: find.widgetWithText(
          AppFilledButton,
          S.current.pendingTransactionDeactivate,
        ),
      );
      await tester.tap(sheetConfirm);
      await tester.pumpAndSettle();

      verify(() => cubit.deactivate(any())).called(1);
    });

    testWidgets('shows loading indicator while deactivating', (tester) async {
      when(() => cubit.state).thenReturn(const PendingTransactionDetailLoading());

      await tester.pumpWidget(host(_tx()));
      await tester.pump();

      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    });

    testWidgets('PopScope blocks pop while loading', (tester) async {
      when(() => cubit.state).thenReturn(const PendingTransactionDetailLoading());

      await tester.pumpWidget(host(_tx()));
      await tester.pump();

      final popScope = tester.widget<PopScope>(find.byType(PopScope));
      expect(popScope.canPop, isFalse);
    });

    testWidgets('PopScope allows pop on initial', (tester) async {
      await tester.pumpWidget(host(_tx()));
      await tester.pump();

      final popScope = tester.widget<PopScope>(find.byType(PopScope));
      expect(popScope.canPop, isTrue);
    });

    testWidgets('shows snackbar on Failure', (tester) async {
      whenListen(
        cubit,
        Stream.fromIterable([
          const PendingTransactionDetailFailure(),
        ]),
        initialState: const PendingTransactionDetailInitial(),
      );

      await tester.pumpWidget(host(_tx()));
      await tester.pump();

      expect(find.text(S.current.pendingTransactionDeactivateFailed), findsOneWidget);
    });

    testWidgets('Success pops the route', (tester) async {
      final states = StreamController<PendingTransactionDetailState>();
      addTearDown(states.close);
      whenListen(
        cubit,
        states.stream,
        initialState: const PendingTransactionDetailInitial(),
      );

      final router = GoRouter(
        initialLocation: '/parent',
        routes: [
          GoRoute(
            path: '/parent',
            builder: (_, _) => const Scaffold(body: Text('parent-marker')),
            routes: [
              GoRoute(
                path: 'child',
                builder: (_, _) => BlocProvider<PendingTransactionDetailCubit>.value(
                  value: cubit,
                  child: PendingTransactionDetailView(transaction: _tx()),
                ),
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(host(_tx(), router: router));
      await tester.pump();
      expect(find.text('parent-marker'), findsOneWidget);

      final popped = router.push<String>('/parent/child');
      await tester.pump();
      await tester.pump();
      expect(find.byType(PendingTransactionDetailView), findsOneWidget);

      states.add(const PendingTransactionDetailSuccess());
      await tester.pump();

      expect(await popped, '1');
      expect(find.text('parent-marker'), findsOneWidget);
      expect(find.byType(PendingTransactionDetailView), findsNothing);
    });

    testWidgets('Success pops the uid when id is null', (tester) async {
      final states = StreamController<PendingTransactionDetailState>();
      addTearDown(states.close);
      whenListen(
        cubit,
        states.stream,
        initialState: const PendingTransactionDetailInitial(),
      );

      final router = GoRouter(
        initialLocation: '/parent',
        routes: [
          GoRoute(
            path: '/parent',
            builder: (_, _) => const Scaffold(body: Text('parent-marker')),
            routes: [
              GoRoute(
                path: 'child',
                builder: (_, _) => BlocProvider<PendingTransactionDetailCubit>.value(
                  value: cubit,
                  child: PendingTransactionDetailView(
                    transaction: _tx(id: null, uid: 'u-wait'),
                  ),
                ),
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(host(_tx(id: null, uid: 'u-wait'), router: router));
      await tester.pump();

      final popped = router.push<String>('/parent/child');
      await tester.pump();
      await tester.pump();

      states.add(const PendingTransactionDetailSuccess());
      await tester.pump();

      expect(await popped, 'u-wait');
    });

    testWidgets('renders amount-only and asset-only when the other is missing', (tester) async {
      await tester.pumpWidget(
        host(
          _tx(inputAmount: 100, inputAsset: null),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('pendingTxDetailAmount')), findsOneWidget);

      await tester.pumpWidget(
        host(
          _tx(inputAmount: null, inputAsset: 'CHF'),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('pendingTxDetailAsset')), findsOneWidget);
    });

    testWidgets('renders fractional amount with two decimals', (tester) async {
      await tester.pumpWidget(host(_tx(inputAmount: 100.5)));
      await tester.pump();
      expect(find.textContaining('100.50'), findsOneWidget);
    });

    testWidgets('renders uid when id is null', (tester) async {
      await tester.pumpWidget(
        host(
          _tx(id: null, uid: 'uid-xyz'),
        ),
      );
      await tester.pump();
      expect(find.text('uid-xyz'), findsOneWidget);
    });

    testWidgets('page widget builds the view', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          home: BlocProvider<PendingTransactionDetailCubit>.value(
            value: cubit,
            child: PendingTransactionDetailPage(transaction: _tx()),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(PendingTransactionDetailView), findsOneWidget);
    });

    testWidgets('sell type label is shown', (tester) async {
      await tester.pumpWidget(
        host(_tx(type: TransactionType.sell, state: TransactionState.processing)),
      );
      await tester.pump();
      expect(find.text(S.current.transactionSell), findsOneWidget);
    });

    testWidgets('non buy/sell type falls back to the enum value string', (tester) async {
      await tester.pumpWidget(
        host(
          const TransactionDto(
            type: TransactionType.swap,
            state: TransactionState.processing,
          ),
        ),
      );
      await tester.pump();
      expect(find.text(TransactionType.swap.value), findsOneWidget);
      expect(find.byKey(const ValueKey('pendingTxDetailId')), findsNothing);
      expect(find.byKey(const ValueKey('pendingTxDetailDate')), findsNothing);
    });

    testWidgets('null type falls back to em dash', (tester) async {
      await tester.pumpWidget(
        host(
          const TransactionDto(
            type: null,
            state: TransactionState.processing,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('—'), findsOneWidget);
    });
  });

  group('$CancelQuoteConfirmSheet', () {
    Widget sheetHost(Widget home) => MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: S.delegate.supportedLocales,
      home: home,
    );

    testWidgets('non-const constructor and both button pops', (tester) async {
      // Load localizations so S.current is available for the non-const ctor.
      await tester.pumpWidget(sheetHost(const SizedBox.shrink()));
      await tester.pump();

      // Non-const so CancelQuoteConfirmSheet's constructor lines are covered.
      // ignore: prefer_const_constructors
      final sheet = CancelQuoteConfirmSheet(strings: S.current);

      await tester.pumpWidget(
        sheetHost(
          Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  AppFilledButton(
                    label: 'open-cancel',
                    onPressed: () {
                      showModalBottomSheet<bool>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => sheet,
                      );
                    },
                  ),
                  AppFilledButton(
                    label: 'open-confirm',
                    onPressed: () {
                      // Second non-const pump path for the primary button.
                      // ignore: prefer_const_constructors
                      showModalBottomSheet<bool>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => CancelQuoteConfirmSheet(strings: S.current),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('open-cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(CancelQuoteConfirmSheet), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(CancelQuoteConfirmSheet),
          matching: find.widgetWithText(AppFilledButton, S.current.cancel),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CancelQuoteConfirmSheet), findsNothing);

      await tester.tap(find.text('open-confirm'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(CancelQuoteConfirmSheet),
          matching: find.widgetWithText(
            AppFilledButton,
            S.current.pendingTransactionDeactivate,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CancelQuoteConfirmSheet), findsNothing);
    });
  });
}
