import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/bitbox_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/kyc/kyc_personal_data.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/registration_status.dart';
import 'package:realunit_wallet/packages/service/dfx/models/user/dto/real_unit_user_data_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_registration_service.dart';
import 'package:realunit_wallet/packages/wallet/exceptions/signing_cancelled_exception.dart';
import 'package:realunit_wallet/packages/wallet/wallet_account.dart';
import 'package:realunit_wallet/screens/migrate_bitbox/cubits/migrate_bitbox/migrate_bitbox_cubit.dart';
import 'package:realunit_wallet/screens/migrate_bitbox/widgets/migrate_register_view.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

import '../../../helper/pump_app.dart';

class _MockMigrateBitboxCubit extends MockCubit<MigrateBitboxState>
    implements MigrateBitboxCubit {}

class _MockRegistrationService extends Mock implements RealUnitRegistrationService {}

class _MockWalletAccount extends Mock implements AWalletAccount {}

const _userData = RealUnitUserDataDto(
  email: 'ada@example.com',
  name: 'Ada Lovelace',
  type: 'HUMAN',
  phoneNumber: '+41 79 000 00 00',
  birthday: '1815-12-10',
  nationality: 'CH',
  addressStreet: 'Bahnhofstrasse 1',
  addressPostalCode: '8000',
  addressCity: 'Zurich',
  addressCountry: 'CH',
  swissTaxResidence: true,
  lang: 'de',
  kycData: KycPersonalData(
    accountType: KycAccountType.personal,
    firstName: 'Ada',
    lastName: 'Lovelace',
    phone: '+41 79 000 00 00',
    address: KycAddress(
      street: 'Bahnhofstrasse',
      zip: '8000',
      city: 'Zurich',
      country: 41,
    ),
  ),
);

void main() {
  late _MockMigrateBitboxCubit parentCubit;
  late _MockRegistrationService registrationService;
  late _MockWalletAccount account;

  setUpAll(() {
    registerFallbackValue(_MockWalletAccount());
    registerFallbackValue(_userData);
  });

  setUp(() {
    parentCubit = _MockMigrateBitboxCubit();
    registrationService = _MockRegistrationService();
    account = _MockWalletAccount();
    when(() => parentCubit.state).thenReturn(
      const MigrateBitboxRegisterReady(_userData, '0x1234567890abcdef'),
    );
    whenListen(
      parentCubit,
      const Stream<MigrateBitboxState>.empty(),
      initialState: const MigrateBitboxRegisterReady(
        _userData,
        '0x1234567890abcdef',
      ),
    );
    when(() => parentCubit.draftAccount).thenReturn(account);
    when(() => parentCubit.linkedJwt).thenReturn('linked-jwt');
    when(() => parentCubit.onRegisterCompleted()).thenAnswer((_) async {});
    when(() => parentCubit.onRegisterPending()).thenReturn(null);
    GetIt.instance.registerSingleton<RealUnitRegistrationService>(
      registrationService,
    );
  });

  tearDown(() async {
    await GetIt.instance.unregister<RealUnitRegistrationService>();
  });

  Future<void> pumpView(WidgetTester tester, String address) => tester.pumpApp(
    BlocProvider<MigrateBitboxCubit>.value(
      value: parentCubit,
      child: MigrateRegisterView(
        userData: _userData,
        bitboxAddress: address,
      ),
    ),
  );

  testWidgets('ready shows user data, truncates a long address, and submits', (
    tester,
  ) async {
    when(
      () => registrationService.registerWalletFor(any(), any(), any()),
    ).thenAnswer((_) async => RegistrationStatus.completed);
    await pumpView(tester, '0x1234567890abcdef');

    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('0x1234…cdef'), findsOneWidget);
    await tester.tap(find.byType(AppFilledButton));
    await tester.pump();

    verify(
      () => registrationService.registerWalletFor(
        account,
        _userData,
        'linked-jwt',
      ),
    ).called(1);
  });

  testWidgets('keeps a short address unchanged', (tester) async {
    await pumpView(tester, '0x1234');

    expect(find.text('0x1234'), findsOneWidget);
  });

  testWidgets('submitting disables back navigation and shows a loading button', (
    tester,
  ) async {
    final pending = Completer<RegistrationStatus>();
    when(
      () => registrationService.registerWalletFor(any(), any(), any()),
    ).thenAnswer((_) => pending.future);
    await pumpView(tester, '0x1234');

    await tester.tap(find.byType(AppFilledButton));
    await tester.pump();

    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
    final button = tester.widget<FilledButton>(find.bySubtype<FilledButton>());
    expect(button.onPressed, isNull);

    pending.complete(RegistrationStatus.completed);
    await tester.pump();
  });

  final failureCases = <Exception>[
    const SigningCancelledException(),
    const BitboxNotConnectedException(),
    Exception('registration failed'),
  ];

  for (final error in failureCases) {
    testWidgets('$error shows the classified failure and retries', (tester) async {
      var calls = 0;
      when(
        () => registrationService.registerWalletFor(any(), any(), any()),
      ).thenAnswer((_) async {
        calls++;
        if (calls == 1) throw error;
        return RegistrationStatus.completed;
      });
      await pumpView(tester, '0x1234');

      await tester.tap(find.byType(AppFilledButton));
      await tester.pump();
      await tester.pump();

      final expectedMessage = switch (error) {
        SigningCancelledException() => S.current.sendFailureSignatureCancelled,
        BitboxNotConnectedException() => S.current.connectBitboxFailed,
        _ => error.toString(),
      };
      expect(find.text(expectedMessage), findsOneWidget);
      expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isTrue);
      expect(find.text(S.current.close), findsOneWidget);

      await tester.tap(find.widgetWithText(AppFilledButton, S.current.retry));
      await tester.pump();
      await tester.pump();
      expect(calls, 2);
    });
  }

  testWidgets('completed registration notifies the parent and shows a transient spinner', (
    tester,
  ) async {
    when(
      () => registrationService.registerWalletFor(any(), any(), any()),
    ).thenAnswer((_) async => RegistrationStatus.completed);
    await pumpView(tester, '0x1234');

    await tester.tap(find.byType(AppFilledButton));
    await tester.pump();
    await tester.pump();

    verify(() => parentCubit.onRegisterCompleted()).called(1);
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
  });

  for (final status in [
    RegistrationStatus.pendingReview,
    RegistrationStatus.forwardingFailed,
  ]) {
    testWidgets('$status notifies the parent registration is pending', (tester) async {
      when(
        () => registrationService.registerWalletFor(any(), any(), any()),
      ).thenAnswer((_) async => status);
      await pumpView(tester, '0x1234');

      await tester.tap(find.byType(AppFilledButton));
      await tester.pump();
      await tester.pump();

      verify(() => parentCubit.onRegisterPending()).called(1);
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    });
  }
}
