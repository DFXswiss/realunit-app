/// Request body for `PUT /v1/realunit/pay/unsigned-transaction`. References the
/// scanned payment link and its active quote so the backend resolves recipient
/// and exact ZCHF amount.
class RealUnitOcpPayDto {
  final String paymentLinkId;
  final String quoteId;

  const RealUnitOcpPayDto({required this.paymentLinkId, required this.quoteId});

  Map<String, dynamic> toJson() => {
    'paymentLinkId': paymentLinkId,
    'quoteId': quoteId,
  };
}
