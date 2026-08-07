import 'dart:convert';

import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_auth_service.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/dto/support_issue_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue_reason.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue_type.dart';

class DfxSupportService extends DFXAuthService {
  static const _supportPath = '/v1/support/issue';

  DfxSupportService(super.appStore, super.walletService);

  Future<List<SupportIssueDto>> getTickets() async {
    final uri = buildUri(host, _supportPath);
    final response = await authenticatedGet(
      uri,
      headers: {
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      final errorJson = jsonDecode(response.body) as Map<String, dynamic>;
      throw ApiException.fromJson(errorJson, httpStatusCode: response.statusCode);
    }

    final List<dynamic> jsonList = jsonDecode(response.body) as List<dynamic>;
    return jsonList.map((e) => SupportIssueDto.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<SupportIssueDto> getTicket(String uid) async {
    final uri = buildUri(host, '$_supportPath/$uid');
    final response = await authenticatedGet(
      uri,
      headers: {
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      final errorJson = jsonDecode(response.body) as Map<String, dynamic>;
      throw ApiException.fromJson(errorJson, httpStatusCode: response.statusCode);
    }

    return SupportIssueDto.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<SupportIssueDto> createTicket({
    required SupportIssueType type,
    required SupportIssueReason reason,
    required String name,
    String? message,
    String? file,
    String? fileName,
  }) async {
    final uri = buildUri(host, _supportPath);

    final body = jsonEncode({
      'type': type.toJson(),
      'reason': reason.toJson(),
      'name': name,
      if (message != null) 'message': message,
      if (file != null) 'file': file,
      if (fileName != null) 'fileName': fileName,
    });

    final response = await authenticatedPost(
      uri,
      headers: {
        'Content-Type': 'application/json',
      },
      body: body,
    );

    if (response.statusCode != 201) {
      final errorJson = jsonDecode(response.body) as Map<String, dynamic>;
      throw ApiException.fromJson(errorJson, httpStatusCode: response.statusCode);
    }

    return SupportIssueDto.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> sendMessage(
    String ticketUid, {
    String? message,
    String? file,
    String? fileName,
  }) async {
    final uri = buildUri(host, '$_supportPath/$ticketUid/message');

    final body = jsonEncode({
      if (message != null) 'message': message,
      if (file != null) 'file': file,
      if (fileName != null) 'fileName': fileName,
    });

    final response = await authenticatedPost(
      uri,
      headers: {
        'Content-Type': 'application/json',
      },
      body: body,
    );

    if (response.statusCode != 201) {
      final errorJson = jsonDecode(response.body) as Map<String, dynamic>;
      throw ApiException.fromJson(errorJson, httpStatusCode: response.statusCode);
    }
  }
}
