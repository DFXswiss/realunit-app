import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/models/balance.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/repository/balance_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/payment/transfer_exceptions.dart';
import 'package:realunit_wallet/packages/utils/default_assets.dart';
import 'package:realunit_wallet/screens/send/cubits/send_recipient/send_recipient_cubit.dart';
import 'package:realunit_wallet/screens/send/send_amount_page.dart';
import 'package:realunit_wallet/screens/send/send_recipient_page.dart';

import '../../helper/helper.dart';

class _MockSendRecipientCubit extends MockCubit<SendRecipientState> implements SendRecipientCubit {}

class _MockBalanceRepository extends Mock implements BalanceRepository {}

class _MockAppStore extends Mock implements AppStore {}

class _MockApiConfig extends Mock implements ApiConfig {}

void main() {
  late _MockSendRecipientCubit recipientCubit;

  Balance balanceOf(BigInt value) => Balance(
    chainId: realUnitAsset.chainId,
    contractAddress: realUnitAsset.address,
    walletAddress: '0xwallet',
    balance: value,
    asset: realUnitAsset,
  );

  setUpAll(() {
    registerFallbackValue(
      Balance(
        chainId: 1,
        contractAddress: '0x',
        walletAddress: '0x',
        balance: BigInt.zero,
        asset: realUnitAsset,
      ),
    );
    stubMobileScannerChannel();

    // A valid recipient pushes SendAmountPage, which builds a SellBalanceCubit
    // off getIt; register a balance repository + app store so the pushed route
    // resolves and renders.
    final getIt = GetIt.instance;
    final balanceRepo = _MockBalanceRepository();
    when(() => balanceRepo.watchBalance(any())).thenAnswer(
      (_) => Stream<Balance>.value(balanceOf(BigInt.from(100))),
    );
    getIt.registerFactory<BalanceRepository>(() => balanceRepo);
    final appStore = _MockAppStore();
    final apiConfig = _MockApiConfig();
    when(() => apiConfig.asset).thenReturn(realUnitAsset);
    when(() => appStore.apiConfig).thenReturn(apiConfig);
    when(() => appStore.primaryAddress).thenReturn('0xwallet');
    getIt.registerSingleton<AppStore>(appStore);
  });

  tearDownAll(() async => GetIt.instance.reset());

  setUp(() {
    recipientCubit = _MockSendRecipientCubit();
    when(() => recipientCubit.state).thenReturn(const SendRecipientEmpty());
    when(() => recipientCubit.reset()).thenReturn(null);
    when(() => recipientCubit.submit(any())).thenReturn(null);
    when(() => recipientCubit.onCodeDetected(any())).thenReturn(null);
  });

  Widget buildSubject() => BlocProvider<SendRecipientCubit>.value(
    value: recipientCubit,
    child: const SendRecipientView(),
  );

  group('$SendRecipientPage', () {
    testWidgets('builds its own cubit and renders $SendRecipientView', (tester) async {
      await tester.pumpApp(const SendRecipientPage());

      expect(find.byType(SendRecipientView), findsOne);
    });
  });

  group('$SendRecipientView', () {
    testWidgets('renders the title, scanner preview and the manual field', (tester) async {
      await tester.pumpApp(buildSubject());

      expect(find.text(S.current.sendRecipientTitle), findsOne);
      expect(find.byType(MobileScanner), findsOne);
      expect(find.text(S.current.sendRecipientManualHint), findsOne);
    });

    testWidgets('onDetect forwards a scanned raw value to the cubit', (tester) async {
      await tester.pumpApp(buildSubject());

      final scanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
      scanner.onDetect!(const BarcodeCapture());
      scanner.onDetect!(const BarcodeCapture(barcodes: [Barcode(rawValue: '0xabc')]));

      verify(() => recipientCubit.onCodeDetected('0xabc')).called(1);
    });

    testWidgets('the continue button submits the typed address', (tester) async {
      await tester.pumpApp(buildSubject());

      await tester.enterText(find.byType(TextField), '0xRecipient');
      await tester.tap(find.text(S.current.next));
      await tester.pump();

      verify(() => recipientCubit.submit('0xRecipient')).called(1);
    });

    testWidgets('the paste button fills the field from the clipboard', (tester) async {
      // Stub the clipboard platform channel so getData returns a known address.
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.getData') {
            return <String, dynamic>{'text': '  0xPasted  '};
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await tester.pumpApp(buildSubject());

      await tester.tap(find.byIcon(Icons.paste_rounded));
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '0xPasted');
    });

    testWidgets('an invalid recipient shows a snackbar', (tester) async {
      whenListen(
        recipientCubit,
        Stream<SendRecipientState>.fromIterable([
          const SendRecipientInvalid(InvalidRecipientAddressException('bad')),
        ]),
        initialState: const SendRecipientEmpty(),
      );

      await tester.pumpApp(buildSubject());
      await tester.pump();

      expect(find.byType(SnackBar), findsOne);
      expect(find.text(S.current.sendRecipientInvalid), findsOne);
    });

    testWidgets('a valid recipient navigates to the amount step and resets', (tester) async {
      whenListen(
        recipientCubit,
        Stream<SendRecipientState>.fromIterable([
          const SendRecipientValid('0x9F5713dEAcb8e9CaB6c2D3FaE1aFc2715F8D2D71'),
        ]),
        initialState: const SendRecipientEmpty(),
      );

      await tester.pumpApp(buildSubject());
      await tester.pumpAndSettle();

      expect(find.byType(SendAmountView), findsOne);
      verify(() => recipientCubit.reset()).called(1);
    });
  });
}
