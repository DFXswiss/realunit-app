import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/packages/config/network_mode.dart';
import 'package:realunit_wallet/packages/repository/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // Initialise the binding so SharedPreferences plugin channels work.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('$SettingsRepository', () {
    group('currentWalletId', () {
      test('returns null when no value is stored', () async {
        SharedPreferences.setMockInitialValues({});
        final repo = SettingsRepository(await SharedPreferences.getInstance());

        expect(repo.currentWalletId, isNull);
      });

      test('saveCurrentWalletId persists the id', () async {
        SharedPreferences.setMockInitialValues({});
        final repo = SettingsRepository(await SharedPreferences.getInstance());

        await repo.saveCurrentWalletId(42);

        expect(repo.currentWalletId, 42);
      });

      test('removeCurrentWalletId clears the stored id', () async {
        SharedPreferences.setMockInitialValues({'currentWalletId': 7});
        final repo = SettingsRepository(await SharedPreferences.getInstance());
        expect(repo.currentWalletId, 7);

        await repo.removeCurrentWalletId();

        expect(repo.currentWalletId, isNull);
      });
    });

    group('language', () {
      test('falls back to "en" for non-German system locales', () async {
        SharedPreferences.setMockInitialValues({});
        final repo = SettingsRepository(await SharedPreferences.getInstance());

        // PlatformDispatcher.instance.locale in the test binding defaults to
        // en_US; the fallback rule says "anything non-de → en".
        expect(repo.language, 'en');
      });

      test('returns the stored language when set', () async {
        SharedPreferences.setMockInitialValues({'language': 'de'});
        final repo = SettingsRepository(await SharedPreferences.getInstance());

        expect(repo.language, 'de');
      });

      test('language setter persists', () async {
        SharedPreferences.setMockInitialValues({});
        final repo = SettingsRepository(await SharedPreferences.getInstance());

        repo.language = 'de';

        // The setter is fire-and-forget; give the platform channel a tick.
        await Future<void>.delayed(Duration.zero);
        expect(repo.language, 'de');
      });
    });

    group('currency', () {
      test('defaults to EUR when nothing is stored', () async {
        SharedPreferences.setMockInitialValues({});
        final repo = SettingsRepository(await SharedPreferences.getInstance());

        expect(repo.currency, 'EUR');
        expect(repo.hasStoredCurrency, isFalse);
      });

      test('returns the stored currency when set', () async {
        SharedPreferences.setMockInitialValues({'currency': 'EUR'});
        final repo = SettingsRepository(await SharedPreferences.getInstance());

        expect(repo.currency, 'EUR');
        expect(repo.hasStoredCurrency, isTrue);
      });

      test('currency setter persists', () async {
        SharedPreferences.setMockInitialValues({});
        final repo = SettingsRepository(await SharedPreferences.getInstance());

        repo.currency = 'EUR';
        await Future<void>.delayed(Duration.zero);

        expect(repo.currency, 'EUR');
      });
    });

    group('terms', () {
      test('defaults to false when not stored', () async {
        SharedPreferences.setMockInitialValues({});
        final repo = SettingsRepository(await SharedPreferences.getInstance());

        expect(repo.termsAccepted, isFalse);
        expect(repo.softwareTermsAccepted, isFalse);
      });

      test('termsAccepted setter persists', () async {
        SharedPreferences.setMockInitialValues({});
        final repo = SettingsRepository(await SharedPreferences.getInstance());

        repo.termsAccepted = true;
        await Future<void>.delayed(Duration.zero);

        expect(repo.termsAccepted, isTrue);
      });

      test('softwareTermsAccepted setter persists independently', () async {
        SharedPreferences.setMockInitialValues({});
        final repo = SettingsRepository(await SharedPreferences.getInstance());

        repo.softwareTermsAccepted = true;
        await Future<void>.delayed(Duration.zero);

        expect(repo.softwareTermsAccepted, isTrue);
        expect(repo.termsAccepted, isFalse);
      });
    });

    group('insiderFeaturesUnlocked', () {
      test('defaults to false when not stored', () async {
        SharedPreferences.setMockInitialValues({});
        final repo = SettingsRepository(await SharedPreferences.getInstance());

        expect(repo.insiderFeaturesUnlocked, isFalse);
      });

      test('returns the stored value when set', () async {
        SharedPreferences.setMockInitialValues({'insiderFeaturesUnlocked': true});
        final repo = SettingsRepository(await SharedPreferences.getInstance());

        expect(repo.insiderFeaturesUnlocked, isTrue);
      });

      test('setter persists', () async {
        SharedPreferences.setMockInitialValues({});
        final repo = SettingsRepository(await SharedPreferences.getInstance());

        repo.insiderFeaturesUnlocked = true;
        await Future<void>.delayed(Duration.zero);

        expect(repo.insiderFeaturesUnlocked, isTrue);
      });
    });

    group('networkMode', () {
      test('defaults to mainnet when no value is stored', () async {
        SharedPreferences.setMockInitialValues({});
        final repo = SettingsRepository(await SharedPreferences.getInstance());

        expect(repo.networkMode, NetworkMode.mainnet);
      });

      test('defaults to mainnet when stored value is unknown', () async {
        SharedPreferences.setMockInitialValues({'networkMode': 'localnet'});
        final repo = SettingsRepository(await SharedPreferences.getInstance());

        // firstWhere falls back to mainnet via orElse.
        expect(repo.networkMode, NetworkMode.mainnet);
      });

      test('returns testnet when stored under the enum constructor name', () async {
        // The setter writes `mode.name`, which is the constructor arg
        // ('Mainnet' / 'Testnet') — NOT the Dart enum identifier.
        SharedPreferences.setMockInitialValues({'networkMode': 'Testnet'});
        final repo = SettingsRepository(await SharedPreferences.getInstance());

        expect(repo.networkMode, NetworkMode.testnet);
      });

      test('networkMode setter persists by enum name', () async {
        SharedPreferences.setMockInitialValues({});
        final repo = SettingsRepository(await SharedPreferences.getInstance());

        repo.networkMode = NetworkMode.testnet;
        await Future<void>.delayed(Duration.zero);

        expect(repo.networkMode, NetworkMode.testnet);
      });
    });
  });
}
