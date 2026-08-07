import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_support_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue_reason.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue_state.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue_type.dart';
import 'package:realunit_wallet/screens/support/cubits/support_tickets/support_tickets_cubit.dart';
import 'package:realunit_wallet/screens/support/cubits/support_tickets/support_tickets_state.dart';
import 'package:realunit_wallet/screens/support/subpages/support_tickets_page.dart';
import 'package:realunit_wallet/widgets/outlined_tile.dart';

import '../../helper/pump_app.dart';

class MockSupportTicketsCubit extends MockCubit<SupportTicketsState>
    implements SupportTicketsCubit {}

class MockDfxSupportService extends Mock implements DfxSupportService {}

void main() {
  late SupportTicketsCubit supportTicketsCubit;

  setUp(() {
    supportTicketsCubit = MockSupportTicketsCubit();
    when(() => supportTicketsCubit.state).thenReturn(const SupportTicketsInitial());
  });

  void setupDependencyInjection() {
    final getIt = GetIt.instance;
    getIt.registerSingleton<DfxSupportService>(MockDfxSupportService());
  }

  setUpAll(() {
    setupDependencyInjection();
  });

  Widget buildSubject(Widget child) {
    return BlocProvider.value(
      value: supportTicketsCubit,
      child: child,
    );
  }

  group('$SupportTicketsPage', () {
    testWidgets('renders $SupportTicketsView', (tester) async {
      await tester.pumpApp(const SupportTicketsPage());

      expect(find.byType(SupportTicketsView), findsOne);
    });
  });

  group('$SupportTicketsView', () {
    testWidgets('renders initially correctly', (tester) async {
      await tester.pumpApp(buildSubject(const SupportTicketsView()));

      expect(find.byType(SizedBox), findsOne);
    });

    testWidgets('renders correctly when loading', (tester) async {
      when(() => supportTicketsCubit.state).thenReturn(const SupportTicketsLoading());

      await tester.pumpApp(buildSubject(const SupportTicketsView()));

      expect(find.byType(SizedBox), findsOne);
    });

    testWidgets('renders correctly when loading failed', (tester) async {
      final error = 'failed';
      when(() => supportTicketsCubit.state).thenReturn(SupportTicketsError(error));

      await tester.pumpApp(buildSubject(const SupportTicketsView()));

      expect(find.text(error), findsOne);
    });

    testWidgets('renders correctly when successfully loaded', (tester) async {
      final tickets = [
        SupportIssue(
          uid: '123',
          created: DateTime.now(),
          messages: [],
          name: 'name',
          reason: SupportIssueReason.other,
          state: SupportIssueState.created,
          type: SupportIssueType.genericIssue,
        ),
      ];
      when(() => supportTicketsCubit.state).thenReturn(SupportTicketsLoaded(tickets));

      await tester.pumpApp(buildSubject(const SupportTicketsView()));

      expect(find.byType(ListView), findsOne);
      expect(find.byType(OutlinedTile), findsNWidgets(tickets.length));
    });

    testWidgets('renders the ticket date in local time, not UTC', (tester) async {
      // 23:30 UTC crosses midnight only in a positive-offset zone, where the
      // local calendar date differs from the UTC one — the case that tells the
      // fix apart from the old raw-UTC rendering. On a zero/negative-offset
      // runner (e.g. the GitHub-hosted UTC CI job) the two coincide, so skip
      // rather than pass vacuously and masquerade as a real regression guard.
      final createdUtc = DateTime.utc(2024, 1, 15, 23, 30);
      final local = createdUtc.toLocal();
      if (local.day == createdUtc.day) {
        markTestSkipped(
          'runner timezone does not push 23:30 UTC across midnight; '
          'the local-vs-UTC date regression is not exercised here',
        );
        return;
      }
      final tickets = [
        SupportIssue(
          uid: '123',
          created: createdUtc,
          messages: [],
          name: 'name',
          reason: SupportIssueReason.other,
          state: SupportIssueState.created,
          type: SupportIssueType.genericIssue,
        ),
      ];
      when(() => supportTicketsCubit.state).thenReturn(SupportTicketsLoaded(tickets));

      await tester.pumpApp(buildSubject(const SupportTicketsView()));

      expect(find.text('${local.day}.${local.month}.${local.year}'), findsOne);
    });

    testWidgets('renders correctly when successfully loaded but no tickets', (tester) async {
      final tickets = <SupportIssue>[];
      when(() => supportTicketsCubit.state).thenReturn(SupportTicketsLoaded(tickets));

      await tester.pumpApp(buildSubject(const SupportTicketsView()));

      expect(find.byType(ListView), findsNothing);
      expect(find.byType(OutlinedTile), findsNWidgets(tickets.length));
      expect(find.text(S.current.supportNoTickets), findsOne);
    });
  });
}
