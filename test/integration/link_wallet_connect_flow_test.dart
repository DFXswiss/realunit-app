// Cross-layer integration tests for the BitBox-gated "add wallet" (link_wallet)
// KYC step.
//
// These stitch the real `KycLinkWalletCubit` together with a real
// `RealUnitRegistrationService`, the real `Eip712Signer`, a
// `FakeBitboxCredentials` standing in for the hardware-wallet sign boundary,
// and a `MockClient` HTTP boundary — only the device transport and the network
// are faked, the orchestration runs through production code.
//
// They pin the seam the unit/widget suites only cover in isolation: a
// disconnected BitBox must surface as `KycLinkWalletBitboxRequired` (never a
// dead-end) WITHOUT touching the API, and once the device connects,
// `retrySubmit` must drive `registerWallet` (sign + POST) to a completed
// registration.
//
// The pairing ceremony itself (scan / init / channel-hash / confirm) is the
// subject of `connect_bitbox_flow_test.dart`; here we flip
// `FakeBitboxCredentials.behavior` from `disconnect` to `success` to model
// "the user connected the BitBox via that ceremony".

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/config/network_mode.dart';
import 'package:realunit_wallet/packages/repository/cache_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/kyc/kyc_personal_data.dart';
import 'package:realunit_wallet/packages/service/dfx/models/user/dto/real_unit_user_data_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_registration_service.dart';
import 'package:realunit_wallet/packages/service/session_cache.dart';
import 'package:realunit_wallet/packages/service/wallet_service.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/packages/wallet/wallet_account.dart';
import 'package:realunit_wallet/screens/kyc/steps/link_wallet/cubits/kyc_link_wallet_cubit.dart';

import '../helper/fake_bitbox_credentials.dart';

class _MockAppStore extends Mock implements AppStore {}

class _MockWallet extends Mock implements AWallet {}

class _MockAccount extends Mock implements AWalletAccount {}

class _MockCacheRepository extends Mock implements CacheRepository {}

class _MockWalletService extends Mock implements WalletService {}

const _userData = RealUnitUserDataDto(
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
    address: KycAddress(street: 'Bahnhofstrasse', zip: '8000', city: 'Zurich', country: 41),
  ),
);

void main() {
  late _MockAppStore appStore;
  late _MockWallet wallet;
  late _MockAccount account;
  late _MockWalletService walletService;
  late SessionCache session;
  late FakeBitboxCredentials credentials;

  setUp(() {
    appStore = _MockAppStore();
    wallet = _MockWallet();
    account = _MockAccount();
    walletService = _MockWalletService();
    session = SessionCache(_MockCacheRepository());
    session.setAuthToken('jwt-1');
    // signDelay zero keeps the ceremony synchronous-ish for tight assertions.
    credentials = FakeBitboxCredentials(signDelay: Duration.zero);

    when(() => appStore.apiConfig).thenReturn(const ApiConfig(networkMode: NetworkMode.mainnet));
    when(() => appStore.sessionCache).thenReturn(session);
    when(() => appStore.wallet).thenReturn(wallet);
    when(() => wallet.primaryAccount).thenReturn(account);
    when(() => account.primaryAddress).thenReturn(credentials);
    when(() => walletService.ensureCurrentWalletUnlocked()).thenAnswer((_) async {});
    when(() => walletService.lockCurrentWallet()).thenAnswer((_) async {});
  });

  KycLinkWalletCubit buildCubit(http.Client client) {
    when(() => appStore.httpClient).thenReturn(client);
    return KycLinkWalletCubit(RealUnitRegistrationService(appStore, walletService), _userData);
  }

  group('$KycLinkWalletCubit × RealUnitRegistrationService × FakeBitboxCredentials', () {
    test(
      'submit with a disconnected BitBox surfaces BitboxRequired and never reaches the API',
      () async {
        credentials.behavior = FakeBitboxBehavior.disconnect;
        var posts = 0;
        final client = MockClient((request) async {
          if (request.url.path == '/v1/realunit/register/date') {
            return http.Response(jsonEncode({'date': '2026-07-13'}), 200);
          }
          posts++;
          return http.Response(jsonEncode({'status': 'completed'}), 201);
        });
        final cubit = buildCubit(client);
        addTearDown(cubit.close);

        await cubit.submit(_userData);

        expect(cubit.state, isA<KycLinkWalletBitboxRequired>());
        expect(
          posts,
          0,
          reason: 'the EIP-712 sign throws BitboxNotConnectedException before the register POST',
        );
        // The wallet is unlocked for the ceremony and re-locked in the finally
        // even though signing throws.
        verify(() => walletService.ensureCurrentWalletUnlocked()).called(1);
        verify(() => walletService.lockCurrentWallet()).called(1);
      },
    );

    test(
      'retrySubmit after the BitBox connects signs and POSTs to /register/wallet → Success',
      () async {
        credentials.behavior = FakeBitboxBehavior.success;
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
        final cubit = buildCubit(client);
        addTearDown(cubit.close);

        await cubit.retrySubmit(_userData);

        expect(cubit.state, isA<KycLinkWalletSuccess>());
        expect(sentUri!.path, '/v1/realunit/register/wallet');
        expect(body!['walletAddress'], credentials.address.hexEip55);
        // 65-byte ECDSA signature → 0x + 130 hex chars.
        expect((body!['signature'] as String).length, 132);
        // The signed registrationDate is the server-provided date.
        expect(body!['registrationDate'], '2026-07-13');
      },
    );

    test(
      'end-to-end reconnect: disconnected submit → BitboxRequired → connect → retry → Success',
      () async {
        Uri? sentUri;
        final client = MockClient((request) async {
          if (request.url.path == '/v1/realunit/register/date') {
            return http.Response(jsonEncode({'date': '2026-07-13'}), 200);
          }
          sentUri = request.url;
          return http.Response(jsonEncode({'status': 'completed'}), 201);
        });
        final cubit = buildCubit(client);
        addTearDown(cubit.close);

        final emitted = <KycLinkWalletState>[];
        final sub = cubit.stream.listen(emitted.add);
        addTearDown(sub.cancel);

        // Phase 1 — no BitBox: the add-wallet attempt must park on the connect
        // prompt, not fail.
        credentials.behavior = FakeBitboxBehavior.disconnect;
        await cubit.submit(_userData);
        expect(cubit.state, isA<KycLinkWalletBitboxRequired>());
        expect(sentUri, isNull, reason: 'no POST before the device can sign');

        // Phase 2 — the user connects the BitBox (the pairing ceremony lives in
        // connect_bitbox_flow_test); the same credentials instance now signs.
        credentials.behavior = FakeBitboxBehavior.success;
        await cubit.retrySubmit(_userData);

        expect(cubit.state, isA<KycLinkWalletSuccess>());
        expect(sentUri!.path, '/v1/realunit/register/wallet');
        // Flush the broadcast-stream queue so the final emit reaches the
        // listener before we assert the full transition order.
        await pumpEventQueue();
        expect(
          emitted.map((s) => s.runtimeType).toList(),
          [
            KycLinkWalletSubmitting,
            KycLinkWalletBitboxRequired,
            KycLinkWalletSubmitting,
            KycLinkWalletSuccess,
          ],
        );
        // One throwing attempt + one successful attempt — the retry actually
        // re-engaged the device rather than replaying a cached result.
        expect(credentials.signCallCount, 2);
      },
    );
  });
}
