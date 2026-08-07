import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_support_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/dto/support_issue_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue_reason.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue_state.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue_type.dart';
import 'package:realunit_wallet/screens/support/cubits/support_create_ticket/support_create_ticket_cubit.dart';
import 'package:realunit_wallet/screens/support/cubits/support_create_ticket/support_create_ticket_state.dart';

class _MockSupportService extends Mock implements DfxSupportService {}

/// Test double that can force-emit mid-await so the hoist is exercised even
/// when the public mutators are guarded by `isSubmitting`.
class _ProbeCreateTicketCubit extends SupportCreateTicketCubit {
  _ProbeCreateTicketCubit(super.supportService);

  void forceState(SupportCreateTicketState next) => emit(next);
}

/// XFile that mutates cubit state while `toBase64DataUri` awaits `readAsBytes`.
class _RaceXFile extends XFile {
  final void Function() onRead;

  _RaceXFile(
    super.path, {
    required this.onRead,
    super.mimeType,
  });

  @override
  Future<Uint8List> readAsBytes() async {
    onRead();
    return super.readAsBytes();
  }
}

SupportIssueDto _ticket() => SupportIssueDto(
      uid: 'created',
      state: SupportIssueState.created,
      type: SupportIssueType.bugReport,
      reason: SupportIssueReason.other,
      name: 'Bug Report',
      created: DateTime.utc(2026, 1, 1),
      messages: const [],
    );

