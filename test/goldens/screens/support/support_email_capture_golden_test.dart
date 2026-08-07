import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/screens/support/cubits/support_email_capture/support_email_capture_cubit.dart';
import 'package:realunit_wallet/screens/support/subpages/support_email_capture_page.dart';

import '../../../helper/helper.dart';

class _MockSupportEmailCaptureCubit extends MockCubit<SupportEmailCaptureState>
    implements SupportEmailCaptureCubit {}

void main() {
  late _MockSupportEmailCaptureCubit cubit;

  setUp(() {
    cubit = _MockSupportEmailCaptureCubit();
    when(() => cubit.state).thenReturn(const SupportEmailCaptureInitial());
  });

  Widget buildSubject() => BlocProvider<SupportEmailCaptureCubit>.value(
    value: cubit,
    child: const SupportEmailCaptureView(),
  );

  group('$SupportEmailCaptureView', () {
    goldenTest(
      'default state',
      fileName: 'support_email_capture_page_default',
      constraints: phoneConstraints,
      builder: () => wrapForGolden(buildSubject()),
    );

    goldenTest(
      'submitting state shows the loading button',
      fileName: 'support_email_capture_page_submitting',
      constraints: phoneConstraints,
      pumpBeforeTest: pumpOnce,
      builder: () {
        when(() => cubit.state).thenReturn(const SupportEmailCaptureLoading());
        return wrapForGolden(buildSubject());
      },
    );

    // Buy-flow entry point: the caller passes the buy-confirm gate copy as the
    // `description`, replacing the default Support wording. Same form, different
    // explanatory text. The string is resolved via the localization delegate so
    // the golden stays in sync with the production copy.
    goldenTest(
      'buy-flow entry — alternate description copy',
      fileName: 'support_email_capture_page_buy_flow',
      constraints: phoneConstraints,
      builder: () => wrapForGolden(
        Builder(
          builder: (context) => BlocProvider<SupportEmailCaptureCubit>.value(
            value: cubit,
            child: SupportEmailCaptureView(
              description:
                  S.of(context).buyPrimaryEmailRequiredCaptureDescription,
            ),
          ),
        ),
      ),
    );
  });
}
