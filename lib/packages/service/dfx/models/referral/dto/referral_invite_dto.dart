/// One invite row from `GET /v1/realunit/referral/invites`.
/// Status values from the API: `Open` / `Bound` / `Credited` / `Deleted`.
/// The UI only surfaces Open as "offen" and Credited as "gutgeschrieben".
class ReferralInviteDto {
  final int id;
  final String code;
  final String url;
  final String guestName;
  final String status;
  final DateTime created;

  const ReferralInviteDto({
    required this.id,
    required this.code,
    required this.url,
    required this.guestName,
    required this.status,
    required this.created,
  });

  bool get isOpen => status == 'Open';
  bool get isCredited => status == 'Credited';

  factory ReferralInviteDto.fromJson(Map<String, dynamic> json) {
    return ReferralInviteDto(
      id: (json['id'] as num).toInt(),
      code: json['code'] as String,
      url: json['url'] as String,
      guestName: json['guestName'] as String,
      status: json['status'] as String,
      created: DateTime.parse(json['created'] as String),
    );
  }
}
