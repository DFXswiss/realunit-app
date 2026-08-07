import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/storage/secure_storage.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

// The SecureStorage keys migrateSecurityFlags moves the flags into. These mirror
// the private constants in SecureStorage; asserting the literal keys pins the
// migration contract — a rename here is a storage-migration event, not a
// refactor, so the test is meant to break if the target key ever changes.
const _biometricEnabledKey = 'biometric.enabled';
const _pinFailedAttemptsKey = 'pin.failedAttempts';
const _pinLockedUntilKey = 'pin.lockedUntil';

// The SecureStorage key the SQLCipher database encryption key lives under
// (mirrors SecureStorage's private `_databaseEncryptionKey`).
const _databaseEncryptionKey = 'drift.encryption.password';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockFlutterSecureStorage mockStorage;
  late SecureStorage secureStorage;

  setUp(() {
    mockStorage = _MockFlutterSecureStorage();
    secureStorage = SecureStorage.withStorage(mockStorage);
    when(() => mockStorage.write(key: any(named: 'key'), value: any(named: 'value')))
        .thenAnswer((_) async {});
  });

  group('migrateSecurityFlags', () {
    test('moves a stored biometric flag into secure storage and clears the pref', () async {
      SharedPreferences.setMockInitialValues({'isBiometricEnabled': true});
      final prefs = await SharedPreferences.getInstance();

      await migrateSecurityFlags(prefs, secureStorage);

      verify(() => mockStorage.write(key: _biometricEnabledKey, value: 'true')).called(1);
      expect(prefs.getBool('isBiometricEnabled'), isNull);
    });

    test('moves the PIN lockout attempt counter and clears the pref', () async {
      SharedPreferences.setMockInitialValues({'pinFailedAttempts': 3});
      final prefs = await SharedPreferences.getInstance();

      await migrateSecurityFlags(prefs, secureStorage);

      verify(() => mockStorage.write(key: _pinFailedAttemptsKey, value: '3')).called(1);
      expect(prefs.getInt('pinFailedAttempts'), isNull);
    });

    test('moves a valid lockout timestamp and clears the pref', () async {
      final until = DateTime.utc(2030, 1, 2, 3, 4, 5);
      SharedPreferences.setMockInitialValues({'pinLockedUntil': until.toIso8601String()});
      final prefs = await SharedPreferences.getInstance();

      await migrateSecurityFlags(prefs, secureStorage);

      verify(() => mockStorage.write(key: _pinLockedUntilKey, value: until.toIso8601String()))
          .called(1);
      expect(prefs.getString('pinLockedUntil'), isNull);
    });

    test('drops an unparseable lockout timestamp without writing it but still clears the pref',
        () async {
      SharedPreferences.setMockInitialValues({'pinLockedUntil': 'not-a-date'});
      final prefs = await SharedPreferences.getInstance();

      await migrateSecurityFlags(prefs, secureStorage);

      verifyNever(() => mockStorage.write(key: _pinLockedUntilKey, value: any(named: 'value')));
      expect(prefs.getString('pinLockedUntil'), isNull);
    });

    test('always clears the legacy isPinEnabled flag', () async {
      SharedPreferences.setMockInitialValues({'isPinEnabled': true});
      final prefs = await SharedPreferences.getInstance();

      await migrateSecurityFlags(prefs, secureStorage);

      expect(prefs.getBool('isPinEnabled'), isNull);
    });

    test('is a no-op on a clean install: nothing migrated, no secure writes', () async {
      SharedPreferences.setMockInitialValues(const <String, Object>{});
      final prefs = await SharedPreferences.getInstance();

      await migrateSecurityFlags(prefs, secureStorage);

      verifyNever(() => mockStorage.write(key: any(named: 'key'), value: any(named: 'value')));
    });

    test('migrates a zero attempt counter (0 is a stored value, not "absent")', () async {
      // getInt returns 0 for a stored 0; the migration must treat that as a real
      // value to move, not skip it as if the key were missing.
      SharedPreferences.setMockInitialValues({'pinFailedAttempts': 0});
      final prefs = await SharedPreferences.getInstance();

      await migrateSecurityFlags(prefs, secureStorage);

      verify(() => mockStorage.write(key: _pinFailedAttemptsKey, value: '0')).called(1);
      expect(prefs.getInt('pinFailedAttempts'), isNull);
    });

    test('migrates every flag in one pass without interference', () async {
      final until = DateTime.utc(2031, 6, 7, 8, 9, 10);
      SharedPreferences.setMockInitialValues({
        'isBiometricEnabled': false,
        'pinFailedAttempts': 5,
        'pinLockedUntil': until.toIso8601String(),
        'isPinEnabled': true,
      });
      final prefs = await SharedPreferences.getInstance();

      await migrateSecurityFlags(prefs, secureStorage);

      verify(() => mockStorage.write(key: _biometricEnabledKey, value: 'false')).called(1);
      verify(() => mockStorage.write(key: _pinFailedAttemptsKey, value: '5')).called(1);
      verify(() => mockStorage.write(key: _pinLockedUntilKey, value: until.toIso8601String()))
          .called(1);
      expect(prefs.getBool('isBiometricEnabled'), isNull);
      expect(prefs.getInt('pinFailedAttempts'), isNull);
      expect(prefs.getString('pinLockedUntil'), isNull);
      expect(prefs.getBool('isPinEnabled'), isNull);
    });

    test('is idempotent: a second pass migrates nothing (prefs already cleared)', () async {
      SharedPreferences.setMockInitialValues({'pinFailedAttempts': 2});
      final prefs = await SharedPreferences.getInstance();

      await migrateSecurityFlags(prefs, secureStorage);
      await migrateSecurityFlags(prefs, secureStorage);

      // Written exactly once: the second pass sees the cleared pref and is a
      // no-op, matching the idempotency the dartdoc promises.
      verify(() => mockStorage.write(key: _pinFailedAttemptsKey, value: '2')).called(1);
    });
  });

  group('setupEssentials (encryption-key lifecycle)', () {
    // setupEssentials registers SharedPreferences / SettingsRepository /
    // SecureStorage into the global getIt; reset it around each case so
    // registrations never leak between tests.
    setUp(() async {
      await getIt.reset();
      SharedPreferences.setMockInitialValues(const <String, Object>{});
    });
    tearDown(() => getIt.reset());

    test('returns the stored key untouched and never even probes the database', () async {
      when(() => mockStorage.read(key: _databaseEncryptionKey))
          .thenAnswer((_) async => 'deadbeef');

      final key = await setupEssentials(
        secureStorage: secureStorage,
        // A stored key must short-circuit before the db-existence check: a
        // returning user's boot must not depend on the database probe. `fail`
        // trips the test if the guard is ever consulted on this path.
        databaseFileExists: () async => fail('database must not be probed when a key exists'),
      );

      expect(key, 'deadbeef');
      verifyNever(
        () => mockStorage.write(key: _databaseEncryptionKey, value: any(named: 'value')),
      );
    });

    test('mints, stores and returns a fresh key on a clean first boot, dropping the stale wallet id',
        () async {
      SharedPreferences.setMockInitialValues({'currentWalletId': 7});
      when(() => mockStorage.read(key: _databaseEncryptionKey)).thenAnswer((_) async => null);

      final key = await setupEssentials(
        secureStorage: secureStorage,
        databaseFileExists: () async => false,
      );

      // getNewEncryptionKey() mints 32 random bytes → 64 lowercase hex chars.
      expect(key, matches(RegExp(r'^[0-9a-f]{64}$')));
      verify(() => mockStorage.write(key: _databaseEncryptionKey, value: key)).called(1);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getInt('currentWalletId'),
        isNull,
        reason: 'a clean first boot must drop any stale current-wallet pointer',
      );
    });

    test('fails loud when a database exists but its key is missing — never silently re-keys',
        () async {
      when(() => mockStorage.read(key: _databaseEncryptionKey)).thenAnswer((_) async => null);

      await expectLater(
        setupEssentials(
          secureStorage: secureStorage,
          databaseFileExists: () async => true,
        ),
        // Match the specific guard message so the test can't pass for the wrong
        // reason (an unrelated earlier throw) — this is the security assertion.
        throwsA(
          isA<Exception>().having((e) => e.toString(), 'toString()', contains('key is missing')),
        ),
      );

      // Must NOT mint or persist a key when a DB is present without one —
      // that would strand the still-encrypted data behind a fresh key.
      verifyNever(
        () => mockStorage.write(key: _databaseEncryptionKey, value: any(named: 'value')),
      );
    });
  });
}
