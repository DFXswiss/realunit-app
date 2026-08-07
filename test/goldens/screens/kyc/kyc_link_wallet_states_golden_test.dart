import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/kyc/kyc_personal_data.dart';
import 'package:realunit_wallet/packages/service/dfx/models/user/dto/real_unit_user_data_dto.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/screens/kyc/cubits/kyc/kyc_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/link_wallet/cubits/kyc_link_wallet_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/link_wallet/kyc_link_wallet_page.dart';

import '../../../helper/helper.dart';

class _MockKycLinkWalletCubit extends MockCubit<KycLinkWalletState>
    implements KycLinkWalletCubit {}

class _MockKycCubit extends MockCubit<KycState> implements KycCubit {}

class _MockAppStore extends Mock implements AppStore {}

const _kycData = KycPersonalData(
  accountType: KycAccountType.personal,
  firstName: 'Ada',
  lastName: 'Lovelace',
  phone: '+41790000000',
  address: KycAddress(street: 'S', zip: '8000', city: 'Zurich', country: 41),
);

const _userData = RealUnitUserDataDto(
  email: 'ada@example.com',
  name: 'Ada Lovelace',
  type: 'HUMAN',
  phoneNumber: '+41790000000',
  birthday: '1815-12-10',
  nationality: 'CH',
  addressStreet: 'S',
  addressPostalCode: '8000',
  addressCity: 'Zurich',
  addressCountry: 'CH',
  swissTaxResidence: true,
  lang: 'de',
  kycData: _kycData,
);

const _debugAddress = '0xfaeefaeefaeefaeefaeefaeefaeefaeefaeeb6a0';

void main() {
  // The `kyc_link_wallet_page_default` (ready) and `_bitbox_required` baselines
  // live in `kyc_link_wallet_golden_test.dart`. This file covers the remaining
  // BlocConsumer branches of `KycLinkWalletView` plus the defensive
  // missing-userData page (`kyc_link_wallet_page.dart`).
  late _MockKycLinkWalletCubit linkCubit;
  late _MockKycCubit kycCubit;

  setUpAll(() {
    final appStore = _MockAppStore();
    when(() => appStore.wallet)
        .thenReturn(DebugWallet(1, 'Test', _debugAddress));
    GetIt.instance.registerSingleton<AppStore>(appStore);
  });

  tearDownAll(() async => GetIt.instance.reset());

  setUp(() {
    linkCubit = _MockKycLinkWalletCubit();
    kycCubit = _MockKycCubit();
    when(() => kycCubit.state).thenReturn(const KycInitial());
  });

  Widget buildView() => wrapForGolden(
        MultiBlocProvider(
          providers: [
            BlocProvider<KycCubit>.value(value: kycCubit),
            BlocProvider<KycLinkWalletCubit>.value(value: linkCubit),
          ],
          child: const KycLinkWalletView(),
        ),
      );

  group('$KycLinkWalletView', () {
    // KycLinkWalletSubmitting → _LinkWalletBody(isSubmitting: true): the submit
    // AppFilledButton renders its loading spinner (page:139-145). Freeze it.
    goldenTest(
      'submitting — submit button spinner',
      fileName: 'kyc_link_wallet_page_submitting',
      constraints: phoneConstraints,
      pumpBeforeTest: pumpOnce,
      builder: () {
        when(() => linkCubit.state)
            .thenReturn(const KycLinkWalletSubmitting(_userData));
        return buildView();
      },
    );

    // KycLinkWalletSuccess → the transient centered spinner the builder renders
    // while the parent KycCubit re-routes (page:107). Static state, so the
    // listener's checkKyc() never fires; freeze the spinner.
    goldenTest(
      'success — transient centered spinner',
      fileName: 'kyc_link_wallet_page_success',
      constraints: phoneConstraints,
      pumpBeforeTest: pumpOnce,
      builder: () {
        when(() => linkCubit.state).thenReturn(const KycLinkWalletSuccess());
        return buildView();
      },
    );

    // KycLinkWalletFailure → the catch-all builder branch shows the centered
    // spinner (page:108) while the listener fires the red `registrationFailed`
    // SnackBar (page:59-66). Spinner + SnackBar cannot pumpAndSettle, so deliver
    // the emission then advance a fixed 500ms — well past the SnackBar entrance
    // — freezing the spinner at a deterministic frame.
    goldenTest(
      'failure — centered spinner + red snackbar',
      fileName: 'kyc_link_wallet_page_failure',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) async {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
      },
      builder: () {
        whenListen(
          linkCubit,
          Stream<KycLinkWalletState>.value(
            const KycLinkWalletFailure('network error'),
          ),
          initialState: const KycLinkWalletSubmitting(_userData),
        );
        return buildView();
      },
    );

    // userData == null → KycLinkWalletPage short-circuits to the defensive
    // `_LinkWalletMissingUserDataPage` (kycFailure copy + Refresh button,
    // page:180-210). No cubit is created, so drive the page directly with only
    // the parent KycCubit in scope for the Refresh handler.
    goldenTest(
      'missing user data — defensive refresh page',
      fileName: 'kyc_link_wallet_page_missing_user_data',
      constraints: phoneConstraints,
      builder: () => wrapForGolden(
        BlocProvider<KycCubit>.value(
          value: kycCubit,
          child: const KycLinkWalletPage(userData: null),
        ),
      ),
    );
  });
}
