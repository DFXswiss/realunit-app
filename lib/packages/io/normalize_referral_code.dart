import 'dart:convert';

/// Format characters messengers inject around copied URLs (ZWSP, LRM/RLM,
/// bidi embeddings/isolates, BOM, soft hyphen).
final invisibleReferralChars = RegExp(
  r'[\u00AD\u200B-\u200F\u202A-\u202E\u2060\u2066-\u2069\uFEFF]',
);

String stripInvisibleReferralChars(String value) => value.replaceAll(invisibleReferralChars, '');

/// HTML, JSON, fullwidth, and Word compatibility folds used before
/// URL detection so a Play referrer still matches `realunit.app`.
String foldReferralPastedText(String raw) => _repairSplitUrlSchemes(_stripPastedWrappers(raw));

/// Yahoo search redirects put the landing URL in a path `RU=` segment.
String? _codeFromYahooRu(String value) {
  final match = RegExp(
    r'RU=(https?(?::|%3A)(?:/|%2F){2}[^&\s]+)',
    caseSensitive: false,
  ).firstMatch(value);
  if (match == null) return null;
  var inner = match[1]!;
  inner = inner.replaceFirst(RegExp(r'/RK=.*'), '');
  try {
    inner = Uri.decodeComponent(inner);
  } catch (_) {}
  inner = _repairSplitUrlSchemes(inner);
  if (inner.toLowerCase().contains('realunit.app')) {
    return _codeFromPastedReferralUrl(inner) ??
        referralCodeFromPathRemainder(
          inner.replaceFirst(RegExp(r'^https?://[^/]+/'), ''),
        );
  }
  return null;
}

/// Dart `Uri.pathSegments` splits `https://` so Yahoo `RU=` wrappers become
/// `RU=https:/realunit.app/…`. Put the second slash back before URL detect.
String _repairSplitUrlSchemes(String value) =>
    value.replaceAllMapped(RegExp(r'(https?:)/(?!/)'), (m) => '${m[1]}//');

/// Same cap as the API `sanitizeReferralCode` / `VARCHAR(32)` column.
const int kReferralCodeMaxLength = 32;

/// Trims, percent-decodes, strips zero-width and whitespace characters,
/// drops trailing slash or sentence punctuation, and caps an invite/promo
/// code at [kReferralCodeMaxLength]. Empty or whitespace-only values
/// (including `%20`) become null.
String _unwrapNestedReferralCode(String value) {
  final nested = RegExp(
    r'(?:invite|promo)/([^/?#]+)',
    caseSensitive: false,
  ).firstMatch(value);
  return nested != null ? nested.group(1)! : value;
}

String? normalizeReferralCode(String? raw) {
  if (raw == null) return null;
  var value = raw.trim();
  if (value.isEmpty) return null;
  value = _unescapeFullwidthUrlChars(value);
  value = stripInvisibleReferralChars(value).replaceAll(RegExp(r'\s+'), '');
  if (value.isEmpty) return null;
  // Same order as the API sanitizeReferralCode: unwrap invite|promo/{code}
  // before percent-decode so `invite/AB%2F12` stays AB/12, then unwrap
  // again after decode so `%2Finvite%2FAB12CD` still yields AB12CD.
  value = _unwrapNestedReferralCode(value);
  try {
    value = Uri.decodeComponent(value);
  } catch (_) {
    // Keep the trimmed raw value when it is not valid percent-encoding.
  }
  value = _unescapeFullwidthUrlChars(value);
  value = stripInvisibleReferralChars(value).replaceAll(RegExp(r'\s+'), '');
  value = _unwrapNestedReferralCode(value);
  if (value.isEmpty) return null;
  // Same fold as the API sanitizeReferralCode (uppercase, drop trailing
  // punct including `!` and `/`, max 32). An encoded slash inside the
  // token (`AB/12`) is kept; `AB/12/` and `AB12CD!` fold to `AB/12` /
  // `AB12CD`.
  value = value.toUpperCase().replaceAll(RegExp(r'[.?#&,;!/]+$'), '');
  if (value.isEmpty) return null;
  if (value.length > kReferralCodeMaxLength) {
    value = value.substring(0, kReferralCodeMaxLength);
  }
  // Same fold as the landing capCode: leftover URL is never a programme token.
  if (value.contains('://')) return null;
  return value;
}

