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
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue_reason.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue_state.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue_type.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_message.dart';
import 'package:realunit_wallet/screens/support/cubits/support_chat/support_chat_cubit.dart';
import 'package:realunit_wallet/screens/support/cubits/support_chat/support_chat_state.dart';
import 'package:realunit_wallet/screens/support/subpages/support_chat_page.dart';
import 'package:realunit_wallet/screens/support/widgets/support_chat_message_bubble.dart';
import 'package:realunit_wallet/screens/support/widgets/support_chat_message_input_field.dart';

import '../../helper/pump_app.dart';

class MockSupportChatCubit extends MockCubit<SupportChatState>
    implements SupportChatCubit {}

class MockDfxSupportService extends Mock implements DfxSupportService {}

void main() {
  late SupportChatCubit supportChatCubit;
  late Directory tempDir;
  late File imageFile;

  setUp(() {
    supportChatCubit = MockSupportChatCubit();
    when(() => supportChatCubit.state).thenReturn(const SupportChatInitial());
  });

  void setupDependencyInjection() {
    final getIt = GetIt.instance;
    getIt.registerSingleton<DfxSupportService>(MockDfxSupportService());
  }

  setUpAll(() async {
    setupDependencyInjection();
    tempDir = await Directory.systemTemp.createTemp('chat_page_attach_');
    imageFile = File('${tempDir.path}${Platform.pathSeparator}chat_shot.png');
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
      value: supportChatCubit,
      child: child,
    );
  }

  SupportIssue openTicket({List<SupportMessage> messages = const []}) => SupportIssue(
        uid: '123',
        created: DateTime.now(),
        messages: messages,
        name: 'name',
        reason: SupportIssueReason.other,
        state: SupportIssueState.created,
        type: SupportIssueType.genericIssue,
      );

  group('$SupportChatPage', () {
    testWidgets('renders $SupportChatView', (tester) async {
      await tester.pumpApp(const SupportChatPage(ticketUid: 'test-uid'));

      expect(find.byType(SupportChatView), findsOne);
    });
  });

  group('$SupportChatView', () {
    testWidgets('renders initially correctly', (tester) async {
      await tester.pumpApp(buildSubject(const SupportChatView()));

      expect(find.byType(SizedBox), findsOne);
    });

    testWidgets('renders correctly when loading', (tester) async {
      when(() => supportChatCubit.state).thenReturn(const SupportChatLoading());

      await tester.pumpApp(buildSubject(const SupportChatView()));

      expect(find.byType(CupertinoActivityIndicator), findsOne);
    });

    testWidgets('renders correctly when loading failed', (tester) async {
      const error = 'failed';
      when(() => supportChatCubit.state).thenReturn(const SupportChatError(error));

      await tester.pumpApp(buildSubject(const SupportChatView()));

      expect(find.text(error), findsOne);
    });

    testWidgets('renders correctly when successfully loaded', (tester) async {
      final messages = [
        SupportMessage(id: 1, created: DateTime.now(), message: 'Hello'),
        SupportMessage(id: 2, created: DateTime.now(), message: 'World'),
      ];
      when(() => supportChatCubit.state).thenReturn(
        SupportChatLoaded(ticket: openTicket(messages: messages)),
      );

      await tester.pumpApp(buildSubject(const SupportChatView()));

      expect(find.byType(ListView), findsOne);
      expect(find.byType(SupportChatMessageBubble), findsNWidgets(messages.length));
      expect(find.byType(SupportChatMessageInputField), findsOne);
    });

    testWidgets('renders correctly when successfully loaded with no messages', (tester) async {
      when(() => supportChatCubit.state).thenReturn(
        SupportChatLoaded(ticket: openTicket()),
      );

      await tester.pumpApp(buildSubject(const SupportChatView()));

      expect(find.byType(ListView), findsOne);
      expect(find.byType(SupportChatMessageBubble), findsNothing);
      expect(find.byType(SupportChatMessageInputField), findsOne);
    });

    testWidgets(
      'forwards SupportChatLoaded.attachment into SupportChatMessageInputField',
      (tester) async {
        final attachment = XFile(imageFile.path);
        when(() => supportChatCubit.state).thenReturn(
          SupportChatLoaded(
            ticket: openTicket(),
            attachment: attachment,
          ),
        );

        await tester.pumpApp(buildSubject(const SupportChatView()));
        await tester.pumpAndSettle();

        final input = tester.widget<SupportChatMessageInputField>(
          find.byType(SupportChatMessageInputField),
        );
        expect(input.attachment, same(attachment));
        expect(find.text(attachment.name), findsOneWidget);
      },
    );

    testWidgets(
      'send with attachment and empty text still calls sendMessage',
      (tester) async {
        final attachment = XFile(imageFile.path);
        when(() => supportChatCubit.state).thenReturn(
          SupportChatLoaded(
            ticket: openTicket(),
            attachment: attachment,
          ),
        );
        when(() => supportChatCubit.sendMessage(any())).thenAnswer((_) async => true);

        await tester.pumpApp(buildSubject(const SupportChatView()));
        await tester.pumpAndSettle();

        // Controller starts empty; only the attachment enables send.
        await tester.tap(find.byIcon(Icons.send_rounded));
        await tester.pump();

        verify(() => supportChatCubit.sendMessage(any())).called(1);
      },
    );

    testWidgets(
      'keeps typed text when sendMessage returns false (failed send)',
      (tester) async {
        final ticket = openTicket();
        whenListen(
          supportChatCubit,
          Stream.fromIterable([
            SupportChatLoaded(ticket: ticket, isSending: true),
            SupportChatLoaded(ticket: ticket, isSending: false),
          ]),
          initialState: SupportChatLoaded(ticket: ticket),
        );
        when(() => supportChatCubit.sendMessage(any())).thenAnswer((_) async => false);

        await tester.pumpApp(buildSubject(const SupportChatView()));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'my important message');
        await tester.tap(find.byIcon(Icons.send_rounded));
        await tester.pumpAndSettle();

        verify(() => supportChatCubit.sendMessage('my important message')).called(1);
        expect(find.text('my important message'), findsOneWidget);
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.controller?.text, 'my important message');
      },
    );

    testWidgets(
      'clears typed text when sendMessage returns true (successful send)',
      (tester) async {
        final ticket = openTicket();
        whenListen(
          supportChatCubit,
          Stream.fromIterable([
            SupportChatLoaded(ticket: ticket, isSending: true),
            SupportChatLoaded(ticket: ticket, isSending: false),
          ]),
          initialState: SupportChatLoaded(ticket: ticket),
        );
        when(() => supportChatCubit.sendMessage(any())).thenAnswer((_) async => true);

        await tester.pumpApp(buildSubject(const SupportChatView()));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'my important message');
        await tester.tap(find.byIcon(Icons.send_rounded));
        await tester.pumpAndSettle();

        verify(() => supportChatCubit.sendMessage('my important message')).called(1);
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.controller?.text, isEmpty);
      },
    );
  });
}

