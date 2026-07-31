import 'package:equatable/equatable.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/real_unit_swap_payment_info_dto.dart';

/// Domain model for an IBAN-free REALU → ZCHF swap quote. The backend decides
/// validity, limits and the ZCHF estimate; this model only carries those fields
/// for the flow's cubits to render and to drive the ETH-balance / swap steps.
class SwapPaymentInfo extends Equatable {
  final int id;
  final double amount;
  final double estimatedAmount;
  final String targetAsset;
  final double ethBalance;
  final double requiredGasEth;
  final bool isValid;
  final String? error;
  final double? feesTotal;

  const SwapPaymentInfo({
    required this.id,
    required this.amount,
    required this.estimatedAmount,
    required this.targetAsset,
    required this.ethBalance,
    required this.requiredGasEth,
    required this.isValid,
    this.error,
    this.feesTotal,
  });

  factory SwapPaymentInfo.fromDto(RealUnitSwapPaymentInfoDto dto) => SwapPaymentInfo(
    id: dto.id,
    amount: dto.amount,
    estimatedAmount: dto.estimatedAmount,
    targetAsset: dto.targetAsset,
    ethBalance: dto.ethBalance,
    requiredGasEth: dto.requiredGasEth,
    isValid: dto.isValid,
    error: dto.error,
    feesTotal: dto.fees?.total,
  );

  @override
  List<Object?> get props => [
    id,
    amount,
    estimatedAmount,
    targetAsset,
    ethBalance,
    requiredGasEth,
    isValid,
    error,
    feesTotal,
  ];
}
