// We deliberately use non-const constructors throughout this file so the
// generative constructor lines get counted as executed in the coverage
// report. Const-only construction is a compile-time optimisation and is
// not visible to the line-coverage instrumentation.
// ignore_for_file: prefer_const_constructors
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue_reason.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue_state.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue_type.dart';
import 'package:realunit_wallet/screens/support/cubits/support_chat/support_chat_state.dart';

/// Equatable-`props` surface tests for `SupportChatState`.
///
/// Builds on top of the existing partial coverage in
/// `debug_auth_support_states_test.dart` and pins every subclass + the base
/// `props => []` default + the runtimeType guard between subclasses at
/// runtime (non-const constructors).
SupportIssue _ticket({String uid = 'u1'}) => SupportIssue(
  uid: uid,
  state: SupportIssueState.created,
  type: SupportIssueType.genericIssue,
  reason: SupportIssueReason.other,
  name: 'n',
  created: DateTime.utc(2026, 5, 15),
  messages: const [],
);

void main() {
  group('SupportChatInitial', () {
    test('two instances are equal and props are empty', () {
      final a = SupportChatInitial();
      final b = SupportChatInitial();
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a.props, isEmpty);
    });
  });

  group('SupportChatLoading', () {
    test('two instances are equal and props are empty', () {
      final a = SupportChatLoading();
      final b = SupportChatLoading();
      expect(a, equals(b));
      expect(a.props, isEmpty);
    });
  });

  group('SupportChatLoaded', () {
    test('same ticket and isSending are equal', () {
      final ticket = _ticket();
      final a = SupportChatLoaded(ticket: ticket);
      final b = SupportChatLoaded(ticket: ticket);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a.props, [ticket, false, null]);
    });

    test('different isSending flags are unequal', () {
      final ticket = _ticket();
      final a = SupportChatLoaded(ticket: ticket);
      final b = SupportChatLoaded(ticket: ticket, isSending: true);
      expect(a, isNot(equals(b)));
    });

    test('copyWith with isSending changes only that field', () {
      final ticket = _ticket();
      final base = SupportChatLoaded(ticket: ticket);
      final next = base.copyWith(isSending: true);
      expect(next.ticket, ticket);
      expect(next.isSending, isTrue);
      expect(next.attachment, isNull);
    });

    test('copyWith with ticket changes only that field', () {
      final ticket1 = _ticket(uid: 'u1');
      final ticket2 = _ticket(uid: 'u2');
      final base = SupportChatLoaded(ticket: ticket1, isSending: true);
      final next = base.copyWith(ticket: ticket2);
      expect(next.ticket, ticket2);
      expect(next.isSending, isTrue);
    });

    test('copyWith with no arguments returns equal instance', () {
      final ticket = _ticket();
      final base = SupportChatLoaded(ticket: ticket, isSending: true);
      final next = base.copyWith();
      expect(next, equals(base));
    });

    test('copyWith clearAttachment removes the attachment', () {
      final ticket = _ticket();
      final attachment = XFile('path/to/img.jpg');
      final base = SupportChatLoaded(ticket: ticket, attachment: attachment);
      final next = base.copyWith(clearAttachment: true);
      expect(next.attachment, isNull);
      expect(next.ticket, ticket);
    });
  });

  group('SupportChatError', () {
    test('same message is equal and props match', () {
      final a = SupportChatError('boom');
      final b = SupportChatError('boom');
      expect(a, equals(b));
      expect(a.props, ['boom']);
    });

    test('different messages are unequal', () {
      final a = SupportChatError('boom');
      final b = SupportChatError('other');
      expect(a, isNot(equals(b)));
    });
  });

  group('SupportChatState (cross-subclass identity)', () {
    test('Initial vs Loading are unequal even though props match', () {
      expect(SupportChatInitial(), isNot(equals(SupportChatLoading())));
    });

    test('Loaded vs Error are unequal', () {
      final loaded = SupportChatLoaded(ticket: _ticket());
      final err = SupportChatError('boom');
      expect(loaded, isNot(equals(err)));
    });
  });
}
