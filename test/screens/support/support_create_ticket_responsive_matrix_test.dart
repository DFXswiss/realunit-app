// Responsive matrix gate for SupportCreateTicketView CTA.
//
// Proves the "Senden" button stays fully tappable across the full device ×
// text-scale matrix when a long German message expands the multiline field.
// Regression lock for the iPhone SE + textScale 2.0 bug where the CTA was
// scrolled below the fold inside the legacy Spacer layout.
//
// A second group covers the filled-attachment row (48 px thumbnail + long
// ellipsized file name + 48×48 close target) under the same matrix pressure.
// Close is scrolled into view first: the field lives in the scrollable body,
// while the sticky CTA sits outside it.
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue_reason.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue_type.dart';
import 'package:realunit_wallet/screens/support/cubits/support_create_ticket/support_create_ticket_cubit.dart';
import 'package:realunit_wallet/screens/support/cubits/support_create_ticket/support_create_ticket_state.dart';
import 'package:realunit_wallet/screens/support/subpages/support_create_ticket_page.dart';
import 'package:realunit_wallet/styles/themes.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

import '../../helper/helper.dart';

class _MockSupportCreateTicketCubit extends MockCubit<SupportCreateTicketState>
    implements SupportCreateTicketCubit {}

/// Realistic long German support message that expands the multiline TextField
/// (maxLines: 5) the way a real user report would.
const _longGermanMessage =
    'Guten Tag, ich habe ein Problem mit meiner letzten Transaktion vom 12. März. '
    'Der Betrag wurde von meinem Bankkonto abgebucht, erscheint aber nicht in der '
    'Wallet und der Status bleibt seit mehreren Tagen auf „in Bearbeitung“. '
    'Können Sie bitte prüfen, was mit der Zahlung passiert ist und mir den '
    'aktuellen Stand mitteilen? Vielen Dank im Voraus.';

/// Long file name so Expanded + ellipsis is under real pressure at large scales.
const _longAttachmentName =
    'screenshot_fehler_transaktion_maerz_2026_bankkonto_abgebucht_wallet_status_in_bearbeitung.png';

const _submittableState = SupportCreateTicketState(
  selectedType: SupportIssueType.genericIssue,
  selectedReason: SupportIssueReason.other,
  message: 'Ich habe ein Problem mit meiner Transaktion.',
);

