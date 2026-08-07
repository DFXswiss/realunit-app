import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/transfer/dto/real_unit_transfer_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/transfer/dto/real_unit_transfer_eip7702_data_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/transfer/dto/real_unit_transfer_payment_info_dto.dart';

Map<String, dynamic> _eip7702Json() => {
  'relayerAddress': '0xRelayer',
  'delegationManagerAddress': '0xManager',
  'delegatorAddress': '0xDelegator',
  'userNonce': 7,
  'domain': {
    'name': 'DelegationManager',
    'version': '1',
    'chainId': 11155111,
    'verifyingContract': '0xManager',
  },
  'types': {
    'Delegation': [
      {'name': 'delegate', 'type': 'address'},
    ],
    'Caveat': [
      {'name': 'enforcer', 'type': 'address'},
    ],
  },
  'message': {
    'delegate': '0xRelayer',
    'delegator': '0xSender',
    'authority': '0xRoot',
    'caveats': <dynamic>[],
    'salt': 3,
  },
  'tokenAddress': '0xRealu',
  'amountWei': '5',
  'recipient': '0xRecipient',
};

void main() {
  group('RealUnitTransferDto', () {
    test('toJson carries toAddress + amount', () {
      const dto = RealUnitTransferDto(toAddress: '0xRecipient', amount: 5);

      expect(dto.toJson(), {'toAddress': '0xRecipient', 'amount': 5});
    });
  });

  group('RealUnitTransferEip7702DataDto', () {
    test('fromJson parses the recipient (transfer) shape', () {
      final data = RealUnitTransferEip7702DataDto.fromJson(_eip7702Json());

      expect(data.relayerAddress, '0xRelayer');
      expect(data.delegatorAddress, '0xDelegator');
      expect(data.userNonce, 7);
      expect(data.domain.chainId, 11155111);
      expect(data.types.delegation.first.name, 'delegate');
      expect(data.types.caveat.first.type, 'address');
      expect(data.message.delegator, '0xSender');
      expect(data.message.salt, 3);
      expect(data.tokenAddress, '0xRealu');
      expect(data.amountWei, '5');
      expect(data.recipient, '0xRecipient');
    });

    test('toEip7702Data maps recipient into the shared signer DTO depositAddress', () {
      final data = RealUnitTransferEip7702DataDto.fromJson(_eip7702Json());

      final shared = data.toEip7702Data();

      // The recipient flows through depositAddress (the signers never read it),
      // while every signed field is preserved verbatim.
      expect(shared.depositAddress, '0xRecipient');
      expect(shared.relayerAddress, '0xRelayer');
      expect(shared.delegatorAddress, '0xDelegator');
      expect(shared.userNonce, 7);
      expect(shared.domain.chainId, 11155111);
      expect(shared.message.delegator, '0xSender');
      expect(shared.message.salt, 3);
      expect(shared.tokenAddress, '0xRealu');
      expect(shared.amountWei, '5');
    });
  });

  group('RealUnitTransferPaymentInfoDto', () {
    test('fromJson parses the full prepare response', () {
      final dto = RealUnitTransferPaymentInfoDto.fromJson({
        'id': 99,
        'uid': 'RTabc',
        'toAddress': '0xRecipient',
        'amount': 5,
        'tokenAddress': '0xRealu',
        'chainId': 11155111,
        'eip7702': _eip7702Json(),
      });

      expect(dto.id, 99);
      expect(dto.uid, 'RTabc');
      expect(dto.toAddress, '0xRecipient');
      expect(dto.amount, 5);
      expect(dto.tokenAddress, '0xRealu');
      expect(dto.chainId, 11155111);
      expect(dto.eip7702.recipient, '0xRecipient');
      expect(dto.eip7702.amountWei, '5');
    });

    test('fromJson tolerates a numeric (double) amount from the API', () {
      final dto = RealUnitTransferPaymentInfoDto.fromJson({
        'id': 1,
        'uid': 'RTx',
        'toAddress': '0xRecipient',
        'amount': 5.0,
        'tokenAddress': '0xRealu',
        'chainId': 1,
        'eip7702': _eip7702Json(),
      });

      expect(dto.amount, 5);
    });
  });
}
