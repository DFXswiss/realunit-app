import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/screens/pin/bloc/setup_pin/setup_pin_cubit.dart';
import 'package:realunit_wallet/screens/pin/setup_pin_page.dart';

import '../../../helper/helper.dart';

class _MockSetupPinCubit extends MockCubit<SetupPinState> implements SetupPinCubit {}

void main() {
  late _MockSetupPinCubit setupPinCubit;

  setUp(() {
    setupPinCubit = _MockSetupPinCubit();
    when(() => setupPinCubit.state).thenReturn(
      const SetupPinState(mode: SetupPinMode.create),
    );
    when(() => setupPinCubit.isBiometricAvailable()).thenAnswer((_) async => false);
  });

  Widget buildSubject() => BlocProvider<SetupPinCubit>.value(
    value: setupPinCubit,
    child: const SetupPinView(),
  );

  group('$SetupPinView', () {
    goldenTest(
      'create mode default',
      fileName: 'setup_pin_page_default',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () => wrapForGolden(buildSubject()),
    );

    goldenTest(
      'confirming step after first pin entered',
      fileName: 'setup_pin_page_confirming',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () {
        when(() => setupPinCubit.state).thenReturn(
          const SetupPinState(mode: SetupPinMode.confirm),
        );
        return wrapForGolden(buildSubject());
      },
    );

    goldenTest(
      'submitting state replaces the number pad with a spinner',
      fileName: 'setup_pin_page_submitting',
      // CupertinoActivityIndicator never settles; pump once to capture the
      // initial frame instead of letting pumpAndSettle hang.
      pumpBeforeTest: pumpOnce,
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () {
        when(() => setupPinCubit.state).thenReturn(
          const SetupPinState(mode: SetupPinMode.confirm, isSubmitting: true),
        );
        return wrapForGolden(buildSubject());
      },
    );

    goldenTest(
      'confirm mismatch marks the dots red and shows the mismatch message',
      fileName: 'setup_pin_page_confirm_mismatch',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () {
        when(() => setupPinCubit.state).thenReturn(
          const SetupPinState(mode: SetupPinMode.confirm, mismatch: true),
        );
        return wrapForGolden(buildSubject());
      },
    );

    goldenTest(
      'store failure keeps the pad and shows the save-failed message',
      fileName: 'setup_pin_page_store_failed',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () {
        when(() => setupPinCubit.state).thenReturn(
          const SetupPinState(mode: SetupPinMode.confirm, storeFailed: true),
        );
        return wrapForGolden(buildSubject());
      },
    );
  });
}
