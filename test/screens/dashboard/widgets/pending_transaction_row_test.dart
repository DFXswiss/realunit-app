import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/transactions/dto/transactions_dto.dart';
import 'package:realunit_wallet/screens/dashboard/widgets/pending_transaction_row.dart';

import '../../../helper/helper.dart';

TransactionDto _tx({
  TransactionType? type,
  TransactionState? state,
  double? inputAmount,
  String? inputAsset,
}) => TransactionDto(
  id: 1,
  type: type,
  state: state,
  inputAmount: inputAmount,
  inputAsset: inputAsset,
  date: DateTime.utc(2026, 5, 15, 10),
);

void main() {
  group('$PendingTransactionRow', () {
    testWidgets('always renders a CupertinoActivityIndicator (still pending)', (tester) async {
      await tester.pumpApp(
        Scaffold(
          body: PendingTransactionRow(
            transaction: _tx(type: TransactionType.buy, state: TransactionState.processing),
          ),
        ),
      );

      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    });

    testWidgets('buy vs sell produce DIFFERENT first-line labels', (tester) async {
      await tester.pumpApp(
        Scaffold(
          body: PendingTransactionRow(
            transaction: _tx(type: TransactionType.buy, state: TransactionState.processing),
          ),
        ),
      );
      // Capture buy line.
      final buyLine = tester.widgetList<Text>(find.byType(Text)).first.data;

      await tester.pumpApp(
        Scaffold(
          body: PendingTransactionRow(
            transaction: _tx(type: TransactionType.sell, state: TransactionState.processing),
          ),
        ),
      );
      final sellLine = tester.widgetList<Text>(find.byType(Text)).first.data;

      expect(buyLine, isNotNull);
      expect(sellLine, isNotNull);
      expect(buyLine, isNot(sellLine));
    });

    testWidgets('state=waitingForPayment vs other state produces DIFFERENT second-line labels', (
      tester,
    ) async {
      await tester.pumpApp(
        Scaffold(
          body: PendingTransactionRow(
            transaction: _tx(
              type: TransactionType.buy,
              state: TransactionState.waitingForPayment,
            ),
          ),
        ),
      );
      final waitingSecondLine = tester.widgetList<Text>(find.byType(Text)).elementAt(1).data;

      await tester.pumpApp(
        Scaffold(
          body: PendingTransactionRow(
            transaction: _tx(
              type: TransactionType.buy,
              state: TransactionState.processing,
            ),
          ),
        ),
      );
      final processingSecondLine = tester.widgetList<Text>(find.byType(Text)).elementAt(1).data;

      expect(waitingSecondLine, isNotNull);
      expect(processingSecondLine, isNotNull);
      expect(waitingSecondLine, isNot(processingSecondLine));
    });

    testWidgets('BUY row with onDeactivate shows an IconButton', (tester) async {
      await tester.pumpApp(
        Scaffold(
          body: PendingTransactionRow(
            transaction: _tx(type: TransactionType.buy, state: TransactionState.processing),
            onDeactivate: () async {},
          ),
        ),
      );

      expect(find.byType(IconButton), findsOneWidget);
    });

    testWidgets('SELL row never shows an IconButton even with onDeactivate', (tester) async {
      await tester.pumpApp(
        Scaffold(
          body: PendingTransactionRow(
            transaction: _tx(type: TransactionType.sell, state: TransactionState.processing),
            onDeactivate: () async {},
          ),
        ),
      );

      expect(find.byType(IconButton), findsNothing);
    });

    testWidgets('BUY row cancel in dialog does not invoke onDeactivate', (tester) async {
      var calls = 0;
      await tester.pumpApp(
        Scaffold(
          body: PendingTransactionRow(
            transaction: _tx(type: TransactionType.buy, state: TransactionState.processing),
            onDeactivate: () async {
              calls++;
            },
          ),
        ),
      );

      await tester.tap(find.byType(IconButton));
      // CupertinoActivityIndicator animates indefinitely, so pumpAndSettle
      // would hang.
      await tester.pump();

      expect(find.text(S.current.pendingTransactionDeactivateConfirm), findsOneWidget);

      await tester.tap(find.text(S.current.cancel));
      await tester.pump();

      expect(calls, 0);
    });

    testWidgets('BUY row confirm in dialog invokes onDeactivate once', (tester) async {
      var calls = 0;
      await tester.pumpApp(
        Scaffold(
          body: PendingTransactionRow(
            transaction: _tx(type: TransactionType.buy, state: TransactionState.processing),
            onDeactivate: () async {
              calls++;
            },
          ),
        ),
      );

      await tester.tap(find.byType(IconButton));
      // CupertinoActivityIndicator animates indefinitely, so pumpAndSettle
      // would hang.
      await tester.pump();

      // Confirm action uses the deactivate label.
      await tester.tap(find.widgetWithText(TextButton, S.current.pendingTransactionDeactivate));
      await tester.pump();

      expect(calls, 1);
    });

    testWidgets('BUY row does not invoke onDeactivate twice while busy', (tester) async {
      var calls = 0;
      final gate = Completer<void>();
      await tester.pumpApp(
        Scaffold(
          body: PendingTransactionRow(
            transaction: _tx(type: TransactionType.buy, state: TransactionState.processing),
            onDeactivate: () async {
              calls++;
              await gate.future;
            },
          ),
        ),
      );

      await tester.tap(find.byType(IconButton));
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, S.current.pendingTransactionDeactivate));
      await tester.pump();

      expect(calls, 1);
      await tester.tap(find.byType(IconButton));
      await tester.pump();
      expect(calls, 1);

      gate.complete();
      await tester.pump();
    });

    testWidgets('BUY row confirm in dialog shows snackbar when onDeactivate throws', (
      tester,
    ) async {
      await tester.pumpApp(
        Scaffold(
          body: PendingTransactionRow(
            transaction: _tx(type: TransactionType.buy, state: TransactionState.processing),
            onDeactivate: () async {
              throw Exception('api down');
            },
          ),
        ),
      );

      await tester.tap(find.byType(IconButton));
      // CupertinoActivityIndicator animates indefinitely, so pumpAndSettle
      // would hang.
      await tester.pump();

      await tester.tap(
        find.widgetWithText(TextButton, S.current.pendingTransactionDeactivate),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text(S.current.pendingTransactionDeactivateFailed), findsOneWidget);
    });

    testWidgets('integer inputAmount renders without decimals', (tester) async {
      await tester.pumpApp(
        Scaffold(
          body: PendingTransactionRow(
            transaction: _tx(
              type: TransactionType.buy,
              state: TransactionState.processing,
              inputAmount: 100.0,
              inputAsset: 'CHF',
            ),
          ),
        ),
      );

      expect(find.textContaining('100 CHF'), findsOneWidget);
    });

    testWidgets('fractional inputAmount renders with two decimals', (tester) async {
      await tester.pumpApp(
        Scaffold(
          body: PendingTransactionRow(
            transaction: _tx(
              type: TransactionType.buy,
              state: TransactionState.processing,
              inputAmount: 100.5,
              inputAsset: 'CHF',
            ),
          ),
        ),
      );

      expect(find.textContaining('100.50 CHF'), findsOneWidget);
    });

    testWidgets('BUY row with inputAmount, inputAsset and date still shows IconButton '
        'when onDeactivate is provided', (tester) async {
      await tester.pumpApp(
        Scaffold(
          body: PendingTransactionRow(
            transaction: _tx(
              type: TransactionType.buy,
              state: TransactionState.processing,
              inputAmount: 100.0,
              inputAsset: 'CHF',
            ),
            onDeactivate: () async {},
          ),
        ),
      );

      expect(find.byType(IconButton), findsOneWidget);
    });
  });
}
