import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/packages/service/dfx/models/brokerbot/dfx_buy_price_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/brokerbot/dfx_buy_shares_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/brokerbot/dfx_sell_price_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/brokerbot/dfx_sell_shares_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/country/country.dart';
import 'package:realunit_wallet/packages/service/dfx/models/country/dto/dfx_country_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/faucet/faucet_response_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/fees/dfx_fees_data.dart';
import 'package:realunit_wallet/packages/service/dfx/models/kyc/kyc_level.dart';
import 'package:realunit_wallet/packages/service/dfx/models/user/dto/real_unit_user_data_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/user/dto/user_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/wallet/real_unit_registration_info_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/wallet/real_unit_registration_state.dart';

void main() {
  group('$BrokerbotBuyPriceDto.fromJson', () {
    test('maps totalPrice → totalCost and widens nums', () {
      final dto = BrokerbotBuyPriceDto.fromJson({
        'totalPrice': 1000,
        'pricePerShare': 50.5,
        'availableShares': 20,
      });

      expect(dto.totalCost, 1000.0);
      expect(dto.pricePerShare, 50.5);
      expect(dto.availableShares, 20);
    });
  });

  group('$BrokerbotBuySharesDto.fromJson', () {
    test('parses shares + pricePerShare + availableShares', () {
      final dto = BrokerbotBuySharesDto.fromJson({
        'shares': 5,
        'pricePerShare': 50.0,
        'availableShares': 100,
      });

      expect(dto.shares, 5);
      expect(dto.pricePerShare, 50.0);
      expect(dto.availableShares, 100);
    });
  });

  group('$BrokerbotSellPriceDto.fromJson', () {
    test('parses every field + currency code', () {
      final dto = BrokerbotSellPriceDto.fromJson({
        'shares': 10,
        'pricePerShare': 50.0,
        'estimatedAmount': 500.0,
        'currency': 'CHF',
      });

      expect(dto.shares, 10);
      expect(dto.estimatedAmount, 500.0);
      expect(dto.currency, 'CHF');
    });
  });

  group('$BrokerbotSellSharesDto.fromJson', () {
    test('parses targetAmount + shares + pricePerShare + currency', () {
      final dto = BrokerbotSellSharesDto.fromJson({
        'targetAmount': 500.0,
        'shares': 10,
        'pricePerShare': 50.0,
        'currency': 'CHF',
      });

      expect(dto.targetAmount, 500.0);
      expect(dto.shares, 10);
      expect(dto.currency, 'CHF');
    });
  });

  group('$FaucetResponseDto.fromJson', () {
    test('parses txId + amount', () {
      final dto = FaucetResponseDto.fromJson({'txId': '0xabc', 'amount': 0.1});

      expect(dto.txId, '0xabc');
      expect(dto.amount, 0.1);
    });
  });

  group('$DfxFeesData.fromJson', () {
    test('parses every numeric field as double', () {
      final dto = DfxFeesData.fromJson({
        'rate': 0.01,
        'fixed': 0.5,
        'network': 0,
        'min': 1,
        'dfx': 0.25,
        'total': 1.76,
      });

      expect(dto.rate, 0.01);
      expect(dto.fixed, 0.5);
      // Integer wire values are widened to double.
      expect(dto.network, 0.0);
      expect(dto.min, 1.0);
      expect(dto.total, 1.76);
    });
  });

  group('$Country', () {
    test('equality is by id only', () {
      const a = Country(
        id: 41,
        symbol: 'CH',
        name: 'Switzerland',
        kycAllowed: true,
      );
      const b = Country(
        id: 41,
        symbol: 'XX',
        name: 'Different',
        kycAllowed: true,
      );
      const c = Country(
        id: 49,
        symbol: 'DE',
        name: 'Germany',
        kycAllowed: true,
      );

      expect(a, b);
      expect(a, isNot(c));
    });

    test('DfxCountryDtoMapper.toCountry forwards id / symbol / name / foreignName', () {
      const dto = DfxCountryDto(
        id: 41,
        symbol: 'CH',
        name: 'Switzerland',
        foreignName: 'Schweiz',
        locationAllowed: true,
        ibanAllowed: true,
        kycAllowed: true,
        kycOrganizationAllowed: true,
        nationalityAllowed: true,
        bankAllowed: true,
        cardAllowed: true,
        cryptoAllowed: true,
      );

      final country = dto.toCountry();

      expect(country.id, 41);
      expect(country.symbol, 'CH');
      expect(country.name, 'Switzerland');
      expect(country.foreignName, 'Schweiz');
    });
  });

  group('$UserDto.fromJson', () {
    test('parses mail + kyc', () {
      final dto = UserDto.fromJson({
        'mail': 'a@b.com',
        'kyc': {'hash': 'kyc-1', 'level': 30, 'dataComplete': true},
      });

      expect(dto.mail, 'a@b.com');
      expect(dto.kyc.hash, 'kyc-1');
      expect(dto.kyc.level, KycLevel.level30);
      expect(dto.kyc.dataComplete, isTrue);
    });

    test('mail is optional', () {
      final dto = UserDto.fromJson({
        'kyc': {'hash': 'kyc-1', 'level': 0, 'dataComplete': false},
      });

      expect(dto.mail, isNull);
      expect(dto.kyc.dataComplete, isFalse);
    });
  });

  group('$RealUnitRegistrationInfoDto.fromJson', () {
    test('parses AddWallet + userData branch', () {
      final dto = RealUnitRegistrationInfoDto.fromJson({
        'state': 'AddWallet',
        'userData': _userDataJson(),
      });

      expect(dto.state, RealUnitRegistrationState.addWallet);
      expect(dto.realUnitUserDataDto, isNotNull);
      expect(dto.realUnitUserDataDto!.email, 'a@b.com');
    });

    test('parses AlreadyRegistered with null userData', () {
      final dto = RealUnitRegistrationInfoDto.fromJson({
        'state': 'AlreadyRegistered',
        'userData': null,
      });

      expect(dto.state, RealUnitRegistrationState.alreadyRegistered);
      expect(dto.realUnitUserDataDto, isNull);
    });

    test('parses NewRegistration with pre-fill userData', () {
      final dto = RealUnitRegistrationInfoDto.fromJson({
        'state': 'NewRegistration',
        'userData': _userDataJson(),
      });

      expect(dto.state, RealUnitRegistrationState.newRegistration);
      expect(dto.realUnitUserDataDto, isNotNull);
    });

    test('parses NewRegistration with null userData (first-time user → empty form)', () {
      final dto = RealUnitRegistrationInfoDto.fromJson({
        'state': 'NewRegistration',
        'userData': null,
      });

      expect(dto.state, RealUnitRegistrationState.newRegistration);
      expect(dto.realUnitUserDataDto, isNull);
    });

    test('throws ArgumentError on unknown state', () {
      expect(
        () => RealUnitRegistrationInfoDto.fromJson({
          'state': 'Bogus',
          'userData': null,
        }),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('parses emailConfirmed + confirmedDate when present', () {
      final dto = RealUnitRegistrationInfoDto.fromJson({
        'state': 'AlreadyRegistered',
        'userData': null,
        'emailConfirmed': true,
        'confirmedDate': '2026-07-11T10:20:30.000Z',
      });

      expect(dto.emailConfirmed, isTrue);
      expect(dto.confirmedDate, DateTime.parse('2026-07-11T10:20:30.000Z'));
    });

    test('parses emailConfirmed=false with no confirmedDate', () {
      final dto = RealUnitRegistrationInfoDto.fromJson({
        'state': 'AlreadyRegistered',
        'userData': null,
        'emailConfirmed': false,
      });

      expect(dto.emailConfirmed, isFalse);
      expect(dto.confirmedDate, isNull);
    });

    test('legacy fallback: emailConfirmed + confirmedDate absent → null', () {
      final dto = RealUnitRegistrationInfoDto.fromJson({
        'state': 'AlreadyRegistered',
        'userData': null,
      });

      expect(dto.emailConfirmed, isNull);
      expect(dto.confirmedDate, isNull);
    });

    test('parses manualReview=true', () {
      final dto = RealUnitRegistrationInfoDto.fromJson({
        'state': 'AlreadyRegistered',
        'userData': null,
        'manualReview': true,
      });

      expect(dto.manualReview, isTrue);
    });

    test('parses manualReview=false', () {
      final dto = RealUnitRegistrationInfoDto.fromJson({
        'state': 'AlreadyRegistered',
        'userData': null,
        'manualReview': false,
      });

      expect(dto.manualReview, isFalse);
    });

    test('legacy fallback: manualReview absent → null', () {
      final dto = RealUnitRegistrationInfoDto.fromJson({
        'state': 'AlreadyRegistered',
        'userData': null,
      });

      expect(dto.manualReview, isNull);
    });

    test('throws on a present but unparseable confirmedDate (fail loud)', () {
      expect(
        () => RealUnitRegistrationInfoDto.fromJson({
          'state': 'AlreadyRegistered',
          'userData': null,
          'emailConfirmed': true,
          'confirmedDate': 'not-a-date',
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('$RealUnitUserDataDto.fromJson', () {
    test('parses every field on the happy path (no countryAndTINs)', () {
      final dto = RealUnitUserDataDto.fromJson(_userDataJson());

      expect(dto.email, 'a@b.com');
      expect(dto.name, 'Ada Lovelace');
      expect(dto.type, 'HUMAN');
      expect(dto.swissTaxResidence, isTrue);
      expect(dto.countryAndTINs, isNull);
      expect(dto.kycData.firstName, 'Ada');
    });

    test('parses countryAndTINs when provided', () {
      final json = _userDataJson()
        ..['countryAndTINs'] = [
          {'country': 'CH', 'tin': '756.1234.5678.97'},
        ];

      final dto = RealUnitUserDataDto.fromJson(json);

      expect(dto.countryAndTINs, hasLength(1));
      expect(dto.countryAndTINs!.first.tin, '756.1234.5678.97');
    });
  });
}

Map<String, dynamic> _userDataJson() => {
  'email': 'a@b.com',
  'name': 'Ada Lovelace',
  'type': 'HUMAN',
  'phoneNumber': '+41 79 000 00 00',
  'birthday': '1815-12-10',
  'nationality': 'CH',
  'addressStreet': 'Bahnhofstrasse 1',
  'addressPostalCode': '8000',
  'addressCity': 'Zurich',
  'addressCountry': 'CH',
  'swissTaxResidence': true,
  'lang': 'de',
  'kycData': {
    'accountType': 'Personal',
    'firstName': 'Ada',
    'lastName': 'Lovelace',
    'phone': '+41 79 000 00 00',
    'address': {
      'street': 'Bahnhofstrasse',
      'houseNumber': '1',
      'zip': '8000',
      'city': 'Zurich',
      'country': {'id': 41},
    },
  },
};
