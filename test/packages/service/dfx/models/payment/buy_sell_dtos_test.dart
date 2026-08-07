import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/buy/dto/real_unit_buy_confirm_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/buy/dto/real_unit_buy_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/buy/dto/real_unit_buy_payment_info_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/payment_info_error.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/real_unit_sell_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/real_unit_sell_payment_info_dto.dart';
import 'package:realunit_wallet/styles/currency.dart';

void main() {
  group('$RealUnitBuyDto.toJson', () {
    test('defaults currency to CHF and serialises amount + code', () {
      const dto = RealUnitBuyDto(amount: 100);

      expect(dto.toJson(), {'amount': 100, 'currency': 'CHF'});
    });

    test('honours an overridden currency by code', () {
      const dto = RealUnitBuyDto(amount: 250, currency: Currency.eur);

      expect(dto.toJson()['currency'], 'EUR');
    });
  });

  group('$RealUnitBuyConfirmDto.fromJson', () {
    test('reads the reference, remittance info and optional payment request', () {
      final dto = RealUnitBuyConfirmDto.fromJson({
        'reference': 'XYZ-123',
        'remittanceInfo': 'XYZ-123',
        'paymentRequest': 'SPC-qr',
      });

      expect(dto.reference, 'XYZ-123');
      expect(dto.remittanceInfo, 'XYZ-123');
      expect(dto.paymentRequest, 'SPC-qr');
    });

    test('leaves paymentRequest null when absent', () {
      final dto = RealUnitBuyConfirmDto.fromJson({
        'reference': 'XYZ-123',
        'remittanceInfo': 'XYZ-123',
      });

      expect(dto.paymentRequest, isNull);
    });

    test('backward compatible: a reference-only payload (current API) leaves '
        'remittanceInfo and paymentRequest null', () {
      final dto = RealUnitBuyConfirmDto.fromJson({'reference': 'XYZ-123'});

      expect(dto.reference, 'XYZ-123');
      expect(dto.remittanceInfo, isNull);
      expect(dto.paymentRequest, isNull);
    });

    test('forward path: all three fields present are parsed', () {
      final dto = RealUnitBuyConfirmDto.fromJson({
        'reference': 'XYZ-123',
        'remittanceInfo': 'REMIT-123',
        'paymentRequest': 'SPC-qr',
      });

      expect(dto.reference, 'XYZ-123');
      expect(dto.remittanceInfo, 'REMIT-123');
      expect(dto.paymentRequest, 'SPC-qr');
    });
  });

  group('$RealUnitBuyPaymentInfoDto.fromJson', () {
    Map<String, dynamic> baseJson() => {
          'id': 1,
          'routeId': 2,
          'timestamp': '2026-05-15T10:00:00Z',
          'iban': 'CH...',
          'bic': 'BIC',
          'name': 'DFX AG',
          'street': 'Bahnhofstrasse',
          'number': '1',
          'zip': '8000',
          'city': 'Zurich',
          'country': 'CH',
          'amount': 100.5,
          'currency': 'CHF',
          'fees': {
            'rate': 0.01,
            'fixed': 0.5,
            'network': 0.0,
            'min': 1.0,
            'dfx': 0.5,
            'total': 2.0,
          },
          'minVolume': 5.0,
          'maxVolume': 5000.0,
          'minVolumeTarget': 5.1,
          'maxVolumeTarget': 5100.0,
          'exchangeRate': 1.1,
          'rate': 1.05,
          'priceSteps': <Map<String, dynamic>>[],
          'estimatedAmount': 95.5,
          'paymentRequest': 'pay-req',
          'remittanceInfo': 'rem-info',
          'isValid': true,
        };

    test('parses every field on the happy path', () {
      final dto = RealUnitBuyPaymentInfoDto.fromJson(baseJson());

      expect(dto.id, 1);
      expect(dto.routeId, 2);
      expect(dto.timestamp, DateTime.utc(2026, 5, 15, 10));
      expect(dto.amount, 100.5);
      expect(dto.currency, Currency.chf);
      expect(dto.fees.total, 2.0);
      expect(dto.minVolume, 5.0);
      expect(dto.maxVolume, 5000.0);
      expect(dto.paymentRequest, 'pay-req');
      expect(dto.remittanceInfo, 'rem-info');
      expect(dto.isValid, isTrue);
      expect(dto.priceSteps, isEmpty);
    });

    test('keeps optional fields null when the wire sends null', () {
      final json = baseJson()
        ..['minVolume'] = null
        ..['maxVolume'] = null
        ..['paymentRequest'] = null
        ..['remittanceInfo'] = null;

      final dto = RealUnitBuyPaymentInfoDto.fromJson(json);

      expect(dto.minVolume, isNull);
      expect(dto.maxVolume, isNull);
      expect(dto.paymentRequest, isNull);
      expect(dto.remittanceInfo, isNull);
    });
  });

  group('$RealUnitSellDto.toJson', () {
    test('serialises amount-only and defaults currency to CHF', () {
      final dto = RealUnitSellDto(amount: 100, iban: 'CH...');

      expect(dto.toJson(), {'amount': 100, 'iban': 'CH...', 'currency': 'CHF'});
    });

    test('serialises targetAmount-only and omits the amount key', () {
      final dto = RealUnitSellDto(targetAmount: 50, iban: 'CH...');

      expect(dto.toJson().containsKey('amount'), isFalse);
      expect(dto.toJson()['targetAmount'], 50);
    });

    test('honours an overridden currency by code', () {
      final dto =
          RealUnitSellDto(amount: 100, iban: 'CH...', currency: Currency.eur);

      expect(dto.toJson()['currency'], 'EUR');
    });

    test('asserts that exactly one of amount / targetAmount is set', () {
      expect(() => RealUnitSellDto(iban: 'CH...'), throwsA(isA<AssertionError>()));
      expect(
        () => RealUnitSellDto(amount: 1, targetAmount: 1, iban: 'CH...'),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('$BeneficiaryDto.fromJson', () {
    test('parses name + iban', () {
      final dto = BeneficiaryDto.fromJson({'name': 'Alice', 'iban': 'CH...'});

      expect(dto.name, 'Alice');
      expect(dto.iban, 'CH...');
    });

    test('keeps name null when missing', () {
      final dto = BeneficiaryDto.fromJson({'iban': 'CH...'});

      expect(dto.name, isNull);
      expect(dto.iban, 'CH...');
    });
  });

  group('$PaymentInfoError', () {
    test('has the eight documented variants', () {
      // Pin the wire contract — any new variant has to be added intentionally.
      expect(PaymentInfoError.values, hasLength(8));
      expect(
        PaymentInfoError.values.toSet(),
        {
          PaymentInfoError.registrationRequired,
          PaymentInfoError.kycRequired,
          PaymentInfoError.primaryEmailRequired,
          PaymentInfoError.primaryEmailNotConfirmed,
          PaymentInfoError.minAmountNotMet,
          PaymentInfoError.bitboxDisconnected,
          PaymentInfoError.priceSourceUnavailable,
          PaymentInfoError.unknown,
        },
      );
    });
  });
}
