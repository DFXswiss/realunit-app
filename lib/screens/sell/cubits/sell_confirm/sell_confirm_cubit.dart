import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/payment/sell_exceptions.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/sell_payment_info.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_sell_payment_info_service.dart';

part 'sell_confirm_state.dart';

class SellConfirmCubit extends Cubit<SellConfirmState> {
  final RealUnitSellPaymentInfoService _sellPaymentInfoService;

  SellConfirmCubit(RealUnitSellPaymentInfoService sellPaymentInfoService)
    : _sellPaymentInfoService = sellPaymentInfoService,
      super(SellConfirmInitial());

  Future<void> confirmPayment(SellPaymentInfo paymentInfo) async {
    try {
      emit(SellConfirmLoading());
      await _sellPaymentInfoService.confirmPayment(paymentInfo);
      if (isClosed) return;
      emit(SellConfirmSuccess());
    } on AlreadyConfirmedException {
      // The sell already completed server-side; only the response was lost.
      if (isClosed) return;
      emit(SellConfirmSuccess());
    } catch (e) {
      if (isClosed) return;
      emit(SellConfirmFailure(ApiException.userFacingMessage(e)));
    }
  }
}
