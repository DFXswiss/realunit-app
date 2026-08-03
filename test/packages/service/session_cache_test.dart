import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/repository/cache_repository.dart';
import 'package:realunit_wallet/packages/service/session_cache.dart';

class _MockCacheRepository extends Mock implements CacheRepository {}

void main() {
  late _MockCacheRepository repo;
  late SessionCache cache;

  setUp(() {
    repo = _MockCacheRepository();
    cache = SessionCache(repo);
    when(() => repo.write(any(), any())).thenAnswer((_) async => 1);
    when(() => repo.delete(any())).thenAnswer((_) async {});
  });

  group('$SessionCache', () {
    group('auth token', () {
      test('starts null', () {
        expect(cache.authToken, isNull);
        expect(cache.authTokenAddress, isNull);
      });

      test('setAuthToken stores in memory only', () {
        cache.setAuthToken('jwt-123', '0xabc');

        expect(cache.authToken, 'jwt-123');
        expect(cache.authTokenAddress, '0xabc');
        // setAuthToken must NEVER touch the repository — JWTs live for one
        // session and persisting them to disk would defeat that lifetime.
        verifyNever(() => repo.write(any(), any()));
      });

      test('clearAuthToken resets to null without touching the repository', () {
        cache.setAuthToken('jwt-123', '0xabc');

        cache.clearAuthToken();

        expect(cache.authToken, isNull);
        expect(cache.authTokenAddress, isNull);
        verifyNever(() => repo.write(any(), any()));
        verifyNever(() => repo.delete(any()));
      });
    });

    group('signature', () {
      test('starts null', () {
        expect(cache.signature, isNull);
        expect(cache.signatureAddress, isNull);
        expect(cache.signedMessage, isNull);
      });

      test('saveSignature writes signature, address, and message to the repo', () async {
        await cache.saveSignature('0xabc', '0xsig', 'sign-message');

        expect(cache.signature, '0xsig');
        expect(cache.signatureAddress, '0xabc');
        expect(cache.signedMessage, 'sign-message');
        verify(() => repo.write('cached_signature', '0xsig')).called(1);
        verify(() => repo.write('cached_signature_address', '0xabc')).called(1);
        verify(() => repo.write('cached_signature_message', 'sign-message')).called(1);
      });

      test('loadSignature populates from the repo when memory is empty', () async {
        when(() => repo.read('cached_signature')).thenAnswer((_) async => '0xsig');
        when(() => repo.read('cached_signature_address')).thenAnswer((_) async => '0xabc');
        when(() => repo.read('cached_signature_message'))
            .thenAnswer((_) async => 'sign-message');

        await cache.loadSignature();

        expect(cache.signature, '0xsig');
        expect(cache.signatureAddress, '0xabc');
        expect(cache.signedMessage, 'sign-message');
      });

      test('loadSignature does not overwrite an in-memory signature', () async {
        await cache.saveSignature('0xabc', '0xsig', 'sign-message');
        when(() => repo.read(any())).thenAnswer((_) async => 'wrong');

        await cache.loadSignature();

        expect(cache.signature, '0xsig');
        expect(cache.signatureAddress, '0xabc');
        expect(cache.signedMessage, 'sign-message');
        verifyNever(() => repo.read(any()));
      });

      test('loadSignature tolerates a missing entry in the repo', () async {
        when(() => repo.read(any())).thenAnswer((_) async => null);

        await cache.loadSignature();

        expect(cache.signature, isNull);
        expect(cache.signatureAddress, isNull);
        expect(cache.signedMessage, isNull);
      });

      test('loadSignature keeps a legacy entry without a message scope', () async {
        when(() => repo.read('cached_signature')).thenAnswer((_) async => '0xlegacy');
        when(() => repo.read('cached_signature_address')).thenAnswer((_) async => '0xabc');
        when(() => repo.read('cached_signature_message')).thenAnswer((_) async => null);

        await cache.loadSignature();

        expect(cache.signature, '0xlegacy');
        expect(cache.signatureAddress, '0xabc');
        expect(cache.signedMessage, isNull);
      });
    });

    group('clear', () {
      test('removes all signature keys and resets auth token + memory', () async {
        cache.setAuthToken('jwt-123', '0xabc');
        await cache.saveSignature('0xabc', '0xsig', 'sign-message');
        clearInteractions(repo);
        when(() => repo.delete(any())).thenAnswer((_) async {});

        await cache.clear();

        expect(cache.authToken, isNull);
        expect(cache.authTokenAddress, isNull);
        expect(cache.signature, isNull);
        expect(cache.signatureAddress, isNull);
        expect(cache.signedMessage, isNull);
        verify(() => repo.delete('cached_signature')).called(1);
        verify(() => repo.delete('cached_signature_address')).called(1);
        verify(() => repo.delete('cached_signature_message')).called(1);
      });
    });
  });
}
