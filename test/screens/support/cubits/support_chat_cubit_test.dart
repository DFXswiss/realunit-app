import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_support_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/dto/support_issue_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue_reason.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue_state.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue_type.dart';
import 'package:realunit_wallet/screens/support/cubits/support_chat/support_chat_cubit.dart';
import 'package:realunit_wallet/screens/support/cubits/support_chat/support_chat_state.dart';

class _MockSupportService extends Mock implements DfxSupportService {}

const _ticketUid = 'uid-1';

SupportIssueDto _ticket({String uid = _ticketUid}) => SupportIssueDto(
      uid: uid,
      state: SupportIssueState.created,
      type: SupportIssueType.genericIssue,
      reason: SupportIssueReason.other,
      name: 'Test ticket',
      created: DateTime.utc(2026, 1, 1),
      messages: const [],
    );

void main() {
  late _MockSupportService service;
  late Directory tempDir;

  setUp(() async {
    service = _MockSupportService();
    tempDir = await Directory.systemTemp.createTemp('chat_cubit_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  XFile writeTempFile(String name, List<int> bytes) {
    final file = File('${tempDir.path}/$name')..writeAsBytesSync(bytes);
    return XFile(file.path, mimeType: 'image/png');
  }

  // Constructor fires loadTicket(); we assert the final state via
  // stream.firstWhere rather than the full sequence.
  group('$SupportChatCubit', () {
    test('reaches Loaded with the mapped ticket', () async {
      when(() => service.getTicket(_ticketUid))
          .thenAnswer((_) async => _ticket());

      final cubit = SupportChatCubit(service, _ticketUid);
      await cubit.stream.firstWhere((s) => s is SupportChatLoaded);

      expect((cubit.state as SupportChatLoaded).ticket.uid, _ticketUid);
      expect((cubit.state as SupportChatLoaded).isSending, isFalse);
    });

    test('reaches Error when getTicket fails', () async {
      when(() => service.getTicket(any()))
          .thenAnswer((_) async => throw Exception('boom'));

      final cubit = SupportChatCubit(service, _ticketUid);
      await cubit.stream.firstWhere((s) => s is SupportChatError);

      expect((cubit.state as SupportChatError).message, contains('boom'));
    });

    test('sendMessage is a no-op when not in Loaded state', () async {
      when(() => service.getTicket(any()))
          .thenAnswer((_) async => throw Exception('still loading'));
      final cubit = SupportChatCubit(service, _ticketUid);
      await cubit.stream.firstWhere((s) => s is SupportChatError);

      final ok = await cubit.sendMessage('hello');

      expect(ok, isFalse);
      // sendMessage must NOT call the service while in Error state.
      verifyNever(() => service.sendMessage(
            any(),
            message: any(named: 'message'),
            file: any(named: 'file'),
            fileName: any(named: 'fileName'),
          ));
    });

    test('sendMessage is a no-op for whitespace-only input without attachment', () async {
      when(() => service.getTicket(_ticketUid))
          .thenAnswer((_) async => _ticket());
      final cubit = SupportChatCubit(service, _ticketUid);
      await cubit.stream.firstWhere((s) => s is SupportChatLoaded);
      clearInteractions(service);

      final ok = await cubit.sendMessage('   \t  ');

      expect(ok, isFalse);
      verifyNever(() => service.sendMessage(
            any(),
            message: any(named: 'message'),
            file: any(named: 'file'),
            fileName: any(named: 'fileName'),
          ));
    });

    test('sendMessage with empty text and attachment still sends', () async {
      when(() => service.getTicket(_ticketUid))
          .thenAnswer((_) async => _ticket());
      when(() => service.sendMessage(
            any(),
            message: any(named: 'message'),
            file: any(named: 'file'),
            fileName: any(named: 'fileName'),
          )).thenAnswer((_) async {});
      final cubit = SupportChatCubit(service, _ticketUid);
      await cubit.stream.firstWhere((s) => s is SupportChatLoaded);
      final file = writeTempFile('only.png', [1, 2, 3, 4]);
      cubit.selectAttachment(file);

      final ok = await cubit.sendMessage('   ');

      expect(ok, isTrue);
      final captured = verify(() => service.sendMessage(
            _ticketUid,
            message: captureAny(named: 'message'),
            file: captureAny(named: 'file'),
            fileName: captureAny(named: 'fileName'),
          )).captured;
      expect(captured[0], isNull);
      expect(captured[1], startsWith('data:image/png;base64,'));
      expect(captured[2], 'only.png');
      expect(cubit.state, isA<SupportChatLoaded>());
      expect((cubit.state as SupportChatLoaded).attachment, isNull);
    });

    test('sendMessage posts the message and re-fetches the ticket', () async {
      when(() => service.getTicket(_ticketUid))
          .thenAnswer((_) async => _ticket());
      when(() => service.sendMessage(
            any(),
            message: any(named: 'message'),
            file: any(named: 'file'),
            fileName: any(named: 'fileName'),
          )).thenAnswer((_) async {});
      final cubit = SupportChatCubit(service, _ticketUid);
      await cubit.stream.firstWhere((s) => s is SupportChatLoaded);

      final ok = await cubit.sendMessage('hello');

      expect(ok, isTrue);
      verify(() => service.sendMessage(
            _ticketUid,
            message: 'hello',
            file: null,
            fileName: null,
          )).called(1);
      // After loadTicket() + sendMessage(), getTicket has been called twice.
      verify(() => service.getTicket(_ticketUid)).called(2);
      expect(cubit.state, isA<SupportChatLoaded>());
      expect((cubit.state as SupportChatLoaded).isSending, isFalse);
    });

    test('sendMessage clears isSending=true when the service fails', () async {
      when(() => service.getTicket(_ticketUid))
          .thenAnswer((_) async => _ticket());
      when(() => service.sendMessage(
            any(),
            message: any(named: 'message'),
            file: any(named: 'file'),
            fileName: any(named: 'fileName'),
          )).thenAnswer((_) async => throw Exception('nope'));

      final cubit = SupportChatCubit(service, _ticketUid);
      await cubit.stream.firstWhere((s) => s is SupportChatLoaded);
      final file = writeTempFile('keep.png', [5]);
      cubit.selectAttachment(file);

      final ok = await cubit.sendMessage('hello');

      expect(ok, isFalse);
      // Stays Loaded but isSending is reset to false; attachment kept for retry.
      expect(cubit.state, isA<SupportChatLoaded>());
      expect((cubit.state as SupportChatLoaded).isSending, isFalse);
      expect((cubit.state as SupportChatLoaded).attachment, file);
    });

    test('clearAttachment removes the attachment and keeps the ticket', () async {
      when(() => service.getTicket(_ticketUid))
          .thenAnswer((_) async => _ticket());
      final cubit = SupportChatCubit(service, _ticketUid);
      await cubit.stream.firstWhere((s) => s is SupportChatLoaded);
      final file = writeTempFile('to_clear.png', [7, 8]);
      cubit.selectAttachment(file);
      final ticketBefore = (cubit.state as SupportChatLoaded).ticket;

      cubit.clearAttachment();

      final loaded = cubit.state as SupportChatLoaded;
      expect(loaded.attachment, isNull);
      expect(loaded.ticket, ticketBefore);
      expect(loaded.isSending, isFalse);
    });

    test('clearAttachment is a no-op when not in Loaded state', () async {
      when(() => service.getTicket(any()))
          .thenAnswer((_) async => throw Exception('boom'));
      final cubit = SupportChatCubit(service, _ticketUid);
      await cubit.stream.firstWhere((s) => s is SupportChatError);
      final before = cubit.state;

      expect(() => cubit.clearAttachment(), returnsNormally);
      expect(cubit.state, same(before));
      expect(cubit.state, isA<SupportChatError>());
    });

    test('clearAttachment is a no-op while isSending is true', () async {
      when(() => service.getTicket(_ticketUid))
          .thenAnswer((_) async => _ticket());
      final hang = Completer<void>();
      when(() => service.sendMessage(
            any(),
            message: any(named: 'message'),
            file: any(named: 'file'),
            fileName: any(named: 'fileName'),
          )).thenAnswer((_) => hang.future);

      final cubit = SupportChatCubit(service, _ticketUid);
      await cubit.stream.firstWhere((s) => s is SupportChatLoaded);
      final file = writeTempFile('sending.png', [9]);
      cubit.selectAttachment(file);

      // Leave send in-flight so isSending stays true with attachment kept.
      final pending = cubit.sendMessage('hello');
      await Future<void>.delayed(Duration.zero);
      expect((cubit.state as SupportChatLoaded).isSending, isTrue);
      expect((cubit.state as SupportChatLoaded).attachment, file);

      cubit.clearAttachment();

      // Guard uses OR: isSending alone must block clear, even though Loaded.
      final after = cubit.state as SupportChatLoaded;
      expect(after.isSending, isTrue);
      expect(after.attachment, file);

      hang.complete();
      await pending;
    });

    test('selectAttachment is a no-op while isSending is true', () async {
      when(() => service.getTicket(_ticketUid))
          .thenAnswer((_) async => _ticket());
      final hang = Completer<void>();
      when(() => service.sendMessage(
            any(),
            message: any(named: 'message'),
            file: any(named: 'file'),
            fileName: any(named: 'fileName'),
          )).thenAnswer((_) => hang.future);

      final cubit = SupportChatCubit(service, _ticketUid);
      await cubit.stream.firstWhere((s) => s is SupportChatLoaded);
      final original = writeTempFile('original.png', [1]);
      final replacement = writeTempFile('replacement.png', [2]);
      cubit.selectAttachment(original);

      final pending = cubit.sendMessage('hello');
      await Future<void>.delayed(Duration.zero);
      expect((cubit.state as SupportChatLoaded).isSending, isTrue);

      cubit.selectAttachment(replacement);

      final after = cubit.state as SupportChatLoaded;
      expect(after.isSending, isTrue);
      expect(after.attachment, original);
      expect(after.attachment, isNot(replacement));

      hang.complete();
      await pending;
    });

    test(
      'sendMessage returns true when POST succeeds but getTicket fails, '
      'clears attachment and isSending',
      () async {
        var getTicketCalls = 0;
        when(() => service.getTicket(_ticketUid)).thenAnswer((_) async {
          getTicketCalls++;
          if (getTicketCalls == 1) return _ticket();
          throw Exception('refetch failed');
        });
        when(() => service.sendMessage(
              any(),
              message: any(named: 'message'),
              file: any(named: 'file'),
              fileName: any(named: 'fileName'),
            )).thenAnswer((_) async {});

        final cubit = SupportChatCubit(service, _ticketUid);
        await cubit.stream.firstWhere((s) => s is SupportChatLoaded);
        final file = writeTempFile('sent.png', [3, 4]);
        cubit.selectAttachment(file);
        final ticketBefore = (cubit.state as SupportChatLoaded).ticket;

        final ok = await cubit.sendMessage('hello');

        expect(ok, isTrue);
        final loaded = cubit.state as SupportChatLoaded;
        expect(loaded.isSending, isFalse);
        expect(loaded.attachment, isNull);
        // Prior ticket content retained — refetch failed, so no new ticket.
        expect(loaded.ticket, ticketBefore);
        verify(() => service.sendMessage(
              _ticketUid,
              message: 'hello',
              file: any(named: 'file'),
              fileName: 'sent.png',
            )).called(1);
      },
    );

    test(
      'sendMessage after close does not throw and returns false without emitting',
      () async {
        when(() => service.getTicket(_ticketUid))
            .thenAnswer((_) async => _ticket());
        final cubit = SupportChatCubit(service, _ticketUid);
        await cubit.stream.firstWhere((s) => s is SupportChatLoaded);

        final emitted = <SupportChatState>[];
        final sub = cubit.stream.listen(emitted.add);
        await cubit.close();
        final countAtClose = emitted.length;

        final ok = await cubit.sendMessage('hello');
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();

        expect(ok, isFalse);
        expect(emitted.length, countAtClose);
        verifyNever(() => service.sendMessage(
              any(),
              message: any(named: 'message'),
              file: any(named: 'file'),
              fileName: any(named: 'fileName'),
            ));
      },
    );

    test(
      'sendMessage does not emit after close while send is in flight (success path)',
      () async {
        when(() => service.getTicket(_ticketUid))
            .thenAnswer((_) async => _ticket());
        final hang = Completer<void>();
        when(() => service.sendMessage(
              any(),
              message: any(named: 'message'),
              file: any(named: 'file'),
              fileName: any(named: 'fileName'),
            )).thenAnswer((_) => hang.future);

        final cubit = SupportChatCubit(service, _ticketUid);
        await cubit.stream.firstWhere((s) => s is SupportChatLoaded);

        final emitted = <SupportChatState>[];
        final sub = cubit.stream.listen(emitted.add);
        final pending = cubit.sendMessage('hello');
        await Future<void>.delayed(Duration.zero);
        expect((cubit.state as SupportChatLoaded).isSending, isTrue);

        final countAtClose = emitted.length;
        await cubit.close();
        hang.complete();
        final ok = await pending;
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();

        expect(ok, isFalse);
        expect(emitted.length, countAtClose);
      },
    );

    test(
      'sendMessage does not emit after close while send is in flight (error path)',
      () async {
        when(() => service.getTicket(_ticketUid))
            .thenAnswer((_) async => _ticket());
        final hang = Completer<void>();
        when(() => service.sendMessage(
              any(),
              message: any(named: 'message'),
              file: any(named: 'file'),
              fileName: any(named: 'fileName'),
            )).thenAnswer((_) => hang.future);

        final cubit = SupportChatCubit(service, _ticketUid);
        await cubit.stream.firstWhere((s) => s is SupportChatLoaded);

        final emitted = <SupportChatState>[];
        final sub = cubit.stream.listen(emitted.add);
        final pending = cubit.sendMessage('hello');
        await Future<void>.delayed(Duration.zero);

        final countAtClose = emitted.length;
        await cubit.close();
        hang.completeError(Exception('socket hung up'));
        final ok = await pending;
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();

        expect(ok, isFalse);
        expect(emitted.length, countAtClose);
      },
    );

    test(
      'loadTicket after close does not throw and does not emit',
      () async {
        when(() => service.getTicket(_ticketUid))
            .thenAnswer((_) async => _ticket());
        final cubit = SupportChatCubit(service, _ticketUid);
        await cubit.stream.firstWhere((s) => s is SupportChatLoaded);

        final emitted = <SupportChatState>[];
        final sub = cubit.stream.listen(emitted.add);
        await cubit.close();
        final countAtClose = emitted.length;
        clearInteractions(service);

        await cubit.loadTicket();
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();

        expect(emitted.length, countAtClose);
        verifyNever(() => service.getTicket(any()));
      },
    );

    test(
      'loadTicket does not emit after close while getTicket is in flight',
      () async {
        final hang = Completer<SupportIssueDto>();
        when(() => service.getTicket(_ticketUid))
            .thenAnswer((_) => hang.future);

        final cubit = SupportChatCubit(service, _ticketUid);
        final emitted = <SupportChatState>[];
        final sub = cubit.stream.listen(emitted.add);
        // Constructor already fired loadTicket — wait for Loading emit.
        await Future<void>.delayed(Duration.zero);
        expect(cubit.state, isA<SupportChatLoading>());

        final countAtClose = emitted.length;
        await cubit.close();
        hang.complete(_ticket());
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();

        expect(emitted.length, countAtClose);
        expect(cubit.state, isA<SupportChatLoading>());
      },
    );

    test(
      'loadTicket does not emit Error after close when getTicket fails',
      () async {
        final hang = Completer<SupportIssueDto>();
        when(() => service.getTicket(_ticketUid))
            .thenAnswer((_) => hang.future);

        final cubit = SupportChatCubit(service, _ticketUid);
        final emitted = <SupportChatState>[];
        final sub = cubit.stream.listen(emitted.add);
        await Future<void>.delayed(Duration.zero);

        final countAtClose = emitted.length;
        await cubit.close();
        hang.completeError(Exception('gone'));
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();

        expect(emitted.length, countAtClose);
        expect(cubit.state, isNot(isA<SupportChatError>()));
      },
    );

    test(
      'sendMessage does not emit after close when getTicket fails post-send',
      () async {
        when(() => service.getTicket(_ticketUid))
            .thenAnswer((_) async => _ticket());
        final hangSend = Completer<void>();
        when(() => service.sendMessage(
              any(),
              message: any(named: 'message'),
              file: any(named: 'file'),
              fileName: any(named: 'fileName'),
            )).thenAnswer((_) => hangSend.future);

        final cubit = SupportChatCubit(service, _ticketUid);
        await cubit.stream.firstWhere((s) => s is SupportChatLoaded);

        // After initial load, make the next getTicket fail (post-send refetch).
        when(() => service.getTicket(_ticketUid))
            .thenAnswer((_) async => throw Exception('refetch failed'));

        final emitted = <SupportChatState>[];
        final sub = cubit.stream.listen(emitted.add);
        final pending = cubit.sendMessage('hello');
        await Future<void>.delayed(Duration.zero);

        final countAtClose = emitted.length;
        await cubit.close();
        hangSend.complete();
        final ok = await pending;
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();

        // POST succeeded but cubit closed before refetch emit → false (isClosed).
        expect(ok, isFalse);
        expect(emitted.length, countAtClose);
      },
    );
  });
}

