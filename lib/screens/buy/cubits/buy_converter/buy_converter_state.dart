part of 'buy_converter_cubit.dart';

class BuyConverterState extends Equatable {
  final String fiatText;
  final String sharesText;
  // Rappen-exact amount the live conversion charges (shares × list price in
  // Rappen). Empty while no conversion result is live. The fiat input field
  // must never render this — it always keeps the user's own [fiatText].
  final String payableText;
  final Currency currency;
  final bool loading;

  const BuyConverterState({
    this.fiatText = '',
    this.sharesText = '',
    this.payableText = '',
    this.currency = Currency.chf,
    this.loading = false,
  });

  /// Amount a quote must be requested with: the Rappen-exact payable when a
  /// conversion result is live, otherwise the raw typed amount.
  String get quoteAmountText => payableText.isNotEmpty ? payableText : fiatText;

  BuyConverterState copyWith({
    String? fiatText,
    String? sharesText,
    String? payableText,
    Currency? currency,
    bool? loading,
  }) {
    return BuyConverterState(
      fiatText: fiatText ?? this.fiatText,
      sharesText: sharesText ?? this.sharesText,
      payableText: payableText ?? this.payableText,
      currency: currency ?? this.currency,
      loading: loading ?? this.loading,
    );
  }

  @override
  List<Object?> get props => [fiatText, sharesText, payableText, currency, loading];
}
