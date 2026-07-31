import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/repository/balance_repository.dart';
import 'package:realunit_wallet/packages/repository/settings_repository.dart';
import 'package:realunit_wallet/packages/repository/wallet_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_pay_service.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_transfer_service.dart';
import 'package:realunit_wallet/setup/di.dart';

class _MockAppStore extends Mock implements AppStore {}

class _MockBalanceRepository extends Mock implements BalanceRepository {}

class _MockSettingsRepository extends Mock implements SettingsRepository {}

class _MockWalletRepository extends Mock implements WalletRepository {}

void main() {
  // The pay and wallet-to-wallet flows wire their backend clients through
  // `setupServices()` as factories:
  //   () => RealUnitPayService(getIt<AppStore>(), getIt<WalletService>())
  //   () => RealUnitTransferService(getIt<AppStore>(), getIt<WalletService>())
  // This test exercises both registrations and then resolves each factory.
  //
  // `setupServices()` constructs `BalanceService` (eager singleton) up front,
  // so `AppStore` + `BalanceRepository` must already be registered. Resolving
  // either service then pulls the lazy `WalletService`, whose dependencies
  // bottom out at `WalletRepository` + `SettingsRepository` + `AppStore`
  // (`BitboxService` is registered by `setupServices()` itself). Registering
  // those leaf mocks keeps the whole chain construct-only — none of the mocked
  // collaborators perform I/O on construction.
  setUp(() {
    getIt.reset();
    getIt.registerSingleton<AppStore>(_MockAppStore());
    getIt.registerSingleton<BalanceRepository>(_MockBalanceRepository());
    getIt.registerSingleton<SettingsRepository>(_MockSettingsRepository());
    getIt.registerSingleton<WalletRepository>(_MockWalletRepository());
  });

  tearDown(() => getIt.reset());

  test('setupServices registers a resolvable RealUnitPayService factory', () {
    setupServices();

    expect(getIt.isRegistered<RealUnitPayService>(), isTrue);

    final service = getIt<RealUnitPayService>();
    expect(service, isA<RealUnitPayService>());
    expect(identical(service, getIt<RealUnitPayService>()), isFalse);
  });

  test('setupServices registers a resolvable RealUnitTransferService factory', () {
    setupServices();

    expect(getIt.isRegistered<RealUnitTransferService>(), isTrue);

    final service = getIt<RealUnitTransferService>();
    expect(service, isA<RealUnitTransferService>());
    expect(identical(service, getIt<RealUnitTransferService>()), isFalse);
  });
}
