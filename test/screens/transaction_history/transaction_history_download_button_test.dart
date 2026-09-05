import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/models/transaction.dart';
import 'package:realunit_wallet/packages/utils/default_assets.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/screens/transaction_history/cubits/multi_receipt/transaction_history_multi_receipt_cubit.dart';
import 'package:realunit_wallet/screens/transaction_history/widgets/transaction_history_download_button.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/styles/currency.dart';
import 'package:realunit_wallet/styles/language.dart';

import '../../helper/helper.dart';

class _MockMultiReceiptCubit extends MockCubit<TransactionHistoryMultiReceiptState>
    implements TransactionHistoryMultiReceiptCubit {}

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState> implements SettingsBloc {}

Transaction _tx({
  required String txId,
  TransactionTypes type = TransactionTypes.tokenTransfer,
}) => Transaction(
  height: 0,
  txId: txId,
  chainId: realUnitAsset.chainId,
  senderAddress: type == TransactionTypes.referralPayout ? kReferralPayoutSenderAddress : '0xfrom',
  receiverAddress: '0xto',
  amount: BigInt.from(20),
  asset: realUnitAsset,
  type: type,
  note: '',
  data: type == TransactionTypes.referralPayout ? '246.50' : null,
  timestamp: DateTime.utc(2026, 8, 24, 10),
);

void main() {
  setUpAll(() {
    registerFallbackValue(Currency.chf);
    registerFallbackValue(Language.en);
    registerFallbackValue(<String>[]);
  });

  test('receiptTxIdsForDownload drops prize rows so a prize cannot fail the Beleg PDF', () {
    expect(
      receiptTxIdsForDownload([
        _tx(txId: '0xbuy'),
        _tx(txId: '0xprize', type: TransactionTypes.referralPayout),
        _tx(txId: 'referral-payout-9', type: TransactionTypes.referralPayout),
        _tx(txId: '0xsell'),
      ]),
      ['0xbuy', '0xsell'],
    );
    expect(
      receiptTxIdsForDownload([
        _tx(txId: '0xprize', type: TransactionTypes.referralPayout),
      ]),
      isEmpty,
    );
  });

  group('$TransactionHistoryDownloadButtonView', () {
    late _MockMultiReceiptCubit cubit;
    late _MockSettingsBloc settings;

    setUp(() {
      cubit = _MockMultiReceiptCubit();
      settings = _MockSettingsBloc();
      when(() => cubit.state).thenReturn(
        const TransactionHistoryMultiReceiptInitial(),
      );
      when(() => settings.state).thenReturn(const SettingsState());
      when(
        () => cubit.generateReceipt(
          any(),
          currency: any(named: 'currency'),
          language: any(named: 'language'),
        ),
      ).thenAnswer((_) async {});
    });

    Future<void> pumpButton(
      WidgetTester tester,
      List<Transaction> transactions,
    ) {
      return tester.pumpApp(
        MultiBlocProvider(
          providers: [
            BlocProvider<SettingsBloc>.value(value: settings),
            BlocProvider<TransactionHistoryMultiReceiptCubit>.value(
              value: cubit,
            ),
          ],
          child: Scaffold(
            body: TransactionHistoryDownloadButtonView(
              transactions: transactions,
            ),
          ),
        ),
      );
    }

    testWidgets(
      'sends only buy/sell ids when the range also has a prize',
      (tester) async {
        await pumpButton(tester, [
          _tx(txId: '0xbuy'),
          _tx(txId: '0xprize', type: TransactionTypes.referralPayout),
        ]);

        await tester.tap(find.byIcon(Icons.file_download_outlined));
        await tester.pump();

        verify(
          () => cubit.generateReceipt(
            ['0xbuy'],
            currency: Currency.chf,
            language: Language.en,
          ),
        ).called(1);
      },
    );

    testWidgets(
      'stays disabled when the range is only prizes',
      (tester) async {
        await pumpButton(tester, [
          _tx(txId: 'referral-payout-9', type: TransactionTypes.referralPayout),
        ]);

        final icon = tester.widget<Icon>(find.byIcon(Icons.file_download_outlined));
        expect(icon.color, RealUnitColors.basic.white);
        final box = tester.widget<Container>(
          find
              .ancestor(
                of: find.byIcon(Icons.file_download_outlined),
                matching: find.byType(Container),
              )
              .first,
        );
        expect(
          (box.decoration as BoxDecoration).color,
          RealUnitColors.neutral300,
        );

        await tester.tap(find.byIcon(Icons.file_download_outlined));
        await tester.pump();
        verifyNever(
          () => cubit.generateReceipt(
            any(),
            currency: any(named: 'currency'),
            language: any(named: 'language'),
          ),
        );
      },
    );
  });
}
