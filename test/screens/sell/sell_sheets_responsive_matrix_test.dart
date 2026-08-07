// Responsive matrix gate for SellConfirmSheetView and SellExecutedSheet CTAs.
//
// Proves both sell bottom sheets stay fully tappable and overflow-free across
// the full device × text-scale matrix (see test/helper/responsive_matrix.dart).
// Regression lock for:
// - CTA clipped out of the hit-test region at large system text scale (no red
//   overflow stripe in release builds).
// - Horizontal RenderFlex overflow of the IBAN row in the confirm info card.
// - SellExecutedSheet shown without isScrollControlled (modal height clamped
//   to 9/16 of the screen) — the dedicated test below documents/demonstrates
//   why sell_button.dart needs isScrollControlled: true by reproducing the
//   underlying Flutter clamp behavior in isolation. It does NOT exercise the
//   real SellButton widget, so it cannot detect a regression at that call site
//   itself — only the behavior the call site depends on. The matrix loops
//   always pump with isScrollControlled: true and do not cover this case.
//
// Matrix sheets are pumped via a real showModalBottomSheet(isScrollControlled:
// true) so the screen-height bound production imposes is reproduced.
// pumpClippedSheet is intentionally not used — it does not reproduce that
// modal constraint.
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/eip7702/eip7702_data_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/real_unit_sell_payment_info_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/sell_payment_info.dart';
import 'package:realunit_wallet/screens/sell/cubits/sell_confirm/sell_confirm_cubit.dart';
import 'package:realunit_wallet/screens/sell/widgets/sell_confirm_sheet.dart';
import 'package:realunit_wallet/screens/sell/widgets/sell_executed_sheet.dart';
import 'package:realunit_wallet/styles/currency.dart';
import 'package:realunit_wallet/styles/themes.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

import '../../helper/helper.dart';

class _MockSellConfirmCubit extends MockCubit<SellConfirmState> implements SellConfirmCubit {}

class _FakeSellPaymentInfo extends Fake implements SellPaymentInfo {}

/// Worst-case-but-realistic confirm payload: long IBAN forces the unfixed
/// spaceBetween Row to overflow on every matrix device width; amounts stay
/// plausible so they do not gratuitously blow the other info rows.
SellPaymentInfo _worstCasePaymentInfo() => const SellPaymentInfo(
  id: 42,
  eip7702: Eip7702Data(
    relayerAddress: '0x1',
    delegationManagerAddress: '0x2',
    delegatorAddress: '0x3',
    userNonce: 0,
    domain: Eip7702Domain(
      name: 'RealUnit',
      version: '1',
      chainId: 1,
      verifyingContract: '0x4',
    ),
    types: Eip7702Types(delegation: [], caveat: []),
    message: Eip7702Message(
      delegate: '0x5',
      delegator: '0x6',
      authority: '0x7',
      caveats: [],
      salt: 0,
    ),
    tokenAddress: '0x8',
    amountWei: '0',
    depositAddress: '0x9',
  ),
  amount: 12345,
  exchangeRate: 1.0,
  rate: 1.0,
  // Two standard Swiss IBANs concatenated — long enough to overflow the
  // unfixed receiver Row on every matrix width, realistic character set.
  beneficiary: BeneficiaryDto(
    iban: 'CH93 ACCT-000017 CH93 ACCT-000017',
  ),
  estimatedAmount: 12345.67,
  currency: Currency.chf,
  depositAddress: '0xA',
  tokenAddress: '0xB',
  chainId: 1,
  ethBalance: 0.01,
  requiredGasEth: 0.001,
);

