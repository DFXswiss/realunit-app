import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_country_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/country/country.dart';
import 'package:realunit_wallet/screens/kyc/steps/registration/steps/kyc_registration_tax_step.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

import '../../../helper/helper.dart';

const _switzerland = Country(id: 41, symbol: 'CH', name: 'Switzerland', kycAllowed: true);
const _germany = Country(id: 55, symbol: 'DE', name: 'Germany', kycAllowed: true);

/// Tall phone for multi-row tax scenarios so every row is fully visible.
const tallPhoneConstraints = BoxConstraints.tightFor(width: 390, height: 1200);

void main() {
  setUpAll(() {
    GetIt.instance.registerSingleton<DfxCountryService>(fixtureCountryService());
  });

  tearDownAll(() async => GetIt.instance.reset());

  Widget buildSubject({Country? residenceCountry}) => wrapForGolden(
        Scaffold(
          body: KycRegistrationTaxStep(
            residenceCountry: residenceCountry,
            initialTaxResidences: const [],
            onSubmit: (_) async {},
          ),
        ),
      );

  Finder pageScrollable() => find
      .descendant(
        of: find.byType(KycRegistrationTaxStep),
        matching: find.byType(Scrollable),
      )
      .first;

  Future<void> openCountryDropdown(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<Country>).last);
    await tester.pumpAndSettle();
  }

  Future<void> selectFreeCountry(WidgetTester tester, String name) async {
    await openCountryDropdown(tester);
    final nameFinder = find.text(name);
    if (nameFinder.evaluate().isEmpty || find.text(name).hitTestable().evaluate().isEmpty) {
      await tester.dragUntilVisible(
        nameFinder,
        find.byType(Scrollable).last,
        const Offset(0, -300),
        maxIteration: 120,
      );
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  Future<void> tapComplete(WidgetTester tester) async {
    final button = find.byType(AppFilledButton);
    await tester.scrollUntilVisible(button, 100, scrollable: pageScrollable());
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<void> addTaxResidence(WidgetTester tester) async {
    final context = tester.element(find.byType(KycRegistrationTaxStep));
    final addButton = find.text(S.of(context).addTaxResidence);
    await tester.scrollUntilVisible(addButton, 100, scrollable: pageScrollable());
    await tester.tap(addButton);
    await tester.pumpAndSettle();
  }

  Future<void> enterTinAt(WidgetTester tester, int index, String value) async {
    final context = tester.element(find.byType(KycRegistrationTaxStep));
    final tinFields = find.widgetWithText(TextFormField, S.of(context).tinHint);
    final field = tinFields.at(index);
    await tester.scrollUntilVisible(field, 100, scrollable: pageScrollable());
    await tester.enterText(field, value);
    await tester.pump();
  }

  group('$KycRegistrationTaxStep', () {
    // Empty fallback: no residence country yet (address not filled).
    goldenTest(
      'empty — nothing picked, no TIN',
      fileName: 'kyc_registration_tax_step_default',
      constraints: phoneConstraints,
      builder: () => buildSubject(),
    );

    goldenTest(
      'country dropdown open — the selectable country list',
      fileName: 'kyc_registration_tax_step_dropdown_open',
      constraints: phoneConstraints,
      pumpBeforeTest: openCountryDropdown,
      builder: () => buildSubject(),
    );

    goldenTest(
      'Swiss tax residence locked from address — no TIN',
      fileName: 'kyc_registration_tax_step_swiss',
      constraints: phoneConstraints,
      builder: () => buildSubject(residenceCountry: _switzerland),
    );

    goldenTest(
      'non-Swiss tax residence locked from address — TIN revealed',
      fileName: 'kyc_registration_tax_step_non_swiss',
      constraints: phoneConstraints,
      builder: () => buildSubject(residenceCountry: _germany),
    );

    goldenTest(
      'validation error — no tax-residence country picked (empty fallback)',
      fileName: 'kyc_registration_tax_step_country_error',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) async {
        await tester.pumpAndSettle();
        await tapComplete(tester);
      },
      builder: () => buildSubject(),
    );

    goldenTest(
      'validation error — locked non-Swiss residence with an empty TIN',
      fileName: 'kyc_registration_tax_step_tin_error',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) async {
        await tester.pumpAndSettle();
        await tapComplete(tester);
      },
      builder: () => buildSubject(residenceCountry: _germany),
    );

    goldenTest(
      'multi tax residence — locked DE plus free second country',
      fileName: 'kyc_registration_tax_step_multi',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) async {
        await tester.pumpAndSettle();
        await addTaxResidence(tester);
        await selectFreeCountry(tester, 'Switzerland');
      },
      builder: () => buildSubject(residenceCountry: _germany),
    );
  });

  // ---------------------------------------------------------------------------
  // Customer scenarios S1–S5 (locked address country + additional tax rows)
  // ---------------------------------------------------------------------------
  group('$KycRegistrationTaxStep customer scenarios S1–S5', () {
    // S1 — CH only, ready to complete
    goldenTest(
      'S1 CH only — locked Switzerland ready to complete',
      fileName: 'kyc_tax_scenario_s1_ch_only',
      constraints: phoneConstraints,
      builder: () => buildSubject(residenceCountry: _switzerland),
    );

    // S2 — DE only, empty TIN (pre-submit)
    goldenTest(
      'S2 DE only — locked Germany with empty TIN',
      fileName: 'kyc_tax_scenario_s2_de_only_empty_tin',
      constraints: phoneConstraints,
      builder: () => buildSubject(residenceCountry: _germany),
    );

    // S2 — DE only, TIN filled
    goldenTest(
      'S2 DE only — locked Germany with TIN filled',
      fileName: 'kyc_tax_scenario_s2_de_only_filled',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) async {
        await tester.pumpAndSettle();
        await enterTinAt(tester, 0, 'DE123456789');
      },
      builder: () => buildSubject(residenceCountry: _germany),
    );

    // S2 — DE only, empty TIN validation error
    goldenTest(
      'S2 DE only — empty TIN validation error after complete',
      fileName: 'kyc_tax_scenario_s2_de_only_tin_error',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) async {
        await tester.pumpAndSettle();
        await tapComplete(tester);
      },
      builder: () => buildSubject(residenceCountry: _germany),
    );

    // S3 — CH locked + FR selected with TIN filled
    goldenTest(
      'S3 CH + FR — Switzerland locked, France with TIN filled',
      fileName: 'kyc_tax_scenario_s3_ch_fr',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) async {
        await tester.pumpAndSettle();
        await addTaxResidence(tester);
        await selectFreeCountry(tester, 'France');
        await enterTinAt(tester, 0, 'FR999');
      },
      builder: () => buildSubject(residenceCountry: _switzerland),
    );

    // S3 — FR added but TIN empty → error
    goldenTest(
      'S3 CH + FR — France TIN empty, complete shows error',
      fileName: 'kyc_tax_scenario_s3_ch_fr_tin_error',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) async {
        await tester.pumpAndSettle();
        await addTaxResidence(tester);
        await selectFreeCountry(tester, 'France');
        await tapComplete(tester);
      },
      builder: () => buildSubject(residenceCountry: _switzerland),
    );

    // S4 — DE locked TIN filled + CH added
    goldenTest(
      'S4 DE + CH — Germany locked TIN filled, Switzerland added',
      fileName: 'kyc_tax_scenario_s4_de_ch',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) async {
        await tester.pumpAndSettle();
        await enterTinAt(tester, 0, 'DE111');
        await addTaxResidence(tester);
        await selectFreeCountry(tester, 'Switzerland');
      },
      builder: () => buildSubject(residenceCountry: _germany),
    );

    // S5 — DE + FR + US all TINs filled
    goldenTest(
      'S5 DE + FR + US — all three TINs filled',
      fileName: 'kyc_tax_scenario_s5_de_fr_us',
      constraints: tallPhoneConstraints,
      pumpBeforeTest: (tester) async {
        await tester.pumpAndSettle();
        await enterTinAt(tester, 0, 'DE111');
        await addTaxResidence(tester);
        await selectFreeCountry(tester, 'France');
        await enterTinAt(tester, 1, 'FR999');
        await addTaxResidence(tester);
        await selectFreeCountry(tester, 'United States');
        await enterTinAt(tester, 2, 'US123');
      },
      builder: () => buildSubject(residenceCountry: _germany),
    );

    // S5 — missing one TIN → error
    goldenTest(
      'S5 DE + FR + US — partial TIN missing shows error',
      fileName: 'kyc_tax_scenario_s5_de_fr_us_partial_tin_error',
      constraints: tallPhoneConstraints,
      pumpBeforeTest: (tester) async {
        await tester.pumpAndSettle();
        await enterTinAt(tester, 0, 'DE111');
        await addTaxResidence(tester);
        await selectFreeCountry(tester, 'France');
        await enterTinAt(tester, 1, 'FR999');
        await addTaxResidence(tester);
        await selectFreeCountry(tester, 'United States');
        // US TIN deliberately left empty
        await tapComplete(tester);
      },
      builder: () => buildSubject(residenceCountry: _germany),
    );
  });
}
