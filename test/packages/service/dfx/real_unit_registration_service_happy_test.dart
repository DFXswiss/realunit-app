import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/config/network_mode.dart';
import 'package:realunit_wallet/packages/repository/cache_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/country/country.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/dto/real_unit_registration_request_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/kyc/kyc_personal_data.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/registration.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/registration_status.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/registration_user_type.dart';
import 'package:realunit_wallet/packages/service/dfx/models/user/dto/real_unit_user_data_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_registration_service.dart';
import 'package:realunit_wallet/packages/service/session_cache.dart';
import 'package:realunit_wallet/packages/service/wallet_service.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/packages/wallet/wallet_account.dart';
import 'package:web3dart/web3dart.dart';

class _MockAppStore extends Mock implements AppStore {}

class _MockWallet extends Mock implements AWallet {}

class _MockAccount extends Mock implements AWalletAccount {}

class _MockCacheRepository extends Mock implements CacheRepository {}

class _MockWalletService extends Mock implements WalletService {}

const _testPrivateKeyHex = 'fb1ace12f9801e85f3db1b3935dd47d9f064f98152466f47c701b5e12680e612';

final _privKey = EthPrivateKey.fromHex(_testPrivateKeyHex);

void main() {
  late _MockAppStore appStore;
  late _MockWallet wallet;
  late _MockAccount account;
  late _MockWalletService walletService;
  late SessionCache session;

  setUp(() {
    appStore = _MockAppStore();
    wallet = _MockWallet();
    account = _MockAccount();
    walletService = _MockWalletService();
    session = SessionCache(_MockCacheRepository());
    session.setAuthToken('jwt-1');

    when(() => appStore.apiConfig).thenReturn(const ApiConfig(networkMode: NetworkMode.mainnet));
    when(() => appStore.sessionCache).thenReturn(session);
    when(() => appStore.wallet).thenReturn(wallet);
    when(() => wallet.primaryAccount).thenReturn(account);
    when(() => account.primaryAddress).thenReturn(_privKey);
    when(() => walletService.ensureCurrentWalletUnlocked()).thenAnswer((_) async {});
    when(() => walletService.lockCurrentWallet()).thenAnswer((_) async {});
  });

  RealUnitRegistrationService build(http.Client client) {
    when(() => appStore.httpClient).thenReturn(client);
    return RealUnitRegistrationService(appStore, walletService);
  }

  Registration buildRegistration({
    bool swissTaxResidence = true,
    List<CountryAndTin>? countryAndTINs,
  }) => Registration(
    type: RegistrationUserType.human,
    email: 'AdA@ExAmPlE.COM',
    // Diacritics -> must be ASCII-transliterated (ä->ae, ü->ue) for the
    // BitBox-safe wire envelope; the test asserts the transliteration
    // round-trip below.
    firstName: 'Adä',
    lastName: 'Loveläce',
    phoneNumber: '+41 79 000 00 00',
    birthday: '1815-12-10',
    nationality: const Country(
      id: 41,
      symbol: 'CH',
      name: 'Switzerland',
      kycAllowed: true,
    ),
    addressStreet: 'Bahnhofstraße',
    addressStreetNumber: '1',
    addressPostalCode: '8000',
    addressCity: 'Zürich',
    addressCountry: const Country(
      id: 41,
      symbol: 'CH',
      name: 'Switzerland',
      kycAllowed: true,
    ),
    swissTaxResidence: swissTaxResidence,
    countryAndTINs: countryAndTINs,
  );

  RealUnitUserDataDto buildUserData() => const RealUnitUserDataDto(
    email: 'a@b.com',
    name: 'Ada Lovelace',
    type: 'HUMAN',
    phoneNumber: '+41 79 000 00 00',
    birthday: '1815-12-10',
    nationality: 'CH',
    addressStreet: 'Bahnhofstrasse 1',
    addressPostalCode: '8000',
    addressCity: 'Zurich',
    addressCountry: 'CH',
    swissTaxResidence: true,
    lang: 'de',
    kycData: KycPersonalData(
      accountType: KycAccountType.personal,
      firstName: 'Ada',
      lastName: 'Lovelace',
      phone: '+41 79 000 00 00',
      address: KycAddress(
        street: 'Bahnhofstrasse',
        zip: '8000',
        city: 'Zurich',
        country: 41,
      ),
    ),
  );

  group('completeRegistration happy path', () {
    test(
      'POSTs to /v1/realunit/register/complete with the ASCII-transliterated '
      'envelope, the EIP-712 signature, and the original KYC personal data',
      () async {
        Uri? sentUri;
        Map<String, dynamic>? body;
        Map<String, String>? headers;
        final client = MockClient((request) async {
          if (request.url.path == '/v1/realunit/register/date') {
            return http.Response(jsonEncode({'date': '2026-07-13'}), 200);
          }
          sentUri = request.url;
          body = jsonDecode(request.body) as Map<String, dynamic>;
          headers = request.headers;
          return http.Response(jsonEncode({'status': 'completed'}), 201);
        });

        final status = await build(client).completeRegistration(buildRegistration());

        expect(status, RegistrationStatus.completed);
        expect(sentUri!.path, '/v1/realunit/register/complete');
        expect(headers!['authorization'], 'Bearer jwt-1');

        // The signed registrationDate must be the server-provided date, not a
        // locally-derived one — the whole point of the /register/date fetch.
        expect(body!['registrationDate'], '2026-07-13');

        // Signed envelope copy — must be ASCII-transliterated to match what
        // BitBox firmware would have signed.
        expect(body!['email'], 'ada@example.com'); // lowercased + ASCII
        // ä → ae per German transliteration convention.
        expect(body!['name'], 'Adae Lovelaece');
        expect(body!['addressStreet'], 'Bahnhofstrasse 1');
        // ü → ue, so Zürich → Zuerich.
        expect(body!['addressCity'], 'Zuerich');

        // KYC personal data keeps the original spelling so the ID
        // verification provider sees the legal name.
        final kyc = body!['kycData'] as Map<String, dynamic>;
        expect(kyc['firstName'], 'Adä');
        expect(kyc['lastName'], 'Loveläce');
        final address = kyc['address'] as Map<String, dynamic>;
        expect(address['street'], 'Bahnhofstraße');
        expect(address['city'], 'Zürich');

        // EIP-712 signature: 65 bytes → 0x + 130 hex chars.
        expect((body!['signature'] as String).length, 132);
        expect(body!['lang'], 'DE');
        expect(body!['type'], 'HUMAN');

        // A Swiss-only resident carries no `countryAndTINs`, so the DTO must
        // omit the key entirely — covers the `if (countryAndTINs != null)`
        // false branch in RealUnitRegistrationRequestDto.toJson.
        expect(body!.containsKey('countryAndTINs'), isFalse);
      },
    );

    test(
      'POSTs countryAndTINs for non-Swiss tax residence at the registration boundary',
      () async {
        Uri? sentUri;
        Map<String, dynamic>? body;
        final client = MockClient((request) async {
          if (request.url.path == '/v1/realunit/register/date') {
            return http.Response(jsonEncode({'date': '2026-07-13'}), 200);
          }
          sentUri = request.url;
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'status': 'completed'}), 201);
        });

        final status = await build(client).completeRegistration(
          buildRegistration(
            swissTaxResidence: false,
            countryAndTINs: const [
              CountryAndTin(country: 'DE', tin: '12 345 678 901'),
            ],
          ),
        );

        expect(status, RegistrationStatus.completed);
        expect(sentUri!.path, '/v1/realunit/register/complete');
        expect(body!['swissTaxResidence'], isFalse);
        expect(
          body!['countryAndTINs'],
          [
            {'country': 'DE', 'tin': '12 345 678 901'},
          ],
        );
        expect(body!['email'], 'ada@example.com');
        expect(body!['name'], 'Adae Lovelaece');
        expect(body!['addressCountry'], 'CH');
        expect(body!['walletAddress'], _privKey.address.hexEip55);
        expect((body!['signature'] as String).length, 132);
      },
    );
  });

  group('completeRegistration error path', () {
    test(
      'a 4xx response is rewrapped as ApiException carrying the backend status',
      () async {
        // Coverage pin for the `if (response.statusCode != 201 && != 202)`
        // branch in `_completeRegistration`. The disconnect test in the
        // sibling file short-circuits before the HTTP call, so the wire
        // error path stays uncovered without this.
        var calls = 0;
        final client = MockClient((request) async {
          if (request.url.path == '/v1/realunit/register/date') {
            return http.Response(jsonEncode({'date': '2026-07-13'}), 200);
          }
          calls++;
          return http.Response(
            jsonEncode({
              'statusCode': 422,
              'code': 'KYC_DECLINED',
              'message': 'kyc declined',
            }),
            422,
          );
        });

        await expectLater(
          () => build(client).completeRegistration(buildRegistration()),
          throwsA(isA<ApiException>()),
        );
        // wallet must be unlocked → ceremony → re-locked, even when the API
        // rejects the registration. The finally-block in completeRegistration
        // owes the relock.
        expect(calls, 1);
        verify(() => walletService.ensureCurrentWalletUnlocked()).called(1);
        verify(() => walletService.lockCurrentWallet()).called(1);
      },
    );
  });

  group('registerWallet error path', () {
    test(
      'a 4xx response is rewrapped as ApiException carrying the backend status',
      () async {
        // Coverage pin for the matching branch in `_registerWallet`.
        var calls = 0;
        final client = MockClient((request) async {
          if (request.url.path == '/v1/realunit/register/date') {
            return http.Response(jsonEncode({'date': '2026-07-13'}), 200);
          }
          calls++;
          return http.Response(
            jsonEncode({
              'statusCode': 409,
              'code': 'WALLET_TAKEN',
              'message': 'wallet already registered',
            }),
            409,
          );
        });

        await expectLater(
          () => build(client).registerWallet(buildUserData()),
          throwsA(isA<ApiException>()),
        );
        expect(calls, 1);
        verify(() => walletService.ensureCurrentWalletUnlocked()).called(1);
        verify(() => walletService.lockCurrentWallet()).called(1);
      },
    );
  });

  group('registerWallet happy path', () {
    test(
      'POSTs to /v1/realunit/register/wallet with walletAddress + signature + registrationDate',
      () async {
        Uri? sentUri;
        Map<String, dynamic>? body;
        final client = MockClient((request) async {
          if (request.url.path == '/v1/realunit/register/date') {
            return http.Response(jsonEncode({'date': '2026-07-13'}), 200);
          }
          sentUri = request.url;
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'status': 'completed'}), 201);
        });

        final status = await build(client).registerWallet(buildUserData());

        expect(status, RegistrationStatus.completed);
        expect(sentUri!.path, '/v1/realunit/register/wallet');
        expect(body!['walletAddress'], _privKey.address.hexEip55);
        expect((body!['signature'] as String).length, 132);
        // The signed registrationDate must be the server-provided date.
        expect(body!['registrationDate'], '2026-07-13');
      },
    );
  });

  group('getRegistrationDate', () {
    test('GETs /v1/realunit/register/date and returns the server date', () async {
      Uri? sentUri;
      String? method;
      final client = MockClient((request) async {
        sentUri = request.url;
        method = request.method;
        return http.Response(jsonEncode({'date': '2026-07-13'}), 200);
      });

      final date = await build(client).getRegistrationDate();

      expect(date, '2026-07-13');
      expect(method, 'GET');
      expect(sentUri!.path, '/v1/realunit/register/date');
    });

    test('rewraps a non-200 response as ApiException carrying the backend status', () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({'statusCode': 503, 'code': 'UNAVAILABLE', 'message': 'down'}),
          503,
        );
      });

      await expectLater(
        () => build(client).getRegistrationDate(),
        throwsA(isA<ApiException>()),
      );
    });

    test('throws when the response omits the date field (no silent fallback)', () async {
      final client = MockClient((_) async {
        return http.Response(jsonEncode({'notDate': true}), 200);
      });

      await expectLater(
        () => build(client).getRegistrationDate(),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
