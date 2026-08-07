// Responsive matrix gate for the five settings/user-data edit & status pages.
//
// Proves every save/refresh CTA stays tappable and no layout overflows across
// the full device x text-scale matrix (see test/helper/responsive_matrix.dart),
// after migrating these pages from `SingleChildScrollView + Spacer + CTA
// inside the scroll view` (or a bare `Column(Spacer(), ..., Spacer())` with no
// scroll view at all) to `ScrollableActionsLayout`. This is the regression
// lock for: (1) the save CTA dropping below the fold on the three edit-form
// pages, (2) the refresh CTA overflowing off-screen on the two status pages,
// (3) the horizontal RenderFlex overflow inside `FilePickerField`, and (4) the
// sticky action block staying above the soft keyboard on the form pages.
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_country_service.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/screens/settings_user_data/subpages/edit_address/cubit/settings_edit_address_cubit.dart';
import 'package:realunit_wallet/screens/settings_user_data/subpages/edit_address/settings_edit_address_page.dart';
import 'package:realunit_wallet/screens/settings_user_data/subpages/edit_name/cubit/settings_edit_name_cubit.dart';
import 'package:realunit_wallet/screens/settings_user_data/subpages/edit_name/settings_edit_name_page.dart';
import 'package:realunit_wallet/screens/settings_user_data/subpages/edit_phone_number/cubit/settings_edit_phone_number_cubit.dart';
import 'package:realunit_wallet/screens/settings_user_data/subpages/edit_phone_number/settings_edit_phone_number_page.dart';
import 'package:realunit_wallet/screens/settings_user_data/subpages/others/settings_edit_failure_page.dart';
import 'package:realunit_wallet/screens/settings_user_data/subpages/others/settings_edit_pending_page.dart';
import 'package:realunit_wallet/styles/themes.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/form/file_picker_field.dart';

import '../../helper/helper.dart';

class MockSettingsEditAddressCubit extends MockCubit<SettingsEditAddressState>
    implements SettingsEditAddressCubit {}

class MockSettingsEditNameCubit extends MockCubit<SettingsEditNameState>
    implements SettingsEditNameCubit {}

class MockSettingsEditPhoneNumberCubit extends MockCubit<SettingsEditPhoneNumberState>
    implements SettingsEditPhoneNumberCubit {}

class MockDfxKycService extends Mock implements DfxKycService {}

/// A long, realistic file name -- stresses the `selectedFile!.name` row of
/// [FilePickerField] (used by the name and address pages).
const _longFileName =
    'Nachweisdokument_Wohnsitzbestaetigung_Frontseite_und_Rueckseite_gescannt_hochaufloesend.jpg';

/// A long, realistic German API error -- stresses the phone page's inline
/// failure text.
const _longApiError =
    'Die Verbindung zum Server wurde unerwartet unterbrochen, bevor die '
    'eingegebene Telefonnummer verifiziert werden konnte. Bitte ueberpruefen '
    'Sie Ihre Internetverbindung und versuchen Sie es in wenigen Minuten '
    'erneut.';

/// The short error from the original bug report ("breaks at 3.0 already with
/// a short error").
const _shortApiError = 'Ungueltige Anfrage.';

