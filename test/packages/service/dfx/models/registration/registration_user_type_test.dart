import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/registration_user_type.dart';

/// Coverage for the `RegistrationUserType` enum.
///
/// Pin the JSON aliases, `fromName` round-trip + error branch, and the
/// locale-aware `name(context)` so the enum lands at 100%.
void main() {
  group('RegistrationUserType.jsonName', () {
    test('human → HUMAN', () {
      expect(RegistrationUserType.human.jsonName, 'HUMAN');
    });

    test('corporation → CORPORATION', () {
      expect(RegistrationUserType.corporation.jsonName, 'CORPORATION');
    });
  });

  group('RegistrationUserType.fromName', () {
    test('HUMAN → human', () {
      expect(RegistrationUserType.fromName('HUMAN'), RegistrationUserType.human);
    });

    test('CORPORATION → corporation', () {
      expect(
        RegistrationUserType.fromName('CORPORATION'),
        RegistrationUserType.corporation,
      );
    });

    test('unknown string throws ArgumentError', () {
      expect(
        () => RegistrationUserType.fromName('UNKNOWN'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('RegistrationUserType.name(context)', () {
    testWidgets('returns localized label for each variant', (tester) async {
      String? humanLabel;
      String? corpLabel;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          home: Builder(
            builder: (context) {
              humanLabel = RegistrationUserType.human.name(context);
              corpLabel = RegistrationUserType.corporation.name(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // Locale-agnostic assertion: only require that the labels are
      // non-empty and distinct from each other. The actual strings live in
      // the ARB files and may change for translation reasons.
      expect(humanLabel, isNotNull);
      expect(humanLabel, isNotEmpty);
      expect(corpLabel, isNotNull);
      expect(corpLabel, isNotEmpty);
      expect(humanLabel, isNot(equals(corpLabel)));
    });
  });

  group('RegistrationUserType (enum identity)', () {
    test('values list has exactly two variants', () {
      expect(RegistrationUserType.values.length, 2);
    });
  });
}
