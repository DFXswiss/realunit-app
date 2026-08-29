/// Reads a JSON array of objects, including DFX wrappers
/// (`invites` / `payouts` / `data` / `items`). Unknown shapes yield `[]`
/// so a wrapper cannot hide open invites or settled prizes.
List<Map<String, dynamic>> referralJsonList(dynamic decoded) {
  if (decoded is List) {
    return [
      for (final item in decoded)
        if (item is Map<String, dynamic>) item,
    ];
  }
  if (decoded is Map<String, dynamic>) {
    for (final key in const ['invites', 'payouts', 'data', 'items']) {
      final value = decoded[key];
      if (value is List) {
        return [
          for (final item in value)
            if (item is Map<String, dynamic>) item,
        ];
      }
    }
  }
  return const [];
}

/// JSON numbers sometimes arrive as strings (`"20"`, `"246.50"`). Missing or
/// non-numeric values are null so a prize row is not silently shown as 0.
/// DE/CH frozen-CHF strings (`246,5`, `1'246.50`, `CHF 246.50`) parse too
/// so a locale-formatted `chfValue` does not drop the payout.
num? referralJsonNum(dynamic value) {
  if (value is num) return value;
  if (value is String) return parseReferralDecimal(value);
  return null;
}

/// Parses a JSON or locale numeric string. Swiss thousands apostrophes,
/// a DE/CH decimal comma, and an optional `CHF`/`Fr` prefix are accepted.
num? parseReferralDecimal(String? raw) {
  if (raw == null) return null;
  var value = raw.trim();
  if (value.isEmpty) return null;
  value = value.replaceFirst(
    RegExp(r'^(CHF|Fr\.?)\s*', caseSensitive: false),
    '',
  );
  value = value.replaceAll(RegExp(r"['’`´]"), '');
  value = value.replaceAll(RegExp(r'\s+'), '');
  if (value.isEmpty) return null;
  if (value.contains(',') && value.contains('.')) {
    final lastComma = value.lastIndexOf(',');
    final lastDot = value.lastIndexOf('.');
    if (lastComma > lastDot) {
      value = value.replaceAll('.', '').replaceAll(',', '.');
    } else {
      value = value.replaceAll(',', '');
    }
  } else if (value.contains(',')) {
    value = value.replaceAll(',', '.');
  }
  return num.tryParse(value);
}

int referralJsonInt(dynamic value, {int orElse = 0}) => referralJsonNum(value)?.round() ?? orElse;

DateTime _fromEpoch(num value) {
  final n = value.toInt();
  if (n.abs() >= 100000000000) {
    return DateTime.fromMillisecondsSinceEpoch(n, isUtc: true);
  }
  return DateTime.fromMillisecondsSinceEpoch(n * 1000, isUtc: true);
}

final _zonelessDateTime = RegExp(
  r'^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2}(?:\.\d+)?)$',
);

/// ISO-8601 strings or Unix seconds/milliseconds. Null if missing/unparseable.
/// MySQL DATETIME has no zone (TypeORM `timezone: 'Z'`). A zoneless
/// `2026-08-24 10:00:00` is UTC so prize Datum is the credit timestamp,
/// not shifted by the phone's local zone (TB Ziff. 6).
DateTime? referralJsonDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value.isUtc ? value : value.toUtc();
  if (value is num) return _fromEpoch(value);
  if (value is String) {
    final text = value.trim();
    if (text.isEmpty) return null;
    if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(text)) {
      final n = num.tryParse(text);
      if (n != null) return _fromEpoch(n);
    }
    final zoneless = _zonelessDateTime.firstMatch(text);
    final iso = zoneless != null ? '${zoneless.group(1)}T${zoneless.group(2)}Z' : text;
    try {
      return DateTime.parse(iso).toUtc();
    } catch (_) {
      return null;
    }
  }
  return null;
}

