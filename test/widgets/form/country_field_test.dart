import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_country_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/country/country.dart';
import 'package:realunit_wallet/widgets/form/country_field.dart';

import '../../helper/country_fixture.dart';
import '../../helper/pump_app.dart';

void main() {
  // Concrete fixture countries used by the purpose-filter assertions.
  // Switzerland (id 41) is KYC-allowed; Afghanistan (id 3) is not — both are
  // present in the committed country fixture.
  const switzerland = Country(id: 41, symbol: 'CH', name: 'Switzerland', kycAllowed: true);
  const afghanistan = Country(id: 3, symbol: 'AF', name: 'Afghanistan', kycAllowed: false);

  tearDown(() async => GetIt.instance.reset());

  void registerCountryService(DfxCountryService service) {
    GetIt.instance.registerSingleton<DfxCountryService>(service);
  }

  Widget host(Widget child, {GlobalKey<FormState>? formKey}) {
    return Scaffold(
      body: Form(
        key: formKey,
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );
  }

  List<Country> renderedCountries(WidgetTester tester) {
    final button = tester.widget<DropdownButton<Country>>(
      find.byType(DropdownButton<Country>),
    );
    return button.items!.map((item) => item.value!).toList();
  }

  group('$CountryFieldPurpose', () {
    test('nationality allows every country regardless of kycAllowed', () {
      expect(CountryFieldPurpose.nationality.allows(switzerland), isTrue);
      expect(CountryFieldPurpose.nationality.allows(afghanistan), isTrue);
    });

    test('residence reads kycAllowed', () {
      expect(CountryFieldPurpose.residence.allows(switzerland), isTrue);
      expect(CountryFieldPurpose.residence.allows(afghanistan), isFalse);
    });
  });

  group('$CountryField filtering', () {
    testWidgets('nationality purpose offers every fixture country, KYC-allowed or not', (
      tester,
    ) async {
      registerCountryService(fixtureCountryService());

      await tester.pumpApp(
        host(
          CountryField(
            label: 'Citizenship',
            purpose: CountryFieldPurpose.nationality,
            onChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final names = renderedCountries(tester).map((c) => c.name);
      expect(names, isNotEmpty);
      expect(names, contains('Switzerland'));
      expect(names, contains('Afghanistan'));
    });

    testWidgets('residence purpose drops countries with kycAllowed false', (tester) async {
      registerCountryService(fixtureCountryService());

      await tester.pumpApp(
        host(
          CountryField(
            label: 'Country',
            purpose: CountryFieldPurpose.residence,
            onChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final names = renderedCountries(tester).map((c) => c.name);
      expect(names, isNotEmpty);
      expect(names, contains('Switzerland'));
      expect(names, isNot(contains('Afghanistan')));
    });
  });

  group('$CountryField no auto-selection', () {
    testWidgets('does not preselect a country and does not fire onChanged', (tester) async {
      registerCountryService(fixtureCountryService());
      Country? picked;

      await tester.pumpApp(
        host(
          CountryField(
            label: 'Citizenship',
            purpose: CountryFieldPurpose.nationality,
            onChanged: (c) => picked = c,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(picked, isNull);
      // Nothing is selected, so the field falls back to its hint.
      final field = tester.widget<DropdownButtonFormField<Country>>(
        find.byType(DropdownButtonFormField<Country>),
      );
      expect(field.initialValue, isNull);
    });

    testWidgets('an untouched field makes the surrounding Form invalid', (tester) async {
      registerCountryService(fixtureCountryService());
      final formKey = GlobalKey<FormState>();

      await tester.pumpApp(
        host(
          const CountryField(label: 'Citizenship', purpose: CountryFieldPurpose.nationality),
          formKey: formKey,
        ),
      );
      await tester.pumpAndSettle();

      expect(formKey.currentState!.validate(), isFalse);
    });
  });

  group('$CountryField loading state', () {
    testWidgets('keeps the field present and the Form invalid while loading', (tester) async {
      final gate = Completer<http.Response>();
      registerCountryService(countryServiceWithClient(MockClient((_) => gate.future)));
      final formKey = GlobalKey<FormState>();

      await tester.pumpApp(
        host(
          const CountryField(label: 'Citizenship', purpose: CountryFieldPurpose.nationality),
          formKey: formKey,
        ),
      );
      // Still loading — no pumpAndSettle.
      await tester.pump();

      expect(find.text('Citizenship'), findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(formKey.currentState!.validate(), isFalse);

      gate.complete(countriesFixtureResponse());
      await tester.pumpAndSettle();
    });
  });

  group('$CountryField initialValue', () {
    testWidgets('preselects the initialValue and fires onChanged once countries load', (
      tester,
    ) async {
      registerCountryService(fixtureCountryService());
      Country? picked;

      await tester.pumpApp(
        host(
          CountryField(
            label: 'Citizenship',
            purpose: CountryFieldPurpose.nationality,
            initialValue: switzerland,
            onChanged: (c) => picked = c,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(picked, switzerland);
      expect(find.text('Switzerland'), findsWidgets);
    });

    testWidgets('ignores an initialValue absent from the filtered country list', (tester) async {
      // Afghanistan is filtered out for residence purpose; the preselect must not push it back.
      registerCountryService(fixtureCountryService());
      Country? picked;

      await tester.pumpApp(
        host(
          CountryField(
            label: 'Country',
            purpose: CountryFieldPurpose.residence,
            initialValue: afghanistan,
            onChanged: (c) => picked = c,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(picked, isNull);
    });
  });

  group('$CountryField error state', () {
    testWidgets('surfaces the error state and hides the dropdown when the load fails', (
      tester,
    ) async {
      registerCountryService(failingCountryService());
      final formKey = GlobalKey<FormState>();

      await tester.pumpApp(
        host(
          const CountryField(label: 'Citizenship', purpose: CountryFieldPurpose.nationality),
          formKey: formKey,
        ),
      );
      await tester.pumpAndSettle();

      // The field is present, the raw exception is not leaked, the Form is invalid.
      expect(find.text('Citizenship'), findsOneWidget);
      expect(find.textContaining('Failed to fetch'), findsNothing);
      expect(formKey.currentState!.validate(), isFalse);
      expect(find.byType(DropdownButtonFormField<Country>), findsNothing);
      expect(find.byType(TextButton), findsOneWidget);
    });

    testWidgets('retry re-runs the load and recovers into the dropdown', (tester) async {
      var calls = 0;
      registerCountryService(
        countryServiceWithClient(
          MockClient((_) async {
            calls++;
            return calls == 1 ? http.Response('error', 500) : countriesFixtureResponse();
          }),
        ),
      );

      await tester.pumpApp(
        host(const CountryField(label: 'Citizenship', purpose: CountryFieldPurpose.nationality)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DropdownButtonFormField<Country>), findsNothing);

      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();

      expect(calls, 2);
      expect(find.byType(DropdownButtonFormField<Country>), findsOneWidget);
    });
  });

  group('$CountryField stale-error clearing', () {
    testWidgets('an empty field reports an error once the Form is validated', (tester) async {
      registerCountryService(fixtureCountryService());
      final formKey = GlobalKey<FormState>();

      await tester.pumpApp(
        host(
          const CountryField(label: 'Citizenship', purpose: CountryFieldPurpose.nationality),
          formKey: formKey,
        ),
      );
      await tester.pumpAndSettle();

      expect(formKey.currentState!.validate(), isFalse);
      await tester.pump();

      final state = tester.state<FormFieldState<Country>>(
        find.byType(DropdownButtonFormField<Country>),
      );
      expect(state.hasError, isTrue);
    });

    testWidgets('selecting a country clears the stale error without re-validating the Form', (
      tester,
    ) async {
      registerCountryService(fixtureCountryService());
      final formKey = GlobalKey<FormState>();

      await tester.pumpApp(
        host(
          CountryField(
            label: 'Citizenship',
            purpose: CountryFieldPurpose.nationality,
            // A non-null onChanged is what enables the dropdown so it can open.
            onChanged: (_) {},
          ),
          formKey: formKey,
        ),
      );
      await tester.pumpAndSettle();

      // The user hits "Next" on an empty field: the Form validates and the
      // country field turns red.
      expect(formKey.currentState!.validate(), isFalse);
      await tester.pump();

      final state = tester.state<FormFieldState<Country>>(
        find.byType(DropdownButtonFormField<Country>),
      );
      expect(state.hasError, isTrue);

      // Open the dropdown and pick Switzerland. More than one 'Switzerland'
      // Text can be laid out while the menu is open, so target the last.
      await tester.tap(find.byType(DropdownButton<Country>));
      await tester.pumpAndSettle();
      expect(find.byType(DropdownMenuItem<Country>), findsWidgets);
      await tester.tap(find.text('Switzerland').last);
      await tester.pumpAndSettle();

      // autovalidateMode.onUserInteraction re-validates on didChange, so the
      // red border clears immediately without a second Form.validate() — the
      // regression was that the stale error persisted until the next validate().
      expect(state.value?.symbol, 'CH');
      expect(state.hasError, isFalse);
    });
  });

  group('$CountryField hint', () {
    testWidgets('shows the neutral placeholder hint, not a country name, when empty', (
      tester,
    ) async {
      registerCountryService(fixtureCountryService());

      await tester.pumpApp(
        host(
          const CountryField(label: 'Citizenship', purpose: CountryFieldPurpose.nationality),
        ),
      );
      await tester.pumpAndSettle();

      // pumpApp resolves to the en locale in tests, so the hint is the English
      // ARB value. This asserts the hint by text, guarding against a silent ARB
      // regression that the pixel-only goldens cannot catch by value.
      expect(find.text('Select country'), findsOneWidget);
    });
  });
}
