import 'package:alchemist/alchemist.dart' show precacheImages;
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/transactions/dto/transactions_dto.dart';
import 'package:realunit_wallet/screens/dashboard/cubits/pending_transaction_detail/pending_transaction_detail_cubit.dart';
import 'package:realunit_wallet/screens/dashboard/pending_transaction_detail_page.dart';

import '../../../helper/helper.dart';

class _MockDetailCubit extends MockCubit<PendingTransactionDetailState>
    implements PendingTransactionDetailCubit {}

void main() {
  late _MockDetailCubit cubit;

  const buyWaiting = TransactionDto(
    id: 1,
    type: TransactionType.buy,
    state: TransactionState.waitingForPayment,
    inputAmount: 500,
    inputAsset: 'CHF',
    date: null,
  );

  const sellProcessing = TransactionDto(
    id: 2,
    type: TransactionType.sell,
    state: TransactionState.processing,
    inputAmount: 30,
    inputAsset: 'REALU',
    date: null,
  );

  setUp(() {
    cubit = _MockDetailCubit();
    when(() => cubit.state).thenReturn(const PendingTransactionDetailInitial());
    when(() => cubit.deactivate(any())).thenAnswer((_) async {});
  });

  setUpAll(() {
    registerFallbackValue(buyWaiting);
  });

  Widget buildSubject(TransactionDto tx) => BlocProvider<PendingTransactionDetailCubit>.value(
        value: cubit,
        child: PendingTransactionDetailView(transaction: tx),
      );

  group('$PendingTransactionDetailView', () {
    goldenTest(
      'buy waiting for payment — fields + cancel CTA',
      fileName: 'pending_transaction_detail_buy_waiting',
      constraints: phoneConstraints,
      builder: () => wrapForGolden(buildSubject(buyWaiting)),
    );

    goldenTest(
      'deactivate confirm dialog open',
      fileName: 'pending_transaction_detail_deactivate_overlay',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) async {
        await precacheImages(tester);
        await tester.pump();
        await tester.tap(find.text(S.current.pendingTransactionDeactivate));
        await tester.pump();
      },
      builder: () => wrapForGolden(buildSubject(buyWaiting)),
    );

    goldenTest(
      'sell / not cancellable — no cancel CTA',
      fileName: 'pending_transaction_detail_not_cancellable',
      constraints: phoneConstraints,
      builder: () => wrapForGolden(buildSubject(sellProcessing)),
    );
  });
}
