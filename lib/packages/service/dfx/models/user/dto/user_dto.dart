import 'package:realunit_wallet/packages/service/dfx/models/kyc/kyc_level.dart';
import 'package:realunit_wallet/styles/currency.dart';

class UserDto {
  final String? mail;
  final UserKycDto kyc;
  final UserCapabilitiesDto capabilities;
  /// Account display currency from GET /v2/user. Null when the field is
  /// absent or not a currency this app build knows.
  final Currency? currency;

  const UserDto({
    this.mail,
    required this.kyc,
    this.capabilities = const UserCapabilitiesDto(),
    this.currency,
  });

  factory UserDto.fromJson(Map<String, dynamic> json) {
    final currencyJson = json['currency'];
    return UserDto(
      mail: json['mail'] as String?,
      kyc: UserKycDto.fromJson(json['kyc'] as Map<String, dynamic>),
      capabilities: json['capabilities'] != null
          ? UserCapabilitiesDto.fromJson(json['capabilities'] as Map<String, dynamic>)
          : const UserCapabilitiesDto(),
      currency: currencyJson is Map<String, dynamic>
          ? Currency.tryFromCode(currencyJson['name'] as String?)
          : null,
    );
  }
}

class UserKycDto {
  final String hash;
  final KycLevel level;
  final bool dataComplete;

  const UserKycDto({
    required this.hash,
    required this.level,
    required this.dataComplete,
  });

  factory UserKycDto.fromJson(Map<String, dynamic> json) {
    return UserKycDto(
      hash: json['hash'] as String,
      level: KycLevelExtension.fromValue(json['level'] as int),
      dataComplete: json['dataComplete'] as bool,
    );
  }
}

// Mirror of `UserCapabilitiesDto` on the API. Authoritative per-action
// edit gating — the app renders Edit affordances from these flags
// instead of inferring them from KYC step status. Defaults are
// conservative (everything `false`) so pre-PR backends do not silently
// expose actions the API isn't yet ready to handle.
class UserCapabilitiesDto {
  final bool canEditName;
  final bool canEditMail;
  final bool canEditPhone;
  final bool canEditAddress;

  // Routing capability for the "Contact support" entry point. `null`
  // when the API does not (yet) ship the field — the app then falls
  // back to a direct push and lets the API reject the call if the
  // user is ineligible.
  final CreateSupportTicketCapabilityDto? createSupportTicket;

  const UserCapabilitiesDto({
    this.canEditName = false,
    this.canEditMail = false,
    this.canEditPhone = false,
    this.canEditAddress = false,
    this.createSupportTicket,
  });

  factory UserCapabilitiesDto.fromJson(Map<String, dynamic> json) {
    return UserCapabilitiesDto(
      canEditName: json['canEditName'] as bool? ?? false,
      canEditMail: json['canEditMail'] as bool? ?? false,
      canEditPhone: json['canEditPhone'] as bool? ?? false,
      canEditAddress: json['canEditAddress'] as bool? ?? false,
      createSupportTicket: json['createSupportTicket'] != null
          ? CreateSupportTicketCapabilityDto.fromJson(
              json['createSupportTicket'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}

// Mirror of `CreateSupportTicketCapabilityDto` on the API. When
// `available` is false, the API additionally reports the single
// `missingPrerequisite` blocking the flow. The app dispatches on the
// prerequisite to push the right capture page; it does not interpret
// `user.mail == null` itself.
class CreateSupportTicketCapabilityDto {
  final bool available;
  final MissingPrerequisite? missingPrerequisite;

  const CreateSupportTicketCapabilityDto({
    required this.available,
    this.missingPrerequisite,
  });

  factory CreateSupportTicketCapabilityDto.fromJson(Map<String, dynamic> json) {
    final missingRaw = json['missingPrerequisite'] as String?;
    return CreateSupportTicketCapabilityDto(
      available: json['available'] as bool? ?? false,
      missingPrerequisite: missingRaw == null ? null : MissingPrerequisite.fromString(missingRaw),
    );
  }
}

// Open enum: today the API models `Email` as a missing prerequisite
// (PHONE was removed in the API PR review). When the backend ships a
// new value, additive: extend this enum + add a routing branch in
// `SettingsContactPage._onSupportTap`. Until then, unknown wire values
// must NOT break the entire `getUser()` call — they degrade to `unknown`
// and the page falls back to a direct Support push (the support
// endpoint stays the authority).
enum MissingPrerequisite {
  email,
  unknown
  ;

  static MissingPrerequisite fromString(String value) => switch (value) {
    'Email' => email,
    _ => unknown,
  };
}
