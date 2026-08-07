import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/screens/kyc/cubits/kyc/kyc_cubit.dart';
import 'package:realunit_wallet/screens/kyc/subpages/kyc_manual_review_page.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

import '../../../helper/helper.dart';

class _MockKycCubit extends MockCubit<KycState> implements KycCubit {}

Widget _host(KycCubit cubit) => BlocProvider<KycCubit>.value(
      value: cubit,
      child: const KycManualReviewPage(),
    );

void main() {
  late _MockKycCubit cubit;

  setUp(() {
    cubit = _MockKycCubit();
    when(() => cubit.state).thenReturn(const KycInitial());
    when(() => cubit.checkKyc()).thenAnswer((_) async {});
  });

  group('$KycManualReviewPage', () {
    testWidgets('renders an AppBar + headline + body + refresh button',
        (tester) async {
      await tester.pumpApp(_host(cubit));

      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(AppFilledButton), findsOneWidget);
      // Headline + description + button label = 4 Texts (AppBar title + 2
      // copy lines + button label).
      expect(find.byType(Text), findsNWidgets(4));
    });

    testWidgets('tapping refresh fires KycCubit.checkKyc', (tester) async {
      await tester.pumpApp(_host(cubit));

      await tester.tap(find.byType(AppFilledButton));
      await tester.pump();

      verify(() => cubit.checkKyc()).called(1);
    });
  });
}
