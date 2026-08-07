import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue_reason.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue_state.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue_type.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_message.dart';
import 'package:realunit_wallet/screens/support/cubits/support_chat/support_chat_cubit.dart';
import 'package:realunit_wallet/screens/support/cubits/support_chat/support_chat_state.dart';
import 'package:realunit_wallet/screens/support/subpages/support_chat_page.dart';

import '../../../helper/helper.dart';

class _MockSupportChatCubit extends MockCubit<SupportChatState>
    implements SupportChatCubit {}

// Deterministic two-message conversation. The customer bubble (author ==
// `customerAuthor`) renders blue and right-aligned; the support bubble renders
// grey, left-aligned, with the "Support" label above it. `created` is a fixed
// UTC instant and the bubble formats it via `toLocal()`, so the rendered HH:MM
// is stable across render dates: these March 2024 instants (before that year's
// DST switch) always show CET, i.e. 08:15/08:42 UTC render as 09:15 and 09:42
// on the Europe/Zurich runner regardless of when the golden is captured.
List<SupportMessage> _conversation() => [
      SupportMessage(
        id: 1,
        author: customerAuthor,
        created: DateTime.utc(2024, 3, 4, 8, 15),
        message: 'Meine Auszahlung ist noch nicht angekommen.',
      ),
      SupportMessage(
        id: 2,
        author: 'RealUnit Support',
        created: DateTime.utc(2024, 3, 4, 8, 42),
        message:
            'Guten Tag, wir prüfen Ihre Transaktion und melden uns in Kürze bei Ihnen.',
      ),
    ];

SupportIssue _ticket(SupportIssueState state) => SupportIssue(
      uid: 'ticket-1',
      state: state,
      type: SupportIssueType.transactionIssue,
      reason: SupportIssueReason.fundsNotReceived,
      name: 'Transaction Issue',
      created: DateTime.utc(2024, 3, 4, 8, 15),
      messages: _conversation(),
    );

void main() {
  late _MockSupportChatCubit cubit;

  setUp(() {
    cubit = _MockSupportChatCubit();
    when(() => cubit.state).thenReturn(const SupportChatLoading());
  });

  Widget buildSubject() => BlocProvider<SupportChatCubit>.value(
        value: cubit,
        child: const SupportChatView(),
      );

  // The chat bubbles cap their width at `MediaQuery.size.width * 0.75`.
  // Alchemist renders inside the 390-wide `constraints` but leaves MediaQuery at
  // the default test-window width (800), which would size the bubble wider than
  // the visible area and overflow the row. Pin MediaQuery to the phone size so
  // the bubbles wrap exactly as they do on a real 390-wide device.
  Widget buildPhoneSubject() => MediaQuery(
        data: const MediaQueryData(size: Size(390, 844)),
        child: buildSubject(),
      );

  group('$SupportChatView', () {
    goldenTest(
      'loading state',
      fileName: 'support_chat_page_default',
      // CircularProgressIndicator never settles; pump once to capture the
      // initial frame instead of letting pumpAndSettle hang.
      pumpBeforeTest: pumpOnce,
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () => wrapForGolden(buildSubject()),
    );

    goldenTest(
      'error state — centered failure text',
      fileName: 'support_chat_page_error',
      constraints: phoneConstraints,
      builder: () {
        when(() => cubit.state).thenReturn(
          const SupportChatError('Chat konnte nicht geladen werden.'),
        );
        return wrapForGolden(buildSubject());
      },
    );

    goldenTest(
      'loaded open ticket — customer/support bubbles + input field',
      fileName: 'support_chat_page_loaded',
      constraints: phoneConstraints,
      builder: () {
        when(() => cubit.state).thenReturn(
          SupportChatLoaded(ticket: _ticket(SupportIssueState.created)),
        );
        return wrapForGolden(buildPhoneSubject());
      },
    );

    goldenTest(
      'loaded open ticket sending — disabled field + spinner',
      fileName: 'support_chat_page_sending',
      // The send button hosts a CupertinoActivityIndicator while sending;
      // freeze it on the first frame instead of letting pumpAndSettle hang.
      pumpBeforeTest: pumpOnce,
      constraints: phoneConstraints,
      builder: () {
        when(() => cubit.state).thenReturn(
          SupportChatLoaded(
            ticket: _ticket(SupportIssueState.created),
            isSending: true,
          ),
        );
        return wrapForGolden(buildPhoneSubject());
      },
    );

    goldenTest(
      'loaded closed ticket — closed banner instead of input field',
      fileName: 'support_chat_page_closed',
      constraints: phoneConstraints,
      builder: () {
        when(() => cubit.state).thenReturn(
          SupportChatLoaded(ticket: _ticket(SupportIssueState.completed)),
        );
        return wrapForGolden(buildPhoneSubject());
      },
    );
  });
}