const _referralLinkHosts = {
  'realunit.app',
  'www.realunit.app',
  'dev.realunit.app',
};

/// Resolves an invite/promo code from typed or pasted field input.
///
/// Accepts a bare code or a RealUnit invite/promo URL:
/// - `https://realunit.app/invite/{code}` and `/promo/{code}`
/// - `realunit.app/invite/{code}` (missing scheme)
/// - `/invite/{code}` and `invite/{code}` (relative)
/// - `realunit-wallet://invite/{code}` and `realunit-wallet:invite/{code}`
/// - Chrome `intent://realunit.app/invite/{code}#Intent;…`
/// - `android-app://swiss.realunit.app/https/realunit.app/invite/{code}`
/// - `ios-app://6759720010/realunit-wallet/invite/{code}`
/// - `/invite?code=` / `?code=` wrapping a landing URL / `?app-argument=` /
///   `utm_content` / `referrer` / Facebook `u=` / Google `q=` / Outlook `url=` /
///   email `link=` wrapping `invite=` or a landing URL (a campaign name in
///   `utm_content` does not hide a later key; empty or foreign `code=` does
///   not hide a later `invite=` / `promo=`)
/// - Facebook `l.php?u=` / Google `url?q=` / `href.li/?https://…` wrappers around a landing URL
/// - Outlook Safe Links `url=` and Proofpoint URL Defense v2 (`-3A` / `_`)
///
/// Falls back to [normalizeReferralCode] when the input is not a URL.
/// A recognized URL with no code returns null so the whole URL is never
/// sent as a lookup token. A share message that contains a RealUnit
/// invite/promo URL (https, wallet, intent, android-app, or ios-app)
/// is reduced to that code.
String? referralCodeFromInput(String? raw) {
  if (raw == null) return null;
  final value = stripInvisibleReferralChars(_stripPastedWrappers(raw));
  if (value.isEmpty) return null;
  final yahoo = _codeFromYahooRu(value);
  if (yahoo != null) return yahoo;
  if (_isPastedReferralUrl(value)) {
    return _codeFromPastedReferralUrl(value);
  }
  final embedded = _embeddedReferralUrl(value);
  if (embedded != null) {
    return _codeFromPastedReferralUrl(embedded);
  }
  return normalizeReferralCode(value);
}

/// Text to put in the registration field after a paste.
///
/// Returns the extracted code, or the stripped paste for a bare token.
/// Returns null when the clipboard is empty, format-only, or a RealUnit
/// invite/promo URL that does not contain a code — the URL must not be
/// looked up as a token.
String? referralPasteFieldText(String? raw) {
  if (raw == null) return null;
  final extracted = referralCodeFromInput(raw);
  if (extracted != null) return extracted;
  final stripped = stripInvisibleReferralChars(_stripPastedWrappers(raw)).trim();
  if (stripped.isEmpty) return null;
  if (_embeddedReferralUrl(stripped) != null) return null;
  if (_isPastedReferralUrl(stripped) && _codeFromPastedReferralUrl(stripped) == null) {
    final lower = stripped.toLowerCase();
    if (lower.contains('realunit.app/') ||
        lower.startsWith('realunit-wallet:') ||
        lower.startsWith('intent://') ||
        lower.startsWith('android-app://swiss.realunit.app/') ||
        lower.startsWith('ios-app://') ||
        lower.startsWith('/invite') ||
        lower.startsWith('/promo') ||
        lower.startsWith('invite?') ||
        lower.startsWith('promo?') ||
        lower.startsWith('invite#') ||
        lower.startsWith('promo#') ||
        lower.startsWith('invite/') ||
        lower.startsWith('promo/')) {
      return null;
    }
  }
  return stripped;
}

