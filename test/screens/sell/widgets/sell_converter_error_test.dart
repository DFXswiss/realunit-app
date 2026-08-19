import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/models/balance.dart';
import 'package:realunit_wallet/packages/repository/supported_fiat_repository.dart';
import 'package:realunit_wallet/packages/utils/default_assets.dart';
import 'package:realunit_wallet/screens/sell/cubits/sell_balance/sell_balance_cubit.dart';
import 'package:realunit_wallet/screens/sell/cubits/sell_converter/sell_converter_cubit.dart';
import 'package:realunit_wallet/screens/sell/widgets/sell_converter.dart';
import 'package:realunit_wallet/styles/currency.dart';

import '../../../helper/helper.dart';

class _MockSellConverterCubit extends MockCubit<SellConverterState>
    implements SellConverterCubit {}

class _MockSellBalanceCubit extends MockCubit<Balance>
    implements SellBalanceCubit {}

class _MockSupportedFiatRepository extends Mock implements SupportedFiatRepository {}

Balance _emptyBalance() => Balance(
      chainId: realUnitAsset.chainId,
      contractAddress: realUnitAsset.address,
      walletAddress: '0x0000000000000000000000000000000000000000',
      balance: BigInt.zero,
      asset: realUnitAsset,
    );

void main() {
  late _MockSupportedFiatRepository fiatRepo;
  late _MockSellConverterCubit converterCubit;
  late _MockSellBalanceCubit balanceCubit;

  setUp(() {
    fiatRepo = _MockSupportedFiatRepository();
    converterCubit = _MockSellConverterCubit();
    balanceCubit = _MockSellBalanceCubit();
    when(() => converterCubit.state).thenReturn(const SellConverterState());
    when(() => balanceCubit.state).thenReturn(_emptyBalance());

    final getIt = GetIt.instance;
    if (getIt.isRegistered<SupportedFiatRepository>()) {
      getIt.unregister<SupportedFiatRepository>();
    }
    getIt.registerSingleton<SupportedFiatRepository>(fiatRepo);
  });

  setUpAll(() => registerFallbackValue(Currency.chf));

  tearDown(() async => GetIt.instance.reset());

  Widget host() => MultiBlocProvider(
        providers: [
          BlocProvider<SellConverterCubit>.value(value: converterCubit),
          BlocProvider<SellBalanceCubit>.value(value: balanceCubit),
        ],
        child: Scaffold(
          body: SellConverter(
            amountController: TextEditingController(),
            resultController: TextEditingController(),
          ),
        ),
      );

  testWidgets(
    'when getSellable fails the picker is disabled and a SnackBar is shown',
    (tester) async {
      when(() => fiatRepo.getSellable())
          .thenAnswer((_) async => Future.error(Exception('API down')));

      await tester.pumpApp(host());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sell-currency-picker-disabled')), findsOneWidget);
      expect(find.byKey(const Key('sell-currency-picker')), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
    },
  );

  testWidgets(
    'on success the picker is enabled (no SnackBar, no disabled key)',
    (tester) async {
      when(() => fiatRepo.getSellable())
          .thenAnswer((_) async => const [Currency.chf]);

      await tester.pumpApp(host());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sell-currency-picker')), findsOneWidget);
      expect(find.byKey(const Key('sell-currency-picker-disabled')), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    'typing 1.000 in the you-receive field is shown as 1000',
    (tester) async {
      when(() => fiatRepo.getSellable()).thenAnswer((_) async => const [Currency.chf]);
      when(() => converterCubit.onFiatChanged(any())).thenAnswer((_) async {});

      final sharesController = TextEditingController();
      final fiatController = TextEditingController();
      addTearDown(sharesController.dispose);
      addTearDown(fiatController.dispose);

      await tester.pumpApp(
        MultiBlocProvider(
          providers: [
            BlocProvider<SellConverterCubit>.value(value: converterCubit),
            BlocProvider<SellBalanceCubit>.value(value: balanceCubit),
          ],
          child: Scaffold(
            body: SellConverter(
              amountController: sharesController,
              resultController: fiatController,
            ),
          ),
        ),
      );
      await tester.pump();

      final fiatField = find.byWidgetPredicate(
        (widget) => widget is TextField && widget.controller == fiatController,
      );

      for (final value in ['1', '1.', '1.0', '1.00']) {
        await tester.enterText(fiatField, value);
        await tester.pump();
        expect(
          fiatController.text,
          value,
          reason: 'Intermediate "$value" must stay as typed in the sell fiat field.',
        );
      }

      await tester.enterText(fiatField, '1.000');
      await tester.pump();

      expect(fiatController.text, '1000');
      expect(fiatController.selection, const TextSelection.collapsed(offset: 4));
      expect(sharesController.text, isEmpty);

      await tester.enterText(fiatField, '1000.000');
      await tester.pump();

      expect(fiatController.text, '1000000');
      expect(fiatController.selection, const TextSelection.collapsed(offset: 7));
    },
  );
}
