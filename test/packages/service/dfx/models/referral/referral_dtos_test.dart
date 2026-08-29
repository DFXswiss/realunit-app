import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_bind_result_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_code_lookup_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_created_invite_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_invite_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_payout_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_summary_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_terms_dto.dart';

void main() {
  group('$ReferralSummaryDto.fromJson', () {
    test('parses the eligibility gate and running totals 1:1', () {
      final dto = ReferralSummaryDto.fromJson({
        'eligible': true,
        'termsAccepted': false,
        'minHolding': 70,
        'openCount': 2,
        'creditedCount': 1,
        'realuSum': 20,
        'chfSum': 246.5,
      });

      expect(dto.eligible, isTrue);
      expect(dto.termsAccepted, isFalse);
      expect(dto.minHolding, 70);
      expect(dto.openCount, 2);
      expect(dto.creditedCount, 1);
      expect(dto.realuSum, 20);
      expect(dto.chfSum, 246.5);
      expect(dto.sharePriceLabel, isNull);
      expect(dto.sharePrice, isNull);
      expect(dto.tileChf, 246.5);
    });

    test('tileChf is the running value at sharePrice when present', () {
      final dto = ReferralSummaryDto.fromJson({
        'eligible': true,
        'termsAccepted': true,
        'openCount': 0,
        'creditedCount': 2,
        'realuSum': 40,
        'chfSum': 512.4,
        'sharePrice': 1.38,
      });
      expect(dto.sharePrice, 1.38);
      expect(dto.tileChf, 55.2);
    });

    test('coerces eligible and termsAccepted from 1/true strings', () {
      final dto = ReferralSummaryDto.fromJson({
        'eligible': 1,
        'termsAccepted': 'true',
        'openCount': 0,
        'creditedCount': 0,
        'realuSum': 0,
        'chfSum': 0,
      });
      expect(dto.eligible, isTrue);
      expect(dto.termsAccepted, isTrue);

      final closed = ReferralSummaryDto.fromJson({
        'eligible': 'false',
        'termsAccepted': 0,
        'openCount': 0,
        'creditedCount': 0,
        'realuSum': 0,
        'chfSum': 0,
      });
      expect(closed.eligible, isFalse);
      expect(closed.termsAccepted, isFalse);
    });

    test('reads counts and sums from numeric strings', () {
      final dto = ReferralSummaryDto.fromJson({
        'eligible': true,
        'termsAccepted': true,
        'minHolding': '70',
        'openCount': '2',
        'creditedCount': '1',
        'realuSum': '40',
        'chfSum': '512.4',
      });
      expect(dto.minHolding, 70);
      expect(dto.openCount, 2);
      expect(dto.creditedCount, 1);
      expect(dto.realuSum, 40);
      expect(dto.chfSum, 512.4);
    });

    test('API Aktienkurs is a token; the tile uses localized copy', () {
      final dto = ReferralSummaryDto.fromJson({
        'eligible': true,
        'termsAccepted': true,
        'openCount': 0,
        'creditedCount': 0,
        'realuSum': 0,
        'chfSum': 0,
        'sharePriceLabel': 'Aktienkurs',
      });
      expect(dto.sharePriceLabel, 'Aktienkurs');
      expect(dto.tileSharePriceLabel, isNull);
    });

    test('empty and NAV sharePriceLabel fall back for the tile', () {
      final empty = ReferralSummaryDto.fromJson({
        'eligible': true,
        'termsAccepted': true,
        'openCount': 0,
        'creditedCount': 0,
        'realuSum': 0,
        'chfSum': 0,
        'sharePriceLabel': '  ',
      });
      expect(empty.sharePriceLabel, isNull);
      expect(empty.tileSharePriceLabel, isNull);

      final nav = ReferralSummaryDto.fromJson({
        'eligible': true,
        'termsAccepted': true,
        'openCount': 0,
        'creditedCount': 0,
        'realuSum': 0,
        'chfSum': 0,
        'sharePriceLabel': 'aktueller NAV',
      });
      expect(nav.sharePriceLabel, 'aktueller NAV');
      expect(nav.tileSharePriceLabel, isNull);
    });
  });

  group('$ReferralTermsDto', () {
    test('EN falls back to DE markdown', () {
      final dto = ReferralTermsDto.fromJson({
        'version': '2026-08-14',
        'markdown': 'DE md',
      });
      expect(dto.textForLang('de'), 'DE md');
      expect(dto.textForLang('en'), 'DE md');
    });

    test('EN prefers markdownEn', () {
      final dto = ReferralTermsDto.fromJson({
        'version': '2026-08-14',
        'markdown': 'DE md',
        'markdownEn': 'EN md',
      });
      expect(dto.textForLang('en'), 'EN md');
    });

    test('EN ignores empty markdownEn and uses DE', () {
      final dto = ReferralTermsDto.fromJson({
        'version': '2026-08-14',
        'markdown': 'DE md',
        'markdownEn': '  ',
      });
      expect(dto.textForLang('en'), 'DE md');
    });

    test('DE ignores empty markdown and uses EN', () {
      final dto = ReferralTermsDto.fromJson({
        'version': '2026-08-14',
        'markdown': '  ',
        'markdownEn': 'EN md',
      });
      expect(dto.textForLang('de'), 'EN md');
    });
  });

  group('$ReferralBindResultDto', () {
    test('maps Promo campaign text 1:1 and prefers EN when asked', () {
      final dto = ReferralBindResultDto.fromJson({
        'kind': 'Promo',
        'campaignText': 'DE text',
        'campaignTextEn': 'EN text',
        'minBuyRealu': 200,
        'validUntil': '2026-09-07T00:00:00Z',
        'redemptionCap': 100,
      });

      expect(dto.isPromo, isTrue);
      expect(dto.isInvite, isFalse);
      expect(dto.minBuyRealu, 200);
      expect(dto.redemptionCap, 100);
      expect(dto.campaignTextForLocale('en'), 'EN text');
      expect(dto.campaignTextForLocale('de'), 'DE text');
    });

    test('reads minBuyRealu from a numeric string', () {
      final dto = ReferralBindResultDto.fromJson({
        'kind': 'Promo',
        'minBuyRealu': '250',
        'redemptionCap': '80',
      });
      expect(dto.minBuyRealu, 250);
      expect(dto.redemptionCap, 80);
    });

    test('promo minBuyRealu defaults to 200 when the API omits it', () {
      final dto = ReferralBindResultDto.fromJson({
        'kind': 'Promo',
        'campaignText': 'DE text',
      });
      expect(dto.minBuyRealu, 200);

      final invite = ReferralBindResultDto.fromJson({'kind': 'Invite'});
      expect(invite.minBuyRealu, isNull);
    });

    test('EN falls back to DE when campaignTextEn is absent', () {
      final dto = ReferralBindResultDto.fromJson({
        'kind': 'Invite',
        'campaignText': 'DE only',
      });

      expect(dto.isInvite, isTrue);
      expect(dto.campaignTextForLocale('en'), 'DE only');
    });

    test('EN falls back to DE when campaignTextEn is empty', () {
      final dto = ReferralBindResultDto.fromJson({
        'kind': 'Promo',
        'campaignText': 'DE only',
        'campaignTextEn': '',
      });
      expect(dto.campaignTextForLocale('en'), 'DE only');
      expect(dto.campaignTextLang('en'), 'de');
    });

    test('campaignTextLang is en when EN campaign copy exists', () {
      final dto = ReferralBindResultDto.fromJson({
        'kind': 'Promo',
        'campaignText': 'DE text',
        'campaignTextEn': 'EN text',
      });
      expect(dto.campaignTextLang('en'), 'en');
      expect(dto.campaignTextLang('de'), 'de');
    });

    test('EN prefers actionTextEn when campaignTextEn is empty', () {
      final dto = ReferralBindResultDto.fromJson({
        'kind': 'Promo',
        'campaignText': 'DE only',
        'campaignTextEn': '',
        'actionTextEn': 'EN action',
      });
      expect(dto.campaignTextForLocale('en'), 'EN action');
    });

    test('DE prefers actionText over campaignText like lookup and the landing', () {
      final dto = ReferralBindResultDto.fromJson({
        'kind': 'Promo',
        'campaignText': 'DE campaign',
        'actionText': 'DE action',
      });
      expect(dto.campaignTextForLocale('de'), 'DE action');
      expect(dto.campaignTextLang('de'), 'de');
    });

    test('falls back to actionText and treats campaign copy without kind as promo', () {
      final dto = ReferralBindResultDto.fromJson({
        'actionText': 'Mit dem Code EVT1 schenken wir dir 20 Token.',
      });
      expect(dto.isPromo, isTrue);
      expect(
        dto.campaignTextForLocale('de'),
        'Mit dem Code EVT1 schenken wir dir 20 Token.',
      );
    });

    test('kind matching is case-insensitive', () {
      expect(
        ReferralBindResultDto.fromJson({'kind': 'promo'}).isPromo,
        isTrue,
      );
      expect(
        ReferralBindResultDto.fromJson({'kind': 'INVITE'}).isInvite,
        isTrue,
      );
    });

    test('keeps inviterName and inviteeName from an invite bind', () {
      final dto = ReferralBindResultDto.fromJson({
        'kind': 'Invite',
        'inviterName': 'Björn',
        'inviteeName': 'Alice',
        'actionText': 'Hey Alice, Björn lädt dich ein',
      });
      expect(dto.isInvite, isTrue);
      expect(dto.inviterName, 'Björn');
      expect(dto.inviteeName, 'Alice');
      expect(dto.displayInviterName, 'Björn');
      expect(dto.actionText, 'Hey Alice, Björn lädt dich ein');
    });

    test('whitespace-only inviterName is not displayed', () {
      final dto = ReferralBindResultDto.fromJson({
        'kind': 'Invite',
        'inviterName': '   ',
      });
      expect(dto.displayInviterName, isNull);
    });

    test('wallet-address and numeric inviterName are not displayed', () {
      final wallet = ReferralBindResultDto.fromJson({
        'kind': 'Invite',
        'inviterName': '0x553C7f9C780316FC1D34b8e14ac2465Ab22a090B',
      });
      expect(wallet.inviterName, isNull);
      expect(wallet.displayInviterName, isNull);

      final numeric = ReferralBindResultDto.fromJson({
        'kind': 'Invite',
        'inviterName': '12345',
      });
      expect(numeric.inviterName, isNull);
    });

    test('campaignTextLang keeps the UI language when there is no copy', () {
      final dto = ReferralBindResultDto.fromJson({
        'kind': 'Invite',
        'inviterName': 'Björn',
      });
      expect(dto.campaignTextForLocale('en'), isNull);
      expect(dto.campaignTextForLocale('de'), isNull);
      expect(dto.campaignTextLang('en'), 'en');
      expect(dto.campaignTextLang('de'), 'de');
    });
  });

  group('$ReferralInviteDto.fromJson', () {
    test('maps Open / Credited status flags', () {
      final open = ReferralInviteDto.fromJson({
        'id': 1,
        'code': 'AB12',
        'url': 'https://realunit.app/invite/AB12',
        'guestName': 'Alice',
        'status': 'Open',
        'created': '2026-08-24T10:00:00Z',
      });
      final credited = ReferralInviteDto.fromJson({
        'id': 2,
        'code': 'CD34',
        'url': 'https://realunit.app/invite/CD34',
        'guestName': 'Bob',
        'status': 'Credited',
        'created': '2026-08-24T10:00:00Z',
      });

      expect(open.isOpen, isTrue);
      expect(open.isCredited, isFalse);
      expect(credited.isCredited, isTrue);
      expect(open.copyTextForLocale('de'), isNull);
      expect(open.inviterName, isNull);
      expect(foldEmpfehlerInviteStatus('Bound'), 'Open');
      expect(foldEmpfehlerInviteStatus('Review'), 'Open');
      expect(foldEmpfehlerInviteStatus('Credited'), 'Credited');
      expect(foldEmpfehlerInviteStatus('Deleted'), 'Deleted');
    });

    test('stringifies a numeric code and trims guestName', () {
      final dto = ReferralInviteDto.fromJson({
        'id': 1,
        'code': 12,
        'url': 'https://realunit.app/invite/12',
        'guestName': '  Alice  ',
        'status': 'Open',
        'created': '2026-08-24T10:00:00Z',
      });
      expect(dto.code, '12');
      expect(dto.guestName, 'Alice');
    });

    test('keeps inviterName so share fallback can name the Empfehler', () {
      final dto = ReferralInviteDto.fromJson({
        'id': 1,
        'code': 'AB12',
        'url': 'https://realunit.app/invite/AB12',
        'guestName': 'Alice',
        'status': 'Open',
        'created': '2026-08-24T10:00:00Z',
        'inviterName': 'Björn',
      });
      expect(dto.inviterName, 'Björn');

      final wallet = ReferralInviteDto.fromJson({
        'id': 3,
        'code': 'EF56',
        'url': 'https://realunit.app/invite/EF56',
        'guestName': 'Cara',
        'status': 'Open',
        'created': '2026-08-24T10:00:00Z',
        'inviterName': '0x553C7f9C780316FC1D34b8e14ac2465Ab22a090B',
      });
      expect(wallet.inviterName, isNull);

      final blank = ReferralInviteDto.fromJson({
        'id': 2,
        'code': 'CD34',
        'url': 'https://realunit.app/invite/CD34',
        'guestName': 'Bob',
        'status': 'Open',
        'created': '2026-08-24T10:00:00Z',
        'inviterName': '   ',
      });
      expect(blank.inviterName, isNull);
    });

    test('keeps a nameless invite when guestName is missing or blank', () {
      final omitted = ReferralInviteDto.fromJson({
        'id': 1,
        'code': 'AB12',
        'url': 'https://realunit.app/invite/AB12',
        'status': 'Open',
        'created': '2026-08-24T10:00:00Z',
      });
      final blank = ReferralInviteDto.fromJson({
        'id': 2,
        'code': 'CD34',
        'url': 'https://realunit.app/invite/CD34',
        'guestName': '  ',
        'status': 'Open',
        'created': '2026-08-24T10:00:00Z',
      });
      expect(omitted.guestName, isEmpty);
      expect(omitted.isOpen, isTrue);
      expect(blank.guestName, isEmpty);
    });

    test('keeps an open invite when created is missing', () {
      final dto = ReferralInviteDto.fromJson({
        'id': 1,
        'code': 'AB12',
        'url': 'https://realunit.app/invite/AB12',
        'guestName': 'Alice',
        'status': 'Open',
      });
      expect(dto.isOpen, isTrue);
      expect(dto.code, 'AB12');
      expect(dto.created, DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
    });

    test('treats a missing or blank status as Open', () {
      final omitted = ReferralInviteDto.fromJson({
        'id': 1,
        'code': 'AB12',
        'url': 'https://realunit.app/invite/AB12',
        'guestName': 'Alice',
        'created': '2026-08-24T10:00:00Z',
      });
      final blank = ReferralInviteDto.fromJson({
        'id': 2,
        'code': 'CD34',
        'url': 'https://realunit.app/invite/CD34',
        'guestName': 'Bob',
        'status': '  ',
        'created': '2026-08-24T10:00:00Z',
      });
      expect(omitted.status, 'Open');
      expect(omitted.isOpen, isTrue);
      expect(blank.status, 'Open');
      expect(blank.isOpen, isTrue);
    });

    test('fills the invite url from the code when url is omitted', () {
      final dto = ReferralInviteDto.fromJson({
        'id': 1,
        'code': 'AB12',
        'guestName': 'Alice',
        'status': 'Open',
        'created': '2026-08-24T10:00:00Z',
      });
      expect(dto.url, 'https://realunit.app/invite/AB12');
    });

    test('status matching is case-insensitive', () {
      expect(
        ReferralInviteDto.fromJson({
          'id': 1,
          'code': 'AB12',
          'url': 'https://realunit.app/invite/AB12',
          'guestName': 'Alice',
          'status': 'open',
          'created': '2026-08-24T10:00:00Z',
        }).isOpen,
        isTrue,
      );
      expect(
        ReferralInviteDto.fromJson({
          'id': 2,
          'code': 'CD34',
          'url': 'https://realunit.app/invite/CD34',
          'guestName': 'Bob',
          'status': 'CREDITED',
          'created': '2026-08-24T10:00:00Z',
        }).isCredited,
        isTrue,
      );
      expect(
        ReferralInviteDto.fromJson({
          'id': 3,
          'code': 'EF56',
          'url': 'https://realunit.app/invite/EF56',
          'guestName': 'Cara',
          'status': 'Pending',
          'created': '2026-08-24T10:00:00Z',
        }).isOpen,
        isTrue,
      );
      expect(
        ReferralInviteDto.fromJson({
          'id': 4,
          'code': 'GH78',
          'url': 'https://realunit.app/invite/GH78',
          'guestName': 'Dan',
          'status': 'Completed',
          'created': '2026-08-24T10:00:00Z',
        }).isCredited,
        isTrue,
      );
      final bound = ReferralInviteDto.fromJson({
        'id': 5,
        'code': 'IJ90',
        'url': 'https://realunit.app/invite/IJ90',
        'guestName': 'Eve',
        'status': 'Bound',
        'created': '2026-08-24T10:00:00Z',
      });
      expect(bound.status, 'Open');
      expect(bound.isOpen, isTrue);
      expect(bound.isCredited, isFalse);
      final review = ReferralInviteDto.fromJson({
        'id': 9,
        'code': 'QR78',
        'url': 'https://realunit.app/invite/QR78',
        'guestName': 'Ina',
        'status': 'Review',
        'created': '2026-08-24T10:00:00Z',
      });
      expect(review.status, 'Open');
      expect(review.isOpen, isTrue);
      expect(review.isCredited, isFalse);
      expect(
        ReferralInviteDto.fromJson({
          'id': 10,
          'code': 'ST90',
          'url': 'https://realunit.app/invite/ST90',
          'guestName': 'Jay',
          'status': 'Expired',
          'created': '2026-08-24T10:00:00Z',
        }).isOpen,
        isFalse,
      );
      expect(
        ReferralInviteDto.fromJson({
          'id': 7,
          'code': 'MN34',
          'url': 'https://realunit.app/invite/MN34',
          'guestName': 'Gus',
          'status': 'Registered',
          'created': '2026-08-24T10:00:00Z',
        }).isOpen,
        isTrue,
      );
      expect(
        ReferralInviteDto.fromJson({
          'id': 8,
          'code': 'OP56',
          'url': 'https://realunit.app/invite/OP56',
          'guestName': 'Hal',
          'status': 'Paid',
          'created': '2026-08-24T10:00:00Z',
        }).isOpen,
        isFalse,
      );
      expect(
        ReferralInviteDto.fromJson({
          'id': 6,
          'code': 'KL12',
          'url': 'https://realunit.app/invite/KL12',
          'guestName': 'Fay',
          'status': 'Deleted',
          'created': '2026-08-24T10:00:00Z',
        }).isOpen,
        isFalse,
      );
    });

    test('EN share text falls back to DE copyText', () {
      final dto = ReferralInviteDto.fromJson({
        'id': 1,
        'code': 'AB12',
        'url': 'https://realunit.app/invite/AB12',
        'guestName': 'Alice',
        'status': 'Open',
        'created': '2026-08-24T10:00:00Z',
        'copyText': 'Hey Alice, Björn lädt dich ein',
        'copyTextEn': 'Hey Alice, Björn is inviting you',
      });
      expect(dto.copyTextForLocale('en'), 'Hey Alice, Björn is inviting you');
      expect(dto.copyTextForLocale('de'), 'Hey Alice, Björn lädt dich ein');

      final fallback = ReferralInviteDto.fromJson({
        'id': 2,
        'code': 'CD34',
        'url': 'https://realunit.app/invite/CD34',
        'guestName': 'Bob',
        'status': 'Open',
        'created': '2026-08-24T10:00:00Z',
        'copyText': 'Hey Bob, Björn lädt dich ein',
        'copyTextEn': '',
      });
      expect(fallback.copyTextForLocale('en'), 'Hey Bob, Björn lädt dich ein');
    });

    test('throws when code is missing or blank', () {
      expect(
        () => ReferralInviteDto.fromJson({
          'id': 1,
          'url': 'https://realunit.app/invite/AB12',
          'guestName': 'Alice',
          'status': 'Open',
          'created': '2026-08-24T10:00:00Z',
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'referral invite missing fields',
          ),
        ),
      );
      expect(
        () => ReferralInviteDto.fromJson({
          'id': 2,
          'code': '   ',
          'guestName': 'Bob',
          'status': 'Open',
          'created': '2026-08-24T10:00:00Z',
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('$ReferralPayoutDto.fromJson', () {
    test('keeps the CHF value frozen at credit', () {
      final dto = ReferralPayoutDto.fromJson({
        'id': 9,
        'amount': 20,
        'chfValue': 246.5,
        'created': '2026-08-24T10:00:00Z',
        'kind': 'Invite',
        'status': 'Complete',
        'txHash': '0xabc',
      });

      expect(dto.amount, 20);
      expect(dto.chfValue, 246.5);
      expect(dto.txHash, '0xabc');
      expect(dto.isSettled, isTrue);
    });

    test('reads amount and frozen CHF when the API sends numeric strings', () {
      final dto = ReferralPayoutDto.fromJson({
        'id': '9',
        'amount': '20',
        'chfValue': '246.50',
        'created': '2026-08-24T10:00:00Z',
        'kind': 'Invite',
        'status': 'Complete',
      });
      expect(dto.id, 9);
      expect(dto.amount, 20);
      expect(dto.chfValue, 246.5);
    });

    test('reads a locale-formatted frozen CHF string', () {
      final dto = ReferralPayoutDto.fromJson({
        'id': 9,
        'amount': 20,
        'chfValue': "CHF 1'246,50",
        'created': '2026-08-24T10:00:00Z',
        'status': 'Complete',
      });
      expect(dto.chfValue, 1246.5);
    });

    test('keeps Anzahl and Datum when frozen CHF is missing', () {
      final dto = ReferralPayoutDto.fromJson({
        'id': 9,
        'amount': 20,
        'created': '2026-08-24T10:00:00Z',
        'status': 'Settled',
      });
      expect(dto.amount, 20);
      expect(dto.chfValue, 0);
      expect(dto.created, DateTime.utc(2026, 8, 24, 10));
    });

    test('reads created from a Unix timestamp', () {
      final dto = ReferralPayoutDto.fromJson({
        'id': 9,
        'amount': 20,
        'chfValue': 246.5,
        'created': 1787565600,
        'status': 'Complete',
      });
      expect(dto.created, DateTime.utc(2026, 8, 24, 10));
    });

    test('treats a zoneless MySQL DATETIME created as UTC', () {
      final dto = ReferralPayoutDto.fromJson({
        'id': 9,
        'amount': 20,
        'chfValue': 246.5,
        'created': '2026-08-24 10:00:00',
        'status': 'Complete',
      });
      expect(dto.created, DateTime.utc(2026, 8, 24, 10));
    });

    test('stringifies a numeric txHash', () {
      final dto = ReferralPayoutDto.fromJson({
        'id': 9,
        'amount': 20,
        'chfValue': 1,
        'created': '2026-08-24T10:00:00Z',
        'status': 'Complete',
        'txHash': 123,
      });
      expect(dto.txHash, '123');
    });

    test('pending and failed payouts are not settled; missing status is', () {
      expect(
        ReferralPayoutDto.fromJson({
          'id': 1,
          'amount': 20,
          'chfValue': 1,
          'created': '2026-08-24T10:00:00Z',
          'status': 'Pending',
        }).isSettled,
        isFalse,
      );
      expect(
        ReferralPayoutDto.fromJson({
          'id': 2,
          'amount': 20,
          'chfValue': 1,
          'created': '2026-08-24T10:00:00Z',
        }).isSettled,
        isTrue,
      );
      expect(
        ReferralPayoutDto.fromJson({
          'id': 3,
          'amount': 20,
          'chfValue': 1,
          'created': '2026-08-24T10:00:00Z',
          'status': 'Settled',
        }).isSettled,
        isTrue,
      );
      expect(
        ReferralPayoutDto.fromJson({
          'id': 4,
          'amount': 20,
          'chfValue': 1,
          'created': '2026-08-24T10:00:00Z',
          'status': 'Paid',
        }).isSettled,
        isTrue,
      );
    });
  });

  group('$ReferralCreatedInviteDto.fromJson', () {
    test('parses code, url, guest name and optional copy text', () {
      final dto = ReferralCreatedInviteDto.fromJson({
        'code': 'AB12',
        'url': 'https://realunit.app/invite/AB12',
        'guestName': 'Alice',
        'copyText': 'Hey Alice',
      });

      expect(dto.code, 'AB12');
      expect(dto.url, 'https://realunit.app/invite/AB12');
      expect(dto.guestName, 'Alice');
      expect(dto.copyText, 'Hey Alice');
      expect(dto.inviterName, isNull);
    });

    test('keeps inviterName so share fallback can name the Empfehler', () {
      final dto = ReferralCreatedInviteDto.fromJson({
        'code': 'AB12',
        'url': 'https://realunit.app/invite/AB12',
        'guestName': 'Alice',
        'inviterName': 'Björn',
      });
      expect(dto.inviterName, 'Björn');

      final blank = ReferralCreatedInviteDto.fromJson({
        'code': 'AB12',
        'url': 'https://realunit.app/invite/AB12',
        'guestName': 'Alice',
        'inviterName': '   ',
      });
      expect(blank.inviterName, isNull);
    });

    test('wallet-address inviterName is omitted on create', () {
      final dto = ReferralCreatedInviteDto.fromJson({
        'code': 'AB12',
        'url': 'https://realunit.app/invite/AB12',
        'guestName': 'Alice',
        'inviterName': '0x553C7f9C780316FC1D34b8e14ac2465Ab22a090B',
      });
      expect(dto.inviterName, isNull);
    });

    test('keeps a nameless created invite when guestName is omitted', () {
      final dto = ReferralCreatedInviteDto.fromJson({
        'code': 'AB12',
        'url': 'https://realunit.app/invite/AB12',
      });
      expect(dto.guestName, isEmpty);
      expect(dto.code, 'AB12');
    });

    test('fills https://realunit.app/invite/{code} when url is relative or missing', () {
      final relative = ReferralCreatedInviteDto.fromJson({
        'code': 'AB12',
        'url': '/invite/AB12',
        'guestName': 'Alice',
      });
      expect(relative.url, 'https://realunit.app/invite/AB12');

      final missing = ReferralCreatedInviteDto.fromJson({
        'code': 'AB12',
        'guestName': 'Alice',
      });
      expect(missing.url, 'https://realunit.app/invite/AB12');
    });

    test('folds protocol-relative and scheme-less hosts onto https://realunit.app', () {
      final protocolRelative = ReferralCreatedInviteDto.fromJson({
        'code': 'AB12',
        'url': '//www.realunit.app/invite/AB12',
        'guestName': 'Alice',
      });
      expect(protocolRelative.url, 'https://realunit.app/invite/AB12');

      final schemeLess = ReferralCreatedInviteDto.fromJson({
        'code': 'EVT1',
        'url': 'realunit.app/promo/EVT1',
        'guestName': 'Alice',
      });
      expect(schemeLess.url, 'https://realunit.app/promo/EVT1');
    });

    test('EN share text falls back to DE copyText', () {
      final dto = ReferralCreatedInviteDto.fromJson({
        'code': 'AB12',
        'url': 'https://realunit.app/invite/AB12',
        'guestName': 'Alice',
        'copyText': 'Hey Alice, Björn lädt dich ein',
        'copyTextEn': 'Hey Alice, Björn is inviting you',
      });
      expect(dto.copyTextForLocale('en'), 'Hey Alice, Björn is inviting you');
      expect(dto.copyTextForLocale('de'), 'Hey Alice, Björn lädt dich ein');
    });

    test('EN share text ignores empty copyTextEn', () {
      final dto = ReferralCreatedInviteDto.fromJson({
        'code': 'AB12',
        'url': 'https://realunit.app/invite/AB12',
        'guestName': 'Alice',
        'copyText': 'Hey Alice, Björn lädt dich ein',
        'copyTextEn': '',
      });
      expect(dto.copyTextForLocale('en'), 'Hey Alice, Björn lädt dich ein');
    });

    test('throws when code is missing or blank', () {
      expect(
        () => ReferralCreatedInviteDto.fromJson({
          'url': 'https://realunit.app/invite/AB12',
          'guestName': 'Alice',
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'referral created invite missing fields',
          ),
        ),
      );
      expect(
        () => ReferralCreatedInviteDto.fromJson({
          'code': '   ',
          'guestName': 'Alice',
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('$ReferralCodeLookupDto.fromJson', () {
    test('maps invite recognition and promo campaign text', () {
      final invite = ReferralCodeLookupDto.fromJson({
        'kind': 'invite',
        'inviterName': 'Björn',
        'inviteeName': 'Alice',
      });
      expect(invite.isInvite, isTrue);
      expect(invite.inviterName, 'Björn');
      expect(invite.displayInviterName, 'Björn');

      final promo = ReferralCodeLookupDto.fromJson({
        'kind': 'Promo',
        'actionText': 'DE action',
        'campaignTextEn': 'EN campaign',
      });
      expect(promo.isPromo, isTrue);
      expect(promo.campaignTextForLocale('en'), 'EN campaign');
      expect(promo.campaignTextForLocale('de'), 'DE action');
      expect(promo.campaignTextLang('en'), 'en');
      expect(promo.campaignTextLang('de'), 'de');
    });

    test('whitespace-only inviterName is not displayed', () {
      final invite = ReferralCodeLookupDto.fromJson({
        'kind': 'invite',
        'inviterName': '   ',
      });
      expect(invite.isInvite, isTrue);
      expect(invite.displayInviterName, isNull);
    });

    test('wallet-address inviterName is not displayed on lookup', () {
      final invite = ReferralCodeLookupDto.fromJson({
        'kind': 'invite',
        'inviterName': '0x553C7f9C780316FC1D34b8e14ac2465Ab22a090B',
      });
      expect(invite.isInvite, isTrue);
      expect(invite.displayInviterName, isNull);
    });

    test('EN campaign text ignores empty campaignTextEn', () {
      final promo = ReferralCodeLookupDto.fromJson({
        'kind': 'promo',
        'actionText': 'DE action',
        'campaignTextEn': '   ',
      });
      expect(promo.campaignTextForLocale('en'), 'DE action');
      expect(promo.campaignTextLang('en'), 'de');
    });

    test('EN prefers actionTextEn and promo minBuyRealu defaults to 200', () {
      final promo = ReferralCodeLookupDto.fromJson({
        'kind': 'promo',
        'actionText': 'DE action',
        'actionTextEn': 'EN action',
      });
      expect(promo.campaignTextForLocale('en'), 'EN action');
      expect(promo.minBuyRealu, 200);
      expect(
        ReferralCodeLookupDto.fromJson({'kind': 'invite'}).minBuyRealu,
        isNull,
      );
    });

    test('infers promo from action text when kind is omitted', () {
      final promo = ReferralCodeLookupDto.fromJson({
        'actionText': 'Mit dem Code EVT1 schenken wir dir 20 Token.',
      });
      expect(promo.isPromo, isTrue);
    });

    test('infers promo from actionTextEn when kind and DE copy are omitted', () {
      final promo = ReferralCodeLookupDto.fromJson({
        'actionTextEn': 'With code EVT1 we give you 20 tokens.',
      });
      expect(promo.isPromo, isTrue);
    });

    test('infers invite from inviterName when kind is omitted', () {
      final invite = ReferralCodeLookupDto.fromJson({
        'inviterName': 'Björn',
      });
      expect(invite.isInvite, isTrue);
    });

    test('blank kind is ignored so action text still infers promo', () {
      final promo = ReferralCodeLookupDto.fromJson({
        'kind': '  ',
        'actionText': 'Mit dem Code EVT1 schenken wir dir 20 Token.',
      });
      expect(promo.isPromo, isTrue);
    });

    test('inviterName wins over action text when kind is omitted', () {
      final invite = ReferralCodeLookupDto.fromJson({
        'inviterName': 'Björn',
        'actionText': 'Mit dem Code EVT1 schenken wir dir 20 Token.',
      });
      expect(invite.isInvite, isTrue);
    });

    test('campaignTextLang keeps the UI language when there is no copy', () {
      final dto = ReferralCodeLookupDto.fromJson({
        'kind': 'invite',
        'inviterName': 'Björn',
      });
      expect(dto.campaignTextForLocale('en'), isNull);
      expect(dto.campaignTextForLocale('de'), isNull);
      expect(dto.campaignTextLang('en'), 'en');
      expect(dto.campaignTextLang('de'), 'de');
    });
  });
}
