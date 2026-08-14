enum TransactionType {
  buy('Buy'),
  sell('Sell'),
  swap('Swap'),
  referral('Referral')
  ;

  final String value;
  const TransactionType(this.value);

  static TransactionType? fromString(String? value) {
    if (value == null) return null;
    return TransactionType.values.cast<TransactionType?>().firstWhere(
      (e) => e?.value == value,
      orElse: () => null,
    );
  }
}

enum TransactionState {
  created('Created'),
  processing('Processing'),
  liquidityPending('LiquidityPending'),
  checkPending('CheckPending'),
  kycRequired('KycRequired'),
  limitExceeded('LimitExceeded'),
  feeTooHigh('FeeTooHigh'),
  priceUndeterminable('PriceUndeterminable'),
  payoutInProgress('PayoutInProgress'),
  completed('Completed'),
  failed('Failed'),
  returnPending('ReturnPending'),
  returned('Returned'),
  unassigned('Unassigned'),
  waitingForPayment('WaitingForPayment')
  ;

  final String value;
  const TransactionState(this.value);

  static TransactionState? fromString(String? value) {
    if (value == null) return null;
    return TransactionState.values.cast<TransactionState?>().firstWhere(
      (e) => e?.value == value,
      orElse: () => null,
    );
  }

  bool get isPending => this != completed && this != failed && this != returned;
}

class TransactionDto {
  final int? id;
  final String? uid;
  final TransactionType? type;
  final TransactionState? state;
  final double? rate;
  final double? inputAmount;
  final String? inputAsset;
  final String? inputTxId;
  final double? outputAmount;
  final String? outputAsset;
  final String? outputTxId;
  final DateTime? date;
  final String? sourceAccount;
  final String? targetAccount;

  const TransactionDto({
    this.id,
    this.uid,
    this.type,
    this.state,
    this.rate,
    this.inputAmount,
    this.inputAsset,
    this.inputTxId,
    this.outputAmount,
    this.outputAsset,
    this.outputTxId,
    this.date,
    this.sourceAccount,
    this.targetAccount,
  });

  factory TransactionDto.fromJson(Map<String, dynamic> json) {
    return TransactionDto(
      id: json['id'] as int?,
      uid: json['uid'] as String?,
      type: TransactionType.fromString(json['type'] as String?),
      state: TransactionState.fromString(json['state'] as String?),
      rate: (json['rate'] as num?)?.toDouble(),
      inputAmount: (json['inputAmount'] as num?)?.toDouble(),
      inputAsset: json['inputAsset'] as String?,
      inputTxId: json['inputTxId'] as String?,
      outputAmount: (json['outputAmount'] as num?)?.toDouble(),
      outputAsset: json['outputAsset'] as String?,
      outputTxId: json['outputTxId'] as String?,
      date: json['date'] != null ? DateTime.parse(json['date'] as String) : null,
      sourceAccount: json['sourceAccount'] as String?,
      targetAccount: json['targetAccount'] as String?,
    );
  }

  bool get isPending => state?.isPending ?? false;

  bool belongsToWallet(String walletAddress) {
    final address = walletAddress.toLowerCase();
    return sourceAccount?.toLowerCase() == address || targetAccount?.toLowerCase() == address;
  }
}
