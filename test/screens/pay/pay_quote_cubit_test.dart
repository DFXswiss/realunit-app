import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/lnurlp_payment_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/real_unit_swap_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/swap_payment_info.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_pay_service.dart';
import 'package:realunit_wallet/screens/pay/cubits/pay_quote/pay_quote_cubit.dart';

class _MockPayService extends Mock implements RealUnitPayService {}

// Real Sepolia OCP capture (DFXswiss/api #3819): a CHF 2.00 payment link whose
// Ethereum method settles 2.0 ZCHF. The cubit reads these amounts verbatim from
// the public lnurlp quote — it never computes them.
LnurlpPaymentDto _details({
  required DateTime expiration,
  bool withEthZchf = true,
  double zchf = 2.0,
  LnurlpRecipientDto? recipient,
}) {
  return LnurlpPaymentDto(
    requestedAmount: const LnurlpRequestedAmountDto(asset: 'CHF', amount: 2),
    quote: LnurlpQuoteDto(id: 'plq_realunit_ocp_sepolia', expiration: expiration),
    transferAmounts: [
      if (withEthZchf)
        LnurlpTransferAmountDto(
          method: 'Ethereum',
          assets: [LnurlpTransferAssetDto(asset: 'ZCHF', amount: zchf)],
        )
      else
        const LnurlpTransferAmountDto(
          method: 'Bitcoin',
          assets: [LnurlpTransferAssetDto(asset: 'BTC', amount: 0.0005)],
        ),
    ],
    recipient: recipient,
  );
}

SwapPaymentInfo _swap({
  double amount = 5,
  double estimatedAmount = 1.98,
  double? feesTotal = 0.02,
}) {
  return SwapPaymentInfo(
    id: 99,
    amount: amount,
    estimatedAmount: estimatedAmount,
    targetAsset: 'ZCHF',
    ethBalance: 1.0,
    requiredGasEth: 0.001,
    isValid: true,
    feesTotal: feesTotal,
  );
}

void main() {
  late _MockPayService payService;

  setUpAll(() {
    registerFallbackValue(const RealUnitSwapDto.fromTargetAmount(1));
  });

  setUp(() {
    payService = _MockPayService();
  });

  PayQuoteCubit build() => PayQuoteCubit(payService, 'pl_realunit_ocp_sepolia');

  blocTest<PayQuoteCubit, PayQuoteState>(
    'a fresh quote with an Ethereum/ZCHF method emits PayQuoteReady',
    build: build,
    setUp: () {
      when(() => payService.getPaymentDetails('pl_realunit_ocp_sepolia')).thenAnswer(
        (_) async => _details(expiration: DateTime.now().add(const Duration(minutes: 5))),
      );
      when(() => payService.getSwapPaymentInfo(any())).thenAnswer((_) async => _swap());
    },
    act: (cubit) => cubit.load(),
    expect: () => [isA<PayQuoteLoading>(), isA<PayQuoteReady>()],
    verify: (cubit) {
      final state = cubit.state as PayQuoteReady;
      expect(state.quoteId, 'plq_realunit_ocp_sepolia');
      expect(state.fiatAsset, 'CHF');
      expect(state.fiatAmount, 2);
      expect(state.zchfAmount, 2.0);
      expect(state.realuAmount, 5);
      expect(state.realuEstimatedZchf, 1.98);
      expect(state.realuFeesTotal, 0.02);
      expect(state.merchantName, isNull);
      expect(state.merchantCity, isNull);
    },
  );

  blocTest<PayQuoteCubit, PayQuoteState>(
    'a fresh quote with a recipient surfaces merchant name and city',
    build: build,
    setUp: () {
      when(() => payService.getPaymentDetails('pl_realunit_ocp_sepolia')).thenAnswer(
        (_) async => _details(
          expiration: DateTime.now().add(const Duration(minutes: 5)),
          recipient: const LnurlpRecipientDto(name: 'Café Zürich', city: 'Zürich'),
        ),
      );
      when(() => payService.getSwapPaymentInfo(any())).thenAnswer((_) async => _swap());
    },
    act: (cubit) => cubit.load(),
    expect: () => [isA<PayQuoteLoading>(), isA<PayQuoteReady>()],
    verify: (cubit) {
      final state = cubit.state as PayQuoteReady;
      expect(state.merchantName, 'Café Zürich');
      expect(state.merchantCity, 'Zürich');
    },
  );

  blocTest<PayQuoteCubit, PayQuoteState>(
    'an expired quote emits PayQuoteExpired',
    build: build,
    setUp: () {
      when(() => payService.getPaymentDetails('pl_realunit_ocp_sepolia')).thenAnswer(
        (_) async => _details(expiration: DateTime.now().subtract(const Duration(minutes: 1))),
      );
    },
    act: (cubit) => cubit.load(),
    expect: () => [isA<PayQuoteLoading>(), isA<PayQuoteExpired>()],
  );

  blocTest<PayQuoteCubit, PayQuoteState>(
    'a link without an Ethereum/ZCHF method emits PayQuoteUnavailable',
    build: build,
    setUp: () {
      when(() => payService.getPaymentDetails('pl_realunit_ocp_sepolia')).thenAnswer(
        (_) async => _details(
          expiration: DateTime.now().add(const Duration(minutes: 5)),
          withEthZchf: false,
        ),
      );
    },
    act: (cubit) => cubit.load(),
    expect: () => [isA<PayQuoteLoading>(), isA<PayQuoteUnavailable>()],
  );

  blocTest<PayQuoteCubit, PayQuoteState>(
    'a service error emits PayQuoteError',
    build: build,
    setUp: () {
      when(() => payService.getPaymentDetails('pl_realunit_ocp_sepolia')).thenThrow(
        const ApiException(code: 'X', message: 'boom'),
      );
    },
    act: (cubit) => cubit.load(),
    expect: () => [isA<PayQuoteLoading>(), isA<PayQuoteError>()],
  );
}