/// Code from the remainder after `/invite/` or `/promo/` on a Universal Link.
/// Nested invite URLs and share messages are unwrapped; a bare code with
/// extra path segments stays the first segment.
String? referralCodeFromPathRemainder(String? rest) {
  if (rest == null) return null;
  var value = _repairSplitUrlSchemes(rest.trim());
  if (value.isEmpty) return null;
  var decoded = value;
  try {
    decoded = Uri.decodeComponent(value).trim();
  } catch (_) {}
  if (decoded.isNotEmpty &&
      (_isPastedReferralUrl(decoded) || _embeddedReferralUrl(decoded) != null)) {
    return referralCodeFromInput(decoded) ?? referralCodeFromInput(value);
  }
  if (_isPastedReferralUrl(value) || _embeddedReferralUrl(value) != null) {
    return referralCodeFromInput(value);
  }
  final token = decoded.isNotEmpty ? decoded : value;
  final parts = token.split('/').where((s) => s.isNotEmpty).toList();
  if (parts.isEmpty) return null;
  final first = parts.first;
  // `invite/AB12CD/extra` keeps the first token. `AB%2F12` decodes to
  // `AB/12` whose first segment is too short to be a programme code.
  if (parts.length > 1 && RegExp(r'^[A-Za-z0-9]{4,}$').hasMatch(first)) {
    return normalizeReferralCode(first);
  }
  return normalizeReferralCode(parts.join('/'));
}

final _embeddedHttpsReferralUrl = RegExp(
  r'https?://(?:www\.|dev\.)?realunit\.app(?=[/?#]|$)(?:/(?:invite|promo)(?:/[^\s<>#?]*)?)?(?:[?#][^\s<>]*)?',
  caseSensitive: false,
);

final _embeddedWalletReferralUrl = RegExp(
  r'realunit-wallet:(?://)?(?:invite|promo)(?:/[^\s<>#?]*)?(?:[?#][^\s<>]*)?',
  caseSensitive: false,
);

final _embeddedIntentReferralUrl = RegExp(
  r'intent://(?:(?:www\.|dev\.)?realunit\.app/)?(?:invite|promo)(?:/[^\s<>#?]*)?(?:[?#][^\s<>]*)?',
  caseSensitive: false,
);

final _embeddedAndroidAppReferralUrl = RegExp(
  r'android-app://swiss\.realunit\.app/https/(?:www\.|dev\.)?realunit\.app/(?:invite|promo)(?:/[^\s<>#?]*)?(?:[?#][^\s<>]*)?',
  caseSensitive: false,
);

final _embeddedIosAppReferralUrl = RegExp(
  r'ios-app://\d+/(?:realunit-wallet/)?(?:invite|promo)(?:/[^\s<>#?]*)?(?:[?#][^\s<>]*)?',
  caseSensitive: false,
);

String? _embeddedReferralUrl(String value) {
  final match =
      _embeddedHttpsReferralUrl.firstMatch(value) ??
      _embeddedWalletReferralUrl.firstMatch(value) ??
      _embeddedIntentReferralUrl.firstMatch(value) ??
      _embeddedAndroidAppReferralUrl.firstMatch(value) ??
      _embeddedIosAppReferralUrl.firstMatch(value);
  if (match == null) return null;
  var url = match.group(0)!;
  url = url.replaceFirst(RegExp(r'__+;.*$'), '');
  return url.replaceFirst(
    RegExp(r'[.!?,;:)\]}*_~`|\u0022\u0027\u201C\u201D\u2018\u2019\u00AB\u00BB]+$'),
    '',
  );
}

const _pastedQuoteOpeners = '"\'(<*_~`|\u201C\u2018\u00AB\u201E';
const _pastedQuoteClosers = '"\'>)*_~`|\u201D\u2019\u00BB\u201C';

String _unescapeHtmlNumericEntity(Match match) {
  final isHex = match[1]!.isNotEmpty;
  final code = int.tryParse(match[2]!, radix: isHex ? 16 : 10);
  if (code == null) return match[0]!;
  if (code == 9) return '\t';
  if (code == 10) return '\n';
  if (code == 13) return '\r';
  if (code == 160) return ' ';
  if (code < 32 || code > 126) return match[0]!;
  return String.fromCharCode(code);
}

