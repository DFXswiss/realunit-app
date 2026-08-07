import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_country_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/country/country.dart';
import 'package:realunit_wallet/screens/kyc/steps/registration/steps/kyc_registration_tax_step.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

import '../../../../../helper/country_fixture.dart';
import '../../../../../helper/pump_app.dart';

// Ids match the committed country fixture (Country equality is id-keyed).
const _switzerland = Country(id: 41, symbol: 'CH', name: 'Switzerland', kycAllowed: true);
const _germany = Country(id: 55, symbol: 'DE', name: 'Germany', kycAllowed: true);
const _france = Country(id: 73, symbol: 'FR', name: 'France', kycAllowed: true);

void main() {
  setUp(() {
    GetIt.instance.registerSingleton<DfxCountryService>(fixtureCountryService());
  });

  tearDown(() async => GetIt.instance.reset());

  Future<_Harness> pump(
    WidgetTester tester, {
    required Country? residenceCountry,
    List<KycTaxResidenceSeed> initialTaxResidences = const [],
  }) async {
    final harness = _Harness();

    await tester.pumpApp(
      Scaffold(
        body: KycRegistrationTaxStep(
          residenceCountry: residenceCountry,
          initialTaxResidences: initialTaxResidences,
          onSubmit: (result) async {
            harness.lastResult = result;
            harness.submitCount++;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return harness;
  }

  Finder scrollable() => find.byType(Scrollable).first;

  S sOf(WidgetTester tester) =>
      S.of(tester.element(find.byType(KycRegistrationTaxStep)));

  Future<void> selectFreeCountry(WidgetTester tester, String name) async {
    final dropdown = find.byType(DropdownButtonFormField<Country>).last;
    await tester.scrollUntilVisible(dropdown, 100, scrollable: scrollable());
    await tester.tap(dropdown);
    await tester.pumpAndSettle();

    // Priority-sorted near the top: CH, DE, IT, FR. United States is far down
    // the alphabetical tail — scroll the open menu until the name is present.
    final nameFinder = find.text(name);
    if (nameFinder.evaluate().isEmpty || find.text(name).hitTestable().evaluate().isEmpty) {
      final menuScrollable = find.byType(Scrollable).last;
      await tester.dragUntilVisible(
        nameFinder,
        menuScrollable,
        const Offset(0, -300),
        maxIteration: 120,
      );
      await tester.pumpAndSettle();
    }
    final item = find.text(name).last;
    await tester.tap(item);
    await tester.pumpAndSettle();
  }

  Future<void> enterTinAt(WidgetTester tester, int index, String value) async {
    final tinFields = find.widgetWithText(TextFormField, sOf(tester).tinHint);
    final field = tinFields.at(index);
    await tester.scrollUntilVisible(field, 100, scrollable: scrollable());
    await tester.enterText(field, value);
    await tester.pump();
  }

  Future<void> tapComplete(WidgetTester tester) async {
    final button = find.byType(AppFilledButton);
    await tester.scrollUntilVisible(button, 100, scrollable: scrollable());
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<void> addTaxResidence(WidgetTester tester) async {
    final addButton = find.text(sOf(tester).addTaxResidence);
    await tester.scrollUntilVisible(addButton, 100, scrollable: scrollable());
    await tester.tap(addButton);
    await tester.pumpAndSettle();
  }

  Finder taxRowKeys() => find.byWidgetPredicate(
        (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('tax-row-'),
      );

  // ---------------------------------------------------------------------------
  // S1 — Address CH, tax residences: CH only
  // Expected: swissTaxResidence=true, countryAndTINs=null
  // ---------------------------------------------------------------------------
  group('S1 CH only (locked Swiss residence)', () {
    testWidgets('locked UI shows Switzerland without a free country dropdown', (tester) async {
      await pump(tester, residenceCountry: _switzerland);

      expect(find.text('Switzerland'), findsWidgets);
      expect(find.byType(DropdownButtonFormField<Country>), findsNothing);
    });

    testWidgets('TIN visibility: CH row has no TIN field', (tester) async {
      await pump(tester, residenceCountry: _switzerland);

      expect(find.text(sOf(tester).taxIdentificationNumber), findsNothing);
      expect(find.widgetWithText(TextFormField, sOf(tester).tinHint), findsNothing);
    });

    testWidgets(
      'happy-path submit: swissTaxResidence=true, countryAndTINs=null',
      (tester) async {
        final harness = await pump(tester, residenceCountry: _switzerland);

        await tapComplete(tester);

        expect(harness.submitCount, 1);
        expect(harness.lastResult!.swissTaxResidence, isTrue);
        expect(harness.lastResult!.countryAndTINs, isNull);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // S2 — Address DE, tax residences: DE only
  // Expected: swissTaxResidence=false, countryAndTINs=[{DE, tin}]
  // ---------------------------------------------------------------------------
  group('S2 DE only (locked German residence)', () {
    testWidgets('locked UI shows Germany without a free country dropdown', (tester) async {
      await pump(tester, residenceCountry: _germany);

      expect(find.text('Germany'), findsWidgets);
      expect(find.byType(DropdownButtonFormField<Country>), findsNothing);
    });

    testWidgets('TIN visibility: DE row shows taxIdentificationNumber', (tester) async {
      await pump(tester, residenceCountry: _germany);

      expect(find.text(sOf(tester).taxIdentificationNumber), findsOneWidget);
      expect(find.widgetWithText(TextFormField, sOf(tester).tinHint), findsOneWidget);
    });

    testWidgets('validation: empty TIN blocks submit and shows tinRequired', (tester) async {
      final harness = await pump(tester, residenceCountry: _germany);

      await tapComplete(tester);

      expect(find.text(sOf(tester).tinRequired), findsOneWidget);
      expect(harness.submitCount, 0);
    });

    testWidgets('validation: whitespace-only TIN is rejected', (tester) async {
      final harness = await pump(tester, residenceCountry: _germany);

      await enterTinAt(tester, 0, '   ');
      await tapComplete(tester);

      expect(find.text(sOf(tester).tinRequired), findsOneWidget);
      expect(harness.submitCount, 0);
    });

    testWidgets(
      'happy-path submit: swissTaxResidence=false, countryAndTINs=[{DE,tin}]',
      (tester) async {
        final harness = await pump(tester, residenceCountry: _germany);

        await enterTinAt(tester, 0, '  DE123456789  ');
        await tapComplete(tester);

        expect(harness.submitCount, 1);
        expect(harness.lastResult!.swissTaxResidence, isFalse);
        final tins = harness.lastResult!.countryAndTINs!;
        expect(tins, hasLength(1));
        expect(tins.single.country, 'DE');
        expect(tins.single.tin, 'DE123456789');
      },
    );
  });

  // ---------------------------------------------------------------------------
  // S3 — Address CH, tax residences: CH + FR
  // Expected: swissTaxResidence=true, countryAndTINs=[{FR, tin}]
  // ---------------------------------------------------------------------------
  group('S3 CH + FR (locked Swiss + free France)', () {
    Future<_Harness> pumpS3Ready(WidgetTester tester) async {
      final harness = await pump(tester, residenceCountry: _switzerland);
      await addTaxResidence(tester);
      await selectFreeCountry(tester, 'France');
      return harness;
    }

    testWidgets('locked UI keeps Switzerland locked; free dropdown for FR row', (tester) async {
      await pumpS3Ready(tester);

      expect(find.text('Switzerland'), findsWidgets);
      // Free row after selection still holds a dropdown (editable free country).
      expect(find.byType(DropdownButtonFormField<Country>), findsOneWidget);
      expect(find.text('France'), findsWidgets);
    });

    testWidgets('TIN visibility: CH no TIN; FR has TIN', (tester) async {
      await pumpS3Ready(tester);

      expect(find.text(sOf(tester).taxIdentificationNumber), findsOneWidget);
      expect(find.widgetWithText(TextFormField, sOf(tester).tinHint), findsOneWidget);
    });

    testWidgets('validation: empty FR TIN blocks submit', (tester) async {
      final harness = await pumpS3Ready(tester);

      await tapComplete(tester);

      expect(find.text(sOf(tester).tinRequired), findsOneWidget);
      expect(harness.submitCount, 0);
    });

    testWidgets('validation: whitespace FR TIN is rejected', (tester) async {
      final harness = await pumpS3Ready(tester);

      await enterTinAt(tester, 0, '  \t  ');
      await tapComplete(tester);

      expect(find.text(sOf(tester).tinRequired), findsOneWidget);
      expect(harness.submitCount, 0);
    });

    testWidgets(
      'happy-path submit: swissTaxResidence=true, countryAndTINs=[{FR,tin}]',
      (tester) async {
        final harness = await pumpS3Ready(tester);

        await enterTinAt(tester, 0, '  FR999  ');
        await tapComplete(tester);

        expect(harness.submitCount, 1);
        expect(harness.lastResult!.swissTaxResidence, isTrue);
        final tins = harness.lastResult!.countryAndTINs!;
        expect(tins, hasLength(1));
        expect(tins.single.country, 'FR');
        expect(tins.single.tin, 'FR999');
      },
    );
  });

  // ---------------------------------------------------------------------------
  // S4 — Address DE, tax residences: DE + CH
  // Expected: swissTaxResidence=true, countryAndTINs=[{DE, tin}]
  // ---------------------------------------------------------------------------
  group('S4 DE + CH (locked German + free Switzerland)', () {
    Future<_Harness> pumpS4Ready(WidgetTester tester) async {
      final harness = await pump(tester, residenceCountry: _germany);
      await enterTinAt(tester, 0, 'DE111');
      await addTaxResidence(tester);
      await selectFreeCountry(tester, 'Switzerland');
      return harness;
    }

    testWidgets('locked UI shows Germany; free CH selectable', (tester) async {
      await pumpS4Ready(tester);

      expect(find.text('Germany'), findsWidgets);
      expect(find.text('Switzerland'), findsWidgets);
      expect(find.byType(DropdownButtonFormField<Country>), findsOneWidget);
    });

    testWidgets('TIN visibility: only DE has TIN; CH has none', (tester) async {
      await pumpS4Ready(tester);

      expect(find.text(sOf(tester).taxIdentificationNumber), findsOneWidget);
      expect(find.widgetWithText(TextFormField, sOf(tester).tinHint), findsOneWidget);
    });

    testWidgets('validation: empty DE TIN blocks submit (CH has no TIN)', (tester) async {
      final harness = await pump(tester, residenceCountry: _germany);
      await addTaxResidence(tester);
      await selectFreeCountry(tester, 'Switzerland');

      await tapComplete(tester);

      expect(find.text(sOf(tester).tinRequired), findsOneWidget);
      expect(harness.submitCount, 0);
    });

    testWidgets('validation: whitespace DE TIN is rejected', (tester) async {
      final harness = await pump(tester, residenceCountry: _germany);
      await enterTinAt(tester, 0, '   ');
      await addTaxResidence(tester);
      await selectFreeCountry(tester, 'Switzerland');

      await tapComplete(tester);

      expect(find.text(sOf(tester).tinRequired), findsOneWidget);
      expect(harness.submitCount, 0);
    });

    testWidgets(
      'happy-path submit: swissTaxResidence=true, countryAndTINs=[{DE,tin}]',
      (tester) async {
        final harness = await pumpS4Ready(tester);

        await tapComplete(tester);

        expect(harness.submitCount, 1);
        expect(harness.lastResult!.swissTaxResidence, isTrue);
        final tins = harness.lastResult!.countryAndTINs!;
        expect(tins, hasLength(1));
        expect(tins.single.country, 'DE');
        expect(tins.single.tin, 'DE111');
      },
    );

    testWidgets(
      'free picker excludes the locked residence country (no DE duplicate option)',
      (tester) async {
        await pump(tester, residenceCountry: _germany);
        await addTaxResidence(tester);

        final dropdown = find.byType(DropdownButtonFormField<Country>);
        await tester.scrollUntilVisible(dropdown, 100, scrollable: scrollable());
        await tester.tap(dropdown);
        await tester.pumpAndSettle();

        // DE is locked on the primary row — only that one display may show
        // "Germany"; the open free-picker menu must not offer it again.
        // Switzerland remains available on the priority list.
        expect(find.text('Switzerland').last, findsOneWidget);
        expect(find.text('Germany'), findsOneWidget);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // S5 — Address DE, tax residences: DE + FR + US
  // Expected: swissTaxResidence=false, countryAndTINs=[{DE},{FR},{US}]
  // ---------------------------------------------------------------------------
  group('S5 DE + FR + US (locked German + free FR + free US)', () {
    Future<_Harness> pumpS5WithCountries(WidgetTester tester) async {
      final harness = await pump(tester, residenceCountry: _germany);
      await addTaxResidence(tester);
      await selectFreeCountry(tester, 'France');
      await addTaxResidence(tester);
      await selectFreeCountry(tester, 'United States');
      return harness;
    }

    testWidgets('locked UI shows Germany; FR and US free rows present', (tester) async {
      await pumpS5WithCountries(tester);

      expect(find.text('Germany'), findsWidgets);
      expect(find.text('France'), findsWidgets);
      expect(find.text('United States'), findsWidgets);
      // Two free country dropdowns (FR, US); locked primary has none.
      expect(find.byType(DropdownButtonFormField<Country>), findsNWidgets(2));
    });

    testWidgets('TIN visibility: three TIN fields for DE, FR, US', (tester) async {
      await pumpS5WithCountries(tester);

      expect(find.text(sOf(tester).taxIdentificationNumber), findsNWidgets(3));
      expect(find.widgetWithText(TextFormField, sOf(tester).tinHint), findsNWidgets(3));
    });

    testWidgets('validation: each empty non-CH TIN blocks submit', (tester) async {
      final harness = await pumpS5WithCountries(tester);

      // All three empty → three tinRequired messages.
      await tapComplete(tester);
      expect(find.text(sOf(tester).tinRequired), findsNWidgets(3));
      expect(harness.submitCount, 0);

      // Fill DE only → FR + US still error.
      await enterTinAt(tester, 0, 'DE111');
      await tapComplete(tester);
      expect(find.text(sOf(tester).tinRequired), findsNWidgets(2));
      expect(harness.submitCount, 0);

      // Fill DE + FR → US still error.
      await enterTinAt(tester, 1, 'FR999');
      await tapComplete(tester);
      expect(find.text(sOf(tester).tinRequired), findsOneWidget);
      expect(harness.submitCount, 0);
    });

    testWidgets('validation: whitespace TIN rejected on at least one non-CH row', (tester) async {
      final harness = await pumpS5WithCountries(tester);

      await enterTinAt(tester, 0, 'DE111');
      await enterTinAt(tester, 1, 'FR999');
      await enterTinAt(tester, 2, '   ');
      await tapComplete(tester);

      expect(find.text(sOf(tester).tinRequired), findsOneWidget);
      expect(harness.submitCount, 0);
    });

    testWidgets(
      'happy-path submit: swissTaxResidence=false, countryAndTINs=[{DE},{FR},{US}]',
      (tester) async {
        final harness = await pumpS5WithCountries(tester);

        await enterTinAt(tester, 0, '  DE111  ');
        await enterTinAt(tester, 1, '  FR999  ');
        await enterTinAt(tester, 2, '  US123  ');
        await tapComplete(tester);

        expect(harness.submitCount, 1);
        expect(harness.lastResult!.swissTaxResidence, isFalse);
        final tins = harness.lastResult!.countryAndTINs!;
        expect(tins, hasLength(3));
        expect(tins[0].country, 'DE');
        expect(tins[0].tin, 'DE111');
        expect(tins[1].country, 'FR');
        expect(tins[1].tin, 'FR999');
        expect(tins[2].country, 'US');
        expect(tins[2].tin, 'US123');
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Remove interaction — the free-row "remove" button and its effect on
  // _usedSymbols and the submit payload. The locked residence primary row
  // must never expose a functioning remove button.
  // ---------------------------------------------------------------------------
  group('$KycRegistrationTaxStep remove tax residence row', () {
    testWidgets(
      'locked residence primary row has no remove button',
      (tester) async {
        await pump(tester, residenceCountry: _switzerland);

        expect(find.text(sOf(tester).removeTaxResidence), findsNothing);
      },
    );

    testWidgets(
      'removing an additional row clears it, frees its country for '
      're-selection, and drops it from the submit payload',
      (tester) async {
        final harness = await pump(tester, residenceCountry: _switzerland);

        await addTaxResidence(tester);
        await selectFreeCountry(tester, 'France');
        await enterTinAt(tester, 0, 'FR999');

        final removeButton = find.text(sOf(tester).removeTaxResidence);
        expect(removeButton, findsOneWidget);
        await tester.scrollUntilVisible(removeButton, 100, scrollable: scrollable());
        await tester.tap(removeButton);
        await tester.pumpAndSettle();

        // (a) the row is gone from the UI.
        expect(find.text('France'), findsNothing);
        expect(find.text(sOf(tester).taxIdentificationNumber), findsNothing);
        expect(find.text(sOf(tester).removeTaxResidence), findsNothing);

        // (c) the removed country is not part of the submit payload.
        await tapComplete(tester);
        expect(harness.submitCount, 1);
        expect(harness.lastResult!.swissTaxResidence, isTrue);
        expect(harness.lastResult!.countryAndTINs, isNull);

        // (b) the country is selectable again in a newly added free picker —
        // proves the _usedSymbols computation was updated on removal.
        await addTaxResidence(tester);
        await selectFreeCountry(tester, 'France');
        expect(find.text('France'), findsWidgets);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Prefill seeds + row/TIN limits
  // ---------------------------------------------------------------------------
  group('$KycRegistrationTaxStep prefill and bounds', () {
    testWidgets(
      'prefill residence CH: locked CH without TIN, DE row prefilled, submit keeps both',
      (tester) async {
        final harness = await pump(
          tester,
          residenceCountry: _switzerland,
          initialTaxResidences: const [
            KycTaxResidenceSeed(country: _switzerland, tin: ''),
            KycTaxResidenceSeed(country: _germany, tin: 'DE123'),
          ],
        );

        expect(find.text('Switzerland'), findsWidgets);
        expect(find.text('Germany'), findsWidgets);
        // Locked primary only — free DE row has a dropdown.
        expect(find.byType(DropdownButtonFormField<Country>), findsOneWidget);
        // CH has no TIN; DE TIN is prefilled.
        expect(find.text(sOf(tester).taxIdentificationNumber), findsOneWidget);
        final tinField = find.widgetWithText(TextFormField, sOf(tester).tinHint);
        expect(tinField, findsOneWidget);
        expect(tester.widget<TextFormField>(tinField).controller!.text, 'DE123');

        await tapComplete(tester);

        expect(harness.submitCount, 1);
        expect(harness.lastResult!.swissTaxResidence, isTrue);
        final tins = harness.lastResult!.countryAndTINs!;
        expect(tins, hasLength(1));
        expect(tins.single.country, 'DE');
        expect(tins.single.tin, 'DE123');
      },
    );

    testWidgets(
      'prefill residence DE plus CH: locked DE TIN prefilled, free CH without TIN',
      (tester) async {
        final harness = await pump(
          tester,
          residenceCountry: _germany,
          initialTaxResidences: const [
            KycTaxResidenceSeed(country: _germany, tin: 'DE123'),
            KycTaxResidenceSeed(country: _switzerland, tin: ''),
          ],
        );

        expect(find.text('Germany'), findsWidgets);
        expect(find.text('Switzerland'), findsWidgets);
        expect(find.byType(DropdownButtonFormField<Country>), findsOneWidget);
        expect(find.text(sOf(tester).taxIdentificationNumber), findsOneWidget);
        final tinField = find.widgetWithText(TextFormField, sOf(tester).tinHint);
        expect(tester.widget<TextFormField>(tinField).controller!.text, 'DE123');

        await tapComplete(tester);

        expect(harness.submitCount, 1);
        expect(harness.lastResult!.swissTaxResidence, isTrue);
        final tins = harness.lastResult!.countryAndTINs!;
        expect(tins, hasLength(1));
        expect(tins.single.country, 'DE');
        expect(tins.single.tin, 'DE123');
      },
    );

    testWidgets('no prefill: exactly one locked residence row', (tester) async {
      await pump(
        tester,
        residenceCountry: _switzerland,
        initialTaxResidences: const [],
      );

      expect(taxRowKeys(), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<Country>), findsNothing);
      expect(find.text(sOf(tester).addTaxResidence), findsOneWidget);
    });

    testWidgets(
      'row limit: add button disappears once 10 free (non-CH) tax residences are present',
      (tester) async {
        await pump(tester, residenceCountry: _switzerland);

        // Locked CH primary does not count against the countryAndTINs cap.
        // 10 free non-CH rows + locked CH = 11 total; further adds are not triggerable.
        for (var i = 0; i < 10; i++) {
          await addTaxResidence(tester);
        }

        expect(taxRowKeys(), findsNWidgets(11));
        expect(find.text(sOf(tester).addTaxResidence), findsNothing);
      },
    );

    testWidgets(
      'CH resident + 10 foreign seeds: all 11 rows appear (none of the 10 non-CH dropped)',
      (tester) async {
        // CH never occupies a countryAndTINs slot, so a CH seed + 10 non-CH seeds
        // must all render (11 rows total).
        final seeds = <KycTaxResidenceSeed>[
          const KycTaxResidenceSeed(country: _switzerland, tin: ''),
          for (var i = 0; i < 10; i++)
            KycTaxResidenceSeed(
              country: Country(id: 2000 + i, symbol: 'X$i', name: 'Country $i', kycAllowed: true),
              tin: 'TIN$i',
            ),
        ];

        await pump(
          tester,
          residenceCountry: _switzerland,
          initialTaxResidences: seeds,
        );

        expect(taxRowKeys(), findsNWidgets(11));
        // 10 free (prefilled) non-CH rows keep a dropdown; primary CH is locked.
        expect(find.byType(DropdownButtonFormField<Country>), findsNWidgets(10));
        expect(find.text(sOf(tester).addTaxResidence), findsNothing);
      },
    );

    testWidgets('TIN length: entering 70 characters is truncated to 64', (tester) async {
      await pump(tester, residenceCountry: _germany);

      final longTin = 'A' * 70;
      await enterTinAt(tester, 0, longTin);

      final tinField = find.widgetWithText(TextFormField, sOf(tester).tinHint);
      final text = tester.widget<TextFormField>(tinField).controller!.text;
      expect(text.length, 64);
      expect(text, 'A' * 64);
    });

    testWidgets(
      'seeded TIN over 64 chars is truncated in the field and on submit',
      (tester) async {
        final longTin = 'B' * 70;
        final harness = await pump(
          tester,
          residenceCountry: _switzerland,
          initialTaxResidences: [
            const KycTaxResidenceSeed(country: _switzerland, tin: ''),
            KycTaxResidenceSeed(country: _germany, tin: longTin),
          ],
        );

        final tinField = find.widgetWithText(TextFormField, sOf(tester).tinHint);
        expect(tinField, findsOneWidget);
        final text = tester.widget<TextFormField>(tinField).controller!.text;
        expect(text.length, 64);
        expect(text, 'B' * 64);

        await tapComplete(tester);

        expect(harness.submitCount, 1);
        final tins = harness.lastResult!.countryAndTINs!;
        expect(tins, hasLength(1));
        expect(tins.single.country, 'DE');
        expect(tins.single.tin.length, 64);
        expect(tins.single.tin, 'B' * 64);
      },
    );

    testWidgets('prefill seeds over the limit keep 10 free non-CH rows (11 total with CH)', (tester) async {
      // 12 foreign seeds + locked CH primary would be 13 without the cap; only
      // 10 free (non-CH) seeds are kept after the primary, for 11 total (CH + 10).
      final seeds = <KycTaxResidenceSeed>[
        for (var i = 0; i < 12; i++)
          KycTaxResidenceSeed(
            country: Country(id: 1000 + i, symbol: 'X$i', name: 'Country $i', kycAllowed: true),
            tin: 'TIN$i',
          ),
      ];

      await pump(
        tester,
        residenceCountry: _switzerland,
        initialTaxResidences: seeds,
      );

      expect(taxRowKeys(), findsNWidgets(11));
      // 10 free (prefilled) rows keep a dropdown; primary is locked.
      expect(find.byType(DropdownButtonFormField<Country>), findsNWidgets(10));
      expect(find.text(sOf(tester).addTaxResidence), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // Empty-form fallback (null residence) + keyboard dismiss + residence re-lock
  // ---------------------------------------------------------------------------
  group('$KycRegistrationTaxStep without residence country (empty fallback)', () {
    testWidgets(
      'does not submit while no tax-residence country is picked',
      (tester) async {
        final harness = await pump(tester, residenceCountry: null);

        await tapComplete(tester);

        expect(harness.submitCount, 0);
      },
    );

    testWidgets(
      'submits a free Swiss pick without TIN',
      (tester) async {
        final harness = await pump(tester, residenceCountry: null);
        await selectFreeCountry(tester, 'Switzerland');
        await tapComplete(tester);

        expect(harness.submitCount, 1);
        expect(harness.lastResult!.swissTaxResidence, isTrue);
        expect(harness.lastResult!.countryAndTINs, isNull);
      },
    );

    testWidgets(
      'submits a free German pick with TIN',
      (tester) async {
        final harness = await pump(tester, residenceCountry: null);
        await selectFreeCountry(tester, 'Germany');
        await enterTinAt(tester, 0, '12 345 678 901');
        await tapComplete(tester);

        expect(harness.submitCount, 1);
        expect(harness.lastResult!.swissTaxResidence, isFalse);
        final tins = harness.lastResult!.countryAndTINs!;
        expect(tins, hasLength(1));
        expect(tins.single.country, 'DE');
        expect(tins.single.tin, '12 345 678 901');
      },
    );

    testWidgets(
      'dismisses the keyboard when tapping outside the fields',
      (tester) async {
        await pump(tester, residenceCountry: null);
        await selectFreeCountry(tester, 'Germany');

        final tinField = find
            .descendant(
              of: find.byType(KycRegistrationTaxStep),
              matching: find.byType(EditableText),
            )
            .first;
        final tinFocus = tester.widget<EditableText>(tinField).focusNode;
        await tester.tap(tinField);
        await tester.pump();
        expect(tinFocus.hasFocus, isTrue);

        final dismissArea = find.ancestor(
          of: find.descendant(
            of: find.byType(KycRegistrationTaxStep),
            matching: find.byType(Form),
          ),
          matching: find.byWidgetPredicate(
            (w) => w is GestureDetector && w.behavior == HitTestBehavior.opaque && w.onTap != null,
          ),
        );
        expect(dismissArea, findsOneWidget);
        tester.widget<GestureDetector>(dismissArea).onTap!();
        await tester.pump();

        expect(tinFocus.hasFocus, isFalse);
      },
    );

    testWidgets(
      'does not render a remove button on the sole free row '
      '(regression guard: index 0 must never be removable)',
      (tester) async {
        await pump(tester, residenceCountry: null);

        expect(find.text(sOf(tester).removeTaxResidence), findsNothing);
      },
    );

    testWidgets(
      'does not render a remove button on free row 0 when a second free row '
      'is added; row 1 remove works and does not resurrect a button on row 0 '
      '(regression guard: only index > 0 is removable)',
      (tester) async {
        await pump(tester, residenceCountry: null);
        await selectFreeCountry(tester, 'Switzerland');
        await addTaxResidence(tester);
        await selectFreeCountry(tester, 'Germany');

        final removeButton = find.text(sOf(tester).removeTaxResidence);
        expect(removeButton, findsOneWidget);
        await tester.scrollUntilVisible(removeButton, 100, scrollable: scrollable());
        await tester.tap(removeButton);
        await tester.pumpAndSettle();

        expect(find.text(sOf(tester).removeTaxResidence), findsNothing);
      },
    );
  });

  group('$KycRegistrationTaxStep residence country re-lock', () {
    testWidgets(
      're-locks the primary row when the residence country changes',
      (tester) async {
        final harness = _Harness();
        final residence = ValueNotifier<Country?>(_switzerland);
        addTearDown(residence.dispose);

        await tester.pumpApp(
          Scaffold(
            body: ValueListenableBuilder<Country?>(
              valueListenable: residence,
              builder: (_, country, _) => KycRegistrationTaxStep(
                residenceCountry: country,
                initialTaxResidences: const [],
                onSubmit: (result) async {
                  harness.lastResult = result;
                  harness.submitCount++;
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        var context = tester.element(find.byType(KycRegistrationTaxStep));
        expect(find.text(S.of(context).taxIdentificationNumber), findsNothing);

        residence.value = _germany;
        await tester.pumpAndSettle();

        context = tester.element(find.byType(KycRegistrationTaxStep));
        expect(find.text('Germany'), findsWidgets);
        expect(find.text(S.of(context).taxIdentificationNumber), findsOneWidget);
      },
    );

    testWidgets(
      'keeps an additional row including its entered TIN when the residence '
      'country changes without a collision',
      (tester) async {
        final harness = _Harness();
        final residence = ValueNotifier<Country?>(_germany);
        addTearDown(residence.dispose);

        await tester.pumpApp(
          Scaffold(
            body: ValueListenableBuilder<Country?>(
              valueListenable: residence,
              builder: (_, country, _) => KycRegistrationTaxStep(
                residenceCountry: country,
                initialTaxResidences: const [],
                onSubmit: (result) async {
                  harness.lastResult = result;
                  harness.submitCount++;
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await addTaxResidence(tester);
        await selectFreeCountry(tester, 'France');
        await enterTinAt(tester, 1, 'FR999');

        residence.value = _switzerland;
        await tester.pumpAndSettle();

        expect(find.text('Switzerland'), findsWidgets);
        expect(find.text('France'), findsWidgets);
        expect(find.byType(DropdownButtonFormField<Country>), findsOneWidget);

        await tapComplete(tester);

        expect(harness.submitCount, 1);
        expect(harness.lastResult!.swissTaxResidence, isTrue);
        final tins = harness.lastResult!.countryAndTINs!;
        expect(tins, hasLength(1));
        expect(tins.single.country, 'FR');
        expect(tins.single.tin, 'FR999');
      },
    );

    testWidgets(
      'drops an additional row that collides with the new residence country',
      (tester) async {
        final harness = _Harness();
        final residence = ValueNotifier<Country?>(_germany);
        addTearDown(residence.dispose);

        await tester.pumpApp(
          Scaffold(
            body: ValueListenableBuilder<Country?>(
              valueListenable: residence,
              builder: (_, country, _) => KycRegistrationTaxStep(
                residenceCountry: country,
                initialTaxResidences: const [],
                onSubmit: (result) async {
                  harness.lastResult = result;
                  harness.submitCount++;
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await addTaxResidence(tester);
        await selectFreeCountry(tester, 'Switzerland');

        residence.value = _switzerland;
        await tester.pumpAndSettle();

        expect(find.text('Switzerland'), findsOneWidget);
        expect(find.byType(DropdownButtonFormField<Country>), findsNothing);
        expect(find.text(sOf(tester).removeTaxResidence), findsNothing);

        await tapComplete(tester);

        expect(harness.submitCount, 1);
        expect(harness.lastResult!.swissTaxResidence, isTrue);
        expect(harness.lastResult!.countryAndTINs, isNull);
      },
    );

    testWidgets(
      'drops a colliding additional seeded row when the residence country changes',
      (tester) async {
        final harness = _Harness();
        final residence = ValueNotifier<Country?>(_switzerland);
        addTearDown(residence.dispose);

        await tester.pumpApp(
          Scaffold(
            body: ValueListenableBuilder<Country?>(
              valueListenable: residence,
              builder: (_, country, _) => KycRegistrationTaxStep(
                residenceCountry: country,
                initialTaxResidences: const [
                  KycTaxResidenceSeed(country: _switzerland, tin: ''),
                  KycTaxResidenceSeed(country: _germany, tin: 'DE123'),
                  KycTaxResidenceSeed(country: _france, tin: 'FR999'),
                ],
                onSubmit: (result) async {
                  harness.lastResult = result;
                  harness.submitCount++;
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // CH locked + DE free + FR free.
        expect(taxRowKeys(), findsNWidgets(3));
        expect(find.text('Germany'), findsWidgets);
        expect(find.text('France'), findsWidgets);

        // Residence becomes DE → the free DE row collides and is dropped; FR remains.
        // didUpdateWidget rebuilds the primary without TIN prefill (user changed
        // the country themselves).
        residence.value = _germany;
        await tester.pumpAndSettle();

        expect(find.text('Germany'), findsWidgets);
        expect(find.text('France'), findsWidgets);
        // Primary locked DE + free FR only (colliding free DE removed).
        expect(taxRowKeys(), findsNWidgets(2));
        // Two free-country dropdowns would mean DE still has a free row; only FR.
        expect(find.byType(DropdownButtonFormField<Country>), findsOneWidget);

        // Primary DE has no prefilled TIN after the re-lock path.
        final tinField = find.widgetWithText(TextFormField, sOf(tester).tinHint);
        // DE (primary, empty) + FR (prefilled FR999).
        expect(tinField, findsNWidgets(2));
        expect(tester.widget<TextFormField>(tinField.at(0)).controller!.text, isEmpty);
        expect(tester.widget<TextFormField>(tinField.at(1)).controller!.text, 'FR999');
      },
    );
  });
}

class _Harness {
  int submitCount = 0;
  KycTaxResidenceSubmit? lastResult;
}
