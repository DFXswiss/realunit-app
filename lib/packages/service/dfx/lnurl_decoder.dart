/// Decodes an Open CryptoPay POS QR into the DFX lnurlp payment-link id and the
/// API URL the app must read the quote from.
///
/// Two encodings are supported, both pointing at the single allowed DFX host:
///   1. A LUD-01 bech32 `LNURL1...` string (carried in the `lightning` query
///      parameter of an `https://app.dfx.swiss/pl/?lightning=LNURL1...` QR).
///      Decoding the bech32 yields the wrapped `https://api.dfx.swiss/v1/lnurlp/pl_...`
///      URL directly.
///   2. A plain `https://app.dfx.swiss/v1/lnurlp/pl_...` (or `/pl/?...`) URL,
///      where the `app` host is rewritten to `api` as a fallback.
///
/// Only `app.dfx.swiss` / `api.dfx.swiss` (and their `dev.` testnet twins) are
/// accepted — any other host is rejected so a malicious QR cannot redirect the
/// authenticated quote read to a third party.
library;

import 'package:realunit_wallet/packages/service/dfx/exceptions/payment/pay_exceptions.dart';

class DecodedPaymentLink {
  /// Fully-qualified `https://<api-host>/v1/lnurlp/<id>` URL the app reads the
  /// OCP quote from.
  final Uri lnurlpUrl;

  /// The payment-link id (e.g. `pl_...` / `plp_...`).
  final String id;

  const DecodedPaymentLink({required this.lnurlpUrl, required this.id});
}

abstract final class LnurlDecoder {
  static const _allowedHosts = {
    'api.dfx.swiss',
    'app.dfx.swiss',
    'dev.api.dfx.swiss',
    'dev.app.dfx.swiss',
  };

  // bech32 character set (BIP-173). Index in this string is the 5-bit value.
  static const _charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';

  /// Decodes [raw] — the full scanned QR payload — into a [DecodedPaymentLink].
  ///
  /// Throws [InvalidPaymentLinkException] when the payload is neither a
  /// DFX-hosted lnurlp URL nor a bech32 LNURL wrapping one.
  static DecodedPaymentLink decode(String raw) {
    final input = raw.trim();
    if (input.isEmpty) {
      throw const InvalidPaymentLinkException('Empty payment code');
    }

    final lightning = _extractLightningParam(input);
    final target = lightning != null ? _decodeBech32(lightning) : input;

    final uri = _parseHttpUri(target);
    final apiUri = _toApiUri(uri);
    final id = _extractId(apiUri);

    return DecodedPaymentLink(lnurlpUrl: apiUri, id: id);
  }

  /// Pulls the `lightning=` value out of a wrapper URL/URI, or returns the raw
  /// bech32 when the scan is a bare `lightning:LNURL1...` / `LNURL1...` string.
  static String? _extractLightningParam(String input) {
    final upper = input.toUpperCase();
    if (upper.startsWith('LNURL1')) return input;
    if (upper.startsWith('LIGHTNING:')) return input.substring('lightning:'.length);

    final uri = Uri.tryParse(input);
    final value = uri?.queryParameters['lightning'];
    if (value != null && value.toUpperCase().startsWith('LNURL1')) return value;
    return null;
  }