String _unescapeHtmlEntities(String value) {
  return value
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&#34;', '"')
      .replaceAll('&#x22;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&#x27;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&')
      .replaceAll('&colon;', ':')
      .replaceAll('&sol;', '/')
      .replaceAll('&equals;', '=')
      .replaceAll('&quest;', '?')
      .replaceAll('&num;', '#')
      .replaceAll('&period;', '.')
      .replaceAll('&dot;', '.')
      .replaceAll('&commat;', '@')
      .replaceAllMapped(
        RegExp(r'&#(x?)([0-9A-Fa-f]+);', caseSensitive: false),
        _unescapeHtmlNumericEntity,
      );
}

/// JSON logs and DevTools copy `https:\/\/…` and `\u003a\u002f\u002f`.
/// Only printable ASCII `\u00XX` so `\u0041` in a code is decoded and
/// high-byte escapes are left alone.
String _unescapeJsonUrlEscapes(String value) {
  if (!value.contains('\\')) return value;
  final unicode = value.replaceAllMapped(RegExp(r'\\u([0-9A-Fa-f]{4})'), (
    match,
  ) {
    final code = int.parse(match[1]!, radix: 16);
    if (code == 9) return '\t';
    if (code == 10) return '\n';
    if (code == 13) return '\r';
    if (code == 160) return ' ';
    if (code < 32 || code > 126) return match[0]!;
    return String.fromCharCode(code);
  });
  return unicode.replaceAll(r'\/', '/');
}

/// Mobile keyboards paste fullwidth `：` / `／` (U+FF01–U+FF5E) and
/// ideographic space. Word/Pages copy uses fraction slash U+2044,
/// division slash U+2215, and ratio colon U+2236. Fold them onto ASCII
/// so `https：／／…` and `https:⁄⁄…` are URLs. CJK keyboards use
/// ideographic full stop `。` (U+3002) as the domain dot. Word/PDF
/// typesetting spaces (nbsp, thin space, narrow nbsp) become ASCII
/// space so `/ invite` still joins. Word/PDF hyphen lookalikes
/// (U+2010, non-breaking hyphen, en/em dash, minus) become `-` so
/// `in‐\\nvite` still joins.
String _unescapeFullwidthUrlChars(String value) {
  return value
      .replaceAllMapped(RegExp(r'[\u3000\uFF01-\uFF5E]'), (match) {
        final code = match[0]!.codeUnitAt(0);
        if (code == 0x3000) return ' ';
        return String.fromCharCode(code - 0xFEE0);
      })
      .replaceAll('\u2044', '/')
      .replaceAll('\u2215', '/')
      .replaceAll('\u2236', ':')
      .replaceAll('\u3002', '.')
      .replaceAll('\uFF61', '.')
      .replaceAll('\u2024', '.')
      .replaceAll(RegExp(r'[\u00A0\u1680\u2000-\u200A\u202F\u205F]'), ' ')
      .replaceAll(RegExp(r'[\u2010-\u2014\u2212\uFE58\uFE63]'), '-');
}

/// Email encoded-words (`=?UTF-8?Q?…?=` / `=?UTF-8?B?…?=`) from a
/// forwarded subject. Adjacent words with only whitespace between them
/// are concatenated (RFC 2047).
String _unescapeRfc2047(String value) {
  if (!value.contains('=?')) return value;
  final glued = value.replaceAll(
    RegExp(r'\?=[ \t\r\n\u0085\u2028\u2029]+=\?'),
    '?==?',
  );
  return glued.replaceAllMapped(
    RegExp(r'=\?[^?]+\?([QqBb])\?([^?]*)\?='),
    (match) {
      final encoding = match[1]!.toUpperCase();
      final data = match[2]!;
      try {
        if (encoding == 'B') {
          var padded = data.replaceAll(RegExp(r'\s+'), '');
          final pad = padded.length % 4;
          if (pad != 0) {
            padded = padded.padRight(padded.length + (4 - pad), '=');
          }
          return utf8.decode(base64.decode(padded), allowMalformed: true);
        }
        final bytes = <int>[];
        for (var i = 0; i < data.length; i++) {
          final ch = data[i];
          if (ch == '_') {
            bytes.add(0x20);
            continue;
          }
          if (ch == '=' && i + 2 < data.length) {
            final hex = data.substring(i + 1, i + 3);
            if (RegExp(r'^[0-9A-Fa-f]{2}$').hasMatch(hex)) {
              bytes.add(int.parse(hex, radix: 16));
              i += 2;
              continue;
            }
          }
          bytes.add(ch.codeUnitAt(0));
        }
        return utf8.decode(bytes, allowMalformed: true);
      } catch (_) {
        return match[0]!;
      }
    },
  );
}

