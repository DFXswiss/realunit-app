import 'package:realunit_wallet/packages/service/dfx/models/user/dto/real_unit_user_data_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/wallet/real_unit_registration_state.dart';

class RealUnitRegistrationInfoDto {
  /// API-side routing decision for this wallet. Drives KYC dispatch in
  /// `KycCubit._runCheckKyc` — see CONTRIBUTING.md "API as Decision
  /// Authority". `userData` is populated whenever a registration row exists —
  /// `alreadyRegistered` and `addWallet` both carry the stored signed payload —
  /// and for `newRegistration` when DFX KYC data can pre-fill the form. It is
  /// `null` only when the stored registration has no signed payload, or when
  /// there is no verified personal data to pre-fill from.
  ///
  /// `alreadyRegistered` is NOT a no-payload case: the personal-data KYC step
  /// is reached only through that branch and seeds its correction form from
  /// this payload, so treating it as null would dead-end that step.
  final RealUnitRegistrationState state;
  final RealUnitUserDataDto? realUnitUserDataDto;

  /// Whether the API has confirmed the account e-mail address for this wallet.
  /// Nullable on purpose: `null` means a pre-rollout backend (the field does
  /// not exist yet) or no registration at all — grandfathered accounts (in
  /// existence before the rollout) report an explicit `true`, never `null`.
  /// `KycCubit` treats `null` as "no confirmation gate" and proceeds as before —
  /// only an explicit `false` routes to the confirm step. See CONTRIBUTING.md
  /// "API as Decision Authority" (legacy backend tolerance).
  final bool? emailConfirmed;

  /// Timestamp of the confirmation, when the API reports one. Not consumed for
  /// routing (that is [emailConfirmed] alone); carried for completeness/display.
  final DateTime? confirmedDate;

  /// Whether this wallet's RealUnit registration is parked in manual review —
  /// the Aktionariat forward failed and it awaits a manual re-forward by staff.
  /// `true` only for the current wallet (`alreadyRegistered`); `false`/absent
  /// otherwise. Nullable on purpose: `null` means a pre-rollout backend (the
  /// field does not exist yet). `KycCubit` treats `null`/`false` as "no
  /// manual-review gate" and proceeds as before — only an explicit `true` routes
  /// to the review screen. See CONTRIBUTING.md "API as Decision Authority"
  /// (legacy backend tolerance).
  final bool? manualReview;

  RealUnitRegistrationInfoDto({
    required this.state,
    this.realUnitUserDataDto,
    this.emailConfirmed,
    this.confirmedDate,
    this.manualReview,
  });

  factory RealUnitRegistrationInfoDto.fromJson(Map<String, dynamic> json) {
    return RealUnitRegistrationInfoDto(
      state: RealUnitRegistrationState.fromJson(json['state'] as String),
      realUnitUserDataDto: json['userData'] != null
          ? RealUnitUserDataDto.fromJson(json['userData'] as Map<String, dynamic>)
          : null,
      emailConfirmed: json['emailConfirmed'] as bool?,
      confirmedDate: json['confirmedDate'] != null
          ? DateTime.parse(json['confirmedDate'] as String)
          : null,
      manualReview: json['manualReview'] as bool?,
    );
  }
}
