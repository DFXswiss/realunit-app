import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/screens/settings_security/cubits/settings_security_cubit.dart';
import 'package:realunit_wallet/screens/settings_security/settings_security_page.dart';

import '../../../helper/helper.dart';

class _MockSettingsSecurityCubit extends MockCubit<SettingsSecurityState>
    implements SettingsSecurityCubit {}

void main() {
  // `settings_security_page_default` (biometrics supported + enabled, Switch
  // ON) lives in `settings_security_golden_test.dart`. This file covers the
  // other rendered branches of `SettingsSecurityView`
  // (`settings_security_page.dart`).
  //
  // The green "PIN geändert" success SnackBar (page:94-102) is intentionally
  // NOT covered: it is fired from the `_onPinChanged` navigation callback that
  // only runs after the full change-PIN flow completes, not from any
  // `SettingsSecurityState`. There is no state-driven path to it, so a faithful
  // golden would require driving the whole PIN navigation stack (out of scope)
  // — reconstructing the SnackBar by hand would be a hack. Documented skip.
  late _MockSettingsSecurityCubit cubit;

  setUp(() {
    cubit = _MockSettingsSecurityCubit();
  });

  Widget buildSubject() => wrapForGolden(
        BlocProvider<SettingsSecurityCubit>.value(
          value: cubit,
          child: const SettingsSecurityView(),
        ),
      );

  group('$SettingsSecurityPage', () {
    // biometricSupported + !biometricEnabled → toggle row present, Switch OFF
    // (page:64-74, 123-129).
    goldenTest(
      'biometrics supported but disabled (switch off)',
      fileName: 'settings_security_page_biometrics_disabled',
      constraints: phoneConstraints,
      builder: () {
        when(() => cubit.state).thenReturn(
          const SettingsSecurityState(
            biometricSupported: true,
            biometricEnabled: false,
          ),
        );
        return buildSubject();
      },
    );

    // !biometricSupported → the whole biometric toggle row is dropped, only the
    // "Change PIN" row remains (page:64 guard).
    goldenTest(
      'biometrics not supported (toggle row hidden)',
      fileName: 'settings_security_page_no_biometrics',
      constraints: phoneConstraints,
      builder: () {
        when(() => cubit.state).thenReturn(
          const SettingsSecurityState(biometricSupported: false),
        );
        return buildSubject();
      },
    );

    // isBusy → the Switch is replaced by a CupertinoActivityIndicator
    // (page:116-122); freeze the spinner on its first frame.
    goldenTest(
      'biometric round-trip in flight (spinner instead of switch)',
      fileName: 'settings_security_page_busy',
      constraints: phoneConstraints,
      pumpBeforeTest: pumpOnce,
      builder: () {
        when(() => cubit.state).thenReturn(
          const SettingsSecurityState(
            biometricSupported: true,
            biometricEnabled: false,
            isBusy: true,
          ),
        );
        return buildSubject();
      },
    );

    // A state with `error != null` drives the BlocConsumer.listener
    // (page:50-56) to show the red failure SnackBar. Emitting the error via
    // `whenListen` (initial state has no error) fires `listenWhen`; pumpAndSettle
    // runs the entrance animation to completion (the 4s auto-dismiss is a Timer,
    // not a frame, so the SnackBar stays visible).
    goldenTest(
      'biometric-enable failure SnackBar (red)',
      fileName: 'settings_security_page_error_snackbar',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) async {
        await tester.pump(); // deliver the whenListen emission to the listener
        await tester.pumpAndSettle(); // run the SnackBar entrance to completion
      },
      builder: () {
        whenListen(
          cubit,
          Stream<SettingsSecurityState>.value(
            const SettingsSecurityState(
              biometricSupported: true,
              biometricEnabled: false,
              error: SettingsSecurityError.biometricEnableFailed,
            ),
          ),
          initialState: const SettingsSecurityState(
            biometricSupported: true,
            biometricEnabled: false,
          ),
        );
        return buildSubject();
      },
    );
  });
}