/// Quoted-printable encodes `://` as `=3A=2F=2F` and `/` as `=2F`.
/// Only URL bytes are decoded so `?code=AB12CD` is not eaten as hex.
String _unescapeQuotedPrintableUrl(String value) {
  if (!RegExp(r'=[0-9A-Fa-f]{2}').hasMatch(value)) return value;
  const urlBytes = {
    0x20,
    0x22,
    0x23,
    0x25,
    0x26,
    0x27,
    0x2B,
    0x2C,
    0x2E,
    0x2F,
    0x3A,
    0x3B,
    0x3D,
    0x3F,
    0x40,
  };
  return value.replaceAllMapped(RegExp(r'=([0-9A-Fa-f]{2})'), (match) {
    final code = int.parse(match[1]!, radix: 16);
    if (!urlBytes.contains(code)) return match[0]!;
    return String.fromCharCode(code);
  });
}

String _joinBrokenReferralUrl(String value) {
  return value
      .replaceAllMapped(
        RegExp(
          r'(https?://|(?:www\.|dev\.)?realunit\.app|/|[=?&])[ \t\u00A0]+',
          caseSensitive: false,
        ),
        (match) => match[1]!,
      )
      .replaceAllMapped(RegExp(r'[ \t\u00A0]+(/)'), (match) => match[1]!);
}

String _stripPastedWrappers(String raw) {
  var value = _unescapeQuotedPrintableUrl(
    _unescapeRfc2047(
      _joinBrokenReferralUrl(
        _unescapeFullwidthUrlChars(
              _unescapeJsonUrlEscapes(_unescapeHtmlEntities(raw)),
            )
            .replaceAll(RegExp(r'^[ \t]*>+[ \t]?', multiLine: true), '')
            .replaceAll(RegExp(r'\\[ \t]*[\r\n\u0085\u2028\u2029]+'), '')
            .replaceAll(RegExp(r'-[\r\n\u0085\u2028\u2029]+'), '')
            .replaceAll(RegExp(r'=[ \t]*[\r\n\u0085\u2028\u2029]+'), '')
            .replaceAll(RegExp(r'[\r\n\u0085\u2028\u2029]+'), ''),
      ),
    ),
  ).trim();
  if (_isPastedReferralUrl(value) && RegExp(r'[ \t\u00A0]').hasMatch(value)) {
    value = value.split(RegExp(r'[ \t\u00A0]')).first;
  }
  for (var i = 0; i < 8 && value.length >= 2; i++) {
    final start = value[0];
    final end = value[value.length - 1];
    if (!_pastedQuoteOpeners.contains(start) || !_pastedQuoteClosers.contains(end)) {
      break;
    }
    value = value.substring(1, value.length - 1).trim();
  }
  return value;
}

bool _isReferralPathKind(String? value) {
  if (value == null) return false;
  final kind = value.toLowerCase();
  return kind == 'invite' || kind == 'promo';
}

bool _isPastedReferralUrl(String value) {
  final lower = value.toLowerCase();
  if (lower.startsWith('realunit-wallet:')) return true;
  if (lower.startsWith('intent://')) return true;
  if (lower.startsWith('android-app://')) return true;
  if (lower.startsWith('ios-app://')) return true;
  if (lower.startsWith('http://') || lower.startsWith('https://')) return true;
  if (lower.startsWith('whatsapp:') ||
      lower.startsWith('tg:') ||
      lower.startsWith('sms:') ||
      lower.startsWith('smsto:') ||
      lower.startsWith('mailto:') ||
      lower.startsWith('fb-messenger:') ||
      lower.startsWith('threema:') ||
      lower.startsWith('sgnl:') ||
      lower.startsWith('signal:') ||
      lower.startsWith('viber:') ||
      lower.startsWith('line://')) {
    return true;
  }
  if (lower.startsWith('/invite') || lower.startsWith('/promo')) return true;
  if (lower.startsWith('invite/') || lower.startsWith('promo/')) return true;
  if (lower.startsWith('invite?') || lower.startsWith('promo?')) return true;
  if (lower.startsWith('invite#') || lower.startsWith('promo#')) return true;
  for (final host in _referralLinkHosts) {
    if (lower == host ||
        lower.startsWith('$host/') ||
        lower.startsWith('$host?') ||
        lower.startsWith('$host#')) {
      return true;
    }
  }
  return false;
}

