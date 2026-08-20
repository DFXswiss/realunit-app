import 'dart:developer' as developer;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_buy_payment_info_service.dart';

part 'buy_confirm_state.dart';

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
      emit(BuyConfirmFailure(e.message));
    } catch (e) {
      developer.log(e.toString());
      emit(BuyConfirmFailure(e.toString()));
    }
  }
}
