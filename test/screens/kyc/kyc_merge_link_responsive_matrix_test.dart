// Responsive matrix gate for KYC merge / link-wallet screens after migration
// onto ScrollableActionsLayout. Proves CTAs stay fully tappable across the
// full device × text-scale matrix (see test/helper/responsive_matrix.dart).
import 'package:bitbox_flutter/bitbox_flutter.dart' as sdk;
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/hardware_wallet/bitbox.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/kyc/kyc_personal_data.dart';
import 'package:realunit_wallet/packages/service/dfx/models/user/dto/real_unit_user_data_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_registration_service.dart';
import 'package:realunit_wallet/packages/service/wallet_service.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/screens/kyc/cubits/kyc/kyc_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/link_wallet/cubits/kyc_link_wallet_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/link_wallet/kyc_link_wallet_page.dart';
import 'package:realunit_wallet/screens/kyc/subpages/kyc_account_merge_page.dart';
import 'package:realunit_wallet/screens/kyc/subpages/kyc_merge_processing_page.dart';
import 'package:realunit_wallet/styles/themes.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

import '../../helper/helper.dart';

class _MockKycCubit extends MockCubit<KycState> implements KycCubit {}

class _MockKycLinkWalletCubit extends MockCubit<KycLinkWalletState>
    implements KycLinkWalletCubit {}

class _MockAppStore extends Mock implements AppStore {}

class _MockRealUnitRegistrationService extends Mock
    implements RealUnitRegistrationService {}

class _MockBitboxService extends Mock implements BitboxService {}

class _MockWalletService extends Mock implements WalletService {}

class _MockDfxKycService extends Mock implements DfxKycService {}

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

