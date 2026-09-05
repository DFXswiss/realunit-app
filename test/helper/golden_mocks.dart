import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_referral_service.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_registration_service.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/screens/home/bloc/home_bloc.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';

class MockHomeBloc extends MockBloc<HomeEvent, HomeState> implements HomeBloc {}

class MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState> implements SettingsBloc {}

class MockAppStore extends Mock implements AppStore {}

class MockRealUnitRegistrationService extends Mock implements RealUnitRegistrationService {}

class MockRealUnitReferralService extends Mock implements RealUnitReferralService {}

class MockSoftwareWallet extends Mock implements SoftwareWallet {}

class MockBitboxWallet extends Mock implements BitboxWallet {}
