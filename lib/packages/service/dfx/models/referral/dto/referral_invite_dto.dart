import 'package:realunit_wallet/packages/service/dfx/models/referral/locale_text.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/referral_json_list.dart';

/// One invite row from `GET /v1/realunit/referral/invites`.
/// Empfehler list statuses: `Open` / `Credited`. Bound and Review are
/// folded to Open server-side and again here (TB Ziff. 7) so a backend
/// that still returns them cannot leak invitee progress into the DTO.
/// Deleted/expired/rejected stay closed. Unknown non-terminal statuses
/// are treated as open so a new API spelling cannot hide copy/share.
/// Credited/paid rows are not open.
bool creditedInviteStatus(String status) {
  final s = status.toLowerCase();
  return s == 'credited' ||
      s == 'complete' ||
      s == 'completed' ||
      s == 'success' ||
      s == 'settled' ||
      s == 'paid' ||
      s == 'done' ||
      s == 'transferred' ||
      s == 'confirmed';
}

bool closedInviteStatus(String status) {
  final s = status.toLowerCase();
  return s == 'deleted' ||
      s == 'cancelled' ||
      s == 'canceled' ||
      s == 'expired' ||
      s == 'rejected' ||
      s == 'closed';
}

/// Bound/Review/unknown non-terminal → Open. Credited and closed stay.
String foldEmpfehlerInviteStatus(String status) {
  if (creditedInviteStatus(status) || closedInviteStatus(status)) {
    return status;
  }
  return 'Open';
}

class ReferralInviteDto {
  final int id;
  final String code;
  final String url;
  final String guestName;
  final String status;
  final DateTime created;
  final String? copyText;
  final String? copyTextEn;
  final String? inviterName;

  const ReferralInviteDto({
    required this.id,
    required this.code,
    required this.url,
    required this.guestName,
    required this.status,
    required this.created,
    this.copyText,
    this.copyTextEn,
    this.inviterName,
  });

  bool get isOpen => !isCredited && !isClosed;

  bool get isCredited => creditedInviteStatus(status);

  bool get isClosed => closedInviteStatus(status);

  String? copyTextForLocale(String languageCode) {
    if (languageCode == 'en') {
      return firstNonEmpty([copyTextEn, copyText]);
    }
    return firstNonEmpty([copyText, copyTextEn]);
  }

  factory ReferralInviteDto.fromJson(Map<String, dynamic> json) {
    final created =
        referralJsonDate(json['created']) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final code = referralJsonString(json['code']);
    final url = referralInviteUrl(url: json['url'], code: code);
    final guestName = referralJsonString(json['guestName']) ?? '';
    if (code == null || url == null) {
      throw const FormatException('referral invite missing fields');
    }
    return ReferralInviteDto(
      id: referralJsonInt(json['id']),
      code: code,
      url: url,
      guestName: guestName,
      status: foldEmpfehlerInviteStatus(
        referralJsonString(json['status']) ?? 'Open',
      ),
      created: created,
      copyText: referralJsonString(json['copyText']),
      copyTextEn: referralJsonString(json['copyTextEn']),
      inviterName: referralPersonName(json['inviterName']),
    );
  }
}
