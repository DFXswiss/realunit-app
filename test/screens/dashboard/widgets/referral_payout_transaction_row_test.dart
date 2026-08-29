import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/models/transaction.dart';
import 'package:realunit_wallet/packages/utils/default_assets.dart';
import 'package:realunit_wallet/screens/dashboard/widgets/transaction_row.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/styles/language.dart';
import 'package:realunit_wallet/styles/themes.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

void main() {
  late _MockSettingsBloc settings;

  Transaction payout() => Transaction(
    height: 0,
    txId: 'referral-payout-7',
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

  Future<void> pumpRow(WidgetTester tester, {required bool hideAmounts}) async {
    settings = _MockSettingsBloc();
    const state = SettingsState(language: Language.de, hideAmounts: false);
    final resolved = hideAmounts
        ? state.copyWith(hideAmounts: true)
        : state;
    when(() => settings.state).thenReturn(resolved);
    whenListen(
      settings,
      const Stream<SettingsState>.empty(),
      initialState: resolved,
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
          body: BlocProvider<SettingsBloc>.value(
            value: settings,
            child: ReferralPayoutTransactionRow(transaction: payout()),
          ),
        ),
      ),
    );
  }

  testWidgets('shows whole REALU, date, and CHF frozen at credit', (tester) async {
    await pumpRow(tester, hideAmounts: false);

    expect(find.text('Empfehlungsprämie'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byIcon(Icons.add),
        matching: find.byType(ExcludeSemantics),
      ),
      findsOneWidget,
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
  });

  testWidgets('hides frozen CHF when amounts are hidden', (tester) async {
    await pumpRow(tester, hideAmounts: true);

    expect(find.textContaining('246.50'), findsNothing);
    expect(find.textContaining('***.**'), findsWidgets);
    expect(find.textContaining('REALU'), findsNothing);
  });
}
