import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/repository/cache_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_widget_service.dart';
import 'package:realunit_wallet/packages/service/session_cache.dart';
import 'package:realunit_wallet/packages/service/wallet_service.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';

class _MockAppStore extends Mock implements AppStore {}

class _MockCacheRepository extends Mock implements CacheRepository {}

class _MockWalletService extends Mock implements WalletService {}

const _testMnemonic =
    'test test test test test test test test test test test junk';

void main() {
  late _MockAppStore appStore;
  late _MockWalletService walletService;
  late SessionCache sessionCache;
  late SoftwareWallet wallet;

  setUp(() {
    appStore = _MockAppStore();
    walletService = _MockWalletService();
    sessionCache = SessionCache(_MockCacheRepository());
    wallet = SoftwareWallet(1, 'Main', _testMnemonic);
    when(() => appStore.sessionCache).thenReturn(sessionCache);
    when(() => appStore.wallet).thenReturn(wallet);
    when(() => walletService.ensureCurrentWalletUnlocked()).thenAnswer((_) async {});
    when(() => walletService.lockCurrentWallet()).thenAnswer((_) async {});
  });

  group('$DfxWidgetService', () {
    test('wallet getter returns appStore.wallet.currentAccount', () {
      final service = DfxWidgetService(appStore, walletService);

      expect(service.wallet, same(wallet.currentAccount));
    });

    test('walletAddress is the EIP-55 hex of the current account primaryAddress', () {
      final service = DfxWidgetService(appStore, walletService);

      // Hardhat #0 EIP-55.
      expect(
        service.walletAddress,
        '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266',
      );
    });

    test('isAvailable=false when no auth token is set', () {
      expect(DfxWidgetService(appStore, walletService).isAvailable, isFalse);
    });

    test('isAvailable=true once an auth token is set', () {
      sessionCache.setAuthToken(
        'jwt-1',
        wallet.currentAccount.primaryAddress.address.hexEip55,
      );

      expect(DfxWidgetService(appStore, walletService).isAvailable, isTrue);
    });

    test('isAvailable flips back to false after clearAuthToken', () {
      sessionCache.setAuthToken(
        'jwt-1',
        wallet.currentAccount.primaryAddress.address.hexEip55,
      );
      final service = DfxWidgetService(appStore, walletService);
      expect(service.isAvailable, isTrue);

      sessionCache.clearAuthToken();

      expect(service.isAvailable, isFalse);
    });
  });
}
