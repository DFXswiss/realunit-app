import 'dart:async';
import 'dart:convert';

import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/io/normalize_referral_code.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_auth_service.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_bind_result_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_code_lookup_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_created_invite_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_invite_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_payout_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_summary_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_terms_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/referral_json_list.dart';

class RealUnitReferralService extends DFXAuthService {
  RealUnitReferralService(super.appStore, super.walletService);

  static const _basePath = '/v1/realunit/referral';

  /// Public lookup and the landing page abort after 15s; authenticated
  /// referral calls use the same budget so terms/summary/bind cannot hang
  /// the UI past the bundled TB fallback.
  static const lookupTimeout = Duration(seconds: 15);

  Future<T> _timed<T>(
    Future<T> future, {
    Duration timeout = lookupTimeout,
  }) => future.timeout(timeout);

  Future<ReferralTermsDto> getTerms({
    Duration timeout = lookupTimeout,
  }) async {
    final uri = buildUri(host, '$_basePath/terms');
    final response = await _timed(
      authenticatedGet(
        uri,
        headers: {'Content-Type': 'application/json'},
      ),
      timeout: timeout,
    );

    if (response.statusCode != 200) {
      throw ApiException.fromBody(
        response.body,
        httpStatusCode: response.statusCode,
      );
    }

    return ReferralTermsDto.fromJson(
      referralJsonObject(
        jsonDecode(response.body),
        markers: const ['markdown', 'markdownEn', 'version'],
      ),
    );
  }

  Future<void> acceptTerms({
    String version = ReferralTermsDto.bundledVersion,
  }) async {
    final uri = buildUri(host, '$_basePath/terms/accept');
    final response = await _timed(
      authenticatedPost(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'accepted': true, 'version': version}),
      ),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw ApiException.fromBody(
        response.body,
        httpStatusCode: response.statusCode,
      );
    }
  }

  Future<ReferralSummaryDto> getSummary() async {
    final uri = buildUri(host, '$_basePath/summary');
    final response = await _timed(
      authenticatedGet(
        uri,
        headers: {'Content-Type': 'application/json'},
      ),
    );

    if (response.statusCode != 200) {
      throw ApiException.fromBody(
        response.body,
        httpStatusCode: response.statusCode,
      );
    }

    return ReferralSummaryDto.fromJson(
      referralJsonObject(
        jsonDecode(response.body),
        markers: const ['eligible', 'termsAccepted'],
      ),
    );
  }

  Future<ReferralCreatedInviteDto> createInvite({
    required String guestName,
  }) async {
    final uri = buildUri(host, '$_basePath/invites');
    final response = await _timed(
      authenticatedPost(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'guestName': guestName,
          'termsAccepted': true,
        }),
      ),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw ApiException.fromBody(
        response.body,
        httpStatusCode: response.statusCode,
      );
    }

    return ReferralCreatedInviteDto.fromJson(
      referralJsonObject(
        jsonDecode(response.body),
        markers: const ['code', 'url', 'guestName'],
      ),
    );
  }

  Future<List<ReferralInviteDto>> getInvites() async {
    final uri = buildUri(host, '$_basePath/invites');
    final response = await _timed(
      authenticatedGet(
        uri,
        headers: {'Content-Type': 'application/json'},
      ),
    );

    if (response.statusCode != 200) {
      throw ApiException.fromBody(
        response.body,
        httpStatusCode: response.statusCode,
      );
    }

    final invites = <ReferralInviteDto>[];
    for (final row in referralJsonList(jsonDecode(response.body))) {
      try {
        final invite = ReferralInviteDto.fromJson(row);
        if (!invite.isClosed) invites.add(invite);
      } catch (_) {
        // Skip a malformed row so one bad invite cannot hide copy/share.
      }
    }
    return invites;
  }

  Future<ReferralCodeLookupDto> lookupCode(
    String code, {
    Duration timeout = lookupTimeout,
  }) async {
    final normalized = _requireCode(code);
    final template = buildUri(host, _basePath);
    final uri = template.replace(
      pathSegments: [
        ...template.pathSegments.where((s) => s.isNotEmpty),
        'code',
        normalized,
      ],
    );
    final response = await _timed(
      appStore.httpClient.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ),
      timeout: timeout,
    );

    if (response.statusCode != 200) {
      throw ApiException.fromBody(
        response.body,
        httpStatusCode: response.statusCode,
      );
    }

    return ReferralCodeLookupDto.fromJson(
      referralJsonObject(
        jsonDecode(response.body),
        markers: const [
          'kind',
          'inviterName',
          'inviteeName',
          'campaignText',
          'actionText',
          'actionTextEn',
        ],
      ),
    );
  }

  Future<ReferralBindResultDto> bind({
    required String code,
    Duration timeout = lookupTimeout,
  }) async {
    final normalized = _requireCode(code);
    final uri = buildUri(host, '$_basePath/bind');
    final response = await _timed(
      authenticatedPost(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'code': normalized}),
      ),
      timeout: timeout,
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw ApiException.fromBody(
        response.body,
        httpStatusCode: response.statusCode,
      );
    }

    return ReferralBindResultDto.fromJson(
      referralJsonObject(
        jsonDecode(response.body),
        markers: const [
          'kind',
          'inviterName',
          'inviteeName',
          'campaignText',
          'actionText',
          'actionTextEn',
        ],
      ),
    );
  }

  Future<List<ReferralPayoutDto>> getPayouts() async {
    final uri = buildUri(host, '$_basePath/payouts');
    final response = await _timed(
      authenticatedGet(
        uri,
        headers: {'Content-Type': 'application/json'},
      ),
    );

    if (response.statusCode != 200) {
      throw ApiException.fromBody(
        response.body,
        httpStatusCode: response.statusCode,
      );
    }

    final payouts = <ReferralPayoutDto>[];
    for (final row in referralJsonList(jsonDecode(response.body))) {
      try {
        final dto = ReferralPayoutDto.fromJson(row);
        if (!dto.isSettled) continue;
        payouts.add(dto);
      } catch (_) {
        // Skip a malformed row so one bad prize cannot hide the rest.
      }
    }
    return payouts;
  }

  String _requireCode(String code) {
    final normalized = referralCodeFromInput(code);
    if (normalized == null) {
      throw const ApiException(
        statusCode: 400,
        code: 'INVALID',
        message: 'empty',
      );
    }
    return normalized;
  }
}