Future<void> _pumpScreen(
  WidgetTester tester,
  Widget widget,
  MediaQueryData mediaQuery,
) async {
  await tester.binding.setSurfaceSize(mediaQuery.size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MediaQuery(
      data: mediaQuery,
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
  late _MockSupportCreateTicketCubit cubit;
  late Directory tempDir;
  late File imageFile;
  late SupportCreateTicketState stateWithAttachment;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('support_create_ticket_matrix_');
    imageFile = File('${tempDir.path}${Platform.pathSeparator}$_longAttachmentName');
    final bytes =
        await File('assets/icons/realunit_wallet_logo_full.png').readAsBytes();
    await imageFile.writeAsBytes(bytes);
    stateWithAttachment = SupportCreateTicketState(
      selectedType: SupportIssueType.genericIssue,
      selectedReason: SupportIssueReason.other,
      message: 'Ich habe ein Problem mit meiner Transaktion.',
      attachment: XFile(imageFile.path),
    );
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() {
    cubit = _MockSupportCreateTicketCubit();
    when(() => cubit.state).thenReturn(_submittableState);
    whenListen(
      cubit,
      const Stream<SupportCreateTicketState>.empty(),
      initialState: _submittableState,
    );
    when(() => cubit.submit()).thenAnswer((_) async {});
    when(() => cubit.updateMessage(any())).thenReturn(null);
    when(() => cubit.clearAttachment()).thenReturn(null);
  });

  Widget buildSubject() => BlocProvider<SupportCreateTicketCubit>.value(
        value: cubit,
        child: const SupportCreateTicketView(),
      );

  group('SupportCreateTicketView responsive matrix (full device × textScale)', () {
    for (final cell in kFullResponsiveMatrix) {
      testWidgets(cell.id, (tester) async {
        await withTargetPlatform(cell.device.platform, () async {
          await expectNoLayoutOverflow(
            tester,
            () async {
              await _pumpScreen(tester, buildSubject(), cell.mediaQuery);
              await tester.enterText(find.byType(TextField), _longGermanMessage);
              await tester.pump();
            },
            reason: 'overflow on ${cell.label}',
          );

          await expectFullyTappable(
            tester,
            find.byType(AppFilledButton),
            within: find.byType(SupportCreateTicketView),
            reason: '${cell.label}: CTA not tappable',
          );
        });
      });
    }
  });

  group(
    'SupportCreateTicketView responsive matrix with filled attachment '
    '(CTA + close target tappable after being scrolled into view, no overflow)',
    () {
      for (final cell in kFullResponsiveMatrix) {
        testWidgets(cell.id, (tester) async {
          when(() => cubit.state).thenReturn(stateWithAttachment);
          whenListen(
            cubit,
            const Stream<SupportCreateTicketState>.empty(),
            initialState: stateWithAttachment,
          );

          await withTargetPlatform(cell.device.platform, () async {
            await expectNoLayoutOverflow(
              tester,
              () async {
                await _pumpScreen(tester, buildSubject(), cell.mediaQuery);
                await tester.enterText(find.byType(TextField), _longGermanMessage);
                await tester.pump();
              },
              reason: 'overflow with attachment on ${cell.label}',
            );

            await expectFullyTappable(
              tester,
              find.byType(AppFilledButton),
              within: find.byType(SupportCreateTicketView),
              reason: '${cell.label}: CTA not tappable with attachment',
            );

            // Attachment is in the scrollable body (sticky CTA is outside it);
            // at large text scales the close control may start off-screen.
            final closeTarget = find.byIcon(Icons.close_rounded);
            await tester.ensureVisible(closeTarget);
            await tester.pumpAndSettle();

            await expectFullyTappable(
              tester,
              closeTarget,
              within: find.byType(SupportCreateTicketView),
              reason: '${cell.label}: close target not tappable',
            );
          });
        });
      }
    },
  );

  // Focused regression: iPhone SE 375×667 DE + textScale 2.0 — proven fail
  // pre-fix when a long message expands the multiline field.
  testWidgets(
    'REGRESSION: iPhone SE DE textScale 2.0 long message — CTA tappable and tap submits',
    (tester) async {
      final cell = MatrixCell(
        kIosDeviceProfiles.firstWhere((d) => d.id == 'iphone_se_3'),
        2.0,
      );
      await withTargetPlatform(cell.device.platform, () async {
        await _pumpScreen(tester, buildSubject(), cell.mediaQuery);
        await tester.enterText(find.byType(TextField), _longGermanMessage);
        await tester.pump();

        await expectFullyTappable(
          tester,
          find.byType(AppFilledButton),
          within: find.byType(SupportCreateTicketView),
        );
        verify(() => cubit.submit()).called(1);
      });
    },
  );

  // Keyboard: Scaffold.resizeToAvoidBottomInset (default true) shrinks the
  // body; ScrollableActionsLayout receives the reduced bounded height. Prove
  // the CTA stays fully tappable with a simulated open keyboard.
  testWidgets(
    'KEYBOARD: iPhone SE textScale 1.3 — CTA tappable with viewInsets keyboard',
    (tester) async {
      final cell = MatrixCell(
        kIosDeviceProfiles.firstWhere((d) => d.id == 'iphone_se_3'),
        1.3,
      );
      final keyboardMediaQuery = cell.mediaQuery.copyWith(
        viewInsets: const EdgeInsets.only(bottom: 336),
      );

      await withTargetPlatform(cell.device.platform, () async {
        await expectNoLayoutOverflow(
          tester,
          () async {
            await _pumpScreen(tester, buildSubject(), cell.mediaQuery);
            await tester.enterText(find.byType(TextField), _longGermanMessage);
            await tester.pump();
            // Re-pump same tree with keyboard open (viewInsets).
            await _pumpScreen(tester, buildSubject(), keyboardMediaQuery);
            await tester.enterText(find.byType(TextField), _longGermanMessage);
            await tester.pump();
          },
          reason: 'overflow with keyboard on ${cell.label}',
        );

        await expectFullyTappable(
          tester,
          find.byType(AppFilledButton),
          within: find.byType(SupportCreateTicketView),
          reason: '${cell.label} + keyboard: CTA not tappable',
        );
      });
    },
  );
}
