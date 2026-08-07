import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/models/balance.dart';
import 'package:realunit_wallet/packages/utils/default_assets.dart';
import 'package:realunit_wallet/screens/sell/cubits/sell_balance/sell_balance_cubit.dart';
import 'package:realunit_wallet/screens/send/cubits/send_amount/send_amount_cubit.dart';
import 'package:realunit_wallet/screens/send/send_amount_page.dart';
import 'package:realunit_wallet/styles/themes.dart';

import '../../helper/helper.dart';

class _MockSellBalanceCubit extends MockCubit<Balance> implements SellBalanceCubit {}

Future<void> _pumpScreen(
  WidgetTester tester,
  MatrixCell cell,
  Widget child,
) async {
  await tester.binding.setSurfaceSize(cell.mediaQuery.size);
  addTearDown(() async => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MediaQuery(
      data: cell.mediaQuery,
      child: MaterialApp(
        theme: realUnitTheme,
        locale: const Locale('de'),
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        home: child,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('SendAmountView responsive matrix (full device × textScale)', () {
    for (final cell in kFullResponsiveMatrix) {
      testWidgets(cell.id, (tester) async {
        await withTargetPlatform(cell.device.platform, () async {
          final balance = Balance(
            chainId: realUnitAsset.chainId,
            contractAddress: realUnitAsset.address,
            walletAddress: '0xwallet',
            balance: BigInt.from(42),
            asset: realUnitAsset,
          );
          final balanceCubit = _MockSellBalanceCubit();
          when(() => balanceCubit.state).thenReturn(balance);
          whenListen(
            balanceCubit,
            const Stream<Balance>.empty(),
            initialState: balance,
          );
          final amountCubit = SendAmountCubit(availableShares: balance.balance)..amountChanged('5');
          addTearDown(amountCubit.close);

          final subject = MultiBlocProvider(
            providers: [
              BlocProvider<SellBalanceCubit>.value(value: balanceCubit),
              BlocProvider<SendAmountCubit>.value(value: amountCubit),
            ],
            child: const SendAmountView(recipient: '0xRecipient'),
          );

          await expectNoLayoutOverflow(
            tester,
            () => _pumpScreen(tester, cell, subject),
            reason: 'SendAmountView overflow / ${cell.label}',
          );

          await expectFullyTappable(
            tester,
            find.widgetWithText(FilledButton, S.current.next),
            within: find.byType(SendAmountView),
            reason: 'SendAmountView / ${cell.label}: Next CTA not tappable',
          );
        });
      });
    }
  });
}
