/// Public payment-link read response of `GET /v1/lnurlp/:id` (on api.dfx.swiss,
/// no auth). Carries the requested fiat amount and the active quote the app
/// needs to size the swap and later settle the payment. Only the fields the pay
/// flow consumes are mapped.
///
/// The backend `recipient` field is mapped as [LnurlpRecipientDto?] (nullable
/// structured object). Only `name` and `city` are carried — the fields the
/// pay-quote screen displays. Everything else on the backend
/// `PaymentLinkRecipientDto` object is intentionally left unmapped. When the
/// merchant configured no recipient the field is absent and parses to null.
class LnurlpPaymentDto {
  final LnurlpRequestedAmountDto requestedAmount;
  final LnurlpQuoteDto quote;

  /// Per-method/chain transfer amounts. The Ethereum entry lists the exact ZCHF
  /// amount the app must transfer; the app does not compute it locally.
  final List<LnurlpTransferAmountDto> transferAmounts;

  final LnurlpRecipientDto? recipient;

  const LnurlpPaymentDto({
    required this.requestedAmount,
    required this.quote,
    required this.transferAmounts,
    this.recipient,
  });

  factory LnurlpPaymentDto.fromJson(Map<String, dynamic> json) {
    final transfersRaw = json['transferAmounts'];
    if (transfersRaw is! List) {
      throw FormatException(
        'transferAmounts is required and must be a list, got: $transfersRaw',
      );
    }
    return LnurlpPaymentDto(
      requestedAmount: LnurlpRequestedAmountDto.fromJson(
        json['requestedAmount'] as Map<String, dynamic>,
      ),
      quote: LnurlpQuoteDto.fromJson(json['quote'] as Map<String, dynamic>),
      transferAmounts: transfersRaw
          .map((e) => LnurlpTransferAmountDto.fromJson(e as Map<String, dynamic>))
          .toList(),
      recipient: json['recipient'] == null
          ? null
          : LnurlpRecipientDto.fromJson(json['recipient'] as Map<String, dynamic>),
    );
  }
}

/// Merchant/recipient fields surfaced on the pay-quote screen. Only `name` and
/// `city` (from nested `address`) are mapped; other backend fields are unused.
class LnurlpRecipientDto {
  final String? name;
  final String? city;

  const LnurlpRecipientDto({this.name, this.city});

  factory LnurlpRecipientDto.fromJson(Map<String, dynamic> json) {
    final address = json['address'] as Map<String, dynamic>?;
    return LnurlpRecipientDto(
      name: json['name'] as String?,
      city: address?['city'] as String?,
    );
  }
}

class LnurlpRequestedAmountDto {
  final String asset;
  final double amount;

  const LnurlpRequestedAmountDto({required this.asset, required this.amount});

  factory LnurlpRequestedAmountDto.fromJson(Map<String, dynamic> json) {
    return LnurlpRequestedAmountDto(
      asset: json['asset'] as String,
      amount: _parseAmount('requestedAmount.amount', json['amount']),
    );
  }
}

class LnurlpQuoteDto {
  final String id;
  final DateTime expiration;

  const LnurlpQuoteDto({required this.id, required this.expiration});

  factory LnurlpQuoteDto.fromJson(Map<String, dynamic> json) {
    return LnurlpQuoteDto(
      id: json['id'] as String,
      expiration: DateTime.parse(json['expiration'] as String),
    );
  }
}

class LnurlpTransferAmountDto {
  final String method;
  final List<LnurlpTransferAssetDto> assets;

  const LnurlpTransferAmountDto({required this.method, required this.assets});

  factory LnurlpTransferAmountDto.fromJson(Map<String, dynamic> json) {
    final assetsRaw = json['assets'];
    if (assetsRaw is! List) {
      throw FormatException(
        'transferAmounts.assets is required and must be a list, got: $assetsRaw',
      );
    }
    return LnurlpTransferAmountDto(
      method: json['method'] as String,
      assets: assetsRaw
          .map((e) => LnurlpTransferAssetDto.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class LnurlpTransferAssetDto {
  final String asset;

  /// Optional on the backend (`amount?`): the non-priced display path emits
  /// amount-less asset entries. Parsed as nullable so reading the whole quote
  /// never throws — the pay flow only requires the amount for the asset it
  /// actually transfers (ZCHF on Ethereum), filtered before it is read.
  final double? amount;

  /// Exact JSON amount string as received (before `double` conversion), when
  /// present. Used by the pay-process settlement guard for plain-decimal exact
  /// comparison so binary-double drift cannot flip a boundary check. Additive —
  /// callers that only read [amount] (e.g. [PayQuoteCubit]) are unaffected.
  final String? rawAmount;

  const LnurlpTransferAssetDto({
    required this.asset,
    this.amount,
    this.rawAmount,
  });

  factory LnurlpTransferAssetDto.fromJson(Map<String, dynamic> json) {
    final raw = json['amount'];
    if (raw == null) {
      return LnurlpTransferAssetDto(asset: json['asset'] as String);
    }
    final rawAmount = raw.toString();
    return LnurlpTransferAssetDto(
      asset: json['asset'] as String,
      amount: _parseAmount('transferAmounts.assets.amount', raw),
      rawAmount: rawAmount,
    );
  }
}

/// Parses a money amount from JSON. Rejects NaN, ±Infinity and negatives fail-
/// closed via [FormatException] (same type [double.parse] already throws on
/// non-numeric input — no new exception class).
double _parseAmount(String fieldName, Object? raw) {
  final value = double.parse(raw.toString());
  if (!value.isFinite) {
    throw FormatException('$fieldName is not a finite number: $raw');
  }
  if (value.isNegative) {
    throw FormatException('$fieldName must not be negative: $raw');
  }
  return value;
}
