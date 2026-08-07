import 'dart:developer' as developer;

import 'package:async/async.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/bitbox_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/payment/buy_exceptions.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/buy/buy_payment_info.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/payment_info_error.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_buy_payment_info_service.dart';
import 'package:realunit_wallet/packages/utils/fiat_amount.dart';
import 'package:realunit_wallet/styles/currency.dart';

part 'buy_payment_info_state.dart';

// Backend QuoteError code for the "amount below the per-currency minimum"
// case. The API returns this in the success body's `error` field together
// with the authoritative `minVolume`; the app surfaces it as a typed state
// for the UI to render. Other QuoteError values (KYC, limit, …) are
// already routed via dedicated ApiExceptions and dedicated failure states.
const String _quoteErrorAmountTooLow = 'AmountTooLow';

// Backend QuoteError code for the "buyer has no primary email on record"
// case. The API pre-tells this on the quote (`isValid: false`) so the app
// can gate the confirm before the tap — routing the user to email capture —
// instead of reacting to a post-submit 400 and losing the flow.
const String _quoteErrorPrimaryEmailRequired = 'PrimaryEmailRequired';

// Backend QuoteError code for the "buyer has a primary email on record but
// has not yet confirmed it" case. This is distinct from having no email at
// all, so it routes to the existing email-confirmation flow (via the KYC
// page), not to the email-capture flow.
const String _quoteErrorPrimaryEmailNotConfirmed = 'PrimaryEmailNotConfirmed';

class BuyPaymentInfoCubit extends Cubit<BuyPaymentInfoState> {
  final RealUnitBuyPaymentInfoService _buyPaymentInfoService;
  CancelableOperation<BuyPaymentInfoState>? _completer;

  BuyPaymentInfoCubit(
    RealUnitBuyPaymentInfoService buyPaymentInfoService,
  ) : _buyPaymentInfoService = buyPaymentInfoService,
      super(const BuyPaymentInfoInitial());

  Future<void> getPaymentInfo({String amount = '300', Currency currency = Currency.chf}) async {
    await _completer?.cancel();

    if (state is! BuyPaymentInfoSuccess) {
      emit(const BuyPaymentInfoLoading());
    }

    _completer = CancelableOperation.fromFuture(
      _runGetPaymentInfo(amount, currency),
    );

    final newState = await _completer!.value;
    if (isClosed) return;
    emit(newState);
  }

  Future<BuyPaymentInfoState> _runGetPaymentInfo(String amount, Currency currency) async {
    try {
      final paymentInfo = await _buyPaymentInfoService.getPaymentInfo(
        chargedFiatAmount(amount),
        currency: currency,
      );

      // Only the backend knows the current per-currency limits, exchange
      // rates and any compliance gating — when it tags the quote
      // `isValid: false` we surface its verdict without re-interpreting it.
      if (!paymentInfo.isValid) {
        if (paymentInfo.error == _quoteErrorAmountTooLow && paymentInfo.minVolume != null) {
          return BuyPaymentInfoMinAmountNotMetFailure(
            PaymentInfoError.minAmountNotMet,
            minAmount: paymentInfo.minVolume!,
          );
        }
        if (paymentInfo.error == _quoteErrorPrimaryEmailRequired) {
          return const BuyPaymentInfoFailure(PaymentInfoError.primaryEmailRequired);
        }
        if (paymentInfo.error == _quoteErrorPrimaryEmailNotConfirmed) {
          return const BuyPaymentInfoFailure(PaymentInfoError.primaryEmailNotConfirmed);
        }
        return const BuyPaymentInfoFailure(PaymentInfoError.unknown);
      }
      return BuyPaymentInfoSuccess(paymentInfo);
    } on KycLevelRequiredException catch (e) {
      return BuyPaymentInfoFailure(
        PaymentInfoError.kycRequired,
        requiredLevel: e.requiredLevel,
        context: e.context,
      );
    } on RegistrationRequiredException catch (e) {
      return BuyPaymentInfoFailure(
        PaymentInfoError.registrationRequired,
        context: e.context,
      );
    } on BitboxNotConnectedException {
      return const BuyPaymentInfoFailure(PaymentInfoError.bitboxDisconnected);
    } on ApiException catch (e) {
      // 503 / PRICE_SOURCE_UNAVAILABLE means the external price provider
      // (Aktionariat) is down, so no quote can be built — surface that
      // explicitly instead of a generic failure. Must stay below the
      // KYC/Registration clauses (those are ApiException subclasses).
      if (e.statusCode == 503 || e.code == 'PRICE_SOURCE_UNAVAILABLE') {
        return const BuyPaymentInfoFailure(PaymentInfoError.priceSourceUnavailable);
      }
      developer.log(e.toString());
      return const BuyPaymentInfoFailure(PaymentInfoError.unknown);
    } catch (e) {
      developer.log(e.toString());
      return const BuyPaymentInfoFailure(PaymentInfoError.unknown);
    }
  }

  @override
  Future<void> close() async {
    await _completer?.cancel();
    return super.close();
  }
}