const _referralSchemeTokens = {
  'http:',
  'https:',
  'intent:',
  'realunit-wallet:',
  'android-app:',
  'ios-app:',
};

bool _isReferralSchemeToken(String? value) {
  if (value == null) return false;
  return _referralSchemeTokens.contains(value.toLowerCase());
}

String _joinedPathRemainder(List<String> segments) {
  if (segments.length < 2) return '';
  var rest = segments.skip(1).join('/');
  if (_isReferralSchemeToken(segments[1])) {
    rest = '${segments[1]}//${segments.skip(2).join('/')}';
  }
  return rest;
}

String? _codeFromPathAndQuery(
  List<String> segments,
  String? query, [
  String? fragment,
]) {
  if (segments.isNotEmpty && _isReferralPathKind(segments.first)) {
    if (segments.length >= 2) {
      final rest = _joinedPathRemainder(segments);
      final fromRest = referralCodeFromPathRemainder(rest);
      if (fromRest != null && !_isReferralSchemeToken(fromRest)) return fromRest;
    }
  } else if (segments.isNotEmpty) {
    return null;
  }
  if (query != null && query.isNotEmpty) {
    Map<String, String> params = const {};
    try {
      params = Uri.splitQueryString(query);
    } catch (_) {}
    final fromQuery = referralCodeFromQueryParameters(params);
    if (fromQuery != null) return fromQuery;
  }
  if (fragment != null && fragment.isNotEmpty) {
    if (segments.isEmpty || (_isReferralPathKind(segments.first) && segments.length < 2)) {
      return referralCodeFromInput(fragment) ?? normalizeReferralCode(fragment);
    }
  }
  return null;
}

/// Nested `invite=` / `promo=` / `code=` or a landing URL inside
/// `utm_content` / `referrer` / `u=` / `q=` / `url=` / `link=`.
/// A bare campaign name is not a code.
String? _codeFromWrappedQueryValue(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final value = stripInvisibleReferralChars(raw.trim());
  if (value.isEmpty) return null;
  if (_isPastedReferralUrl(value) || _embeddedReferralUrl(value) != null) {
    return referralCodeFromInput(value);
  }
  final qs = value.startsWith('?') ? value.substring(1) : value;
  final looksNested =
      RegExp(r'^(invite|promo|code)=', caseSensitive: false).hasMatch(qs) || qs.contains('&');
  if (!looksNested) return null;
  Map<String, String> params = const {};
  try {
    params = Uri.splitQueryString(qs);
  } catch (_) {
    return null;
  }
  const innerKeys = ['invite', 'promo', 'code'];
  for (final key in innerKeys) {
    final inner = params[key];
    if (inner == null || inner.isEmpty) continue;
    final code = referralCodeFromInput(inner);
    if (code != null) return code;
  }
  return null;
}

const _referralCodeQueryKeys = ['code', 'invite', 'promo'];
const _referralWrapperQueryKeys = [
  'utm_content',
  'referrer',
  'u',
  'q',
  'url',
  'link',
];

/// Code from `code=` / `invite=` / `promo=` / `app-argument=` / wrapper keys.
///
/// Each key is tried until one yields a code, matching the landing Pages
/// Function and Play install referrer.
String? referralCodeFromQueryParameters(Map<String, String> params) {
  for (final key in _referralCodeQueryKeys) {
    final raw = params[key];
    if (raw == null || raw.isEmpty) continue;
    final code = referralCodeFromInput(raw);
    if (code != null) return code;
  }
  final argument = params['app-argument'];
  if (argument != null && argument.isNotEmpty) {
    final fromArg = referralCodeFromInput(argument);
    if (fromArg != null) return fromArg;
  }
  for (final key in _referralWrapperQueryKeys) {
    final raw = params[key];
    if (raw == null || raw.isEmpty) continue;
    final code = _codeFromWrappedQueryValue(raw);
    if (code != null) return code;
  }
  return null;
}

