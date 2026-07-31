import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/lnurlp_payment_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/real_unit_ocp_pay_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/real_unit_ocp_pay_result_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/real_unit_ocp_pay_status_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/real_unit_ocp_pay_submit_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/real_unit_ocp_pay_unsigned_transaction_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/real_unit_swap_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/real_unit_swap_payment_info_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/real_unit_swap_unsigned_transaction_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/swap_payment_info.dart';

void main() {
  group('RealUnitSwapDto', () {
    test('fromTargetAmount serialises only targetAmount (no amount key)', () {
      expect(
        const RealUnitSwapDto.fromTargetAmount(95.5).toJson(),
        {'targetAmount': 95.5},
      );
    });
  });

  group('RealUnitSwapPaymentInfoDto.fromJson', () {
    test('maps every field with no dynamic access', () {
      final dto = RealUnitSwapPaymentInfoDto.fromJson({
        'id': 99,
        'uid': 'MOCK-UID',
        'routeId': 7,
        'timestamp': '2026-06-03T00:00:00.000Z',
        'amount': 10,
        'estimatedAmount': 960,
        'targetAsset': 'ZCHF',
        'fees': {'dfx': 1, 'network': 0.5, 'total': 1.5},
        'minVolume': 1,
        'maxVolume': 1000,
        'minVolumeTarget': 95,
        'maxVolumeTarget': 95000,
        'ethBalance': 1.0,
        'requiredGasEth': 0.001,
        'isValid': true,
      });

      expect(dto.id, 99);
      expect(dto.uid, 'MOCK-UID');
      expect(dto.routeId, 7);
      expect(dto.targetAsset, 'ZCHF');
      expect(dto.estimatedAmount, 960);
      expect(dto.minVolumeTarget, 95);
      expect(dto.isValid, isTrue);
      expect(dto.error, isNull);
      expect(dto.fees?.total, 1.5);
    });

    test('maps the error code when isValid is false', () {
      final dto = RealUnitSwapPaymentInfoDto.fromJson({
        'id': 1,
        'uid': 'u',
        'routeId': 1,
        'timestamp': '2026-06-03T00:00:00.000Z',
        'amount': 1,
        'estimatedAmount': 1,
        'targetAsset': 'ZCHF',
        'minVolume': 1,
        'maxVolume': 2,
        'minVolumeTarget': 1,
        'maxVolumeTarget': 2,
        'ethBalance': 0,
        'requiredGasEth': 0.001,
        'isValid': false,
        'error': 'LIMIT_EXCEEDED',
      });

      expect(dto.isValid, isFalse);
      expect(dto.error, 'LIMIT_EXCEEDED');
      expect(dto.fees, isNull);
    });
  });

  test('SwapPaymentInfo.fromDto carries the swap-relevant fields', () {
    final dto = RealUnitSwapPaymentInfoDto.fromJson({
      'id': 5,
      'uid': 'u',
      'routeId': 2,
      'timestamp': '2026-06-03T00:00:00.000Z',
      'amount': 10,
      'estimatedAmount': 960,
      'targetAsset': 'ZCHF',
      'minVolume': 1,
      'maxVolume': 1000,
      'minVolumeTarget': 95,
      'maxVolumeTarget': 95000,
      'ethBalance': 0.4,
      'requiredGasEth': 0.002,
      'isValid': true,
    });

    final info = SwapPaymentInfo.fromDto(dto);

    expect(info.id, 5);
    expect(info.estimatedAmount, 960);
    expect(info.ethBalance, 0.4);
    expect(info.requiredGasEth, 0.002);
    expect(info.isValid, isTrue);
    expect(info.feesTotal, isNull);
  });

  test('SwapPaymentInfo.fromDto carries fees.total as feesTotal', () {
    final dto = RealUnitSwapPaymentInfoDto.fromJson({
      'id': 99,
      'uid': 'MOCK-UID',
      'routeId': 7,
      'timestamp': '2026-06-03T00:00:00.000Z',
      'amount': 10,
      'estimatedAmount': 960,
      'targetAsset': 'ZCHF',
      'fees': {'total': 3.25},
      'minVolume': 1,
      'maxVolume': 1000,
      'minVolumeTarget': 95,
      'maxVolumeTarget': 95000,
      'ethBalance': 1.0,
      'requiredGasEth': 0.001,
      'isValid': true,
    });

    final info = SwapPaymentInfo.fromDto(dto);

    expect(info.feesTotal, 3.25);
  });

  test('SwapPaymentInfo equality is value-based (Equatable props)', () {
    const a = SwapPaymentInfo(
      id: 1,
      amount: 10,
      estimatedAmount: 960,
      targetAsset: 'ZCHF',
      ethBalance: 1,
      requiredGasEth: 0.001,
      isValid: true,
    );
    const same = SwapPaymentInfo(
      id: 1,
      amount: 10,
      estimatedAmount: 960,
      targetAsset: 'ZCHF',
      ethBalance: 1,
      requiredGasEth: 0.001,
      isValid: true,
    );
    const different = SwapPaymentInfo(
      id: 2,
      amount: 10,
      estimatedAmount: 960,
      targetAsset: 'ZCHF',
      ethBalance: 1,
      requiredGasEth: 0.001,
      isValid: true,
      error: 'LIMIT_EXCEEDED',
    );

    expect(a, equals(same));
    expect(a, isNot(equals(different)));
  });

  test('RealUnitSwapUnsignedTransactionDto.fromJson', () {
    final dto = RealUnitSwapUnsignedTransactionDto.fromJson({'swap': '0xswap'});
    expect(dto.swap, '0xswap');
  });

  test('RealUnitOcpPayDto.toJson', () {
    const dto = RealUnitOcpPayDto(paymentLinkId: 'pl_abc', quoteId: 'q1');
    expect(dto.toJson(), {'paymentLinkId': 'pl_abc', 'quoteId': 'q1'});
  });

  test('RealUnitOcpPayUnsignedTransactionDto.fromJson', () {
    final dto = RealUnitOcpPayUnsignedTransactionDto.fromJson({
      'unsignedTx': '0xtx',
      'tokenAddress': '0xzchf',
      'recipient': '0xrecipient',
      'amountWei': '5000000000000000000',
      'chainId': 1,
    });

    expect(dto.unsignedTx, '0xtx');
    expect(dto.tokenAddress, '0xzchf');
    expect(dto.recipient, '0xrecipient');
    expect(dto.amountWei, '5000000000000000000');
    expect(dto.chainId, 1);
  });

  test('RealUnitOcpPaySubmitDto.toJson carries the signed envelope + refs', () {
    const dto = RealUnitOcpPaySubmitDto(
      unsignedTx: '0xtx',
      r: '0xr',
      s: '0xs',
      v: 27,
      paymentLinkId: 'pl_abc',
      quoteId: 'q1',
    );

    expect(dto.toJson(), {
      'unsignedTx': '0xtx',
      'r': '0xr',
      's': '0xs',
      'v': 27,
      'paymentLinkId': 'pl_abc',
      'quoteId': 'q1',
    });
  });

  test('RealUnitOcpPayResultDto.fromJson', () {
    expect(RealUnitOcpPayResultDto.fromJson({'txId': '0xTxId'}).txId, '0xTxId');
  });

  group('RealUnitOcpPayStatusDto.fromJson', () {
    test('maps each known status', () {
      expect(
        RealUnitOcpPayStatusDto.fromJson({'status': 'Completed'}).status,
        OcpPaymentStatus.completed,
      );
      expect(
        RealUnitOcpPayStatusDto.fromJson({'status': 'Pending'}).status,
        OcpPaymentStatus.pending,
      );
      expect(
        RealUnitOcpPayStatusDto.fromJson({'status': 'Cancelled'}).status,
        OcpPaymentStatus.cancelled,
      );
      expect(
        RealUnitOcpPayStatusDto.fromJson({'status': 'Expired'}).status,
        OcpPaymentStatus.expired,
      );
    });

    test('falls back to unknown for an unmapped status', () {
      expect(
        RealUnitOcpPayStatusDto.fromJson({'status': 'Whatever'}).status,
        OcpPaymentStatus.unknown,
      );
    });

    test('falls back to unknown for an empty status without matching the unknown sentinel', () {
      // Regression test: `unknown` is internally represented as `unknown('')`. Before the fix,
      // an empty backend value matched that sentinel directly in the known-value loop and bypassed
      // the developer.log(...) drift-visibility call. The observable return value is `unknown`
      // either way; this pins the mapping so a future regression that makes '' match something
      // else (or crash) is caught. The developer.log call itself has no mockable surface in Dart
      // (same limitation documented in test/screens/sell/widgets/sell_bank_account_field_test.dart).
      expect(
        RealUnitOcpPayStatusDto.fromJson({'status': ''}).status,
        OcpPaymentStatus.unknown,
      );
    });

    test('isTerminal / isCompleted predicates', () {
      expect(OcpPaymentStatus.completed.isTerminal, isTrue);
      expect(OcpPaymentStatus.completed.isCompleted, isTrue);
      expect(OcpPaymentStatus.cancelled.isTerminal, isTrue);
      expect(OcpPaymentStatus.cancelled.isCompleted, isFalse);
      expect(OcpPaymentStatus.expired.isTerminal, isTrue);
      expect(OcpPaymentStatus.pending.isTerminal, isFalse);
      expect(OcpPaymentStatus.unknown.isTerminal, isTrue);
    });
  });

  group('LnurlpPaymentDto.fromJson', () {
    test('maps requestedAmount, quote and ZCHF transfer amounts', () {
      final dto = LnurlpPaymentDto.fromJson({
        'requestedAmount': {'asset': 'CHF', 'amount': 42.5},
        'quote': {'id': 'quote_xyz', 'expiration': '2026-06-03T12:00:00.000Z'},
        'transferAmounts': [
          {
            'method': 'Ethereum',
            'assets': [
              {'asset': 'ZCHF', 'amount': 42.7},
            ],
          },
          {
            'method': 'Bitcoin',
            'assets': [
              {'asset': 'BTC', 'amount': 0.0005},
            ],
          },
        ],
      });

      expect(dto.requestedAmount.asset, 'CHF');
      expect(dto.requestedAmount.amount, 42.5);
      expect(dto.quote.id, 'quote_xyz');
      expect(dto.transferAmounts, hasLength(2));
      expect(dto.transferAmounts.first.method, 'Ethereum');
      expect(dto.transferAmounts.first.assets.first.asset, 'ZCHF');
      expect(dto.transferAmounts.first.assets.first.amount, 42.7);
      // Additive rawAmount captures the JSON value's toString before double parse.
      expect(dto.transferAmounts.first.assets.first.rawAmount, '42.7');
    });

    test('rejects a missing transferAmounts list', () {
      expect(
        () => LnurlpPaymentDto.fromJson({
          'requestedAmount': {'asset': 'CHF', 'amount': 1.0},
          'quote': {'id': 'q', 'expiration': '2026-06-03T12:00:00.000Z'},
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a missing assets list within a transferAmounts entry', () {
      expect(
        () => LnurlpPaymentDto.fromJson({
          'requestedAmount': {'asset': 'CHF', 'amount': 1.0},
          'quote': {'id': 'q', 'expiration': '2026-06-03T12:00:00.000Z'},
          'transferAmounts': [
            {'method': 'Ethereum'},
          ],
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('parses amount-less asset entries (non-priced display path) as null', () {
      final dto = LnurlpPaymentDto.fromJson({
        'requestedAmount': {'asset': 'CHF', 'amount': 1.0},
        'quote': {'id': 'q', 'expiration': '2026-06-03T12:00:00.000Z'},
        'transferAmounts': [
          {
            'method': 'Ethereum',
            'assets': [
              // Optional `amount?` omitted by the backend.
              {'asset': 'ZCHF'},
            ],
          },
        ],
      });

      expect(dto.transferAmounts.first.assets.first.asset, 'ZCHF');
      expect(dto.transferAmounts.first.assets.first.amount, isNull);
      expect(dto.transferAmounts.first.assets.first.rawAmount, isNull);
    });

    test('preserves a string amount as rawAmount without double drift', () {
      final dto = LnurlpPaymentDto.fromJson({
        'requestedAmount': {'asset': 'CHF', 'amount': '10.10'},
        'quote': {'id': 'q', 'expiration': '2026-06-03T12:00:00.000Z'},
        'transferAmounts': [
          {
            'method': 'Ethereum',
            'assets': [
              {'asset': 'ZCHF', 'amount': '42.70000000000001'},
            ],
          },
        ],
      });

      expect(dto.requestedAmount.amount, 10.10);
      expect(dto.transferAmounts.first.assets.first.rawAmount, '42.70000000000001');
      expect(dto.transferAmounts.first.assets.first.amount, isNotNull);
    });

    test('rejects NaN in requestedAmount.amount', () {
      expect(
        () => LnurlpPaymentDto.fromJson({
          'requestedAmount': {'asset': 'CHF', 'amount': 'NaN'},
          'quote': {'id': 'q', 'expiration': '2026-06-03T12:00:00.000Z'},
          'transferAmounts': [
            {
              'method': 'Ethereum',
              'assets': [
                {'asset': 'ZCHF', 'amount': 1.0},
              ],
            },
          ],
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('not a finite number'),
          ),
        ),
      );
    });

    test('rejects Infinity in transfer asset amount', () {
      expect(
        () => LnurlpPaymentDto.fromJson({
          'requestedAmount': {'asset': 'CHF', 'amount': 1.0},
          'quote': {'id': 'q', 'expiration': '2026-06-03T12:00:00.000Z'},
          'transferAmounts': [
            {
              'method': 'Ethereum',
              'assets': [
                {'asset': 'ZCHF', 'amount': 'Infinity'},
              ],
            },
          ],
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('not a finite number'),
          ),
        ),
      );
    });

    test('rejects -Infinity in requestedAmount.amount', () {
      expect(
        () => LnurlpPaymentDto.fromJson({
          'requestedAmount': {'asset': 'CHF', 'amount': '-Infinity'},
          'quote': {'id': 'q', 'expiration': '2026-06-03T12:00:00.000Z'},
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a negative transfer asset amount', () {
      expect(
        () => LnurlpPaymentDto.fromJson({
          'requestedAmount': {'asset': 'CHF', 'amount': 1.0},
          'quote': {'id': 'q', 'expiration': '2026-06-03T12:00:00.000Z'},
          'transferAmounts': [
            {
              'method': 'Ethereum',
              'assets': [
                {'asset': 'ZCHF', 'amount': -1},
              ],
            },
          ],
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('must not be negative'),
          ),
        ),
      );
    });

    test('rejects a negative requestedAmount.amount', () {
      expect(
        () => LnurlpPaymentDto.fromJson({
          'requestedAmount': {'asset': 'CHF', 'amount': -0.01},
          'quote': {'id': 'q', 'expiration': '2026-06-03T12:00:00.000Z'},
          'transferAmounts': [
            {
              'method': 'Ethereum',
              'assets': [
                {'asset': 'ZCHF', 'amount': 1.0},
              ],
            },
          ],
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('must not be negative'),
          ),
        ),
      );
    });

    test('ignores the structured recipient object instead of throwing on it', () {
      // The backend `recipient` is a PaymentLinkRecipientDto object, not a
      // String; reading the quote must not throw on it. Only name+city are
      // mapped; other nested address fields are intentionally left unmapped.
      final dto = LnurlpPaymentDto.fromJson({
        'recipient': {
          'name': 'Acme GmbH',
          'address': {'street': 'Bahnhofstrasse', 'houseNumber': '1', 'city': 'Zürich'},
        },
        'requestedAmount': {'asset': 'CHF', 'amount': 42.5},
        'quote': {'id': 'quote_xyz', 'expiration': '2026-06-03T12:00:00.000Z'},
        'transferAmounts': [
          {
            'method': 'Ethereum',
            'assets': [
              {'asset': 'ZCHF', 'amount': 42.7},
            ],
          },
        ],
      });

      expect(dto.quote.id, 'quote_xyz');
      expect(dto.transferAmounts.first.assets.first.amount, 42.7);
      expect(dto.recipient?.name, 'Acme GmbH');
      expect(dto.recipient?.city, 'Zürich');
    });
  });
}
