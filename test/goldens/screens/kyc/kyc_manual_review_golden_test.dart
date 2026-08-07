import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/screens/kyc/cubits/kyc/kyc_cubit.dart';
import 'package:realunit_wallet/screens/kyc/subpages/kyc_manual_review_page.dart';

import '../../../helper/helper.dart';

class _MockKycCubit extends MockCubit<KycState> implements KycCubit {}

void main() {

  late _MockKycCubit kycCubit;

  setUp(() {
    kycCubit = _MockKycCubit();
    when(() => kycCubit.state).thenReturn(const KycInitial());
  });

  group('$KycManualReviewPage', () {
    goldenTest(
      'default state',
      fileName: 'kyc_manual_review_page_default',
      constraints: phoneConstraints,
      builder: () => wrapForGolden(
        BlocProvider<KycCubit>.value(
          value: kycCubit,
          child: const KycManualReviewPage(),
        ),
      ),
    );
  });
}
