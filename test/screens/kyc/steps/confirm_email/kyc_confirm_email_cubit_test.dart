import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/models/wallet/real_unit_registration_info_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/wallet/real_unit_registration_state.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_registration_service.dart';
import 'package:realunit_wallet/screens/kyc/steps/confirm_email/cubits/kyc_confirm_email_cubit.dart';

class _MockRealUnitRegistrationService extends Mock
    implements RealUnitRegistrationService {}

RealUnitRegistrationInfoDto _info({bool? emailConfirmed}) =>
    RealUnitRegistrationInfoDto(
      state: RealUnitRegistrationState.alreadyRegistered,
      emailConfirmed: emailConfirmed,
    );

void main() {
  late _MockRealUnitRegistrationService registrationService;

  setUp(() {
    registrationService = _MockRealUnitRegistrationService();
  });

  KycConfirmEmailCubit build() => KycConfirmEmailCubit(registrationService);

  group('initial state', () {
    test('is $KycConfirmEmailInitial', () {
      expect(build().state, isA<KycConfirmEmailInitial>());
    });
  });

  group('recheck', () {
    blocTest<KycConfirmEmailCubit, KycConfirmEmailState>(
      'emailConfirmed=false → NotConfirmed (stays on the gate)',
      setUp: () {
        when(() => registrationService.getRegistrationInfo()).thenAnswer(
          (_) async => _info(emailConfirmed: false),
        );
      },
      build: build,
      act: (c) => c.recheck(),
      expect: () => [
        isA<KycConfirmEmailLoading>(),
        isA<KycConfirmEmailNotConfirmed>(),
      ],
    );

    blocTest<KycConfirmEmailCubit, KycConfirmEmailState>(
      'emailConfirmed=true → Confirmed (proceeds)',
      setUp: () {
        when(() => registrationService.getRegistrationInfo()).thenAnswer(
          (_) async => _info(emailConfirmed: true),
        );
      },
      build: build,
      act: (c) => c.recheck(),
      expect: () => [
        isA<KycConfirmEmailLoading>(),
        isA<KycConfirmEmailConfirmed>(),
      ],
    );

    blocTest<KycConfirmEmailCubit, KycConfirmEmailState>(
      'emailConfirmed=null (legacy / no gate) → Confirmed (proceeds)',
      setUp: () {
        when(() => registrationService.getRegistrationInfo()).thenAnswer(
          (_) async => _info(),
        );
      },
      build: build,
      act: (c) => c.recheck(),
      expect: () => [
        isA<KycConfirmEmailLoading>(),
        isA<KycConfirmEmailConfirmed>(),
      ],
    );

    blocTest<KycConfirmEmailCubit, KycConfirmEmailState>(
      'getRegistrationInfo throws → NotConfirmed (fail closed, retryable)',
      setUp: () {
        when(() => registrationService.getRegistrationInfo()).thenThrow(
          Exception('network error'),
        );
      },
      build: build,
      act: (c) => c.recheck(),
      expect: () => [
        isA<KycConfirmEmailLoading>(),
        isA<KycConfirmEmailNotConfirmed>(),
      ],
    );

    blocTest<KycConfirmEmailCubit, KycConfirmEmailState>(
      'retry: still-false then flips-true → NotConfirmed, then Confirmed',
      setUp: () {
        final answers = [_info(emailConfirmed: false), _info(emailConfirmed: true)];
        var i = 0;
        when(() => registrationService.getRegistrationInfo()).thenAnswer(
          (_) async => answers[i++],
        );
      },
      build: build,
      act: (c) async {
        await c.recheck();
        await c.recheck();
      },
      expect: () => [
        isA<KycConfirmEmailLoading>(),
        isA<KycConfirmEmailNotConfirmed>(),
        isA<KycConfirmEmailLoading>(),
        isA<KycConfirmEmailConfirmed>(),
      ],
    );

    // A stalled request (socket up, backend never responds) must not wedge
    // the button in its loading state forever. `recheck()` watch-dogs the
    // call with a 30s timeout; the resulting `TimeoutException` fails closed
    // to NotConfirmed (retryable). fake_async advances virtual time past the
    // budget without a wallclock sleep. Mirrors the `KycCubit` outer-timeout
    // test.
    test(
      'stalled getRegistrationInfo -> NotConfirmed after the timeout (not stuck loading)',
      () {
        fakeAsync((async) {
          when(() => registrationService.getRegistrationInfo()).thenAnswer(
            (_) => Completer<RealUnitRegistrationInfoDto>().future,
          );

          final cubit = build();
          final states = <KycConfirmEmailState>[];
          final sub = cubit.stream.listen(states.add);

          unawaited(cubit.recheck());
          async.elapse(const Duration(seconds: 31));

          expect(states, const [
            KycConfirmEmailLoading(),
            KycConfirmEmailNotConfirmed(),
          ]);

          sub.cancel();
          cubit.close();
        });
      },
    );

    // Concurrency guards: `Future.timeout` does not cancel the underlying HTTP
    // call, so a late continuation from a superseded tap must not emit over the
    // newer run, and a tap after the cubit closed must not emit at all. These
    // pin the guard branches (the early `return`s) that the happy-path tests
    // above execute but never actually take.
    test(
      'recheck() after close returns early without touching the service (isClosed guard)',
      () async {
        when(() => registrationService.getRegistrationInfo()).thenAnswer(
          (_) async => _info(emailConfirmed: true),
        );

        final cubit = build();
        await cubit.close();

        // Must not throw "Cannot emit after close": the isClosed guard returns
        // before the loading emit, and the service is never reached.
        await cubit.recheck();

        expect(cubit.isClosed, isTrue);
        verifyNever(() => registrationService.getRegistrationInfo());
      },
    );

    test(
      'a superseded recheck bails on the stale generation instead of emitting '
      'over the newer run (catch path)',
      () async {
        final first = Completer<RealUnitRegistrationInfoDto>();
        final second = Completer<RealUnitRegistrationInfoDto>();
        final calls = [first, second];
        var i = 0;
        when(() => registrationService.getRegistrationInfo()).thenAnswer(
          (_) => calls[i++].future,
        );

        final cubit = build();
        final states = <KycConfirmEmailState>[];
        final sub = cubit.stream.listen(states.add);

        unawaited(cubit.recheck());
        unawaited(cubit.recheck());

        // The superseded FIRST call FAILS: the catch block must also bail on the
        // stale generation rather than emit its fail-closed NotConfirmed over
        // the newer run.
        first.completeError(Exception('late failure'));
        await Future<void>.delayed(Duration.zero);
        second.complete(_info(emailConfirmed: true));
        await Future<void>.delayed(Duration.zero);

        expect(states, const [KycConfirmEmailLoading(), KycConfirmEmailConfirmed()]);

        await sub.cancel();
        await cubit.close();
      },
    );

    // A late response from a superseded `recheck()` must not overwrite the
    // fresh state of a newer one. The first call hangs on a `Completer`; a
    // second call resolves immediately to `Confirmed`; when the first call's
    // response finally arrives (still `false`) its generation no longer matches,
    // so it emits nothing. Two back-to-back `Loading`s collapse to one via
    // Equatable, so the expected sequence is `[Loading, Confirmed]`. Mirrors the
    // `KycCubit` generation-counter regression test.
    test(
      'a late response from a superseded recheck does NOT overwrite the fresh Confirmed state',
      () async {
        final call1Completer = Completer<RealUnitRegistrationInfoDto>();
        var firstCall = true;
        when(() => registrationService.getRegistrationInfo()).thenAnswer((_) {
          if (firstCall) {
            firstCall = false;
            return call1Completer.future;
          }
          return Future.value(_info(emailConfirmed: true));
        });

        final cubit = build();
        final states = <KycConfirmEmailState>[];
        final sub = cubit.stream.listen(states.add);

        final call1Future = cubit.recheck();

        await Future<void>.delayed(Duration.zero);

        await cubit.recheck();

        call1Completer.complete(_info(emailConfirmed: false));
        await call1Future;
        await Future<void>.delayed(Duration.zero);

        await sub.cancel();
        await cubit.close();

        expect(states, const [
          KycConfirmEmailLoading(),
          KycConfirmEmailConfirmed(),
        ]);
        expect(cubit.state, const KycConfirmEmailConfirmed());
      },
    );
  });
}
