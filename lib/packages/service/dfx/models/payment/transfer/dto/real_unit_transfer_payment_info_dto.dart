import 'package:realunit_wallet/packages/service/dfx/models/payment/transfer/dto/real_unit_transfer_eip7702_data_dto.dart';

/// Response of `PUT /v1/realunit/transfer` — the persisted transfer intent plus
/// the EIP-7702 delegation data the app must sign for the gasless REALU
/// transfer.
class RealUnitTransferPaymentInfoDto {
  final int id;
  final String uid;
  final String toAddress;
  final int amount;
  final String tokenAddress;
  final int chainId;
  final RealUnitTransferEip7702DataDto eip7702;

  const RealUnitTransferPaymentInfoDto({
    required this.id,
    required this.uid,
    required this.toAddress,
    required this.amount,
    required this.tokenAddress,
    required this.chainId,
    required this.eip7702,
  });

  factory RealUnitTransferPaymentInfoDto.fromJson(Map<String, dynamic> json) {
    return RealUnitTransferPaymentInfoDto(
      id: json['id'] as int,
      uid: json['uid'] as String,
      toAddress: json['toAddress'] as String,
      amount: (json['amount'] as num).toInt(),
      tokenAddress: json['tokenAddress'] as String,
      chainId: json['chainId'] as int,
      eip7702: RealUnitTransferEip7702DataDto.fromJson(
        json['eip7702'] as Map<String, dynamic>,
      ),
    );
  }
}
