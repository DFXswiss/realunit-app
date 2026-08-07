import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_country_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/country/country.dart';
import 'package:realunit_wallet/screens/kyc/cubits/kyc/kyc_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/nationality/cubit/kyc_nationality/kyc_nationality_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/nationality/kyc_nationality_page.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

import '../../../helper/helper.dart';

class _MockKycNationalityCubit extends MockCubit<KycNationalityState>
    implements KycNationalityCubit {}

class _MockKycCubit extends MockCubit<KycState> implements KycCubit {}

void main() {
  // The `kyc_nationality_page_default` idle baseline (loaded, nothing picked)
  // lives in `kyc_nationality_golden_test.dart`. This file covers the
  // state-driven branches of `KycNationalityView` (submit spinner, submit-failed
  // SnackBar) and the three CountryField surfaces the default golden can't show
  // (in-field spinner, load error, open dropdown), plus the empty-selection
  // validation border.
  late _MockKycNationalityCubit kycNationalityCubit;
  late _MockKycCubit kycCubit;

  setUp(() {
    kycNationalityCubit = _MockKycNationalityCubit();
    kycCubit = _MockKycCubit();
    when(() => kycNationalityCubit.state)
        .thenReturn(const KycNationalityInitial());
    when(() => kycCubit.state).thenReturn(const KycInitial());
  });

  tearDown(() async => GetIt.instance.reset());

  // Each state needs its own DfxCountryService: the service caches the country
  // list on the instance, so a shared one would defeat the loading/error
  // branches. Register fresh per test; tearDown resets getIt. The country data
  // itself is never mocktail-stubbed — it flows through the real service over a
  // MockClient HTTP seam (see docs/testing.md "Country data in tests").
  void useCountryService(DfxCountryService service) {
    final getIt = GetIt.instance;
    if (getIt.isRegistered<DfxCountryService>()) {
      getIt.unregister<DfxCountryService>();
    }
    getIt.registerSingleton<DfxCountryService>(service);
  }

  Widget buildSubject() => wrapForGolden(
        MultiBlocProvider(
          providers: [
            BlocProvider<KycNationalityCubit>.value(value: kycNationalityCubit),
            BlocProvider<KycCubit>.value(value: kycCubit),
          ],
          child: const KycNationalityView(url: 'https://example.com'),
        ),
      );

  // Tap the closed country field so the dropdown menu route opens (CH/DE/IT/FR
  // are floated to the top by CountryField's priority sort). Mirror of the
  // registration-step goldens.
  Future<void> openCountryDropdown(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<Country>));
    await tester.pumpAndSettle();
  }

  group('$KycNationalityView', () {
    // KycNationalityLoading → the Next AppFilledButton spins (page:80-81). Let
    // the fixture country future resolve into the dropdown first, then freeze
    // the button spinner on a fixed frame (pumpAndSettle would never end).
    goldenTest(
      'submit in flight — next button spinner',
      fileName: 'kyc_nationality_page_submit_loading',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) async {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
      },
      builder: () {
        useCountryService(fixtureCountryService());
        when(() => kycNationalityCubit.state)
            .thenReturn(const KycNationalityLoading());
        return buildSubject();
      },
    );

    // KycNationalityFailure → red `setNationalityFailed` SnackBar (page:51-58)
    // over the loaded, idle body.
    goldenTest(
      'submit failure — red snackbar',
      fileName: 'kyc_nationality_page_submit_failure',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) async {
        await tester.pump();
        await tester.pumpAndSettle();
      },
      builder: () {
        useCountryService(fixtureCountryService());
        whenListen(
          kycNationalityCubit,
          Stream<KycNationalityState>.value(
            const KycNationalityFailure('network error'),
          ),
          initialState: const KycNationalityInitial(),
        );
        return buildSubject();
      },
    );

    // CountryField waiting on the country list → the in-field
    // CupertinoActivityIndicator (country_field.dart:59-68). A never-completing
    // MockClient keeps the FutureBuilder in ConnectionState.waiting; a single
    // pump freezes the spinner.
    goldenTest(
      'country field loading — in-field spinner',
      fileName: 'kyc_nationality_page_country_loading',
      constraints: phoneConstraints,
      pumpBeforeTest: pumpOnce,
      builder: () {
        useCountryService(
          countryServiceWithClient(
            MockClient((_) => Completer<http.Response>().future),
          ),
        );
        return buildSubject();
      },
    );

    // CountryField load failure → the red `countriesLoadFailed` text + Retry
    // button, dropdown hidden (country_field.dart:70-88).
    goldenTest(
      'country field load error — red text + retry',
      fileName: 'kyc_nationality_page_country_error',
      constraints: phoneConstraints,
      builder: () {
        useCountryService(failingCountryService());
        return buildSubject();
      },
    );

    // The open dropdown menu route — the selectable country list overlay.
    goldenTest(
      'country dropdown open — the selectable country list',
      fileName: 'kyc_nationality_page_dropdown_open',
      constraints: phoneConstraints,
      pumpBeforeTest: openCountryDropdown,
      builder: () {
        useCountryService(fixtureCountryService());
        return buildSubject();
      },
    );

    // Tapping Next with nothing picked runs Form.validate(); the country field's
    // DropdownField validator returns '' → red border, no message text
    // (country_field.dart:108, _StatusField:169-184). Mirror of the tax-step
    // country_error golden.
    goldenTest(
      'validation error — empty selection red border',
      fileName: 'kyc_nationality_page_validation_error',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) async {
        await tester.pumpAndSettle();
        await tester.tap(find.byType(AppFilledButton));
        await tester.pumpAndSettle();
      },
      builder: () {
        useCountryService(fixtureCountryService());
        return buildSubject();
      },
    );
  });
}
