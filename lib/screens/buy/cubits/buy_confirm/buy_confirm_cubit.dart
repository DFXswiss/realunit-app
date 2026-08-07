import 'dart:developer' as developer;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_buy_payment_info_service.dart';

part 'buy_confirm_state.dart';

// Backend error code for a confirm rejected by Aktionariat because the
// purchase is below its minimum (HTTP 400). Dispatch on the code, not the
// message text — the message is Aktionariat's and may change.
const String _errorCodeAmountTooLow = 'AmountTooLow';

// Backend error code for a confirm rejected upstream because the buyer's
// primary email is missing or not yet confirmed at the share register
// (HTTP 400). Dispatch on the code, not the message text.
const String _errorCodePrimaryEmailRequired = 'PrimaryEmailRequired';

class BuyConfirmCubit extends Cubit<BuyConfirmState> {
  final RealUnitBuyPaymentInfoService _buyPaymentInfoService;

  BuyConfirmCubit(RealUnitBuyPaymentInfoService buyPaymentInfoService)
    : _buyPaymentInfoService = buyPaymentInfoService,
      super(const BuyConfirmInitial());

  Future<void> confirmPayment(int paymentInfoId) async {
    try {
      emit(const BuyConfirmLoading());
      final dto = await _buyPaymentInfoService.confirmPayment(paymentInfoId);
      emit(
        BuyConfirmSuccess(
          reference: dto.reference,
          remittanceInfo: dto.remittanceInfo,
          paymentRequest: dto.paymentRequest,
        ),
      );
    } on ApiException catch (e) {
      developer.log(e.toString());
      final error = e.statusCode == 503
          ? BuyConfirmError.aktionariat
          : e.code == _errorCodeAmountTooLow
          ? BuyConfirmError.amountTooLow
          : e.code == _errorCodePrimaryEmailRequired
          ? BuyConfirmError.primaryEmailRequired
          : BuyConfirmError.unknown;
      emit(BuyConfirmFailure(error));
    } catch (e) {
      developer.log(e.toString());
      emit(const BuyConfirmFailure(BuyConfirmError.unknown));
    }
  }
}
