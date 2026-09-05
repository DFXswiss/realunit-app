import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_summary_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_referral_service.dart';
import 'package:realunit_wallet/screens/referral/cubit/referral_eligibility_cubit.dart';

class _MockService extends Mock implements RealUnitReferralService {}

void main() {
  late _MockService service;
  late Completer<ReferralSummaryDto> loadRelease;

  setUp(() {
    service = _MockService();
  });

  blocTest<ReferralEligibilityCubit, ReferralEligibilityState>(
    'emits eligible from the API gate 1:1',
    build: () {
      when(() => service.getSummary()).thenAnswer(
        (_) async => const ReferralSummaryDto(
          eligible: true,
          termsAccepted: true,
          openCount: 0,
          creditedCount: 0,
          realuSum: 0,
          chfSum: 0,
        ),
      );
      return ReferralEligibilityCubit(service);
    },
    act: (cubit) => cubit.load(),
    expect: () => const [
      ReferralEligibilityLoading(),
      ReferralEligibilityLoaded(eligible: true),
    ],
  );

  blocTest<ReferralEligibilityCubit, ReferralEligibilityState>(
    'hides the entry when summary is an unmounted NestJS route',
    build: () {
      when(() => service.getSummary()).thenThrow(
        const ApiException(
          statusCode: 404,
          code: 'NOT_FOUND',
          message: 'Cannot GET /v1/realunit/referral/summary',
        ),
      );
      return ReferralEligibilityCubit(service);
    },
    act: (cubit) => cubit.load(),
    expect: () => const [
      ReferralEligibilityLoading(),
      ReferralEligibilityLoaded(eligible: false, unavailable: true),
    ],
    verify: (_) {
      verify(() => service.getSummary()).called(2);
    },
  );

  blocTest<ReferralEligibilityCubit, ReferralEligibilityState>(
    'hides the entry when the API call fails',
    build: () {
      when(() => service.getSummary()).thenThrow(Exception('down'));
      return ReferralEligibilityCubit(service);
    },
    act: (cubit) => cubit.load(),
    expect: () => const [
      ReferralEligibilityLoading(),
      ReferralEligibilityLoaded(eligible: false, unavailable: true),
    ],
  );

  blocTest<ReferralEligibilityCubit, ReferralEligibilityState>(
    'hides the entry when live holding lookup failed (TB Ziff. 2)',
    build: () {
      when(() => service.getSummary()).thenThrow(
        const ApiException(
          statusCode: 503,
          code: 'UNAVAILABLE',
          message: 'holding lookup failed',
        ),
      );
      return ReferralEligibilityCubit(service);
    },
    act: (cubit) => cubit.load(),
    expect: () => const [
      ReferralEligibilityLoading(),
      ReferralEligibilityLoaded(eligible: false, unavailable: true),
    ],
  );

  blocTest<ReferralEligibilityCubit, ReferralEligibilityState>(
    'retries once after a transient summary failure',
    build: () {
      var calls = 0;
      when(() => service.getSummary()).thenAnswer((_) async {
        calls++;
        if (calls == 1) throw Exception('down');
        return const ReferralSummaryDto(
          eligible: true,
          termsAccepted: true,
          openCount: 0,
          creditedCount: 0,
          realuSum: 0,
          chfSum: 0,
        );
      });
      return ReferralEligibilityCubit(service);
    },
    act: (cubit) => cubit.load(),
    expect: () => const [
      ReferralEligibilityLoading(),
      ReferralEligibilityLoaded(eligible: true),
    ],
  );

  blocTest<ReferralEligibilityCubit, ReferralEligibilityState>(
    'hides the entry on a timed-out summary without a second GET',
    build: () {
      when(() => service.getSummary()).thenThrow(
        TimeoutException('summary'),
      );
      return ReferralEligibilityCubit(service);
    },
    act: (cubit) => cubit.load(),
    expect: () => const [
      ReferralEligibilityLoading(),
      ReferralEligibilityLoaded(eligible: false, unavailable: true),
    ],
    verify: (_) {
      verify(() => service.getSummary()).called(1);
    },
  );

  blocTest<ReferralEligibilityCubit, ReferralEligibilityState>(
    'load ignores a second call while summary is in flight',
    build: () {
      loadRelease = Completer<ReferralSummaryDto>();
      when(() => service.getSummary()).thenAnswer((_) => loadRelease.future);
      return ReferralEligibilityCubit(service);
    },
    act: (cubit) async {
      final first = cubit.load();
      final second = cubit.load();
      loadRelease.complete(
        const ReferralSummaryDto(
          eligible: true,
          termsAccepted: true,
          openCount: 0,
          creditedCount: 0,
          realuSum: 0,
          chfSum: 0,
        ),
      );
      await first;
      await second;
    },
    expect: () => const [
      ReferralEligibilityLoading(),
      ReferralEligibilityLoaded(eligible: true),
    ],
    verify: (_) {
      verify(() => service.getSummary()).called(1);
    },
  );

  blocTest<ReferralEligibilityCubit, ReferralEligibilityState>(
    'load does not emit after the cubit is closed mid-flight',
    build: () {
      loadRelease = Completer<ReferralSummaryDto>();
      when(() => service.getSummary()).thenAnswer((_) => loadRelease.future);
      return ReferralEligibilityCubit(service);
    },
    act: (cubit) async {
      final pending = cubit.load();
      await cubit.close();
      loadRelease.complete(
        const ReferralSummaryDto(
          eligible: true,
          termsAccepted: true,
          openCount: 0,
          creditedCount: 0,
          realuSum: 0,
          chfSum: 0,
        ),
      );
      await pending;
    },
    // Only the synchronous Loading survives: the post-await emit is guarded by
    // `isClosed`, so no ReferralEligibilityLoaded is emitted after close (and
    // no emit-after-close StateError is thrown).
    expect: () => const [
      ReferralEligibilityLoading(),
    ],
  );

  blocTest<ReferralEligibilityCubit, ReferralEligibilityState>(
    'reload opens the gate after a failed first load',
    build: () {
      var calls = 0;
      when(() => service.getSummary()).thenAnswer((_) async {
        calls++;
        if (calls <= 2) {
          throw const ApiException(
            statusCode: 404,
            code: 'NOT_FOUND',
            message: 'Cannot GET /v1/realunit/referral/summary',
          );
        }
        return const ReferralSummaryDto(
          eligible: true,
          termsAccepted: true,
          openCount: 0,
          creditedCount: 0,
          realuSum: 0,
          chfSum: 0,
        );
      });
      return ReferralEligibilityCubit(service);
    },
    act: (cubit) async {
      await cubit.load();
      await cubit.reload();
    },
    expect: () => const [
      ReferralEligibilityLoading(),
      ReferralEligibilityLoaded(eligible: false, unavailable: true),
      ReferralEligibilityLoaded(eligible: true),
    ],
  );

  blocTest<ReferralEligibilityCubit, ReferralEligibilityState>(
    'reload does not hide a tile that is already shown',
    build: () {
      var calls = 0;
      when(() => service.getSummary()).thenAnswer((_) async {
        calls++;
        if (calls == 1) {
          return const ReferralSummaryDto(
            eligible: true,
            termsAccepted: true,
            openCount: 0,
            creditedCount: 0,
            realuSum: 0,
            chfSum: 0,
          );
        }
        throw Exception('down');
      });
      return ReferralEligibilityCubit(service);
    },
    act: (cubit) async {
      await cubit.load();
      await cubit.reload();
    },
    expect: () => const [
      ReferralEligibilityLoading(),
      ReferralEligibilityLoaded(eligible: true),
    ],
  );

  blocTest<ReferralEligibilityCubit, ReferralEligibilityState>(
    'reload does not hide a tile that is already shown on timeout',
    build: () {
      var calls = 0;
      when(() => service.getSummary()).thenAnswer((_) async {
        calls++;
        if (calls == 1) {
          return const ReferralSummaryDto(
            eligible: true,
            termsAccepted: true,
            openCount: 0,
            creditedCount: 0,
            realuSum: 0,
            chfSum: 0,
          );
        }
        throw TimeoutException('summary');
      });
      return ReferralEligibilityCubit(service);
    },
    act: (cubit) async {
      await cubit.load();
      await cubit.reload();
    },
    expect: () => const [
      ReferralEligibilityLoading(),
      ReferralEligibilityLoaded(eligible: true),
    ],
  );

  blocTest<ReferralEligibilityCubit, ReferralEligibilityState>(
    'reload from initial hides the tile on a timed-out summary',
    build: () {
      when(() => service.getSummary()).thenThrow(
        TimeoutException('summary'),
      );
      return ReferralEligibilityCubit(service);
    },
    act: (cubit) => cubit.reload(),
    expect: () => const [
      ReferralEligibilityLoaded(eligible: false, unavailable: true),
    ],
  );

  blocTest<ReferralEligibilityCubit, ReferralEligibilityState>(
    'reload from initial hides the tile when the API call fails',
    build: () {
      when(() => service.getSummary()).thenThrow(Exception('down'));
      return ReferralEligibilityCubit(service);
    },
    act: (cubit) => cubit.reload(),
    expect: () => const [
      ReferralEligibilityLoaded(eligible: false, unavailable: true),
    ],
  );
}