String? _codeFromWalletRemainder(String remainder) {
  if (remainder.startsWith('//')) remainder = remainder.substring(2);
  var fragment = '';
  final hash = remainder.indexOf('#');
  if (hash >= 0) {
    fragment = remainder.substring(hash + 1);
    remainder = remainder.substring(0, hash);
  }
  final q = remainder.indexOf('?');
  final query = q >= 0 ? remainder.substring(q + 1) : '';
  final path = q >= 0 ? remainder.substring(0, q) : remainder;
  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  return _codeFromPathAndQuery(segments, query, fragment);
}

String? _codeFromPastedReferralUrl(String value) {
  value = _repairSplitUrlSchemes(value);
  final lower = value.toLowerCase();
  if (lower.startsWith('realunit-wallet:')) {
    return _codeFromWalletRemainder(value.substring('realunit-wallet:'.length));
  }

  var toParse = value;
  if (!toParse.contains('://')) {
    for (final host in _referralLinkHosts) {
      if (lower == host ||
          lower.startsWith('$host/') ||
          lower.startsWith('$host?') ||
          lower.startsWith('$host#')) {
        toParse = 'https://$value';
        break;
      }
    }
  }

  final uri = Uri.tryParse(toParse);
  if (uri == null) return null;

  if (uri.scheme == 'intent') {
    if (_referralLinkHosts.contains(uri.host.toLowerCase())) {
      final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      return _codeFromPathAndQuery(segs, uri.query);
    }
    if (_isReferralPathKind(uri.host)) {
      final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segs.isNotEmpty) return normalizeReferralCode(segs.first);
      return _codeFromPathAndQuery([uri.host], uri.query);
    }
    return _codeFromWrapperUri(uri);
  }

  if (uri.scheme == 'android-app') {
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.length >= 3 &&
        (segs[0] == 'https' || segs[0] == 'http') &&
        _referralLinkHosts.contains(segs[1].toLowerCase()) &&
        _isReferralPathKind(segs[2])) {
      if (segs.length >= 4) return normalizeReferralCode(segs[3]);
      return _codeFromPathAndQuery([segs[2]], uri.query);
    }
    return _codeFromWrapperUri(uri);
  }

  if (uri.scheme == 'ios-app') {
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.length >= 2 &&
        segs[0].toLowerCase() == 'realunit-wallet' &&
        _isReferralPathKind(segs[1])) {
      if (segs.length >= 3) return normalizeReferralCode(segs[2]);
      return _codeFromPathAndQuery([segs[1]], uri.query);
    }
    if (segs.isNotEmpty && _isReferralPathKind(segs[0])) {
      if (segs.length >= 2) return normalizeReferralCode(segs[1]);
      return _codeFromPathAndQuery([segs[0]], uri.query);
    }
    return _codeFromWrapperUri(uri);
  }

  if (uri.scheme == 'https' || uri.scheme == 'http') {
    if (_referralLinkHosts.contains(uri.host.toLowerCase())) {
      final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      return _codeFromPathAndQuery(segs, uri.query, uri.fragment);
    }
    return _codeFromWrapperUri(uri);
  }

  if (uri.scheme.isEmpty) {
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    return _codeFromPathAndQuery(segs, uri.query, uri.fragment);
  }

  return _codeFromWrapperUri(uri);
}

/// Chrome Android `intent://send?text=…#Intent;scheme=whatsapp;end` (and
/// Telegram/SMS) put the landing URL in a query param or an `#Intent;`
/// string extra (`S.text`, `S.browser_fallback_url`). Split extras so
/// `;end` is not glued onto the code.
Iterable<String> _intentFragmentValues(String fragment) sync* {
  final trimmed = fragment.trim();
  final lower = trimmed.toLowerCase();
  if (lower == 'intent' || lower.startsWith('intent;')) {
    for (final extra in trimmed.split(';')) {
      if (extra.isEmpty) continue;
      final extraLower = extra.toLowerCase();
      if (extraLower == 'intent' || extraLower == 'end') continue;
      final eq = extra.indexOf('=');
      if (eq <= 0) {
        yield extra;
        continue;
      }
      yield extra.substring(eq + 1);
      yield extra.substring(0, eq);
    }
    return;
  }
  yield fragment;
}

