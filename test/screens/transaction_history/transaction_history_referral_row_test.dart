import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/models/transaction.dart';
import 'package:realunit_wallet/packages/utils/default_assets.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/screens/transaction_history/cubits/receipt/transaction_history_receipt_cubit.dart';
import 'package:realunit_wallet/screens/transaction_history/widgets/transaction_history_row.dart';
import 'package:realunit_wallet/styles/language.dart';
import 'package:realunit_wallet/styles/themes.dart';

class _MockReceiptCubit extends MockCubit<TransactionHistoryReceiptState>
    implements TransactionHistoryReceiptCubit {}

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

void main() {
  testWidgets(
    'history row shows referral premium with frozen CHF, not buy/sell',
    (tester) async {
      final receiptCubit = _MockReceiptCubit();
      when(() => receiptCubit.state).thenReturn(
        const TransactionHistoryReceiptInitial(),
      );

      final tx = Transaction(
        height: 0,
        txId: 'referral-payout-9',
        chainId: realUnitAsset.chainId,
        senderAddress: kReferralPayoutSenderAddress,
        receiverAddress: '0xabc',
        amount: BigInt.from(20),
        asset: realUnitAsset,
        type: TransactionTypes.referralPayout,
        note: '',
        data: '246.5',
        timestamp: DateTime.utc(2026, 8, 24, 10),
      );

      final settings = _MockSettingsBloc();
      const settingsState = SettingsState(language: Language.de);
      when(() => settings.state).thenReturn(settingsState);
      whenListen(
        settings,
        const Stream<SettingsState>.empty(),
        initialState: settingsState,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: realUnitTheme,
          locale: const Locale('de'),
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          home: Scaffold(
            body: MultiBlocProvider(
              providers: [
                BlocProvider<TransactionHistoryReceiptCubit>.value(
                  value: receiptCubit,
                ),
                BlocProvider<SettingsBloc>.value(value: settings),
              ],
              child: TransactionHistoryRowView(
                transaction: tx,
                isOutbound: false,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Empfehlungsprämie'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byIcon(Icons.add),
          matching: find.byWidgetPredicate(
            (widget) => widget is ExcludeSemantics && widget.excluding,
          ),
        ),
        findsAtLeastNWidgets(1),
      );
      expect(find.textContaining('246.50'), findsOneWidget);
      expect(find.textContaining('24.08.2026'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              (widget.properties.label ?? '').contains('Empfehlungsprämie') &&
              (widget.properties.label ?? '').contains('246.50') &&
              (widget.properties.label ?? '').contains('20 REALU'),
        ),
        findsOneWidget,
      );
      expect(find.text('Kaufen'), findsNothing);
      expect(find.text('Verkaufen'), findsNothing);
    },
  );

  testWidgets('hides REALU and frozen CHF when amounts are hidden', (
    tester,
  ) async {
    final receiptCubit = _MockReceiptCubit();
    when(() => receiptCubit.state).thenReturn(
      const TransactionHistoryReceiptInitial(),
    );

    final tx = Transaction(
      height: 0,
      txId: 'referral-payout-9',
      chainId: realUnitAsset.chainId,
      senderAddress: kReferralPayoutSenderAddress,
      receiverAddress: '0xabc',
      amount: BigInt.from(20),
      asset: realUnitAsset,
      type: TransactionTypes.referralPayout,
      note: '',
      data: '246.5',
      timestamp: DateTime.utc(2026, 8, 24, 10),
    );

    final settings = _MockSettingsBloc();
    const settingsState = SettingsState(
      language: Language.de,
      hideAmounts: true,
    );
    when(() => settings.state).thenReturn(settingsState);
    whenListen(
      settings,
      const Stream<SettingsState>.empty(),
      initialState: settingsState,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: realUnitTheme,
        locale: const Locale('de'),
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<TransactionHistoryReceiptCubit>.value(
                value: receiptCubit,
              ),
              BlocProvider<SettingsBloc>.value(value: settings),
            ],
            child: TransactionHistoryRowView(
              transaction: tx,
              isOutbound: false,
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('246.50'), findsNothing);
    expect(find.textContaining('***.**'), findsWidgets);
    expect(find.textContaining('REALU'), findsNothing);
  });
}
