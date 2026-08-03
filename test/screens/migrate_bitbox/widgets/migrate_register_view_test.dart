import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/kyc/kyc_personal_data.dart';
import 'package:realunit_wallet/packages/service/dfx/models/user/dto/real_unit_user_data_dto.dart';
import 'package:realunit_wallet/screens/migrate_bitbox/cubits/migrate_bitbox/migrate_bitbox_cubit.dart';
import 'package:realunit_wallet/screens/migrate_bitbox/widgets/migrate_register_view.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

import '../../../helper/pump_app.dart';

class _MockMigrateBitboxCubit extends MockCubit<MigrateBitboxState>
    implements MigrateBitboxCubit {}

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
  late _MockMigrateBitboxCubit cubit;

  setUp(() {
    cubit = _MockMigrateBitboxCubit();
    when(() => cubit.state).thenReturn(
      const MigrateBitboxRegisterReady(_userData, '0x1234567890abcdef'),
    );
    whenListen(
      cubit,
      const Stream<MigrateBitboxState>.empty(),
      initialState: const MigrateBitboxRegisterReady(
        _userData,
        '0x1234567890abcdef',
      ),
    );
    when(() => cubit.register()).thenAnswer((_) async {});
  });

  Future<void> pumpView(WidgetTester tester, String address) => tester.pumpApp(
    BlocProvider<MigrateBitboxCubit>.value(
      value: cubit,
      child: MigrateRegisterView(
        userData: _userData,
        bitboxAddress: address,
      ),
    ),
  );

  testWidgets('shows user data, truncates a long address, and registers', (
    tester,
  ) async {
    await pumpView(tester, '0x1234567890abcdef');

    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('0x1234…cdef'), findsOneWidget);
    await tester.tap(find.byType(AppFilledButton));

    verify(() => cubit.register()).called(1);
  });

  testWidgets('keeps a short address unchanged', (tester) async {
    await pumpView(tester, '0x1234');

    expect(find.text('0x1234'), findsOneWidget);
  });
}
