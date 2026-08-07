import 'package:bloc_test/bloc_test.dart';
import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_pdf_service.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/screens/settings_tax_report/cubit/settings_tax_report_cubit.dart';
import 'package:realunit_wallet/screens/settings_tax_report/settings_tax_report_page.dart';
import 'package:realunit_wallet/widgets/date_picker_field.dart';

import '../../../helper/helper.dart';

class _MockSettingsTaxReportCubit extends MockCubit<SettingsTaxReportState>
    implements SettingsTaxReportCubit {}

class _MockRealUnitPdfService extends Mock implements RealUnitPdfService {}

void main() {
  // `settings_tax_report_page_{default,loading,failure}` live in
  // `settings_tax_report_golden_test.dart`. Note the existing `_failure`
  // golden stubs `cubit.state` without an emission, so its BlocListener never
  // fires — it shows the idle page, NOT the SnackBar. This file adds the two
  // missing surfaces: the actually-visible failure SnackBar and the date-picker
  // overlay.
  late MockSettingsBloc settingsBloc;
  late _MockSettingsTaxReportCubit taxReportCubit;

  setUp(() {
    settingsBloc = MockSettingsBloc();
    taxReportCubit = _MockSettingsTaxReportCubit();
    when(() => settingsBloc.state).thenReturn(const SettingsState());
    when(() => taxReportCubit.state).thenReturn(const SettingsTaxReportInitial());
  });

  setUpAll(() {
    GetIt.instance.registerSingleton<RealUnitPdfService>(_MockRealUnitPdfService());
  });

  tearDownAll(() async {
    await GetIt.instance.reset();
  });

  // `SettingsTaxReportView` field-initializes `_DatePickerModel`, which reads
  // `clock.now()`; the constructor runs inside the alchemist `builder` (and, for
  // the date picker, `ValueListenableBuilder` re-reads `clock.now()` for
  // `lastDate` on each rebuild). Both are pinned via `withClock`.
  final pinnedClock = Clock.fixed(DateTime.utc(2026, 5, 23));

  Widget buildSubject() => wrapForGolden(
        MultiBlocProvider(
          providers: [
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
            BlocProvider<SettingsTaxReportCubit>.value(value: taxReportCubit),
          ],
          child: SettingsTaxReportView(),
        ),
      );

  group('$SettingsTaxReportPage', () {
    // Emitting `SettingsTaxReportFailure` drives the BlocListener
    // (`settings_tax_report_page.dart:38-45`) to show the red failure SnackBar.
    // pumpAndSettle runs the entrance animation to completion (it does not
    // dismiss the SnackBar — the 4s auto-dismiss is a Timer, not a frame).
    goldenTest(
      'failure SnackBar (red)',
      fileName: 'settings_tax_report_page_failure_snackbar',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) => withClock(pinnedClock, () async {
        await tester.pump(); // deliver the whenListen emission to the listener
        await tester.pumpAndSettle(); // run the SnackBar entrance to completion
      }),
      builder: () {
        whenListen(
          taxReportCubit,
          Stream<SettingsTaxReportState>.value(
            const SettingsTaxReportFailure('Konnte Steuerausweis nicht generieren.'),
          ),
          initialState: const SettingsTaxReportInitial(),
        );
        return withClock(pinnedClock, buildSubject);
      },
    );

    // Tapping the DatePickerField opens the platform date picker. Headless the
    // `DeviceInfo.instance.isIOS` guard (`date_picker.dart:13`) is false, so the
    // deterministic Material `showDatePicker` dialog is what renders — pinned to
    // the initial date (31 Dec 2025) via the fixed clock.
    goldenTest(
      'date picker overlay (Material dialog)',
      fileName: 'settings_tax_report_page_date_picker',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) => withClock(pinnedClock, () async {
        await tester.pumpAndSettle();
        await tester.tap(find.byType(DatePickerField));
        await tester.pumpAndSettle();
      }),
      builder: () => withClock(pinnedClock, buildSubject),
    );
  });
}