/// Pumps [child] as a full-page host (real app theme + localizations) under
/// [mediaQuery]. Mirrors `pumpClippedSheet` (test/helper/layout_assertions.dart)
/// for non-sheet, full-screen pages.
Future<void> _pumpPage(
  WidgetTester tester, {
  required Widget child,
  required MediaQueryData mediaQuery,
  Locale locale = const Locale('de'),
}) async {
  await tester.binding.setSurfaceSize(mediaQuery.size);
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });

  await tester.pumpWidget(
    MediaQuery(
      data: mediaQuery,
      child: MaterialApp(
        theme: realUnitTheme,
        locale: locale,
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        home: child,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUpAll(() {
    final getIt = GetIt.instance;
    getIt.registerSingleton<DfxKycService>(MockDfxKycService());
    getIt.registerSingleton<DfxCountryService>(fixtureCountryService());
  });

  group('$SettingsEditAddressView responsive matrix', () {
    late MockSettingsEditAddressCubit cubit;

    setUp(() {
      cubit = MockSettingsEditAddressCubit();
      when(() => cubit.state).thenReturn(const SettingsEditAddressReady('url'));
      when(() => cubit.refresh()).thenReturn(null);
      when(
        () => cubit.submitAddress(
          street: any(named: 'street'),
          houseNumber: any(named: 'houseNumber'),
          zip: any(named: 'zip'),
          city: any(named: 'city'),
          countryId: any(named: 'countryId'),
          fileBase64: any(named: 'fileBase64'),
          fileName: any(named: 'fileName'),
        ),
      ).thenAnswer((_) async {});
    });

    Future<void> pumpPage(WidgetTester tester, MediaQueryData mediaQuery) => _pumpPage(
      tester,
      child: BlocProvider<SettingsEditAddressCubit>.value(
        value: cubit,
        child: const SettingsEditAddressView(),
      ),
      mediaQuery: mediaQuery,
    );

    for (final cell in kFullResponsiveMatrix) {
      testWidgets('Ready . ${cell.id}', (tester) async {
        await withTargetPlatform(cell.device.platform, () async {
          await expectNoLayoutOverflow(
            tester,
            () => pumpPage(tester, cell.mediaQuery),
            reason: 'overflow on address Ready / ${cell.label}',
          );

          await expectFullyTappable(
            tester,
            find.byType(AppFilledButton),
            within: find.byType(SettingsEditAddressView),
            reason: '${cell.label}: save CTA not tappable',
          );
        });
      });
    }

    // Keyboard proof: Scaffold.resizeToAvoidBottomInset defaults to true and
    // is never overridden in this page, so it already shrinks the bounded
    // height ScrollableActionsLayout receives and zeroes descendant
    // viewInsets -- no manual keyboard padding is needed. Proven, not
    // asserted: pump a real open-keyboard MediaQuery and check the CTA.
    testWidgets('keyboard open (viewInsets.bottom: 336) keeps save CTA tappable', (tester) async {
      final cell = MatrixCell(
        kIosDeviceProfiles.firstWhere((d) => d.id == 'iphone_se_3'),
        1.0,
      );
      final keyboardMediaQuery = cell.mediaQuery.copyWith(
        viewInsets: const EdgeInsets.only(bottom: 336),
      );

      await withTargetPlatform(cell.device.platform, () async {
        await expectNoLayoutOverflow(tester, () => pumpPage(tester, keyboardMediaQuery));

        await expectFullyTappable(
          tester,
          find.byType(AppFilledButton),
          within: find.byType(SettingsEditAddressView),
          reason: 'save CTA hidden or unreachable behind the open keyboard',
        );
      });
    });
  });

  group('$SettingsEditNameView responsive matrix', () {
    late MockSettingsEditNameCubit cubit;

    setUp(() {
      cubit = MockSettingsEditNameCubit();
      when(() => cubit.state).thenReturn(const SettingsEditNameReady('url'));
      when(() => cubit.refresh()).thenReturn(null);
      when(
        () => cubit.submitName(
          firstName: any(named: 'firstName'),
          lastName: any(named: 'lastName'),
          fileBase64: any(named: 'fileBase64'),
          fileName: any(named: 'fileName'),
        ),
      ).thenAnswer((_) async {});
    });

    Future<void> pumpPage(WidgetTester tester, MediaQueryData mediaQuery) => _pumpPage(
      tester,
      child: BlocProvider<SettingsEditNameCubit>.value(
        value: cubit,
        child: const SettingsEditNameView(),
      ),
      mediaQuery: mediaQuery,
    );

    for (final cell in kFullResponsiveMatrix) {
      testWidgets('Ready . ${cell.id}', (tester) async {
        await withTargetPlatform(cell.device.platform, () async {
          await expectNoLayoutOverflow(
            tester,
            () => pumpPage(tester, cell.mediaQuery),
            reason: 'overflow on name Ready / ${cell.label}',
          );

          await expectFullyTappable(
            tester,
            find.byType(AppFilledButton),
            within: find.byType(SettingsEditNameView),
            reason: '${cell.label}: save CTA not tappable',
          );
        });
      });
    }

    testWidgets('keyboard open (viewInsets.bottom: 336) keeps save CTA tappable', (tester) async {
      final cell = MatrixCell(
        kIosDeviceProfiles.firstWhere((d) => d.id == 'iphone_se_3'),
        1.0,
      );
      final keyboardMediaQuery = cell.mediaQuery.copyWith(
        viewInsets: const EdgeInsets.only(bottom: 336),
      );

      await withTargetPlatform(cell.device.platform, () async {
        await expectNoLayoutOverflow(tester, () => pumpPage(tester, keyboardMediaQuery));

        await expectFullyTappable(
          tester,
          find.byType(AppFilledButton),
          within: find.byType(SettingsEditNameView),
          reason: 'save CTA hidden or unreachable behind the open keyboard',
        );
      });
    });
  });

  group('$SettingsEditPhoneNumberView responsive matrix', () {
    late MockSettingsEditPhoneNumberCubit cubit;

    void stub(SettingsEditPhoneNumberState state) {
      cubit = MockSettingsEditPhoneNumberCubit();
      when(() => cubit.state).thenReturn(state);
      when(() => cubit.editPhoneNumber(any())).thenAnswer((_) async {});
    }

    Future<void> pumpPage(WidgetTester tester, MediaQueryData mediaQuery) => _pumpPage(
      tester,
      child: BlocProvider<SettingsEditPhoneNumberCubit>.value(
        value: cubit,
        child: const SettingsEditPhoneNumberView(),
      ),
      mediaQuery: mediaQuery,
    );

    for (final cell in kFullResponsiveMatrix) {
      testWidgets('Initial . ${cell.id}', (tester) async {
        stub(const SettingsEditPhoneNumberInitial());
        await withTargetPlatform(cell.device.platform, () async {
          await expectNoLayoutOverflow(
            tester,
            () => pumpPage(tester, cell.mediaQuery),
            reason: 'overflow on phone Initial / ${cell.label}',
          );

          await expectFullyTappable(
            tester,
            find.byType(AppFilledButton),
            within: find.byType(SettingsEditPhoneNumberView),
            reason: '${cell.label}: save CTA not tappable',
          );
        });
      });

      testWidgets('long API error . ${cell.id}', (tester) async {
        stub(const SettingsEditPhoneNumberFailure(_longApiError));
        await withTargetPlatform(cell.device.platform, () async {
          await expectNoLayoutOverflow(
            tester,
            () => pumpPage(tester, cell.mediaQuery),
            reason: 'overflow on phone long API error / ${cell.label}',
          );

          await expectFullyTappable(
            tester,
            find.byType(AppFilledButton),
            within: find.byType(SettingsEditPhoneNumberView),
            reason: '${cell.label}: save CTA not tappable with a long API error shown',
          );
        });
      });
    }

    // REGRESSION: exact reported break (iPhone SE, textScale 3.0, SHORT error).
    testWidgets(
      'REGRESSION: iPhone SE + textScale 3.0 with short error still tappable',
      (tester) async {
        stub(const SettingsEditPhoneNumberFailure(_shortApiError));
        final cell = MatrixCell(
          kIosDeviceProfiles.firstWhere((d) => d.id == 'iphone_se_3'),
          3.0,
        );

        await withTargetPlatform(cell.device.platform, () async {
          await expectNoLayoutOverflow(tester, () => pumpPage(tester, cell.mediaQuery));

          await expectFullyTappable(
            tester,
            find.byType(AppFilledButton),
            within: find.byType(SettingsEditPhoneNumberView),
          );
        });
      },
    );

    testWidgets('keyboard open (viewInsets.bottom: 336) keeps save CTA tappable', (tester) async {
      stub(const SettingsEditPhoneNumberInitial());
      final cell = MatrixCell(
        kIosDeviceProfiles.firstWhere((d) => d.id == 'iphone_se_3'),
        1.0,
      );
      final keyboardMediaQuery = cell.mediaQuery.copyWith(
        viewInsets: const EdgeInsets.only(bottom: 336),
      );

      await withTargetPlatform(cell.device.platform, () async {
        await expectNoLayoutOverflow(tester, () => pumpPage(tester, keyboardMediaQuery));

        await expectFullyTappable(
          tester,
          find.byType(AppFilledButton),
          within: find.byType(SettingsEditPhoneNumberView),
          reason: 'save CTA hidden or unreachable behind the open keyboard',
        );
      });
    });
  });

  group('$SettingsEditPendingPage responsive matrix', () {
    for (final cell in kFullResponsiveMatrix) {
      testWidgets(cell.id, (tester) async {
        await withTargetPlatform(cell.device.platform, () async {
          await expectNoLayoutOverflow(
            tester,
            () => _pumpPage(
              tester,
              child: SettingsEditPendingPage(
                title: 'Adresse aendern',
                onRefresh: () {},
              ),
              mediaQuery: cell.mediaQuery,
            ),
            reason: 'overflow on pending page / ${cell.label}',
          );

          await expectFullyTappable(
            tester,
            find.byType(AppFilledButton),
            within: find.byType(SettingsEditPendingPage),
            reason: '${cell.label}: refresh CTA not tappable',
          );
        });
      });
    }
  });

  group('$SettingsEditFailurePage responsive matrix', () {
    for (final cell in kFullResponsiveMatrix) {
      testWidgets(cell.id, (tester) async {
        await withTargetPlatform(cell.device.platform, () async {
          await expectNoLayoutOverflow(
            tester,
            () => _pumpPage(
              tester,
              child: SettingsEditFailurePage(
                _longApiError,
                title: 'Adresse aendern',
                onRefresh: () {},
              ),
              mediaQuery: cell.mediaQuery,
            ),
            reason: 'overflow on failure page / ${cell.label}',
          );

          await expectFullyTappable(
            tester,
            find.byType(AppFilledButton),
            within: find.byType(SettingsEditFailurePage),
            reason: '${cell.label}: refresh CTA not tappable',
          );
        });
      });
    }
  });

  group('$FilePickerField long file name (used by name & address pages)', () {
    // FilePickerField is one shared widget/class embedded verbatim by both
    // pages, so its Row-overflow bug and fix are identical regardless of
    // which page hosts it. `_selectedFile` is private State on both pages
    // with no external setter, and the real image_picker flow is a platform
    // channel -- so the "selected file" row is exercised by mounting
    // FilePickerField directly, across a representative narrow-device
    // subset (not the full 35-cell matrix -- disproportionate for one
    // simple, shared widget).
    //
    // XFile.name on the io platform (what `flutter test` runs under) is
    // ALWAYS the path's basename -- the `name:` constructor parameter is
    // silently ignored (see package:cross_file's io implementation). So to
    // get a long `.name`, the file on disk must actually be named that; to
    // keep `Image.file` decoding real bytes (no decode-error noise), copy an
    // existing repo asset's bytes into a long-named file in a fresh temp
    // dir at test time -- nothing new is added to the repo.
    late Directory tempDir;
    late File longNameFile;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('file_picker_field_test_');
      longNameFile = File('${tempDir.path}${Platform.pathSeparator}$_longFileName');
      final bytes = await File('assets/icons/realunit_wallet_logo_full.png').readAsBytes();
      await longNameFile.writeAsBytes(bytes);
    });

    tearDownAll(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    final narrowDevices = [
      kIosDeviceProfiles.firstWhere((d) => d.id == 'iphone_se_3'),
      kAndroidDeviceProfiles.firstWhere((d) => d.id == 'android_small'),
    ];

    for (final cell in buildResponsiveMatrix(devices: narrowDevices)) {
      testWidgets(cell.id, (tester) async {
        await withTargetPlatform(cell.device.platform, () async {
          await expectNoLayoutOverflow(
            tester,
            () => _pumpPage(
              tester,
              child: Scaffold(
                body: FilePickerField(
                  label: 'Nachweis-Dokument',
                  selectedFile: XFile(longNameFile.path),
                  onTap: () {},
                ),
              ),
              mediaQuery: cell.mediaQuery,
            ),
            reason: 'overflow on FilePickerField long file name / ${cell.label}',
          );
        });
      });
    }
  });
}
