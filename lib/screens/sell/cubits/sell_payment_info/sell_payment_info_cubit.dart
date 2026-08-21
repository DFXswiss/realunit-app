import 'dart:developer' as developer;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/bitbox_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/payment/buy_exceptions.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/payment_info_error.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/sell_payment_info.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_sell_payment_info_service.dart';
import 'package:realunit_wallet/packages/utils/fiat_amount.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/styles/currency.dart';

part 'sell_payment_info_state.dart';

// Backend QuoteError code for the "amount below the per-currency minimum"
// case. The API returns this in the success body's `error` field together
// with the authoritative `minVolume`; the app surfaces it as a typed state
// for the UI to render. Other QuoteError values (KYC, limit, …) are
// already routed via dedicated ApiExceptions and dedicated failure states.
const String _quoteErrorAmountTooLow = 'AmountTooLow';

class SellPaymentInfoCubit extends Cubit<SellPaymentInfoState> {
  final RealUnitSellPaymentInfoService _sellPaymentInfoService;
  final AppStore _appStore;

  SellPaymentInfoCubit(
    RealUnitSellPaymentInfoService sellPaymentInfoService,
    AppStore appStore,
  ) : _sellPaymentInfoService = sellPaymentInfoService,
      _appStore = appStore,
      super(const SellPaymentInfoInitial());

  Future<void> getPaymentInfo({
    String amount = '100',
    Currency currency = Currency.chf,
    required String iban,
  }) async {
    try {
      emit(const SellPaymentInfoLoading());

      final paymentInfo = await _sellPaymentInfoService.getPaymentInfo(
        chargedFiatAmount(amount).round(),
        iban,
        currency: currency,
      );
      if (isClosed) return;

      // Only the backend knows the current per-currency limits, exchange
      // rates and any compliance gating — when it tags the quote
      // `isValid: false` we surface its verdict without re-interpreting it.
      if (!paymentInfo.isValid) {
        if (paymentInfo.error == _quoteErrorAmountTooLow) {
          emit(
            SellPaymentInfoMinAmountNotMet(
              minAmount: paymentInfo.minVolume,
              currency: paymentInfo.currency,
            ),
          );
          return;
        }
        emit(const SellPaymentInfoFailure(PaymentInfoError.unknown));
        return;
      }

      final isBitbox = _appStore.wallet.walletType == WalletType.bitbox;
      emit(SellPaymentInfoSuccess(paymentInfo, isBitbox: isBitbox));
    } on KycLevelRequiredException catch (e) {
      if (isClosed) return;
      emit(
        SellPaymentInfoFailure(
          PaymentInfoError.kycRequired,
          message: e.message,
          requiredLevel: e.requiredLevel,
          context: e.context,
        ),
      );
    } on RegistrationRequiredException catch (e) {
      if (isClosed) return;
      emit(
        SellPaymentInfoFailure(
          PaymentInfoError.registrationRequired,
          message: e.message,
          context: e.context,
        ),
      );
    } on BitboxNotConnectedException catch (e) {
      if (isClosed) return;
      emit(
        SellPaymentInfoFailure(
          PaymentInfoError.bitboxDisconnected,
          message: e.toString(),
        ),
      );
    } on ApiException catch (e) {
      // 503 / PRICE_SOURCE_UNAVAILABLE = external price provider (Aktionariat)
      // down → no quote possible. Must stay below the KYC/Registration clauses
      // (those are ApiException subclasses).
      if (isClosed) return;
      if (e.statusCode == 503 || e.code == 'PRICE_SOURCE_UNAVAILABLE') {
        emit(
          SellPaymentInfoFailure(
            PaymentInfoError.priceSourceUnavailable,
            message: e.message,
          ),
        );
        return;
      }
      developer.log(e.toString());
      emit(
        SellPaymentInfoFailure(
          PaymentInfoError.unknown,
          message: e.message,
        ),
      );
    } catch (e) {
      developer.log(e.toString());
      if (isClosed) return;
      emit(
        SellPaymentInfoFailure(
          PaymentInfoError.unknown,
          message: e.toString(),
        ),
      );
    }
  }
}
