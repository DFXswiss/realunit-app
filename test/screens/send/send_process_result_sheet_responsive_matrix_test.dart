import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/screens/send/cubits/send_process/send_process_cubit.dart';
import 'package:realunit_wallet/screens/send/send_process_page.dart';
import 'package:realunit_wallet/styles/themes.dart';

import '../../helper/helper.dart';

class _MockSendProcessCubit extends MockCubit<SendProcessState> implements SendProcessCubit {}

Future<void> _pumpResultSheet(
  WidgetTester tester,
  MatrixCell cell,
  SendProcessCubit cubit,
) async {
  await tester.binding.setSurfaceSize(cell.mediaQuery.size);
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
        home: BlocProvider<SendProcessCubit>.value(
          value: cubit,
          child: const SendProcessView(),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('SendProcess result sheet responsive matrix (full device × textScale)', () {
    for (final cell in kFullResponsiveMatrix) {
      testWidgets(cell.id, (tester) async {
        await withTargetPlatform(cell.device.platform, () async {
          final processCubit = _MockSendProcessCubit();
          when(() => processCubit.retryConfirm()).thenAnswer((_) async {});
          whenListen(
            processCubit,
            Stream<SendProcessState>.value(
              const SendProcessFailure(
                SendProcessFailureReason.generic,
                message: 'socket hung up',
                canRetry: true,
              ),
            ),
            initialState: const SendProcessSigning(),
          );

          await expectNoLayoutOverflow(
            tester,
            () => _pumpResultSheet(tester, cell, processCubit),
            reason: 'SendProcess result sheet overflow / ${cell.label}',
          );

          await expectFullyTappable(
            tester,
            find.widgetWithText(FilledButton, S.current.retry),
            within: find.byType(SendProcessView),
            reason: 'SendProcess result sheet / ${cell.label}: Retry CTA not tappable',
          );
        });
      });
    }
  });
}
