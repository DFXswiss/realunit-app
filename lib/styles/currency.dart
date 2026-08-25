import 'package:realunit_wallet/generated/i18n.dart';

enum Currency {
  eur('EUR'),
  chf('CHF');

  const Currency(this.code);

  factory Currency.fromCode(String code) =>
      Currency.values.firstWhere((e) => e.code == code.toUpperCase());

  static Currency? tryFromCode(String? code) {
    if (code == null || code.isEmpty) return null;
    try {
      return Currency.fromCode(code);
    } catch (_) {
      return null;
    }
  }

  final String code;

  String get name {
    switch (this) {
      case Currency.eur:
        return S.current.currencyEur;
      case Currency.chf:
        return S.current.currencyChf;
    }
  }
}
