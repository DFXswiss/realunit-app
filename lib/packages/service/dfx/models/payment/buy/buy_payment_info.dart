import 'package:equatable/equatable.dart';
import 'package:realunit_wallet/styles/currency.dart';

class BuyPaymentInfo extends Equatable {
  final int id;
  final String iban;
  final String bic;
  final String name;
  final String street;
  final String number;
  final String zip;
  final String city;
  final String country;
  final Currency currency;
  final String? paymentRequest;
  final String? remittanceInfo;
  // Fields below come from the API quote response. The backend is the
  // authority on whether the quote is valid for trading and what the
  // current min/max limits are for the user+currency combination.
  final bool isValid;
  // The amount this quote charges (Rappen-exact), echoed by the API — the
  // Details page must render this, never re-derive it from keystrokes.
  final double amount;
  final double? minVolume;
  final double? maxVolume;
  final String? error;

  const BuyPaymentInfo({
    required this.id,
    required this.iban,
    required this.bic,
    required this.name,
    required this.street,
    required this.number,
    required this.zip,
    required this.city,
    required this.country,
    required this.currency,
    required this.amount,
    this.isValid = true,
    this.paymentRequest,
    this.remittanceInfo,
    this.minVolume,
    this.maxVolume,
    this.error,
  });

  @override
  List<Object?> get props => [
    id,
    iban,
    bic,
    name,
    street,
    number,
    zip,
    city,
    country,
    currency,
    paymentRequest,
    remittanceInfo,
    isValid,
    amount,
    minVolume,
    maxVolume,
    error,
  ];
}