Future<void> _pumpMatrixPage(
  WidgetTester tester, {
  required Widget widget,
  required MatrixCell cell,
}) async {
  await tester.binding.setSurfaceSize(cell.device.size);
  addTearDown(() async => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MediaQuery(
      data: cell.mediaQuery,
      child: MaterialApp(
        theme: realUnitTheme,
        locale: const Locale('de'),
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        home: widget,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  // ---------------------------------------------------------------------------
  // Group A — KycAccountMergePage
  // ---------------------------------------------------------------------------
  group('$KycAccountMergePage responsive matrix (full device × textScale)', () {
    late _MockKycCubit cubit;

    setUp(() {
      cubit = _MockKycCubit();
      when(() => cubit.state).thenReturn(const KycInitial());
      when(() => cubit.checkKyc()).thenAnswer((_) async {});
    });

    for (final cell in kFullResponsiveMatrix) {
      testWidgets('account_merge · ${cell.id}', (tester) async {
        await withTargetPlatform(cell.device.platform, () async {
          await expectNoLayoutOverflow(
            tester,
            () async {
              await _pumpMatrixPage(
                tester,
                widget: BlocProvider<KycCubit>.value(
                  value: cubit,
                  child: const KycAccountMergePage(),
                ),
                cell: cell,
              );
            },
            reason: 'overflow on account_merge / ${cell.label}',
          );

          await expectFullyTappable(
            tester,
            find.byType(AppFilledButton),
            within: find.byType(KycAccountMergePage),
            reason: 'account_merge / ${cell.label}: CTA not tappable',
          );
        });
      });
    }
  });

  // ---------------------------------------------------------------------------
  // Group B — KycMergeProcessingPage
  // ---------------------------------------------------------------------------
  group(
    '$KycMergeProcessingPage responsive matrix (full device × textScale)',
    () {
      late _MockKycCubit cubit;

      setUp(() {
        cubit = _MockKycCubit();
        when(() => cubit.state).thenReturn(const KycInitial());
        when(() => cubit.checkKyc()).thenAnswer((_) async {});
      });

      for (final cell in kFullResponsiveMatrix) {
        testWidgets('merge_processing · ${cell.id}', (tester) async {
          await withTargetPlatform(cell.device.platform, () async {
            await expectNoLayoutOverflow(
              tester,
              () async {
                await _pumpMatrixPage(
                  tester,
                  widget: BlocProvider<KycCubit>.value(
                    value: cubit,
                    child: const KycMergeProcessingPage(),
                  ),
                  cell: cell,
                );
              },
              reason: 'overflow on merge_processing / ${cell.label}',
            );

            await expectFullyTappable(
              tester,
              find.byType(AppFilledButton),
              within: find.byType(KycMergeProcessingPage),
              reason: 'merge_processing / ${cell.label}: CTA not tappable',
            );
          });
        });
      }
    },
  );

  // ---------------------------------------------------------------------------
  // Group C — KycLinkWalletView (_LinkWalletBody via Ready state)
  // ---------------------------------------------------------------------------
  group(
    '$KycLinkWalletView responsive matrix (full device × textScale)',
    () {
      late _MockKycLinkWalletCubit linkCubit;
      late _MockKycCubit kycCubit;

      setUpAll(() {
        registerFallbackValue(_userData);

        final getIt = GetIt.instance;
        final appStore = _MockAppStore();
        when(
          () => appStore.wallet,
        ).thenReturn(DebugWallet(1, 'Test', _debugAddress));
        getIt.registerSingleton<AppStore>(appStore);
        getIt.registerSingleton<RealUnitRegistrationService>(
          _MockRealUnitRegistrationService(),
        );

        final bitboxService = _MockBitboxService();
        when(
          () => bitboxService.getAllUsbDevices(),
        ).thenAnswer((_) async => <sdk.BitboxDevice>[]);
        when(() => bitboxService.startScan()).thenAnswer((_) async => false);
        getIt.registerSingleton<BitboxService>(bitboxService);
        getIt.registerSingleton<WalletService>(_MockWalletService());
        getIt.registerSingleton<DfxKycService>(_MockDfxKycService());
      });

      tearDownAll(() async => await GetIt.instance.reset());

      setUp(() {
        linkCubit = _MockKycLinkWalletCubit();
        kycCubit = _MockKycCubit();
        when(
          () => linkCubit.state,
        ).thenReturn(const KycLinkWalletReady(_userData));
        when(() => kycCubit.state).thenReturn(const KycInitial());
        when(() => kycCubit.checkKyc()).thenAnswer((_) async {});
        when(() => linkCubit.submit(any())).thenAnswer((_) async {});
      });

      Widget buildSubject() => MultiBlocProvider(
        providers: [
          BlocProvider<KycCubit>.value(value: kycCubit),
          BlocProvider<KycLinkWalletCubit>.value(value: linkCubit),
        ],
        child: const KycLinkWalletView(),
      );

      for (final cell in kFullResponsiveMatrix) {
        testWidgets('link_wallet · ${cell.id}', (tester) async {
          await withTargetPlatform(cell.device.platform, () async {
            await expectNoLayoutOverflow(
              tester,
              () async {
                await _pumpMatrixPage(
                  tester,
                  widget: buildSubject(),
                  cell: cell,
                );
              },
              reason: 'overflow on link_wallet / ${cell.label}',
            );

            await expectFullyTappable(
              tester,
              find.byType(AppFilledButton),
              within: find.byType(KycLinkWalletView),
              reason: 'link_wallet / ${cell.label}: CTA not tappable',
            );
          });
        });
      }

      // Focused regression: textScale 1.5 is NOT in kFullResponsiveMatrix and
      // is the exact scale this page was measured to first break at.
      testWidgets(
        'REGRESSION: link_wallet · iphone_se_3@1.5x first-break scale',
        (tester) async {
          final cell = MatrixCell(
            kIosDeviceProfiles.firstWhere((d) => d.id == 'iphone_se_3'),
            1.5,
          );
          await withTargetPlatform(cell.device.platform, () async {
            await expectNoLayoutOverflow(
              tester,
              () async {
                await _pumpMatrixPage(
                  tester,
                  widget: buildSubject(),
                  cell: cell,
                );
              },
              reason: 'overflow on link_wallet / ${cell.label}',
            );

            await expectFullyTappable(
              tester,
              find.byType(AppFilledButton),
              within: find.byType(KycLinkWalletView),
              reason: 'link_wallet / ${cell.label}: CTA not tappable',
            );
          });
        },
      );
    },
  );
}
