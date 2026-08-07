import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/lnurlp_payment_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/real_unit_swap_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_pay_service.dart';

part 'pay_quote_state.dart';

/// Reads the public OCP payment-link quote (`GET /v1/lnurlp/:id`) and surfaces
/// the requested fiat amount + the exact ZCHF amount the Ethereum method
/// requires. The amount comes from the API `transferAmounts` (ZCHF on the
/// Ethereum entry) — the app never computes it. An expired quote surfaces as a
/// typed state so the view can prompt a re-scan.
class PayQuoteCubit extends Cubit<PayQuoteState> {
  final RealUnitPayService _payService;
  final String _paymentLinkId;

  PayQuoteCubit(this._payService, this._paymentLinkId) : super(const PayQuoteLoading());

  Future<void> load() async {
    emit(const PayQuoteLoading());

    try {
      final details = await _payService.getPaymentDetails(_paymentLinkId);
      if (isClosed) return;

      if (details.quote.expiration.isBefore(DateTime.now())) {
        emit(const PayQuoteExpired());
        return;
      }

      final zchfAmount = _zchfTransferAmount(details);
      if (zchfAmount == null) {
        emit(const PayQuoteUnavailable());
        return;
      }

      // Preview-only swap quote using the plain bill ZCHF amount (no slippage
      // buffer). Shown on the pay-quote screen so the user sees expected REALU
      // sold, ZCHF proceeds and fees for this bill before confirming. The
      // actual swap executed later in PayProcessCubit re-requests its own quote
      // independently with its own slippage buffer and remains the sole source
      // of truth for what is actually swapped.
      final swap = await _payService.getSwapPaymentInfo(
        RealUnitSwapDto.fromTargetAmount(zchfAmount),
      );
      if (isClosed) return;

      emit(
        PayQuoteReady(
          paymentLinkId: _paymentLinkId,
          quoteId: details.quote.id,
          fiatAsset: details.requestedAmount.asset,
          fiatAmount: details.requestedAmount.amount,
          zchfAmount: zchfAmount,
          merchantName: details.recipient?.name,
          merchantCity: details.recipient?.city,
          realuAmount: swap.amount,
          realuEstimatedZchf: swap.estimatedAmount,
          realuFeesTotal: swap.feesTotal,
        ),
      );
    } catch (e) {
      if (isClosed) return;
      emit(PayQuoteError(e.toString()));
    }
  }

  /// The ZCHF amount listed for the Ethereum transfer method, or null if the
  /// payment link does not offer an Ethereum/ZCHF method.
  static double? _zchfTransferAmount(LnurlpPaymentDto details) {
    for (final transfer in details.transferAmounts) {
      if (transfer.method.toLowerCase() != 'ethereum') continue;
      for (final asset in transfer.assets) {
        if (asset.asset.toUpperCase() == 'ZCHF') return asset.amount;
      }
    }
    return null;
  }
}
