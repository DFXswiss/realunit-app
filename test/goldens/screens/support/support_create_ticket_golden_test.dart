import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue_reason.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue_type.dart';
import 'package:realunit_wallet/screens/support/cubits/support_create_ticket/support_create_ticket_cubit.dart';
import 'package:realunit_wallet/screens/support/cubits/support_create_ticket/support_create_ticket_state.dart';
import 'package:realunit_wallet/screens/support/subpages/support_create_ticket_page.dart';
import 'package:realunit_wallet/styles/themes.dart';
import 'package:realunit_wallet/widgets/form/file_preview_field.dart';

import '../../../helper/helper.dart';

class _MockSupportCreateTicketCubit extends MockCubit<SupportCreateTicketState>
    implements SupportCreateTicketCubit {}

/// Stable name shown in the filled-attachment golden (no random/timestamp).
const _attachedFileName = 'beleg.png';

/// Message for the filled golden — state and enterText must share one value so
/// the snapshot does not show different text than the state this golden claims.
const _filledMessage = 'Ich habe eine Frage zu meinem Konto.';

void main() {
  late _MockSupportCreateTicketCubit cubit;
  late Directory tempDir;
  late File imageFile;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('support_create_ticket_golden_');
    imageFile = File('${tempDir.path}${Platform.pathSeparator}$_attachedFileName');
    final bytes =
        await File('assets/icons/realunit_wallet_logo_full.png').readAsBytes();
    await imageFile.writeAsBytes(bytes);
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() {
    cubit = _MockSupportCreateTicketCubit();
    when(() => cubit.state).thenReturn(const SupportCreateTicketState());
  });

  Widget buildSubject() => BlocProvider<SupportCreateTicketCubit>.value(
        value: cubit,
        child: const SupportCreateTicketView(),
      );

  // The success SnackBar is hosted by the app-level ScaffoldMessenger and the
  // listener pops the form right after showing it (page:40-48), so faithfully
  // it renders over the screen we return to — the Support landing
  // (router tree: /support → create). We rebuild that stack with a real
  // GoRouter because the page uses go_router's `context.pop`, which needs an
  // InheritedGoRouter; a plain MaterialApp would throw. After the pop the green
  // SnackBar shows over a Support-titled host, exactly as in production.
  Widget buildSuccessSubject() {
    final router = GoRouter(
      initialLocation: '/support/create',
      routes: [
        GoRoute(
          path: '/support',
          builder: (context, _) => Scaffold(
            appBar: AppBar(title: Text(S.of(context).contactSupport)),
          ),
          routes: [
            GoRoute(
              path: 'create',
              builder: (context, _) =>
                  BlocProvider<SupportCreateTicketCubit>.value(
                value: cubit,
                child: const SupportCreateTicketView(),
              ),
            ),
          ],
        ),
      ],
    );
    return MaterialApp.router(
      theme: realUnitTheme,
      locale: const Locale('de'),
      localizationsDelegates: [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: S.delegate.supportedLocales,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }

  group('$SupportCreateTicketView', () {
    goldenTest(
      'default empty form',
      fileName: 'support_create_ticket_page_default',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () => wrapForGolden(buildSubject()),
    );

    // `selectType` sets `selectedReason` to `other` alongside `selectedType`,
    // and a non-empty `message` flips `canSubmit` to true, so the Send button
    // renders enabled. The message TextField is uncontrolled (onChanged only),
    // so it does not render `state.message` — pumpBeforeTest types the same
    // text into the field. State still drives canSubmit / the enabled button.
    goldenTest(
      'filled form — type tag selected, send button enabled',
      fileName: 'support_create_ticket_page_filled',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) async {
        await tester.enterText(find.byType(TextField), _filledMessage);
        FocusManager.instance.primaryFocus?.unfocus();
        // InputDecorator animates focusedBorder → enabledBorder
        // (_kTransitionDuration = 167 ms). A single pump() advances one frame
        // with no elapsed time, so the border freezes blue. unfocus keeps
        // cursor and focus ring out of the capture; pumpAndSettle drains the
        // border animation before snapshot.
        await tester.pumpAndSettle();
        expect(
          find.text(_filledMessage),
          findsOneWidget,
          reason: 'Message TextField should show the typed filled-message text',
        );
        // Field focus only — not the border animation. primaryFocus stays non-null
        // (FocusScope), so check the EditableText node.
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .focusNode
              .hasFocus,
          isFalse,
          reason: 'Message field must not hold focus (cursor / focusedBorder)',
        );
      },
      builder: () {
        when(() => cubit.state).thenReturn(
          const SupportCreateTicketState(
            selectedType: SupportIssueType.genericIssue,
            selectedReason: SupportIssueReason.other,
            message: _filledMessage,
          ),
        );
        return wrapForGolden(buildSubject());
      },
    );

    // Filled form plus attachment — covers FilePreviewField with a selected
    // file (cacheWidth / thumbnail path). Image.file decodes on the real async
    // timeline; the default precacheImages ends in pumpAndSettle, which does
    // not return here. Poll until RawImage.image is set (decode done), fail
    // loudly if the budget elapses — never snapshot a blank thumbnail.
    goldenTest(
      'filled form with attachment selected',
      fileName: 'support_create_ticket_page_attached',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) async {
        final rawImage = find.descendant(
          of: find.byType(FilePreviewField),
          matching: find.byType(RawImage),
        );
        // Bounded: 60 × 50 ms ≈ 3 s. Breaks early when decode completes.
        const maxAttempts = 60;
        for (var i = 0; i < maxAttempts; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump();
          if (rawImage.evaluate().isNotEmpty &&
              tester.widget<RawImage>(rawImage).image != null) {
            break;
          }
        }
        expect(
          rawImage,
          findsOneWidget,
          reason: 'FilePreviewField should host a RawImage for the attachment',
        );
        expect(
          tester.widget<RawImage>(rawImage).image,
          isNotNull,
          reason:
              'Attachment thumbnail did not decode within ${maxAttempts * 50} ms',
        );
      },
      builder: () {
        when(() => cubit.state).thenReturn(
          SupportCreateTicketState(
            selectedType: SupportIssueType.genericIssue,
            selectedReason: SupportIssueReason.other,
            message: 'Ich habe eine Frage zu meinem Konto.',
            attachment: XFile(imageFile.path),
          ),
        );
        return wrapForGolden(buildSubject());
      },
    );

    goldenTest(
      'submitting — send button shows the loading spinner',
      fileName: 'support_create_ticket_page_submitting',
      // The loading button hosts a CupertinoActivityIndicator; freeze it on the
      // first frame instead of letting pumpAndSettle hang.
      pumpBeforeTest: pumpOnce,
      constraints: phoneConstraints,
      builder: () {
        when(() => cubit.state).thenReturn(
          const SupportCreateTicketState(
            selectedType: SupportIssueType.genericIssue,
            selectedReason: SupportIssueReason.other,
            message: 'Ich habe eine Frage zu meinem Konto.',
            isSubmitting: true,
          ),
        );
        return wrapForGolden(buildSubject());
      },
    );

    // A state with `error != null` drives the BlocConsumer.listener (page:49-56)
    // to show the red failure SnackBar. The listener renders the raw
    // `e.toString()` the cubit stores (cubit:44), so we feed a real
    // `ApiException` string rather than invented copy. Emitting the error via
    // `whenListen` (the initial state has none) fires the listener; pumpAndSettle
    // runs the entrance animation (the 4s auto-dismiss is a Timer, not a frame,
    // so the SnackBar stays visible).
    goldenTest(
      'submit failure SnackBar (red)',
      fileName: 'support_create_ticket_page_error_snackbar',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) async {
        await tester.pump(); // deliver the whenListen emission to the listener
        await tester.pumpAndSettle(); // run the SnackBar entrance to completion
      },
      builder: () {
        whenListen(
          cubit,
          Stream.fromIterable([
            SupportCreateTicketState(
              selectedType: SupportIssueType.genericIssue,
              selectedReason: SupportIssueReason.other,
              message: 'Ich habe eine Frage zu meinem Konto.',
              error: const ApiException(
                statusCode: 500,
                code: 'UNKNOWN',
                message: 'Internal server error',
              ).toString(),
            ),
          ]),
          initialState: const SupportCreateTicketState(
            selectedType: SupportIssueType.genericIssue,
            selectedReason: SupportIssueReason.other,
            message: 'Ich habe eine Frage zu meinem Konto.',
          ),
        );
        return wrapForGolden(buildSubject());
      },
    );

    // On `isSuccess` the listener shows the green confirmation SnackBar and pops
    // the form (page:40-48). Rendering it over the create-ticket form would be a
    // fiction — that page is already gone — so `buildSuccessSubject` reproduces
    // the real pop to the Support host, where the app-level SnackBar persists.
    goldenTest(
      'success SnackBar (green) — over the Support host after the form pops',
      fileName: 'support_create_ticket_page_success_snackbar',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) async {
        await tester.pump(); // deliver the isSuccess emission to the listener
        await tester.pumpAndSettle(); // pop to the host + run the SnackBar entrance
      },
      builder: () {
        whenListen(
          cubit,
          Stream.fromIterable(const [
            SupportCreateTicketState(
              selectedType: SupportIssueType.genericIssue,
              selectedReason: SupportIssueReason.other,
              message: 'Ich habe eine Frage zu meinem Konto.',
              isSuccess: true,
            ),
          ]),
          initialState: const SupportCreateTicketState(
            selectedType: SupportIssueType.genericIssue,
            selectedReason: SupportIssueReason.other,
            message: 'Ich habe eine Frage zu meinem Konto.',
          ),
        );
        return buildSuccessSubject();
      },
    );
  });
}
