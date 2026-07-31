import 'dart:developer' as developer;

/// Mirrors the backend `PaymentLinkPaymentStatus` enum 1:1 (type-safe DTO
/// mirroring, not local business logic). The backend remains the authority on
/// the payment status; the app renders it and uses [isTerminal] / [isCompleted]
/// only to decide when to stop polling and which UI state to show.
enum OcpPaymentStatus {
  pending('Pending'),
  completed('Completed'),
  cancelled('Cancelled'),
  expired('Expired'),
  unknown('')
  ;

  final String value;

  const OcpPaymentStatus(this.value);

  /// Mirrors the backend status 1:1. An unrecognised value is deliberately
  /// mapped to `unknown` (forward-compat, not a bug) rather than crashing —
  /// but the raw value is logged so the drift stays visible instead of being
  /// silently swallowed. The `unknown` sentinel (`unknown('')`) is never matched
  /// by value inside the known-value loop — only via the fall-through log+return
  /// path — so an empty/unrecognised backend status always hits the log.
  static OcpPaymentStatus fromValue(String value) {
    for (final status in OcpPaymentStatus.values) {
      if (status == OcpPaymentStatus.unknown) continue;
      if (status.value == value) return status;
    }
    developer.log(
      'Unrecognised OcpPaymentStatus "$value" — mapped to unknown (forward-compat).',
      name: 'OcpPaymentStatus',
    );
    return OcpPaymentStatus.unknown;
  }

  /// Polling stops once the payment reaches a final state.
  /// `unknown` is intentionally terminal so an unrecognised status can never cause an unbounded poll.
  bool get isTerminal =>
      this == completed || this == cancelled || this == expired || this == unknown;

  bool get isCompleted => this == completed;
}

/// Response of `GET /v1/realunit/pay/:id/status`.
class RealUnitOcpPayStatusDto {
  final OcpPaymentStatus status;

  const RealUnitOcpPayStatusDto({required this.status});

  factory RealUnitOcpPayStatusDto.fromJson(Map<String, dynamic> json) {
    return RealUnitOcpPayStatusDto(
      status: OcpPaymentStatus.fromValue(json['status'] as String),
    );
  }
}
