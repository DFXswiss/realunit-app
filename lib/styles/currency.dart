import 'package:realunit_wallet/generated/i18n.dart';

enum Currency {
  eur('EUR'),
  chf('CHF');

  const Currency(this.code);

  factory Currency.fromCode(String code) =>
      Currency.values.firstWhere((e) => e.code == code.toUpperCase());

  /// App-wide unset default: CHF for Switzerland and Liechtenstein, EUR otherwise.
  factory Currency.defaultForCountryCode(String? countryCode) {
    switch (countryCode?.toUpperCase()) {
      case 'CH':
      case 'LI':
        return Currency.chf;
      default:
        return Currency.eur;
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
