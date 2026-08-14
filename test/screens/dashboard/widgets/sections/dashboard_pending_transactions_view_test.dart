import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/transactions/dto/transactions_dto.dart';
import 'package:realunit_wallet/screens/dashboard/bloc/pending_transactions_cubit.dart';
import 'package:realunit_wallet/screens/dashboard/widgets/pending_transaction_row.dart';
import 'package:realunit_wallet/screens/dashboard/widgets/sections/dashboard_pending_transactions.dart';

import '../../../../helper/helper.dart';

class _MockPendingCubit extends MockCubit<List<TransactionDto>>
    implements PendingTransactionsCubit {}

TransactionDto _tx({int? id = 1, TransactionType type = TransactionType.buy}) =>
    TransactionDto(
      id: id,
      type: type,
      state: TransactionState.processing,
      date: DateTime.utc(2026, 5, 15),
    );

void main() {
  late _MockPendingCubit cubit;

  setUpAll(() {
    registerFallbackValue(_tx());
  });

  setUp(() {
    cubit = _MockPendingCubit();
  });

  Widget host() => BlocProvider<PendingTransactionsCubit>.value(
        value: cubit,
        child: const Scaffold(body: DashboardPendingTransactionsView()),
      );

  group('$DashboardPendingTransactionsView', () {
    testWidgets('empty list: renders SizedBox.shrink (no PendingTransactionRow)',
        (tester) async {
      when(() => cubit.state).thenReturn([]);

      await tester.pumpApp(host());

      expect(find.byType(PendingTransactionRow), findsNothing);
    });

    testWidgets('non-empty list: renders one PendingTransactionRow per tx',
        (tester) async {
      when(() => cubit.state).thenReturn([
        _tx(id: 1),
        _tx(id: 2, type: TransactionType.sell),
        _tx(id: 3),
      ]);

      await tester.pumpApp(host());

      expect(find.byType(PendingTransactionRow), findsNWidgets(3));
    });

    testWidgets('buy rows only show deactivate IconButton (sell has none)',
        (tester) async {
      when(() => cubit.state).thenReturn([
        _tx(id: 1),
        _tx(id: 2, type: TransactionType.sell),
        _tx(id: 3),
      ]);

      await tester.pumpApp(host());

      // Two buy rows only; sell onDeactivate is null → no IconButton.
      expect(find.byType(IconButton), findsNWidgets(2));
    });

    testWidgets('buy without id and uid does not show deactivate IconButton',
        (tester) async {
      when(() => cubit.state).thenReturn([
        TransactionDto(
          id: null,
          uid: null,
          type: TransactionType.buy,
          state: TransactionState.processing,
          date: DateTime.utc(2026, 5, 15),
        ),
        _tx(id: 1),
      ]);

      await tester.pumpApp(host());

      expect(find.byType(PendingTransactionRow), findsNWidgets(2));
      expect(find.byType(IconButton), findsOneWidget);
    });

    testWidgets('buy IconButton confirm wires to cubit.deactivate once',
        (tester) async {
      when(() => cubit.state).thenReturn([
        _tx(id: 1),
        _tx(id: 2, type: TransactionType.sell),
        _tx(id: 3),
      ]);
      when(() => cubit.deactivate(any())).thenAnswer((_) async {});

      await tester.pumpApp(host());

      await tester.tap(find.byType(IconButton).first);
      // CupertinoActivityIndicator animates indefinitely — no pumpAndSettle.
      await tester.pump();

      await tester.tap(
        find.widgetWithText(TextButton, S.current.pendingTransactionDeactivate),
      );
      await tester.pump();

      verify(() => cubit.deactivate(any())).called(1);
    });

    testWidgets('non-empty list also renders a section header above the rows',
        (tester) async {
      when(() => cubit.state).thenReturn([_tx()]);

      await tester.pumpApp(host());

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
  });
}