/// Messenger / ads wrappers (Facebook `l.php?u=`, Google `url?q=`,
/// `href.li/?https://…`, Yahoo `RU=https://…` in the path, Google AMP
/// `/amp/s/realunit.app/invite/…`) nest the landing URL in a query
/// value, the raw query, or a path segment. Chrome `intent://` share
/// sheets nest it in `text` / `S.text` / `S.browser_fallback_url`.
/// Only follow a RealUnit invite/promo URL so a bare campaign token in
/// another param is not taken as the code.
String? _codeFromWrapperUri(Uri uri) {
  final values = <String>[
    ...uri.queryParameters.values,
    ...uri.queryParameters.keys,
    if (uri.query.isNotEmpty) uri.query,
    if (uri.fragment.isNotEmpty) ..._intentFragmentValues(uri.fragment),
    if (uri.path.isNotEmpty) uri.path,
    ...uri.pathSegments,
  ];
  for (final value in values) {
    if (value.isEmpty) continue;
    final fromValue = _codeFromWrapperValue(value);
    if (fromValue != null) return fromValue;
    if (!value.contains('%')) continue;
    try {
      final decoded = Uri.decodeComponent(value);
      if (decoded.isEmpty || decoded == value) continue;
      final fromDecoded = _codeFromWrapperValue(decoded);
      if (fromDecoded != null) return fromDecoded;
    } catch (_) {}
  }
  return _codeFromReferralHostInPath(uri.pathSegments);
}

/// AMP / CDN paths (`/amp/s/realunit.app/invite/{code}`) have the host as a
/// path segment without `https://`.
String? _codeFromReferralHostInPath(Iterable<String> segments) {
  final segs = segments.where((s) => s.isNotEmpty).toList();
  for (var i = 0; i < segs.length; i++) {
    if (!_referralLinkHosts.contains(segs[i].toLowerCase())) continue;
    final rest = segs.sublist(i).join('/');
    return referralCodeFromInput('https://$rest') ?? _codeFromPastedReferralUrl(rest);
  }
  return null;
}

/// Proofpoint URL Defense v2 encodes `://` as `-3A` and `/` as `_`.
String? _urlDefenseDecode(String value) {
  final lower = value.toLowerCase();
  if (lower.contains('realunit.app/') || lower.contains('realunit.app?')) {
    return null;
  }
  if (!lower.contains('realunit.app')) return null;
  if (!value.contains('-') && !value.contains('_')) return null;
  final decoded = value
      .replaceAllMapped(RegExp(r'-([0-9A-Fa-f]{2})'), (match) {
        final code = int.parse(match[1]!, radix: 16);
        if (code < 32 || code > 126) return match[0]!;
        return String.fromCharCode(code);
      })
      .replaceAll('_', '/');
  if (decoded == value) return null;
  if (!decoded.toLowerCase().contains('realunit.app')) return null;
  return decoded;
}

String? _codeFromWrapperValue(String value) {
  value = _repairSplitUrlSchemes(value);
  value = _unescapeQuotedPrintableUrl(
    _unescapeRfc2047(
      _unescapeFullwidthUrlChars(
        _unescapeJsonUrlEscapes(_unescapeHtmlEntities(value)),
      ),
    ),
  );
  final defense = _urlDefenseDecode(value);
  if (defense != null) {
    final fromDefense = _codeFromPastedReferralUrl(defense) ?? referralCodeFromInput(defense);
    if (fromDefense != null) return fromDefense;
  }
  final embedded = _embeddedReferralUrl(value);
  if (embedded != null) {
    final code = _codeFromPastedReferralUrl(embedded);
    if (code != null) return code;
  }
  if (!_isPastedReferralUrl(value)) return null;
  final inner = Uri.tryParse(value);
  if (inner == null) return null;
  if (!_referralLinkHosts.contains(inner.host.toLowerCase())) return null;
  return _codeFromPastedReferralUrl(value);
}