  static Uri _parseHttpUri(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw InvalidPaymentLinkException('Not a payment link: $value');
    }
    return uri;
  }

  /// Rewrites an allowed `app.dfx.swiss` host to its `api.dfx.swiss` twin and
  /// forces https. Rejects any non-DFX host.
  static Uri _toApiUri(Uri uri) {
    if (!_allowedHosts.contains(uri.host)) {
      throw InvalidPaymentLinkException('Unsupported payment host: ${uri.host}');
    }
    final apiHost = uri.host.replaceFirst('app.dfx.swiss', 'api.dfx.swiss');
    return uri.replace(scheme: 'https', host: apiHost);
  }

  /// Extracts the `pl_...` / `plp_...` id from the lnurlp path.
  static String _extractId(Uri uri) {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final lnurlpIndex = segments.indexOf('lnurlp');
    final candidate = (lnurlpIndex != -1 && lnurlpIndex + 1 < segments.length)
        ? segments[lnurlpIndex + 1]
        : (segments.isNotEmpty ? segments.last : null);
    if (candidate != null && _hasValidPaymentLinkPrefix(candidate)) return candidate;
    throw InvalidPaymentLinkException('No payment id in: $uri');
  }

  static bool _hasValidPaymentLinkPrefix(String id) =>
      id.startsWith('pl_') || id.startsWith('plp_');

  /// Decodes a LUD-01 bech32 `LNURL1...` string to its wrapped UTF-8 URL.
  ///
  /// LUD-01 deliberately drops the 90-char BIP-173 length limit, so only the
  /// charset, the 1-byte-per-char separation, and the 6-char checksum are
  /// validated here.
  static String _decodeBech32(String bech) {
    final lower = bech.toLowerCase();
    final sepIndex = lower.lastIndexOf('1');
    if (sepIndex < 1 || sepIndex + 7 > lower.length) {
      throw InvalidPaymentLinkException('Malformed LNURL: $bech');
    }

    final hrp = lower.substring(0, sepIndex);
    final dataPart = lower.substring(sepIndex + 1);

    final data = <int>[];
    for (final char in dataPart.split('')) {
      final value = _charset.indexOf(char);
      if (value == -1) {
        throw InvalidPaymentLinkException('Invalid LNURL character: $char');
      }
      data.add(value);
    }

    if (!_verifyChecksum(hrp, data)) {
      throw const InvalidPaymentLinkException('Invalid LNURL checksum');
    }

    // Drop the 6-symbol checksum, then regroup 5-bit → 8-bit.
    final payload = data.sublist(0, data.length - 6);
    final bytes = _convertBitsTo8(payload);
    return String.fromCharCodes(bytes);
  }

  /// Regroups 5-bit bech32 symbols into 8-bit bytes (no padding — the LNURL
  /// payload is always a whole number of bytes). Rejects leftover bits that
  /// cannot form a full byte, which signals a corrupt data section.
  static List<int> _convertBitsTo8(List<int> data) {
    const from = 5;
    const to = 8;
    var acc = 0;
    var bits = 0;
    final result = <int>[];
    const maxv = (1 << to) - 1;
    for (final value in data) {
      acc = (acc << from) | value;
      bits += from;
      while (bits >= to) {
        bits -= to;
        result.add((acc >> bits) & maxv);
      }
    }
    // Defensive bech32 invariant: a checksum-valid LNURL payload always
    // regroups into whole bytes, so this only trips on corrupt-yet-checksum-
    // passing input, which the preceding checksum verify already rules out.
    if (bits >= from || ((acc << (to - bits)) & maxv) != 0) {
      throw const InvalidPaymentLinkException('Invalid LNURL padding'); // coverage:ignore-line
    }
    return result;
  }

  static int _polymod(List<int> values) {
    const generator = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3];
    var chk = 1;
    for (final value in values) {
      final top = chk >> 25;
      chk = ((chk & 0x1ffffff) << 5) ^ value;
      for (var i = 0; i < 5; i++) {
        if (((top >> i) & 1) == 1) chk ^= generator[i];
      }
    }
    return chk;
  }

  static List<int> _hrpExpand(String hrp) {
    final result = <int>[];
    for (final c in hrp.codeUnits) {
      result.add(c >> 5);
    }
    result.add(0);
    for (final c in hrp.codeUnits) {
      result.add(c & 31);
    }
    return result;
  }

  static bool _verifyChecksum(String hrp, List<int> data) {
    return _polymod([..._hrpExpand(hrp), ...data]) == 1;
  }
}
