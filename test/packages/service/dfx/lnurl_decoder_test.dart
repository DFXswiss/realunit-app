import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/payment/pay_exceptions.dart';
import 'package:realunit_wallet/packages/service/dfx/lnurl_decoder.dart';

void main() {
  group('LnurlDecoder.decode', () {
    // LUD-01 bech32 of `https://api.dfx.swiss/v1/lnurlp/pl_abc123`.
    const lnurl = 'LNURL1DP68GURN8GHJ7CTSDYHXGENC9EEHW6TNWVHHVVF0D3H82UNVWQHHQMZLV93XXVFJXV5T0E5A';

    test('decodes a bech32 LNURL to the api lnurlp url + id', () {
      final result = LnurlDecoder.decode(lnurl);

      expect(result.lnurlpUrl.toString(), 'https://api.dfx.swiss/v1/lnurlp/pl_abc123');
      expect(result.id, 'pl_abc123');
    });

    test('decodes the lightning= query param of an app.dfx.swiss wrapper URL', () {
      final result = LnurlDecoder.decode('https://app.dfx.swiss/pl/?lightning=$lnurl');

      expect(result.lnurlpUrl.host, 'api.dfx.swiss');
      expect(result.id, 'pl_abc123');
    });

    test('accepts a lowercase lnurl and a lightning: scheme prefix', () {
      final result = LnurlDecoder.decode('lightning:${lnurl.toLowerCase()}');

      expect(result.id, 'pl_abc123');
    });

    test('rewrites a plain app.dfx.swiss lnurlp url to the api host', () {
      final result = LnurlDecoder.decode('https://app.dfx.swiss/v1/lnurlp/pl_xyz');

      expect(result.lnurlpUrl.toString(), 'https://api.dfx.swiss/v1/lnurlp/pl_xyz');
      expect(result.id, 'pl_xyz');
    });

    test('keeps an already-api lnurlp url and forces https', () {
      final result = LnurlDecoder.decode('http://api.dfx.swiss/v1/lnurlp/plp_123');

      expect(result.lnurlpUrl.scheme, 'https');
      expect(result.id, 'plp_123');
    });

    test('rewrites the dev testnet host twin', () {
      final result = LnurlDecoder.decode('https://dev.app.dfx.swiss/v1/lnurlp/pl_dev');

      expect(result.lnurlpUrl.host, 'dev.api.dfx.swiss');
      expect(result.id, 'pl_dev');
    });

    test('rejects an empty code', () {
      expect(
        () => LnurlDecoder.decode('   '),
        throwsA(isA<InvalidPaymentLinkException>()),
      );
    });

    test('rejects a non-DFX host', () {
      expect(
        () => LnurlDecoder.decode('https://evil.example.com/v1/lnurlp/pl_x'),
        throwsA(isA<InvalidPaymentLinkException>()),
      );
    });

    test('rejects a non-http payload', () {
      expect(
        () => LnurlDecoder.decode('not-a-url'),
        throwsA(isA<InvalidPaymentLinkException>()),
      );
    });

    test('rejects a bech32 with an invalid checksum', () {
      // Flip the last data character to break the checksum.
      final broken = '${lnurl.substring(0, lnurl.length - 1)}Q';
      expect(
        () => LnurlDecoder.decode(broken),
        throwsA(isA<InvalidPaymentLinkException>()),
      );
    });

    test('rejects a bech32 with an invalid character in the data part', () {
      // Replace a data char with 'b' (not in the bech32 charset) while keeping
      // the overall length valid, so the per-character guard fires.
      final withBadChar = '${lnurl.substring(0, 20)}B${lnurl.substring(21)}';
      expect(
        () => LnurlDecoder.decode(withBadChar),
        throwsA(isA<InvalidPaymentLinkException>()),
      );
    });

    test('rejects a too-short bech32', () {
      expect(
        () => LnurlDecoder.decode('LNURL1bbb'),
        throwsA(isA<InvalidPaymentLinkException>()),
      );
    });

    test('falls back to the last path segment when there is no lnurlp segment', () {
      final result = LnurlDecoder.decode('https://api.dfx.swiss/pl_direct');
      expect(result.id, 'pl_direct');
    });

    test('rejects a DFX url with an empty path', () {
      expect(
        () => LnurlDecoder.decode('https://api.dfx.swiss/'),
        throwsA(isA<InvalidPaymentLinkException>()),
      );
    });
  });
}