void main() {
  late _MockSellConfirmCubit confirmCubit;

  setUpAll(() {
    registerFallbackValue(_FakeSellPaymentInfo());
  });

  setUp(() {
    confirmCubit = _MockSellConfirmCubit();
    when(() => confirmCubit.state).thenReturn(SellConfirmInitial());
    whenListen(
      confirmCubit,
      const Stream<SellConfirmState>.empty(),
      initialState: SellConfirmInitial(),
    );
    when(() => confirmCubit.confirmPayment(any())).thenAnswer((_) async {});
  });

  /// Pumps a sheet the way production shows it: real [showModalBottomSheet]
  /// with [isScrollControlled] matching the fixed call site (true for both).
  Future<void> pumpModalSheet(
    WidgetTester tester,
    MatrixCell cell, {
    required bool isScrollControlled,
    required WidgetBuilder sheetBuilder,
  }) async {
    await tester.binding.setSurfaceSize(cell.device.size);
    addTearDown(() async => await tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  showModalBottomSheet<void>(
                    isScrollControlled: isScrollControlled,
                    context: context,
                    builder: sheetBuilder,
                  );
                },
                child: const Text('open-sheet'),
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MediaQuery(
        data: cell.mediaQuery,
        child: MaterialApp.router(
          theme: realUnitTheme,
          locale: const Locale('de'),
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('open-sheet'));
    await tester.pumpAndSettle();
  }

  group('SellConfirmSheetView responsive matrix (full device × textScale)', () {
    for (final cell in kFullResponsiveMatrix) {
      testWidgets(cell.id, (tester) async {
        await withTargetPlatform(cell.device.platform, () async {
          await expectNoLayoutOverflow(
            tester,
            () async {
              await pumpModalSheet(
                tester,
                cell,
                isScrollControlled: true,
                sheetBuilder: (_) => BlocProvider<SellConfirmCubit>.value(
                  value: confirmCubit,
                  child: SellConfirmSheetView(paymentInfo: _worstCasePaymentInfo()),
                ),
              );
            },
            reason: 'overflow on SellConfirmSheetView / ${cell.label}',
          );

          await expectFullyTappable(
            tester,
            find.byType(AppFilledButton),
            within: find.byType(SellConfirmSheetView),
            reason: 'SellConfirmSheetView / ${cell.label}: CTA not tappable',
          );
        });
      });
    }
  });

  group('SellExecutedSheet responsive matrix (full device × textScale)', () {
    for (final cell in kFullResponsiveMatrix) {
      testWidgets(cell.id, (tester) async {
        await withTargetPlatform(cell.device.platform, () async {
          await expectNoLayoutOverflow(
            tester,
            () async {
              await pumpModalSheet(
                tester,
                cell,
                isScrollControlled: true,
                sheetBuilder: (_) => const SellExecutedSheet(),
              );
            },
            reason: 'overflow on SellExecutedSheet / ${cell.label}',
          );

          await expectFullyTappable(
            tester,
            find.byType(AppFilledButton),
            within: find.byType(SellExecutedSheet),
            reason: 'SellExecutedSheet / ${cell.label}: CTA not tappable',
          );
        });
      });
    }

    // Documents why sell_button.dart needs isScrollControlled: true when showing
    // SellExecutedSheet: pumps with false (Flutter's default) and asserts the
    // 9/16 clamp. Does not instantiate SellButton, so it cannot catch a call-site
    // regression there — only the underlying Flutter behavior the flag avoids.
    testWidgets(
      'SellExecutedSheet without isScrollControlled=true reproduces the 9/16 clamp bug (iphone_se_3@2.0x, de)',
      (tester) async {
        final cell = MatrixCell(
          kIosDeviceProfiles.firstWhere((d) => d.id == 'iphone_se_3'),
          2.0,
        );

        await withTargetPlatform(cell.device.platform, () async {
          await pumpModalSheet(
            tester,
            cell,
            isScrollControlled: false,
            sheetBuilder: (_) => const SellExecutedSheet(),
          );

          // Without isScrollControlled: true, Flutter clamps the modal to 9/16 of the
          // available height regardless of content, so SellExecutedSheet's content
          // genuinely overflows at this small-device / high-text-scale cell. This is
          // the exact regression the call-site fix in sell_button.dart guards against.
          final exception = tester.takeException();
          expect(
            exception,
            isNotNull,
            reason: 'Expected SellExecutedSheet to overflow / fail to lay out under the '
                '9/16 modal clamp (isScrollControlled: false) at ${cell.label}. If this '
                'no longer fails, either the clamp reproduction stopped working or the '
                'widget silently degrades instead of failing loudly — investigate before '
                'weakening this assertion.',
          );
          expect(
            exception.toString(),
            contains('overflowed'),
            reason: 'Expected the captured exception to be the RenderFlex overflow caused '
                'by the 9/16 clamp, not some unrelated failure.',
          );
        });
      },
    );
  });
}
