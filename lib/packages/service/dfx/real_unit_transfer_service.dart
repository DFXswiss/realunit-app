import 'dart:convert';

import 'package:eip7702/eip7702.dart' as eip7702;
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_auth_service.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/payment/transfer_exceptions.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/eip7702/eip7702_confirm_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/transfer/dto/real_unit_transfer_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/transfer/dto/real_unit_transfer_eip7702_data_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/transfer/dto/real_unit_transfer_payment_info_dto.dart';
import 'package:realunit_wallet/packages/wallet/eip712_signer.dart';
import 'package:realunit_wallet/packages/wallet/eip7702_signer.dart';

/// Consumes the gasless wallet-to-wallet RealUnit transfer endpoints
/// (`PUT /v1/realunit/transfer`, `PUT /v1/realunit/transfer/:id/confirm` —
/// DFXswiss/api #3820). DFX pays gas via EIP-7702 from a dedicated W2W gas
/// wallet, so the app signs an EIP-712 delegation + an EIP-7702 authorization —
/// the exact pattern the SOFTWARE gasless sell confirm uses
/// ([RealUnitSellPaymentInfoService.confirmPayment]).
class RealUnitTransferService extends DFXAuthService {
  static const _transferPath = '/v1/realunit/transfer';
  static String _confirmPath(int id) => '/v1/realunit/transfer/$id/confirm';

  // MetaMask Delegation Framework v1.3.0, CREATE2 — identical on all EVM chains.
  // Pinned exactly as the sell software-confirm path pins them, so a tampered
  // delegation payload is rejected before it is signed.
  static const _metaMaskDelegatorAddress = '0x63c0c19a282a1b52b07dd5a65b58948a07dae32b';
  static const _delegationManagerAddress = '0xdb9b1e94b5b69df7e401ddbede43491141047db3';

  RealUnitTransferService(super.appStore, super.walletService);

