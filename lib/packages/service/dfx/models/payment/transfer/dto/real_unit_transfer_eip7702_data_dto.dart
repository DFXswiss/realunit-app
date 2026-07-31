import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/eip7702/eip7702_data_dto.dart';

/// EIP-7702 delegation data for a gasless wallet-to-wallet REALU transfer.
///
/// Mirrors the sell flow's [Eip7702Data] (`domain`/`types`/`message` are the
/// exact same shape the EIP-712 delegation + EIP-7702 authorization signers
/// consume), but the transfer endpoint returns the on-chain destination as
/// `recipient` rather than the sell flow's `depositAddress`.
class RealUnitTransferEip7702DataDto {
  final String relayerAddress;
  final String delegationManagerAddress;
  final String delegatorAddress;
  final int userNonce;
  final Eip7702Domain domain;
  final Eip7702Types types;
  final Eip7702Message message;
  final String tokenAddress;
  final String amountWei;
  final String recipient;

  const RealUnitTransferEip7702DataDto({
    required this.relayerAddress,
    required this.delegationManagerAddress,
    required this.delegatorAddress,
    required this.userNonce,
    required this.domain,
    required this.types,
    required this.message,
    required this.tokenAddress,
    required this.amountWei,
    required this.recipient,
  });

  factory RealUnitTransferEip7702DataDto.fromJson(Map<String, dynamic> json) {
    return RealUnitTransferEip7702DataDto(
      relayerAddress: json['relayerAddress'] as String,
      delegationManagerAddress: json['delegationManagerAddress'] as String,
      delegatorAddress: json['delegatorAddress'] as String,
      userNonce: json['userNonce'] as int,
      domain: Eip7702Domain.fromJson(json['domain'] as Map<String, dynamic>),
      types: Eip7702Types.fromJson(json['types'] as Map<String, dynamic>),
      message: Eip7702Message.fromJson(json['message'] as Map<String, dynamic>),
      tokenAddress: json['tokenAddress'] as String,
      amountWei: json['amountWei'] as String,
      recipient: json['recipient'] as String,
    );
  }

  /// Adapts to the sell flow's [Eip7702Data] so the shared
  /// `Eip712Signer.signDelegation` / `Eip7702Signer.signAuthorization` can sign
  /// it without a transfer-specific signer. The signers never read
  /// `depositAddress`, so the `recipient` is mapped through it verbatim.
  Eip7702Data toEip7702Data() {
    return Eip7702Data(
      relayerAddress: relayerAddress,
      delegationManagerAddress: delegationManagerAddress,
      delegatorAddress: delegatorAddress,
      userNonce: userNonce,
      domain: domain,
      types: types,
      message: message,
      tokenAddress: tokenAddress,
      amountWei: amountWei,
      depositAddress: recipient,
    );
  }
}
