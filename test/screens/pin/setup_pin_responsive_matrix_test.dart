// Responsive matrix gate for SetupPinView keypad.
//
// Proves digit keys stay fully tappable across the full device × text-scale
// matrix (see test/helper/responsive_matrix.dart). Regression lock for the
// IntrinsicHeight + Spacer shape that pushed the NumberPad below the viewport
// on first frame once header copy grew at high accessibility text scale.
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/biometric_service.dart';
import 'package:realunit_wallet/packages/storage/secure_storage.dart';
import 'package:realunit_wallet/screens/pin/bloc/auth/pin_auth_cubit.dart';
import 'package:realunit_wallet/screens/pin/bloc/setup_pin/setup_pin_cubit.dart';
import 'package:realunit_wallet/screens/pin/setup_pin_page.dart';
import 'package:realunit_wallet/widgets/number_pad.dart';

import '../../helper/helper.dart';

class MockSetupPinCubit extends MockCubit<SetupPinState> implements SetupPinCubit {}

class MockPinAuthCubit extends MockCubit<PinAuthState> implements PinAuthCubit {}

class MockSecureStorage extends Mock implements SecureStorage {}

class MockBiometricService extends Mock implements BiometricService {}

void main() {
  late SetupPinCubit setupPinCubit;
  late PinAuthCubit pinAuthCubit;

  void setupDependencyInjection() {
    final getIt = GetIt.instance;
    getIt.registerSingleton<BiometricService>(MockBiometricService());
    getIt.registerSingleton<SecureStorage>(MockSecureStorage());
    getIt.registerSingleton<PinAuthCubit>(pinAuthCubit);
  }

  setUpAll(() {
    pinAuthCubit = MockPinAuthCubit();
    when(() => pinAuthCubit.state).thenReturn(const PinAuthState());
    when(() => pinAuthCubit.onPinSetupComplete()).thenAnswer((_) => Future.value());
    setupDependencyInjection();
  });

  tearDownAll(() async => await GetIt.instance.reset());

  Future<void> pumpScreen(
    WidgetTester tester,
    MatrixCell cell, {
    required SetupPinState state,
  }) async {
    setupPinCubit = MockSetupPinCubit();
    when(() => setupPinCubit.state).thenReturn(state);
    when(() => setupPinCubit.isBiometricAvailable()).thenAnswer((_) => Future.value(false));
    whenListen(
      setupPinCubit,
      const Stream<SetupPinState>.empty(),
      initialState: state,
    );

    await tester.binding.setSurfaceSize(cell.mediaQuery.size);
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      MediaQuery(
        data: cell.mediaQuery,
        child: MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          home: BlocProvider.value(
            value: setupPinCubit,
            child: const SetupPinView(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('SetupPinMode.create responsive matrix', () {
    for (final cell in kFullResponsiveMatrix) {
      testWidgets('create · ${cell.id}', (tester) async {
        await withTargetPlatform(cell.device.platform, () async {
          await expectNoLayoutOverflow(
            tester,
            () async {
              await pumpScreen(
                tester,
                cell,
                state: const SetupPinState(),
              );
            },
            reason: 'overflow on SetupPin create / ${cell.label}',
          );

          expect(find.byType(NumberPad), findsOneWidget);

          await expectFullyTappable(
            tester,
            find.text('1'),
            within: find.byType(SetupPinView),
            reason: 'SetupPin create / ${cell.label}: digit key not tappable',
          );
        });
      });
    }
  });

  group('SetupPinMode.confirm with mismatch responsive matrix', () {
    for (final cell in kFullResponsiveMatrix) {
      testWidgets('confirm mismatch · ${cell.id}', (tester) async {
        await withTargetPlatform(cell.device.platform, () async {
          await expectNoLayoutOverflow(
            tester,
            () async {
              await pumpScreen(
                tester,
                cell,
                state: const SetupPinState(
                  mode: SetupPinMode.confirm,
                  mismatch: true,
                ),
              );
            },
            reason: 'overflow on SetupPin confirm mismatch / ${cell.label}',
          );

          expect(find.byType(NumberPad), findsOneWidget);
          expect(find.text(S.current.pinConfirmFailed), findsOneWidget);

          await expectFullyTappable(
            tester,
            find.text('1'),
            within: find.byType(SetupPinView),
            reason:
                'SetupPin confirm mismatch / ${cell.label}: digit key not tappable',
          );
        });
      });
    }
  });
}
