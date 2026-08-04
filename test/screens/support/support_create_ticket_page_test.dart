import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_support_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue_reason.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue_type.dart';
import 'package:realunit_wallet/screens/support/cubits/support_create_ticket/support_create_ticket_cubit.dart';
import 'package:realunit_wallet/screens/support/cubits/support_create_ticket/support_create_ticket_state.dart';
import 'package:realunit_wallet/screens/support/subpages/support_create_ticket_page.dart';
import 'package:realunit_wallet/screens/support/widgets/support_attachment_field.dart';
import 'package:realunit_wallet/widgets/tag_selection.dart';

import '../../helper/pump_app.dart';

class MockSupportCreateTicketCubit extends MockCubit<SupportCreateTicketState>
    implements SupportCreateTicketCubit {}

class MockDfxSupportService extends Mock implements DfxSupportService {}

void main() {
  late SupportCreateTicketCubit supportCreateTicketCubit;
  late Directory tempDir;
  late File imageFile;

  setUp(() {
    supportCreateTicketCubit = MockSupportCreateTicketCubit();
    when(() => supportCreateTicketCubit.state).thenReturn(const SupportCreateTicketState());
  });

  void setupDependencyInjection() {
    final getIt = GetIt.instance;
    getIt.registerSingleton<DfxSupportService>(MockDfxSupportService());
  }

  setUpAll(() async {
    registerFallbackValue(SupportIssueType.genericIssue);
    setupDependencyInjection();
    // Real PNG bytes so Image.file decodes cleanly (same pattern as the
    // settings_user_data responsive matrix).
    tempDir = await Directory.systemTemp.createTemp('create_ticket_page_');
    imageFile = File('${tempDir.path}${Platform.pathSeparator}ticket_shot.png');
    final bytes = await File('assets/icons/realunit_wallet_logo_full.png').readAsBytes();
    await imageFile.writeAsBytes(bytes);
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Widget buildSubject(Widget child) {
    return BlocProvider.value(
      value: supportCreateTicketCubit,
      child: child,
    );
  }

  group('$SupportCreateTicketPage', () {
    testWidgets('renders $SupportCreateTicketView', (tester) async {
      await tester.pumpApp(const SupportCreateTicketPage());

      expect(find.byType(SupportCreateTicketView), findsOne);
    });
  });

  group('$SupportCreateTicketView', () {
    testWidgets('renders initially correctly', (tester) async {
      await tester.pumpApp(buildSubject(const SupportCreateTicketView()));

      expect(find.byType(TagSelection<SupportIssueType>), findsOne);
      expect(find.byType(TextField), findsOne);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      final button = tester.widget<FilledButton>(find.bySubtype<FilledButton>());
      expect(button.onPressed, isNull);
    });

    testWidgets('renders SupportAttachmentField for the optional attachment', (tester) async {
      await tester.pumpApp(buildSubject(const SupportCreateTicketView()));

      expect(find.byType(SupportAttachmentField), findsOneWidget);
    });

    testWidgets(
      'with attachment shows the file name and clearAttachment on close tap',
      (tester) async {
        final attachment = XFile(imageFile.path);
        when(() => supportCreateTicketCubit.state).thenReturn(
          SupportCreateTicketState(attachment: attachment),
        );
        when(() => supportCreateTicketCubit.clearAttachment()).thenReturn(null);

        await tester.pumpApp(buildSubject(const SupportCreateTicketView()));
        await tester.pumpAndSettle();

        expect(find.byType(SupportAttachmentField), findsOneWidget);
        expect(find.text(attachment.name), findsOneWidget);
        expect(find.byIcon(Icons.close_rounded), findsOneWidget);

        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pumpAndSettle();

        verify(() => supportCreateTicketCubit.clearAttachment()).called(1);
      },
    );

    testWidgets('renders correctly when submitting', (tester) async {
      when(() => supportCreateTicketCubit.state).thenReturn(
        const SupportCreateTicketState(
          selectedType: SupportIssueType.genericIssue,
          selectedReason: SupportIssueReason.other,
          message: 'test message',
          isSubmitting: true,
        ),
      );

      await tester.pumpApp(buildSubject(const SupportCreateTicketView()));

      expect(find.byType(CupertinoActivityIndicator), findsOne);
      final button = tester.widget<FilledButton>(find.bySubtype<FilledButton>());
      expect(button.onPressed, isNull);
      final attachmentField = tester.widget<SupportAttachmentField>(
        find.byType(SupportAttachmentField),
      );
      expect(attachmentField.enabled, isFalse);
    });

    testWidgets(
      'while isSubmitting the message TextField is enabled:false and does not call updateMessage',
      (tester) async {
        when(() => supportCreateTicketCubit.state).thenReturn(
          const SupportCreateTicketState(
            selectedType: SupportIssueType.bugReport,
            selectedReason: SupportIssueReason.other,
            message: 'first half',
            isSubmitting: true,
          ),
        );
        when(() => supportCreateTicketCubit.updateMessage(any())).thenReturn(null);

        await tester.pumpApp(buildSubject(const SupportCreateTicketView()));

        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.enabled, isFalse);

        // enterText still reaches onChanged on some Flutter versions; assert both
        // the widget flag and that the cubit is not called if the field is locked.
        await tester.enterText(find.byType(TextField), 'first half AND SECOND HALF');
        await tester.pump();

        verifyNever(() => supportCreateTicketCubit.updateMessage(any()));
      },
    );

    testWidgets(
      'while isSubmitting TagSelection chips are disabled (onSelected null) and do not call selectType',
      (tester) async {
        when(() => supportCreateTicketCubit.state).thenReturn(
          const SupportCreateTicketState(
            selectedType: SupportIssueType.bugReport,
            selectedReason: SupportIssueReason.other,
            message: 'hold type',
            isSubmitting: true,
          ),
        );
        when(() => supportCreateTicketCubit.selectType(any())).thenReturn(null);

        await tester.pumpApp(buildSubject(const SupportCreateTicketView()));

        final tagSelection = tester.widget<TagSelection<SupportIssueType>>(
          find.byType(TagSelection<SupportIssueType>),
        );
        expect(tagSelection.onSelected, isNull);

        final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).toList();
        expect(chips, isNotEmpty);
        for (final chip in chips) {
          expect(chip.onSelected, isNull);
        }

        // Tap a different type — must not reach the cubit.
        await tester.tap(find.text('KYC issue'));
        await tester.pump();

        verifyNever(() => supportCreateTicketCubit.selectType(any()));
      },
    );

    testWidgets(
      'when not submitting the message TextField is enabled and TagSelection is tappable',
      (tester) async {
        when(() => supportCreateTicketCubit.state).thenReturn(
          const SupportCreateTicketState(
            selectedType: SupportIssueType.bugReport,
            selectedReason: SupportIssueReason.other,
            message: 'ready',
          ),
        );
        when(() => supportCreateTicketCubit.selectType(any())).thenReturn(null);
        when(() => supportCreateTicketCubit.updateMessage(any())).thenReturn(null);

        await tester.pumpApp(buildSubject(const SupportCreateTicketView()));

        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.enabled, isTrue);

        final tagSelection = tester.widget<TagSelection<SupportIssueType>>(
          find.byType(TagSelection<SupportIssueType>),
        );
        expect(tagSelection.onSelected, isNotNull);

        final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).toList();
        for (final chip in chips) {
          expect(chip.onSelected, isNotNull);
        }
      },
    );

    testWidgets('renders correctly when can submit', (tester) async {
      when(() => supportCreateTicketCubit.state).thenReturn(
        const SupportCreateTicketState(
          selectedType: SupportIssueType.genericIssue,
          selectedReason: SupportIssueReason.other,
          message: 'test message',
        ),
      );

      await tester.pumpApp(buildSubject(const SupportCreateTicketView()));

      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      final button = tester.widget<FilledButton>(find.bySubtype<FilledButton>());
      expect(button.onPressed, isNotNull);
    });
  });

  group('$BlocListener', () {
    testWidgets('shows SnackBar if creating ticket failed', (tester) async {
      whenListen(
        supportCreateTicketCubit,
        Stream.fromIterable([
          const SupportCreateTicketState(error: 'failed'),
        ]),
        initialState: const SupportCreateTicketState(),
      );

      await tester.pumpApp(buildSubject(const SupportCreateTicketView()));
      await tester.pump();

      expect(find.byType(SnackBar), findsOne);
    });
  });
}