/// Fail-closed for the dashboard/settings gate: only an explicit true/1/"true"
/// opens the programme. A TypeError on `as bool` would otherwise fail summary
/// load and show retry instead of hiding the card.
bool referralJsonBool(dynamic value, {bool orElse = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final text = value.trim().toLowerCase();
    if (text == 'true' || text == '1' || text == 'yes') return true;
    if (text == 'false' || text == '0' || text == 'no' || text.isEmpty) {
      return false;
    }
  }
  return orElse;
}

/// Unwraps `{ summary|data|item|result|invite: { ... } }` only when the outer
/// map lacks [markers]. A sibling `data` object must not hide `eligible`.
Map<String, dynamic> referralJsonObject(
  dynamic decoded, {
  List<String> markers = const [],
}) {
  if (decoded is! Map<String, dynamic>) return const {};
  if (markers.any(decoded.containsKey)) return decoded;
  for (final key in const [
    'summary',
    'data',
    'item',
    'result',
    'invite',
    'createdInvite',
    'lookup',
    'bind',
    'terms',
  ]) {
    final inner = decoded[key];
    if (inner is Map<String, dynamic> && (markers.isEmpty || markers.any(inner.containsKey))) {
      return inner;
    }
  }
  return decoded;
}

/// Trims JSON strings. Numbers are stringified so a numeric `code` / `txHash`
/// does not drop the row. Empty / whitespace-only values are null.
String? referralJsonString(dynamic value) {
  if (value is String) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }
  if (value is num) return value.toString();
  return null;
}

final _referralWalletName = RegExp(r'^0x[0-9a-fA-F]{40}$');
final _referralNumericId = RegExp(r'^\d+$');

/// Empfehler display name. Wallet addresses and numeric DFX user ids are
/// not people — share fallback and recognition must not show them.
String? referralPersonName(dynamic value) {
  final text = referralJsonString(value);
  if (text == null) return null;
  if (_referralWalletName.hasMatch(text) || _referralNumericId.hasMatch(text)) {
    return null;
  }
  return text;
}

const referralInviteOrigin = 'https://realunit.app';

const _referralInviteHosts = {
  'realunit.app',
  'www.realunit.app',
  'dev.realunit.app',
};

/// Share/copy URL. Relative paths and a missing `url` become
/// `https://realunit.app/invite/{code}`. Scheme-less hosts
/// (`realunit.app/…`) and protocol-relative URLs (`//realunit.app/…`)
/// are treated as https. `http://` is upgraded and `www.realunit.app`
/// is folded onto the apex so the shared link matches Offerte Entwurf 3
/// and the Universal Link host. A `/promo/…` path is kept — it must not
/// be rewritten to `/invite/`.
String? referralInviteUrl({dynamic url, String? code}) {
  final raw = referralJsonString(url);
  if (raw != null) {
    final canonical = _canonicalRealUnitInviteUrl(raw);
    if (canonical != null) return canonical;
  }
  if (code != null && code.isNotEmpty) {
    return '$referralInviteOrigin/invite/${Uri.encodeComponent(code)}';
  }
  return null;
}

String? _canonicalRealUnitInviteUrl(String raw) {
  var value = raw;
  if (value.startsWith('//')) {
    value = 'https:$value';
  } else if (!value.contains('://')) {
    final lower = value.toLowerCase();
    for (final host in _referralInviteHosts) {
      if (lower == host || lower.startsWith('$host/') || lower.startsWith('$host?')) {
        value = 'https://$value';
        break;
      }
    }
  }

  final uri = Uri.tryParse(value);
  if (uri != null && uri.hasScheme) {
    if (!_referralInviteHosts.contains(uri.host.toLowerCase())) {
      return raw.startsWith('//') ? value : raw;
    }
    var next = uri;
    if (uri.scheme == 'http') {
      next = next.replace(scheme: 'https');
    }
    if (next.host.toLowerCase() == 'www.realunit.app') {
      next = next.replace(host: 'realunit.app');
    }
    return next.toString();
  }

  if (raw.startsWith('/') && !raw.startsWith('//')) {
    return '$referralInviteOrigin$raw';
  }
  return null;
}