void main() {
  late _MockSupportService service;
  late Directory tempDir;

  setUpAll(() {
    registerFallbackValue(SupportIssueType.genericIssue);
    registerFallbackValue(SupportIssueReason.other);
  });

  setUp(() async {
    service = _MockSupportService();
    tempDir = await Directory.systemTemp.createTemp('create_ticket_cubit_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  XFile writeTempFile(String name, List<int> bytes) {
    final file = File('${tempDir.path}/$name')..writeAsBytesSync(bytes);
    return XFile(file.path, mimeType: 'image/jpeg');
  }

  group('$SupportCreateTicketCubit', () {
    test('initial state has no selection, empty message, canSubmit=false', () {
      final cubit = SupportCreateTicketCubit(service);

      expect(cubit.state.selectedType, isNull);
      expect(cubit.state.selectedReason, isNull);
      expect(cubit.state.message, '');
      expect(cubit.state.attachment, isNull);
      expect(cubit.state.canSubmit, isFalse);
    });

    blocTest<SupportCreateTicketCubit, SupportCreateTicketState>(
      'selectType sets the type AND resets reason to SupportIssueReason.other',
      build: () => SupportCreateTicketCubit(service),
      seed: () => const SupportCreateTicketState(
        selectedType: SupportIssueType.genericIssue,
        selectedReason: SupportIssueReason.fundsNotReceived,
      ),
      act: (cubit) => cubit.selectType(SupportIssueType.bugReport),
      expect: () => [
        const SupportCreateTicketState(
          selectedType: SupportIssueType.bugReport,
          selectedReason: SupportIssueReason.other,
        ),
      ],
    );

    blocTest<SupportCreateTicketCubit, SupportCreateTicketState>(
      'selectReason sets the reason without touching the type',
      build: () => SupportCreateTicketCubit(service),
      seed: () => const SupportCreateTicketState(
        selectedType: SupportIssueType.bugReport,
        selectedReason: SupportIssueReason.other,
      ),
      act: (cubit) => cubit.selectReason(SupportIssueReason.transactionMissing),
      expect: () => [
        const SupportCreateTicketState(
          selectedType: SupportIssueType.bugReport,
          selectedReason: SupportIssueReason.transactionMissing,
        ),
      ],
    );

    blocTest<SupportCreateTicketCubit, SupportCreateTicketState>(
      'updateMessage updates the message field',
      build: () => SupportCreateTicketCubit(service),
      act: (cubit) => cubit.updateMessage('hi there'),
      expect: () => [
        const SupportCreateTicketState(message: 'hi there'),
      ],
    );

    test('selectAttachment stores the file; clearAttachment removes it', () {
      final cubit = SupportCreateTicketCubit(service);
      final file = writeTempFile('shot.jpg', [1, 2, 3]);

      cubit.selectAttachment(file);
      expect(cubit.state.attachment, file);

      cubit.clearAttachment();
      expect(cubit.state.attachment, isNull);
    });

    test('canSubmit requires type + reason + non-empty message + not submitting', () {
      const ready = SupportCreateTicketState(
        selectedType: SupportIssueType.bugReport,
        selectedReason: SupportIssueReason.other,
        message: 'a bug',
      );
      expect(ready.canSubmit, isTrue);
      // copyWith uses `?? this.x`, so null-args don't clear fields — build
      // each failing variant explicitly instead.
      expect(
        const SupportCreateTicketState(
          selectedReason: SupportIssueReason.other,
          message: 'a bug',
        ).canSubmit,
        isFalse,
        reason: 'selectedType=null blocks submit',
      );
      expect(
        const SupportCreateTicketState(
          selectedType: SupportIssueType.bugReport,
          message: 'a bug',
        ).canSubmit,
        isFalse,
        reason: 'selectedReason=null blocks submit',
      );
      expect(ready.copyWith(message: '').canSubmit, isFalse);
      expect(
        ready.copyWith(message: '   ').canSubmit,
        isFalse,
        reason: 'whitespace-only message is not enough',
      );
      expect(ready.copyWith(isSubmitting: true).canSubmit, isFalse);
      // Attachment alone does not make canSubmit true; message remains required.
      final withFile = SupportCreateTicketState(
        selectedType: SupportIssueType.bugReport,
        selectedReason: SupportIssueReason.other,
        message: '',
        attachment: writeTempFile('a.jpg', [9]),
      );
      expect(withFile.canSubmit, isFalse);
    });

    test('submit() is a no-op when canSubmit is false', () async {
      final cubit = SupportCreateTicketCubit(service);

      await cubit.submit();

      verifyNever(() => service.createTicket(
            type: any(named: 'type'),
            reason: any(named: 'reason'),
            name: any(named: 'name'),
            message: any(named: 'message'),
            file: any(named: 'file'),
            fileName: any(named: 'fileName'),
          ));
      expect(cubit.state.isSubmitting, isFalse);
      expect(cubit.state.isSuccess, isFalse);
    });

    test('submit() sets isSubmitting=true then isSuccess=true on success and forwards the right name', () async {
      when(() => service.createTicket(
            type: any(named: 'type'),
            reason: any(named: 'reason'),
            name: any(named: 'name'),
            message: any(named: 'message'),
            file: any(named: 'file'),
            fileName: any(named: 'fileName'),
          )).thenAnswer((_) async => _ticket());
      final cubit = SupportCreateTicketCubit(service);
      cubit.selectType(SupportIssueType.bugReport);
      cubit.selectReason(SupportIssueReason.other);
      cubit.updateMessage('a bug');

      await cubit.submit();

      expect(cubit.state.isSuccess, isTrue);
      expect(cubit.state.isSubmitting, isFalse);
      expect(cubit.state.error, isNull);
      // bugReport → 'Bug Report' (one of the explicit mappings).
      verify(() => service.createTicket(
            type: SupportIssueType.bugReport,
            reason: SupportIssueReason.other,
            name: 'Bug Report',
            message: 'a bug',
            file: null,
            fileName: null,
          )).called(1);
    });

    test('submit() trims whitespace before posting the message body', () async {
      when(() => service.createTicket(
            type: any(named: 'type'),
            reason: any(named: 'reason'),
            name: any(named: 'name'),
            message: any(named: 'message'),
            file: any(named: 'file'),
            fileName: any(named: 'fileName'),
          )).thenAnswer((_) async => _ticket());
      final cubit = SupportCreateTicketCubit(service);
      cubit.selectType(SupportIssueType.bugReport);
      cubit.selectReason(SupportIssueReason.other);
      cubit.updateMessage('  hallo  ');

      await cubit.submit();

      verify(() => service.createTicket(
            type: SupportIssueType.bugReport,
            reason: SupportIssueReason.other,
            name: 'Bug Report',
            message: 'hallo',
            file: null,
            fileName: null,
          )).called(1);
    });

    test('submit() with attachment forwards data-URI file and fileName', () async {
      when(() => service.createTicket(
            type: any(named: 'type'),
            reason: any(named: 'reason'),
            name: any(named: 'name'),
            message: any(named: 'message'),
            file: any(named: 'file'),
            fileName: any(named: 'fileName'),
          )).thenAnswer((_) async => _ticket());
      final cubit = SupportCreateTicketCubit(service);
      final file = writeTempFile('screenshot.jpg', [10, 20, 30]);
      cubit.selectType(SupportIssueType.bugReport);
      cubit.selectReason(SupportIssueReason.other);
      cubit.updateMessage('see attachment');
      cubit.selectAttachment(file);

      await cubit.submit();

      final captured = verify(() => service.createTicket(
            type: SupportIssueType.bugReport,
            reason: SupportIssueReason.other,
            name: 'Bug Report',
            message: 'see attachment',
            file: captureAny(named: 'file'),
            fileName: captureAny(named: 'fileName'),
          )).captured;
      final sentFile = captured[0] as String?;
      final sentName = captured[1] as String?;
      expect(sentFile, isNotNull);
      expect(sentFile, startsWith('data:image/jpeg;base64,'));
      expect(sentName, 'screenshot.jpg');
    });

    test('submit() forwards "General Issue" for genericIssue type', () async {
      when(() => service.createTicket(
            type: any(named: 'type'),
            reason: any(named: 'reason'),
            name: any(named: 'name'),
            message: any(named: 'message'),
            file: any(named: 'file'),
            fileName: any(named: 'fileName'),
          )).thenAnswer((_) async => _ticket());
      final cubit = SupportCreateTicketCubit(service);
      cubit.selectType(SupportIssueType.genericIssue);
      cubit.selectReason(SupportIssueReason.other);
      cubit.updateMessage('hi');

      await cubit.submit();

      verify(() => service.createTicket(
            type: SupportIssueType.genericIssue,
            reason: SupportIssueReason.other,
            name: 'General Issue',
            message: 'hi',
            file: null,
            fileName: null,
          )).called(1);
    });

    test('submit() captures the error message on failure', () async {
      when(() => service.createTicket(
            type: any(named: 'type'),
            reason: any(named: 'reason'),
            name: any(named: 'name'),
            message: any(named: 'message'),
            file: any(named: 'file'),
            fileName: any(named: 'fileName'),
          )).thenAnswer((_) async => throw Exception('rate limited'));
      final cubit = SupportCreateTicketCubit(service);
      cubit.selectType(SupportIssueType.bugReport);
      cubit.selectReason(SupportIssueReason.other);
      cubit.updateMessage('msg');

      await cubit.submit();

      expect(cubit.state.isSubmitting, isFalse);
      expect(cubit.state.isSuccess, isFalse);
      expect(cubit.state.error, contains('rate limited'));
    });

    test('clearAttachment is a no-op while isSubmitting is true', () async {
      final hang = Completer<SupportIssueDto>();
      when(() => service.createTicket(
            type: any(named: 'type'),
            reason: any(named: 'reason'),
            name: any(named: 'name'),
            message: any(named: 'message'),
            file: any(named: 'file'),
            fileName: any(named: 'fileName'),
          )).thenAnswer((_) => hang.future);

      final cubit = SupportCreateTicketCubit(service);
      final file = writeTempFile('hold.jpg', [1, 2, 3]);
      cubit.selectType(SupportIssueType.bugReport);
      cubit.selectReason(SupportIssueReason.other);
      cubit.updateMessage('hold attachment');
      cubit.selectAttachment(file);

      final pending = cubit.submit();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.isSubmitting, isTrue);
      expect(cubit.state.attachment, file);

      cubit.clearAttachment();

      expect(cubit.state.isSubmitting, isTrue);
      expect(cubit.state.attachment, file);

      hang.complete(_ticket());
      await pending;
    });

    test('selectAttachment is a no-op while isSubmitting is true', () async {
      final hang = Completer<SupportIssueDto>();
      when(() => service.createTicket(
            type: any(named: 'type'),
            reason: any(named: 'reason'),
            name: any(named: 'name'),
            message: any(named: 'message'),
            file: any(named: 'file'),
            fileName: any(named: 'fileName'),
          )).thenAnswer((_) => hang.future);

      final cubit = SupportCreateTicketCubit(service);
      final original = writeTempFile('orig.jpg', [1]);
      final replacement = writeTempFile('repl.jpg', [2]);
      cubit.selectType(SupportIssueType.bugReport);
      cubit.selectReason(SupportIssueReason.other);
      cubit.updateMessage('hold');
      cubit.selectAttachment(original);

      final pending = cubit.submit();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.isSubmitting, isTrue);

      cubit.selectAttachment(replacement);

      expect(cubit.state.isSubmitting, isTrue);
      expect(cubit.state.attachment, original);
      expect(cubit.state.attachment, isNot(replacement));

      hang.complete(_ticket());
      await pending;
    });

    test(
      'submit with attachment never calls createTicket with file but null fileName',
      () async {
        when(() => service.createTicket(
              type: any(named: 'type'),
              reason: any(named: 'reason'),
              name: any(named: 'name'),
              message: any(named: 'message'),
              file: any(named: 'file'),
              fileName: any(named: 'fileName'),
            )).thenAnswer((_) async => _ticket());

        final cubit = SupportCreateTicketCubit(service);
        final file = writeTempFile('paired.jpg', [4, 5, 6]);
        cubit.selectType(SupportIssueType.bugReport);
        cubit.selectReason(SupportIssueReason.other);
        cubit.updateMessage('with file');
        cubit.selectAttachment(file);

        // Race attempt: clear during submit must not drop fileName (guard + hoist).
        final pending = cubit.submit();
        cubit.clearAttachment();
        await pending;

        final captured = verify(() => service.createTicket(
              type: any(named: 'type'),
              reason: any(named: 'reason'),
              name: any(named: 'name'),
              message: any(named: 'message'),
              file: captureAny(named: 'file'),
              fileName: captureAny(named: 'fileName'),
            )).captured;
        final sentFile = captured[0] as String?;
        final sentName = captured[1] as String?;
        expect(sentFile, isNotNull);
        expect(sentName, 'paired.jpg');
      },
    );

    test(
      'submit hoists attachment: createTicket gets paired file+fileName even if '
      'attachment is force-cleared during toBase64DataUri',
      () async {
        when(() => service.createTicket(
              type: any(named: 'type'),
              reason: any(named: 'reason'),
              name: any(named: 'name'),
              message: any(named: 'message'),
              file: any(named: 'file'),
              fileName: any(named: 'fileName'),
            )).thenAnswer((_) async => _ticket());

        final cubit = _ProbeCreateTicketCubit(service);
        final path = writeTempFile('hoist.jpg', [7, 8, 9]).path;
        final raceFile = _RaceXFile(
          path,
          mimeType: 'image/jpeg',
          onRead: () {
            // Bypass the isSubmitting guard so this probes the hoist, not the guard.
            cubit.forceState(cubit.state.copyWith(clearAttachment: true));
            expect(cubit.state.attachment, isNull);
            expect(cubit.state.isSubmitting, isTrue);
          },
        );
        cubit.selectType(SupportIssueType.bugReport);
        cubit.selectReason(SupportIssueReason.other);
        cubit.updateMessage('hoist probe');
        cubit.selectAttachment(raceFile);

        await cubit.submit();

        final captured = verify(() => service.createTicket(
              type: any(named: 'type'),
              reason: any(named: 'reason'),
              name: any(named: 'name'),
              message: any(named: 'message'),
              file: captureAny(named: 'file'),
              fileName: captureAny(named: 'fileName'),
            )).captured;
        final sentFile = captured[0] as String?;
        final sentName = captured[1] as String?;
        expect(sentFile, isNotNull);
        expect(sentFile, startsWith('data:image/jpeg;base64,'));
        expect(sentName, 'hoist.jpg');
      },
    );

    test('selectType is a no-op while isSubmitting is true', () async {
      final hang = Completer<SupportIssueDto>();
      when(() => service.createTicket(
            type: any(named: 'type'),
            reason: any(named: 'reason'),
            name: any(named: 'name'),
            message: any(named: 'message'),
            file: any(named: 'file'),
            fileName: any(named: 'fileName'),
          )).thenAnswer((_) => hang.future);

      final cubit = SupportCreateTicketCubit(service);
      cubit.selectType(SupportIssueType.bugReport);
      cubit.selectReason(SupportIssueReason.other);
      cubit.updateMessage('hold type');

      final pending = cubit.submit();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.isSubmitting, isTrue);
      expect(cubit.state.selectedType, SupportIssueType.bugReport);

      cubit.selectType(SupportIssueType.genericIssue);

      expect(cubit.state.isSubmitting, isTrue);
      expect(cubit.state.selectedType, SupportIssueType.bugReport);

      hang.complete(_ticket());
      await pending;
    });

    test(
      'submit hoists type/reason/message: createTicket uses submit-time values '
      'even if state is force-changed during toBase64DataUri',
      () async {
        when(() => service.createTicket(
              type: any(named: 'type'),
              reason: any(named: 'reason'),
              name: any(named: 'name'),
              message: any(named: 'message'),
              file: any(named: 'file'),
              fileName: any(named: 'fileName'),
            )).thenAnswer((_) async => _ticket());

        final cubit = _ProbeCreateTicketCubit(service);
        final path = writeTempFile('type_hoist.jpg', [1, 1, 1]).path;
        final raceFile = _RaceXFile(
          path,
          mimeType: 'image/jpeg',
          onRead: () {
            cubit.forceState(
              cubit.state.copyWith(
                selectedType: SupportIssueType.genericIssue,
                selectedReason: SupportIssueReason.fundsNotReceived,
                message: 'changed after submit',
              ),
            );
            expect(cubit.state.selectedType, SupportIssueType.genericIssue);
            expect(cubit.state.isSubmitting, isTrue);
          },
        );
        cubit.selectType(SupportIssueType.bugReport);
        cubit.selectReason(SupportIssueReason.other);
        cubit.updateMessage('original message');
        cubit.selectAttachment(raceFile);

        await cubit.submit();

        verify(() => service.createTicket(
              type: SupportIssueType.bugReport,
              reason: SupportIssueReason.other,
              name: 'Bug Report',
              message: 'original message',
              file: any(named: 'file'),
              fileName: 'type_hoist.jpg',
            )).called(1);
      },
    );

    test('updateMessage is a no-op while isSubmitting is true', () async {
      final hang = Completer<SupportIssueDto>();
      when(() => service.createTicket(
            type: any(named: 'type'),
            reason: any(named: 'reason'),
            name: any(named: 'name'),
            message: any(named: 'message'),
            file: any(named: 'file'),
            fileName: any(named: 'fileName'),
          )).thenAnswer((_) => hang.future);

      final cubit = SupportCreateTicketCubit(service);
      cubit.selectType(SupportIssueType.bugReport);
      cubit.selectReason(SupportIssueReason.other);
      cubit.updateMessage('hold message');

      final pending = cubit.submit();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.isSubmitting, isTrue);

      cubit.updateMessage('mutated during submit');

      expect(cubit.state.message, 'hold message');

      hang.complete(_ticket());
      await pending;
    });

    test('selectReason is a no-op while isSubmitting is true', () async {
      final hang = Completer<SupportIssueDto>();
      when(() => service.createTicket(
            type: any(named: 'type'),
            reason: any(named: 'reason'),
            name: any(named: 'name'),
            message: any(named: 'message'),
            file: any(named: 'file'),
            fileName: any(named: 'fileName'),
          )).thenAnswer((_) => hang.future);

      final cubit = SupportCreateTicketCubit(service);
      cubit.selectType(SupportIssueType.bugReport);
      cubit.selectReason(SupportIssueReason.other);
      cubit.updateMessage('hold reason');

      final pending = cubit.submit();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.isSubmitting, isTrue);

      cubit.selectReason(SupportIssueReason.fundsNotReceived);

      expect(cubit.state.selectedReason, SupportIssueReason.other);

      hang.complete(_ticket());
      await pending;
    });

    test(
      'submit after close does not throw and does not emit',
      () async {
        when(() => service.createTicket(
              type: any(named: 'type'),
              reason: any(named: 'reason'),
              name: any(named: 'name'),
              message: any(named: 'message'),
              file: any(named: 'file'),
              fileName: any(named: 'fileName'),
            )).thenAnswer((_) async => _ticket());

        final cubit = SupportCreateTicketCubit(service);
        cubit.selectType(SupportIssueType.bugReport);
        cubit.selectReason(SupportIssueReason.other);
        cubit.updateMessage('after close');

        final emitted = <SupportCreateTicketState>[];
        final sub = cubit.stream.listen(emitted.add);
        await cubit.close();
        final countAtClose = emitted.length;

        await cubit.submit();
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();

        expect(emitted.length, countAtClose);
        verifyNever(() => service.createTicket(
              type: any(named: 'type'),
              reason: any(named: 'reason'),
              name: any(named: 'name'),
              message: any(named: 'message'),
              file: any(named: 'file'),
              fileName: any(named: 'fileName'),
            ));
      },
    );

    test(
      'submit does not emit after close while createTicket is in flight (success)',
      () async {
        final hang = Completer<SupportIssueDto>();
        when(() => service.createTicket(
              type: any(named: 'type'),
              reason: any(named: 'reason'),
              name: any(named: 'name'),
              message: any(named: 'message'),
              file: any(named: 'file'),
              fileName: any(named: 'fileName'),
            )).thenAnswer((_) => hang.future);

        final cubit = SupportCreateTicketCubit(service);
        cubit.selectType(SupportIssueType.bugReport);
        cubit.selectReason(SupportIssueReason.other);
        cubit.updateMessage('in flight');

        final emitted = <SupportCreateTicketState>[];
        final sub = cubit.stream.listen(emitted.add);
        final pending = cubit.submit();
        await Future<void>.delayed(Duration.zero);
        expect(cubit.state.isSubmitting, isTrue);

        final countAtClose = emitted.length;
        await cubit.close();
        hang.complete(_ticket());
        await pending;
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();

        expect(emitted.length, countAtClose);
        // Last emit before close was isSubmitting:true — no success emit.
        expect(cubit.state.isSuccess, isFalse);
      },
    );

    test(
      'submit does not emit after close while createTicket is in flight (error)',
      () async {
        final hang = Completer<SupportIssueDto>();
        when(() => service.createTicket(
              type: any(named: 'type'),
              reason: any(named: 'reason'),
              name: any(named: 'name'),
              message: any(named: 'message'),
              file: any(named: 'file'),
              fileName: any(named: 'fileName'),
            )).thenAnswer((_) => hang.future);

        final cubit = SupportCreateTicketCubit(service);
        cubit.selectType(SupportIssueType.bugReport);
        cubit.selectReason(SupportIssueReason.other);
        cubit.updateMessage('in flight fail');

        final emitted = <SupportCreateTicketState>[];
        final sub = cubit.stream.listen(emitted.add);
        final pending = cubit.submit();
        await Future<void>.delayed(Duration.zero);

        final countAtClose = emitted.length;
        await cubit.close();
        hang.completeError(Exception('rate limited'));
        await pending;
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();

        expect(emitted.length, countAtClose);
        expect(cubit.state.error, isNull);
      },
    );
  });
}