  /// `PUT /transfer` — persists the transfer intent and returns the EIP-7702
  /// delegation data to sign. A 503 means DFX cannot currently fund gas; it is
  /// surfaced as a typed [TransferGasFundingUnavailableException] so the flow can
  /// render a friendly "temporarily unavailable" state. Every other non-2xx is
  /// an [ApiException] (KYC30 / registration / invalid recipient are signaled by
  /// the API and rendered from its message).
  Future<RealUnitTransferPaymentInfoDto> prepareTransfer(RealUnitTransferDto dto) async {
    final uri = buildUri(host, _transferPath);
    final response = await authenticatedPut(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(dto.toJson()),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return RealUnitTransferPaymentInfoDto.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }

    final errorJson = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 503) {
      throw TransferGasFundingUnavailableException(
        (errorJson['message'] ?? 'gas funding for transfers is temporarily unavailable').toString(),
      );
    }
    throw ApiException.fromJson(errorJson, httpStatusCode: response.statusCode);
  }

  /// `PUT /transfer/:id/confirm` — signs the EIP-712 delegation + EIP-7702
  /// authorization and relays them; DFX broadcasts the gasless transfer and
  /// returns the tx hash.
  ///
  /// [confirmedRecipient] and [confirmedAmount] are the values the user reviewed
  /// and approved on the confirm screen. They are required so every call site
  /// (including retries) must explicitly supply them; the service fail-closes if
  /// the prepare response echoes different values before any signature is
  /// produced.
  ///
  /// Reuses the wallet unlock/lock boundary and the shared
  /// `Eip712Signer.signDelegation` / `Eip7702Signer.signAuthorization` exactly
  /// like the sell software-confirm. A wallet that cannot produce these
  /// signatures (debug wallet, or hardware firmware without raw EIP-7702
  /// support) raises [TransferSignatureUnsupportedException] — the capability
  /// gate, not a wallet-type branch.
  Future<String> confirmTransfer(
    RealUnitTransferPaymentInfoDto info, {
    required String confirmedRecipient,
    required int confirmedAmount,
  }) async {
    // EIP-712 + EIP-7702 typed-data signing needs the private key; promote the
    // view-wallet to a fully unlocked SoftwareWallet before reading credentials.
    await walletService.ensureCurrentWalletUnlocked();
    try {
      final credentials = appStore.wallet.currentAccount.primaryAddress;
      final transferData = info.eip7702;
      _validateAgainstUserConfirmation(info, confirmedRecipient, confirmedAmount);
      _validateEip7702Data(transferData, credentials.address.hexEip55, info.amount);

      final eip7702Data = transferData.toEip7702Data();
      final String delegationSignature;
      final eip7702.EIP7702MsgSignature authorizationSignature;
      try {
        delegationSignature = await Eip712Signer.signDelegation(
          credentials: credentials,
          eip7702Data: eip7702Data,
        );
        authorizationSignature = Eip7702Signer.signAuthorization(
          credentials: credentials,
          eip7702Data: eip7702Data,
        );
      } on UnsupportedError catch (e) {
        // Debug-wallet credentials reject typed-data signing with UnsupportedError.
        throw TransferSignatureUnsupportedException(e.message ?? e.toString());
      }

      return _sendConfirm(
        info.id,
        Eip7702ConfirmDto(
          delegation: Eip7702DelegationDto(
            delegate: transferData.relayerAddress,
            delegator: transferData.message.delegator,
            authority: transferData.message.authority,
            salt: '${transferData.message.salt}',
            signature: delegationSignature,
          ),
          authorization: Eip7702AuthorizationDto(
            chainId: transferData.domain.chainId,
            address: transferData.delegatorAddress,
            nonce: transferData.userNonce,
            r: '0x${authorizationSignature.r.toRadixString(16).padLeft(64, '0')}',
            s: '0x${authorizationSignature.s.toRadixString(16).padLeft(64, '0')}',
            yParity: authorizationSignature.yParity,
          ),
        ),
      );
    } finally {
      // Drop the mnemonic from memory as soon as signing is done — runs on the
      // throw path too so a validation/sign failure mid-sequence does not leave
      // the key resident. Mirrors [RealUnitSellPaymentInfoService.confirmPayment].
      await walletService.lockCurrentWallet();
    }
  }

  /// Fail-closed blind-sign guard: the prepare response must echo the recipient
  /// and amount the user just confirmed on-screen before any signature is
  /// produced.
  ///
  /// Honesty note — the actually-signed EIP-712 struct (`Eip7702Message`:
  /// delegate/delegator/authority/caveats/salt) carries no recipient/amount
  /// field of its own. `recipient` / `amountWei` / `tokenAddress` are unsigned
  /// metadata sitting alongside the signed message. This check only closes the
  /// gap of "did the backend's prepare response echo something different than
  /// what the user just confirmed on-screen" before signing. It is NOT a
  /// decode/validation of the delegation framework's `caveats` payload (the
  /// actual on-chain enforcement mechanism), which remains unparsed exactly as
  /// before. This change alone does NOT establish a full on-chain
  /// recipient/amount cryptographic binding.
  void _validateAgainstUserConfirmation(
    RealUnitTransferPaymentInfoDto info,
    String confirmedRecipient,
    int confirmedAmount,
  ) {
    if (info.toAddress.toLowerCase() != confirmedRecipient.toLowerCase()) {
      throw TransferConfirmMismatchException(
        'toAddress ${info.toAddress} does not match confirmed recipient $confirmedRecipient',
      );
    }
    if (info.eip7702.recipient.toLowerCase() != confirmedRecipient.toLowerCase()) {
      throw TransferConfirmMismatchException(
        'eip7702.recipient ${info.eip7702.recipient} does not match confirmed recipient $confirmedRecipient',
      );
    }
    if (info.amount != confirmedAmount) {
      throw TransferConfirmMismatchException(
        'amount ${info.amount} does not match confirmed amount $confirmedAmount',
      );
    }
  }

  Future<String> _sendConfirm(int id, Eip7702ConfirmDto dto) async {
    final uri = buildUri(host, _confirmPath(id));
    final response = await authenticatedPut(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(dto.toJson()),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      final errorJson = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 503) {
        throw TransferGasFundingUnavailableException(
          (errorJson['message'] ?? 'gas funding for transfers is temporarily unavailable')
              .toString(),
        );
      }
      final error = ApiException.fromJson(errorJson, httpStatusCode: response.statusCode);
      // 409 "already confirmed": an earlier confirm for this id landed but its
      // response was lost. Mirrors RealUnitSellPaymentInfoService._sendConfirm.
      if (error.statusCode == 409 && error.message.toLowerCase().contains('already confirmed')) {
        final rawTxHash = errorJson['txHash'];
        throw TransferAlreadyConfirmedException(
          statusCode: error.statusCode,
          code: error.code,
          message: error.message,
          txHash: rawTxHash is String ? rawTxHash : null,
        );
      }
      throw error;
    }

    return (jsonDecode(response.body) as Map<String, dynamic>)['txHash'] as String;
  }

  /// Pins the signed contract addresses + cross-checks the signed/unsigned
  /// fields against known values before signing, mirroring the sell flow. The
  /// recipient is server-bound (the backend supplies the ERC20 transfer call at
  /// execute time), so it is validated for amount/token/chain consistency here.
  void _validateEip7702Data(
    RealUnitTransferEip7702DataDto data,
    String walletAddress,
    int userAmount,
  ) {
    final expectedChainId = appStore.apiConfig.asset.chainId;

    if (data.delegatorAddress.toLowerCase() != _metaMaskDelegatorAddress) {
      throw Exception(
        'EIP-7702 delegator address does not match expected MetaMask Delegator contract',
      );
    }
    if (data.delegationManagerAddress.toLowerCase() != _delegationManagerAddress) {
      throw Exception('EIP-7702 delegation manager address does not match expected contract');
    }
    if (data.domain.verifyingContract.toLowerCase() != _delegationManagerAddress) {
      throw Exception('EIP-7702 verifying contract does not match expected DelegationManager');
    }
    if (data.message.delegator.toLowerCase() != walletAddress.toLowerCase()) {
      throw Exception('EIP-7702 message delegator does not match wallet address');
    }
    if (data.domain.chainId != expectedChainId) {
      throw Exception(
        'EIP-7702 chain ID mismatch: expected $expectedChainId, got ${data.domain.chainId}',
      );
    }
    if (data.message.delegate.toLowerCase() != data.relayerAddress.toLowerCase()) {
      throw Exception('EIP-7702 message delegate does not match relayer address');
    }
    if (data.tokenAddress.toLowerCase() != appStore.apiConfig.asset.address.toLowerCase()) {
      throw Exception('EIP-7702 token address does not match RealUnit token');
    }
    // REALU has decimals = 0, so the wei amount equals the share count; compute
    // generically against the asset decimals so a non-zero-decimals asset would
    // still be validated correctly.
    final expectedWei =
        BigInt.from(userAmount) * BigInt.from(10).pow(appStore.apiConfig.asset.decimals);
    final actualWei = BigInt.tryParse(data.amountWei);
    if (actualWei == null || actualWei != expectedWei) {
      throw Exception('EIP-7702 amount mismatch: expected $expectedWei, got ${data.amountWei}');
    }
  }
}
