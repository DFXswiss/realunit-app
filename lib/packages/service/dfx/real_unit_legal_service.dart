import 'dart:convert';

import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_auth_service.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/legal/dto/real_unit_legal_info_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/legal/real_unit_legal_agreement.dart';

class RealUnitLegalService extends DFXAuthService {
  RealUnitLegalService(super.appStore, super.walletService);

  static const _legalPath = '/v1/realunit/legal';

  /// Fetches the API-side legal-acceptance state for the current wallet. The
  /// backend owns which agreements exist, their current version, and whether
  /// each is already accepted; the disclaimer gate in `KycCubit` renders
  /// `allAccepted` 1:1 instead of a local session flag — see CONTRIBUTING.md
  /// "API as Decision Authority".
  Future<RealUnitLegalInfoDto> getLegalInfo() async {
    final uri = buildUri(host, _legalPath);
    final response = await authenticatedGet(
      uri,
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode != 200) {
      final errorJson = jsonDecode(response.body) as Map<String, dynamic>;
      throw ApiException.fromJson(errorJson, httpStatusCode: response.statusCode);
    }

    return RealUnitLegalInfoDto.fromJson(jsonDecode(response.body));
  }

  /// Durably records acceptance of [agreements] for the current wallet. The
  /// backend stamps the current version and returns the refreshed info; the
  /// call is idempotent.
  Future<RealUnitLegalInfoDto> acceptLegal(List<RealUnitLegalAgreement> agreements) async {
    final uri = buildUri(host, _legalPath);
    final response = await authenticatedPut(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'agreements': agreements.map((a) => a.value).toList(),
      }),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      final errorJson = jsonDecode(response.body) as Map<String, dynamic>;
      throw ApiException.fromJson(errorJson, httpStatusCode: response.statusCode);
    }

    return RealUnitLegalInfoDto.fromJson(jsonDecode(response.body));
  }
}
