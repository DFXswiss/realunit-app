import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue_reason.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue_state.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue_type.dart';
import 'package:realunit_wallet/screens/support/cubits/support_tickets/support_tickets_cubit.dart';
import 'package:realunit_wallet/screens/support/cubits/support_tickets/support_tickets_state.dart';
import 'package:realunit_wallet/screens/support/subpages/support_tickets_page.dart';

import '../../../helper/helper.dart';

class _MockSupportTicketsCubit extends MockCubit<SupportTicketsState>
    implements SupportTicketsCubit {}

// A ticket for the list tile. Only `name`, `created` (rendered as
// `day.month.year` — timezone-independent) and `isOpen` (derived from `state`,
// drives the green/grey status dot) surface in the OutlinedTile. `messages` is
// empty because the list view never reads it.
SupportIssue _ticket({
  required String name,
  required SupportIssueState state,
  required DateTime created,
}) =>
    SupportIssue(
      uid: name,
      state: state,
      type: SupportIssueType.transactionIssue,
      reason: SupportIssueReason.fundsNotReceived,
      name: name,
      created: created,
      messages: const [],
    );

void main() {
  late _MockSupportTicketsCubit cubit;

  setUp(() {
    cubit = _MockSupportTicketsCubit();
    when(() => cubit.state).thenReturn(const SupportTicketsLoaded([]));
  });

  Widget buildSubject() => BlocProvider<SupportTicketsCubit>.value(
        value: cubit,
        child: const SupportTicketsView(),
      );

  group('$SupportTicketsView', () {
    goldenTest(
      'empty tickets list',
      fileName: 'support_tickets_page_default',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () => wrapForGolden(buildSubject()),
    );

    goldenTest(
      'loading — centered spinner',
      fileName: 'support_tickets_page_loading',
      // The loading indicator is a CupertinoActivityIndicator; freeze it on the
      // first frame instead of letting pumpAndSettle hang.
      pumpBeforeTest: pumpOnce,
      constraints: phoneConstraints,
      builder: () {
        when(() => cubit.state).thenReturn(const SupportTicketsLoading());
        return wrapForGolden(buildSubject());
      },
    );

    goldenTest(
      'error — centered failure text',
      fileName: 'support_tickets_page_error',
      constraints: phoneConstraints,
      builder: () {
        when(() => cubit.state).thenReturn(
          const SupportTicketsError('Tickets konnten nicht geladen werden.'),
        );
        return wrapForGolden(buildSubject());
      },
    );

    goldenTest(
      'loaded — open (green dot) and closed (grey dot) tickets',
      fileName: 'support_tickets_page_loaded',
      constraints: phoneConstraints,
      builder: () {
        when(() => cubit.state).thenReturn(
          SupportTicketsLoaded([
            _ticket(
              name: 'Transaction Issue',
              state: SupportIssueState.created,
              created: DateTime.utc(2024, 3, 4),
            ),
            _ticket(
              name: 'KYC Issue',
              state: SupportIssueState.completed,
              created: DateTime.utc(2024, 2, 18),
            ),
          ]),
        );
        return wrapForGolden(buildSubject());
      },
    );
  });
}
