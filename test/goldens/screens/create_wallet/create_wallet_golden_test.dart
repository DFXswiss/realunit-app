import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/screens/create_wallet/bloc/create_wallet_cubit.dart';
import 'package:realunit_wallet/screens/create_wallet/create_wallet_view.dart';

import '../../../helper/helper.dart';

class _MockCreateWalletCubit extends MockCubit<CreateWalletState> implements CreateWalletCubit {}

void main() {
  late _MockCreateWalletCubit cubit;
  late MockSoftwareWallet wallet;

  setUpAll(() {
    stubNoScreenshotChannel();
  });

  setUp(() {
    cubit = _MockCreateWalletCubit();
    wallet = MockSoftwareWallet();
    when(() => wallet.seed).thenReturn(
      'cheese trigger cannon mention judge hire snack sustain annual predict illness celery',
    );
    when(() => cubit.state).thenReturn(CreateWalletState(wallet: wallet));
  });

  Widget buildSubject() => BlocProvider<CreateWalletCubit>.value(
    value: cubit,
    child: const CreateWalletView(),
  );

  group('$CreateWalletView', () {
    goldenTest(
      'seed generated and blurred',
      fileName: 'create_wallet_page_default',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () => wrapForGolden(buildSubject()),
    );

    goldenTest(
      'seed generated and revealed',
      fileName: 'create_wallet_page_revealed',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () {
        when(() => cubit.state).thenReturn(CreateWalletState(wallet: wallet, hideSeed: false));
        return wrapForGolden(buildSubject());
      },
    );

    goldenTest(
      'loading state before the wallet is generated shows a centered spinner',
      fileName: 'create_wallet_page_loading',
      // wallet == null renders a CupertinoActivityIndicator that never settles;
      // pump once to capture the initial frame instead of hanging pumpAndSettle.
      pumpBeforeTest: pumpOnce,
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () {
        when(() => cubit.state).thenReturn(const CreateWalletState());
        return wrapForGolden(buildSubject());
      },
    );
  });
}
