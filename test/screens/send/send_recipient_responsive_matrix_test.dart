import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/screens/send/cubits/send_recipient/send_recipient_cubit.dart';
import 'package:realunit_wallet/screens/send/send_recipient_page.dart';
import 'package:realunit_wallet/styles/themes.dart';

import '../../helper/helper.dart';

class _MockSendRecipientCubit extends MockCubit<SendRecipientState> implements SendRecipientCubit {}

Future<void> _pumpScreen(
  WidgetTester tester,
  MatrixCell cell,
  Widget child,
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
        home: child,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUpAll(stubMobileScannerChannel);

  group('SendRecipientView responsive matrix (full device × textScale)', () {
    for (final cell in kFullResponsiveMatrix) {
      testWidgets(cell.id, (tester) async {
        await withTargetPlatform(cell.device.platform, () async {
          final recipientCubit = _MockSendRecipientCubit();
          when(() => recipientCubit.state).thenReturn(const SendRecipientEmpty());
          whenListen(
            recipientCubit,
            const Stream<SendRecipientState>.empty(),
            initialState: const SendRecipientEmpty(),
          );
          when(() => recipientCubit.submit(any())).thenReturn(null);
          when(() => recipientCubit.onCodeDetected(any())).thenReturn(null);

          final subject = BlocProvider<SendRecipientCubit>.value(
            value: recipientCubit,
            child: const SendRecipientView(),
          );

          await expectNoLayoutOverflow(
            tester,
            () => _pumpScreen(tester, cell, subject),
            reason: 'SendRecipientView overflow / ${cell.label}',
          );

          await expectFullyTappable(
            tester,
            find.widgetWithText(FilledButton, S.current.next),
            within: find.byType(SendRecipientView),
            reason: 'SendRecipientView / ${cell.label}: Next CTA not tappable',
          );
        });
      });
    }
  });
}
