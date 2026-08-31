import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/packages/service/dfx/models/kyc/kyc_level.dart';
import 'package:realunit_wallet/packages/service/dfx/models/user/dto/user_dto.dart';
import 'package:realunit_wallet/styles/currency.dart';

void main() {
  group('$UserKycDto.fromJson', () {
    test('parses hash + level + dataComplete', () {
      final dto = UserKycDto.fromJson({
        'hash': 'abc123',
        'level': 20,
        'dataComplete': true,
      });

      expect(dto.hash, 'abc123');
      expect(dto.level, KycLevel.level20);
      expect(dto.dataComplete, isTrue);
    });

    test('routes level through KycLevelExtension.fromValue', () {
      // The factory delegates the int → enum mapping; pin a non-trivial
      // sentinel so a future regression in the enum mapper is caught here.
      final dto = UserKycDto.fromJson({
        'hash': 'h',
        'level': -10,
        'dataComplete': false,
      });

      expect(dto.level, KycLevel.terminated);
    });
  });

  group('$UserCapabilitiesDto.fromJson', () {
    test('reads all four flags when the API sends them as true', () {
      // Authoritative shape from the API. Every flag false→true flip
      // enables a different UI edit affordance (name / mail / phone /
      // address).
      final dto = UserCapabilitiesDto.fromJson({
        'canEditName': true,
        'canEditMail': true,
        'canEditPhone': true,
        'canEditAddress': true,
      });

      expect(dto.canEditName, isTrue);
      expect(dto.canEditMail, isTrue);
      expect(dto.canEditPhone, isTrue);
      expect(dto.canEditAddress, isTrue);
    });

    test('reads all four flags when the API sends them as false', () {
      final dto = UserCapabilitiesDto.fromJson({
        'canEditName': false,
        'canEditMail': false,
        'canEditPhone': false,
        'canEditAddress': false,
      });

      expect(dto.canEditName, isFalse);
      expect(dto.canEditMail, isFalse);
      expect(dto.canEditPhone, isFalse);
      expect(dto.canEditAddress, isFalse);
    });

    test('missing flag falls back to false (conservative default)', () {
      // Pre-PR backends do not yet ship the capabilities object. Each
      // missing field must default to false so the app does not silently
      // expose actions the API isn't ready to handle.
      final dto = UserCapabilitiesDto.fromJson(<String, dynamic>{});

      expect(dto.canEditName, isFalse);
      expect(dto.canEditMail, isFalse);
      expect(dto.canEditPhone, isFalse);
      expect(dto.canEditAddress, isFalse);
    });

    test('null flag on the wire falls back to false', () {
      // A null value (instead of just missing) must also fold to false —
      // otherwise an `as bool?` cast that succeeds would later throw at
      // first use.
      final dto = UserCapabilitiesDto.fromJson({
        'canEditName': null,
        'canEditMail': null,
        'canEditPhone': null,
        'canEditAddress': null,
      });

      expect(dto.canEditName, isFalse);
      expect(dto.canEditMail, isFalse);
      expect(dto.canEditPhone, isFalse);
      expect(dto.canEditAddress, isFalse);
    });

    test('flags are independent (true/false mix is preserved per field)', () {
      // Pins per-flag wiring — a copy-paste swap inside the factory
      // (canEditName ← canEditMail) would otherwise round-trip uniform
      // payloads without failing.
      final dto = UserCapabilitiesDto.fromJson({
        'canEditName': true,
        'canEditMail': false,
        'canEditPhone': true,
        'canEditAddress': false,
      });

      expect(dto.canEditName, isTrue);
      expect(dto.canEditMail, isFalse);
      expect(dto.canEditPhone, isTrue);
      expect(dto.canEditAddress, isFalse);
    });

    test('const default constructor yields all-false capabilities', () {
      // The default instance is the fallback used when the API does not
      // return a `capabilities` block at all — it must be conservative.
      const dto = UserCapabilitiesDto();

      expect(dto.canEditName, isFalse);
      expect(dto.canEditMail, isFalse);
      expect(dto.canEditPhone, isFalse);
      expect(dto.canEditAddress, isFalse);
      expect(dto.createSupportTicket, isNull);
    });

    test('createSupportTicket present + available true → parses with no prerequisite', () {
      // Happy path. User has a registered email — the API tells the
      // app it can open a Support ticket directly.
      final dto = UserCapabilitiesDto.fromJson({
        'canEditName': true,
        'canEditMail': true,
        'canEditPhone': true,
        'canEditAddress': true,
        'createSupportTicket': {'available': true},
      });

      expect(dto.createSupportTicket, isNotNull);
      expect(dto.createSupportTicket!.available, isTrue);
      expect(dto.createSupportTicket!.missingPrerequisite, isNull);
    });

    test('createSupportTicket present + available false + Email prerequisite parses', () {
      // Routing-relevant: the page must dispatch on
      // missingPrerequisite to push the email-capture flow.
      final dto = UserCapabilitiesDto.fromJson({
        'canEditName': false,
        'canEditMail': false,
        'canEditPhone': false,
        'canEditAddress': false,
        'createSupportTicket': {
          'available': false,
          'missingPrerequisite': 'Email',
        },
      });

      expect(dto.createSupportTicket, isNotNull);
      expect(dto.createSupportTicket!.available, isFalse);
      expect(
        dto.createSupportTicket!.missingPrerequisite,
        MissingPrerequisite.email,
      );
    });

    test('createSupportTicket absent (legacy backend) → null', () {
      // Pre-3772 backends ship `capabilities` without the new field.
      // The app must treat this as "no information available" and
      // fall back to a direct push.
      final dto = UserCapabilitiesDto.fromJson({
        'canEditName': true,
        'canEditMail': true,
        'canEditPhone': true,
        'canEditAddress': true,
      });

      expect(dto.createSupportTicket, isNull);
    });

    test('createSupportTicket explicitly null → null', () {
      // Same default branch via an explicit JSON null.
      final dto = UserCapabilitiesDto.fromJson({
        'canEditName': true,
        'canEditMail': true,
        'canEditPhone': true,
        'canEditAddress': true,
        'createSupportTicket': null,
      });

      expect(dto.createSupportTicket, isNull);
    });
  });

  group('$CreateSupportTicketCapabilityDto.fromJson', () {
    test('available true with no missingPrerequisite parses cleanly', () {
      final dto = CreateSupportTicketCapabilityDto.fromJson({'available': true});

      expect(dto.available, isTrue);
      expect(dto.missingPrerequisite, isNull);
    });

    test('available false with Email prerequisite parses to enum value', () {
      final dto = CreateSupportTicketCapabilityDto.fromJson({
        'available': false,
        'missingPrerequisite': 'Email',
      });

      expect(dto.available, isFalse);
      expect(dto.missingPrerequisite, MissingPrerequisite.email);
    });

    test('missing `available` field defaults to false (conservative)', () {
      // Defensive parsing: a malformed payload that omits `available`
      // must not silently expose the flow.
      final dto = CreateSupportTicketCapabilityDto.fromJson(
        <String, dynamic>{},
      );

      expect(dto.available, isFalse);
      expect(dto.missingPrerequisite, isNull);
    });

    test('unknown missingPrerequisite string degrades to MissingPrerequisite.unknown', () {
      // Open enum: a future additive value the app does not yet
      // recognise must NOT break /v2/user parsing for unrelated
      // callers (KYC, settings, etc.). We degrade to `unknown` and
      // the page falls back to a direct Support push.
      final dto = CreateSupportTicketCapabilityDto.fromJson({
        'available': false,
        'missingPrerequisite': 'Phone',
      });
      expect(dto.available, isFalse);
      expect(dto.missingPrerequisite, MissingPrerequisite.unknown);
    });
  });

  group('$MissingPrerequisite.fromString', () {
    test('maps backend "Email" PascalCase to the lowercase enum member', () {
      expect(MissingPrerequisite.fromString('Email'), MissingPrerequisite.email);
    });

    test('unknown value maps to MissingPrerequisite.unknown', () {
      // Forward-compat: additive backend changes (new prerequisite
      // types) must not break the user fetch. The page treats
      // `unknown` as a graceful direct-push fallback.
      expect(MissingPrerequisite.fromString('Phone'), MissingPrerequisite.unknown);
    });

    test('empty string also maps to MissingPrerequisite.unknown', () {
      expect(MissingPrerequisite.fromString(''), MissingPrerequisite.unknown);
    });
  });

  group('$UserDto.fromJson', () {
    Map<String, dynamic> kycJson() => {
      'hash': 'abc',
      'level': 30,
      'dataComplete': true,
    };

    test('parses the full shape with mail + kyc + capabilities', () {
      final dto = UserDto.fromJson({
        'mail': 'user@example.com',
        'kyc': kycJson(),
        'capabilities': {
          'canEditName': true,
          'canEditMail': false,
          'canEditPhone': true,
          'canEditAddress': false,
        },
      });

      expect(dto.mail, 'user@example.com');
      expect(dto.kyc.hash, 'abc');
      expect(dto.kyc.level, KycLevel.level30);
      expect(dto.kyc.dataComplete, isTrue);
      expect(dto.capabilities.canEditName, isTrue);
      expect(dto.capabilities.canEditMail, isFalse);
    });

    test('mail is optional (null on the wire stays null)', () {
      final dto = UserDto.fromJson({
        'mail': null,
        'kyc': kycJson(),
      });

      expect(dto.mail, isNull);
    });

    test('capabilities absent → falls back to all-false default', () {
      // Branch 1 of the ternary: `json['capabilities'] == null`. Old API
      // backends do not ship capabilities yet — the app must still parse
      // without throwing and render every edit action as disabled.
      final dto = UserDto.fromJson({
        'mail': 'a@b.com',
        'kyc': kycJson(),
        // capabilities missing
      });

      expect(dto.capabilities.canEditName, isFalse);
      expect(dto.capabilities.canEditMail, isFalse);
      expect(dto.capabilities.canEditPhone, isFalse);
      expect(dto.capabilities.canEditAddress, isFalse);
    });

    test('capabilities explicitly null → falls back to all-false default', () {
      // Same default branch but via an explicit `null` (different code
      // path through the `as Map<String, dynamic>` cast guard).
      final dto = UserDto.fromJson({
        'kyc': kycJson(),
        'capabilities': null,
      });

      expect(dto.capabilities.canEditName, isFalse);
    });

    test('capabilities present → parses via $UserCapabilitiesDto.fromJson', () {
      // Branch 2 of the ternary: capabilities object is forwarded
      // verbatim to the nested factory.
      final dto = UserDto.fromJson({
        'kyc': kycJson(),
        'capabilities': {
          'canEditName': false,
          'canEditMail': true,
          'canEditPhone': false,
          'canEditAddress': true,
        },
      });

      expect(dto.capabilities.canEditName, isFalse);
      expect(dto.capabilities.canEditMail, isTrue);
      expect(dto.capabilities.canEditPhone, isFalse);
      expect(dto.capabilities.canEditAddress, isTrue);
    });

    test('parses currency.name from the account payload', () {
      final dto = UserDto.fromJson({
        'kyc': kycJson(),
        'currency': {'id': 2, 'name': 'CHF'},
      });

      expect(dto.currency, Currency.chf);
    });

    test('unknown or missing currency degrades to null', () {
      expect(
        UserDto.fromJson({'kyc': kycJson(), 'currency': {'name': 'USD'}}).currency,
        isNull,
      );
      expect(UserDto.fromJson({'kyc': kycJson()}).currency, isNull);
      expect(UserDto.fromJson({'kyc': kycJson(), 'currency': null}).currency, isNull);
    });
  });
}
