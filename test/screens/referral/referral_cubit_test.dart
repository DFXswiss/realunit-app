import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_created_invite_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_invite_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_summary_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_referral_service.dart';
import 'package:realunit_wallet/screens/referral/cubit/referral_cubit.dart';
import 'package:realunit_wallet/screens/referral/referral_error_message.dart';
import 'package:realunit_wallet/screens/referral/referral_limits.dart';

class _MockService extends Mock implements RealUnitReferralService {}

const _eligible = ReferralSummaryDto(
  eligible: true,
  termsAccepted: true,
  openCount: 1,
  creditedCount: 0,
  realuSum: 0,
  chfSum: 0,
);

const _needsTerms = ReferralSummaryDto(
  eligible: true,
  termsAccepted: false,
  openCount: 0,
  creditedCount: 0,
  realuSum: 0,
  chfSum: 0,
);

void main() {
  late _MockService service;
  late Completer<ReferralSummaryDto> loadRelease;
  late Completer<ReferralSummaryDto> refreshRelease;
  late Completer<List<ReferralInviteDto>> staleInvites;
  late Completer<void> acceptRelease;

  setUp(() {
    service = _MockService();
  });

  blocTest<ReferralCubit, ReferralState>(
    'load emits not-eligible when the API gate is closed',
    build: () {
      when(() => service.getSummary()).thenAnswer(
        (_) async => const ReferralSummaryDto(
          eligible: false,
          termsAccepted: false,
          openCount: 0,
          creditedCount: 0,
          realuSum: 0,
          chfSum: 0,
        ),
      );
      return ReferralCubit(service);
    },
    act: (cubit) => cubit.load(),
    expect: () => const [
      ReferralLoading(),
      ReferralNotEligible(),
    ],
  );

  blocTest<ReferralCubit, ReferralState>(
    'load emits needs-terms when eligible but terms are not accepted',
    build: () {
      when(() => service.getSummary()).thenAnswer((_) async => _needsTerms);
      return ReferralCubit(service);
    },
    act: (cubit) => cubit.load(),
    expect: () => [
      const ReferralLoading(),
      ReferralNeedsTerms(summary: _needsTerms),
    ],
  );

  blocTest<ReferralCubit, ReferralState>(
    'load emits overview when eligible and terms accepted',
    build: () {
      when(() => service.getSummary()).thenAnswer((_) async => _eligible);
      when(() => service.getInvites()).thenAnswer((_) async => []);
      return ReferralCubit(service);
    },
    act: (cubit) => cubit.load(),
    expect: () => [
      const ReferralLoading(),
      ReferralOverviewLoaded(summary: _eligible, invites: const []),
    ],
  );

  blocTest<ReferralCubit, ReferralState>(
    'acceptTerms posts acceptance then loads overview',
    build: () {
      when(() => service.acceptTerms()).thenAnswer((_) async {});
      when(() => service.getSummary()).thenAnswer((_) async => _eligible);
      when(() => service.getInvites()).thenAnswer((_) async => []);
      return ReferralCubit(service);
    },
    seed: () => ReferralNeedsTerms(summary: _needsTerms),
    act: (cubit) => cubit.acceptTerms(),
    expect: () => [
      ReferralTermsAccepting(summary: _needsTerms),
      ReferralOverviewLoaded(summary: _eligible, invites: const []),
    ],
  );

  blocTest<ReferralCubit, ReferralState>(
    'acceptTerms returns to the checkbox with the API error',
    build: () {
      when(() => service.acceptTerms()).thenThrow(
        const ApiException(code: 'FAILED', message: 'nope'),
      );
      return ReferralCubit(service);
    },
    seed: () => ReferralNeedsTerms(summary: _needsTerms),
    act: (cubit) => cubit.acceptTerms(),
    expect: () => [
      ReferralTermsAccepting(summary: _needsTerms),
      ReferralNeedsTerms(
        summary: _needsTerms,
        errorMessage: referralUnavailableMessage,
      ),
    ],
  );

  blocTest<ReferralCubit, ReferralState>(
    'acceptTerms keeps the previous error while the retry POST is in flight',
    build: () {
      when(() => service.acceptTerms()).thenAnswer((_) async {});
      when(() => service.getSummary()).thenAnswer((_) async => _eligible);
      when(() => service.getInvites()).thenAnswer((_) async => []);
      return ReferralCubit(service);
    },
    seed: () => ReferralNeedsTerms(summary: _needsTerms, errorMessage: 'nope'),
    act: (cubit) => cubit.acceptTerms(),
    expect: () => [
      ReferralTermsAccepting(summary: _needsTerms, errorMessage: 'nope'),
      ReferralOverviewLoaded(summary: _eligible, invites: const []),
    ],
  );

  blocTest<ReferralCubit, ReferralState>(
    'acceptTerms ignores a second call while the POST is in flight',
    build: () {
      acceptRelease = Completer<void>();
      when(() => service.acceptTerms()).thenAnswer((_) => acceptRelease.future);
      when(() => service.getSummary()).thenAnswer((_) async => _eligible);
      when(() => service.getInvites()).thenAnswer((_) async => []);
      return ReferralCubit(service);
    },
    seed: () => ReferralNeedsTerms(summary: _needsTerms),
    act: (cubit) async {
      final first = cubit.acceptTerms();
      final second = cubit.acceptTerms();
      acceptRelease.complete();
      await first;
      await second;
    },
    verify: (_) {
      verify(() => service.acceptTerms()).called(1);
    },
  );

  blocTest<ReferralCubit, ReferralState>(
    'refreshOverview reloads counts after a new invite',
    build: () {
      when(() => service.getSummary()).thenAnswer((_) async => _eligible);
      when(() => service.getInvites()).thenAnswer((_) async => []);
      return ReferralCubit(service);
    },
    seed: () => ReferralInviteCreated(
      summary: _eligible,
      invite: const ReferralCreatedInviteDto(
        code: 'AB12',
        url: 'https://realunit.app/invite/AB12',
        guestName: 'Alice',
      ),
    ),
    act: (cubit) => cubit.refreshOverview(),
    expect: () => [
      ReferralOverviewLoaded(summary: _eligible, invites: const []),
    ],
  );

  blocTest<ReferralCubit, ReferralState>(
    'refreshOverview ignores a second call while summary is in flight',
    build: () {
      refreshRelease = Completer<ReferralSummaryDto>();
      when(() => service.getSummary()).thenAnswer((_) => refreshRelease.future);
      when(() => service.getInvites()).thenAnswer((_) async => []);
      return ReferralCubit(service);
    },
    seed: () => ReferralInviteCreated(
      summary: _eligible,
      invite: const ReferralCreatedInviteDto(
        code: 'AB12',
        url: 'https://realunit.app/invite/AB12',
        guestName: 'Alice',
      ),
    ),
    act: (cubit) async {
      final first = cubit.refreshOverview();
      final second = cubit.refreshOverview();
      refreshRelease.complete(_eligible);
      await first;
      await second;
    },
    expect: () => [
      ReferralOverviewLoaded(summary: _eligible, invites: const []),
    ],
    verify: (_) {
      verify(() => service.getSummary()).called(1);
    },
  );

  blocTest<ReferralCubit, ReferralState>(
    'refreshOverview keeps overview tiles when the summary call fails',
    build: () {
      when(() => service.getSummary()).thenThrow(
        const ApiException(code: 'SERVER_ERROR', message: 'down'),
      );
      return ReferralCubit(service);
    },
    seed: () => ReferralOverviewLoaded(summary: _eligible, invites: const []),
    act: (cubit) => cubit.refreshOverview(),
    expect: () => <ReferralState>[],
  );

  blocTest<ReferralCubit, ReferralState>(
    'createInvite emits the created invite from the API',
    build: () {
      when(() => service.createInvite(guestName: 'Alice')).thenAnswer(
        (_) async => const ReferralCreatedInviteDto(
          code: 'AB12',
          url: 'https://realunit.app/invite/AB12',
          guestName: 'Alice',
        ),
      );
      return ReferralCubit(service);
    },
    seed: () => ReferralCreateReady(summary: _eligible),
    act: (cubit) => cubit.createInvite(guestName: 'Alice'),
    expect: () => [
      ReferralCreating(summary: _eligible, guestName: 'Alice'),
      ReferralInviteCreated(
        summary: _eligible,
        invite: const ReferralCreatedInviteDto(
          code: 'AB12',
          url: 'https://realunit.app/invite/AB12',
          guestName: 'Alice',
        ),
      ),
    ],
  );

  blocTest<ReferralCubit, ReferralState>(
    'createInvite maps NOT_ELIGIBLE to the gate screen',
    build: () {
      when(() => service.createInvite(guestName: 'Alice')).thenThrow(
        const ApiException(
          statusCode: 403,
          code: 'NOT_ELIGIBLE',
          message: 'holding below min',
        ),
      );
      return ReferralCubit(service);
    },
    seed: () => ReferralCreateReady(summary: _eligible),
    act: (cubit) => cubit.createInvite(guestName: 'Alice'),
    expect: () => [
      ReferralCreating(summary: _eligible, guestName: 'Alice'),
      const ReferralNotEligible(),
    ],
  );

  blocTest<ReferralCubit, ReferralState>(
    'createInvite maps NEEDS_TERMS to the terms screen',
    build: () {
      when(() => service.createInvite(guestName: 'Alice')).thenThrow(
        const ApiException(
          statusCode: 409,
          code: 'NEEDS_TERMS',
          message: 'terms not accepted',
        ),
      );
      return ReferralCubit(service);
    },
    seed: () => ReferralCreateReady(summary: _eligible),
    act: (cubit) => cubit.createInvite(guestName: 'Alice'),
    expect: () => [
      ReferralCreating(summary: _eligible, guestName: 'Alice'),
      ReferralNeedsTerms(summary: _eligible),
    ],
  );

  blocTest<ReferralCubit, ReferralState>(
    'createInvite surfaces the API error on the name-entry form',
    build: () {
      when(() => service.createInvite(guestName: 'Alice')).thenThrow(
        const ApiException(code: 'QUOTA', message: 'limit'),
      );
      return ReferralCubit(service);
    },
    seed: () => ReferralCreateReady(summary: _eligible),
    act: (cubit) => cubit.createInvite(guestName: 'Alice'),
    expect: () => [
      ReferralCreating(summary: _eligible, guestName: 'Alice'),
      ReferralCreateReady(
        summary: _eligible,
        errorMessage: referralQuotaMessage,
      ),
    ],
  );

  blocTest<ReferralCubit, ReferralState>(
    'createInvite maps 503 holding lookup failed to the unavailable token',
    build: () {
      when(() => service.createInvite(guestName: 'Alice')).thenThrow(
        const ApiException(
          statusCode: 503,
          code: 'UNAVAILABLE',
          message: 'holding lookup failed',
        ),
      );
      return ReferralCubit(service);
    },
    seed: () => ReferralCreateReady(summary: _eligible),
    act: (cubit) => cubit.createInvite(guestName: 'Alice'),
    expect: () => [
      ReferralCreating(summary: _eligible, guestName: 'Alice'),
      ReferralCreateReady(
        summary: _eligible,
        errorMessage: referralUnavailableMessage,
      ),
    ],
  );

  blocTest<ReferralCubit, ReferralState>(
    'createInvite keeps the previous error while the retry POST is in flight',
    build: () {
      when(() => service.createInvite(guestName: 'Alice')).thenAnswer(
        (_) async => const ReferralCreatedInviteDto(
          code: 'AB12',
          url: 'https://realunit.app/invite/AB12',
          guestName: 'Alice',
        ),
      );
      return ReferralCubit(service);
    },
    seed: () => ReferralCreateReady(summary: _eligible, errorMessage: 'limit'),
    act: (cubit) => cubit.createInvite(guestName: 'Alice'),
    expect: () => [
      ReferralCreating(
        summary: _eligible,
        guestName: 'Alice',
        errorMessage: 'limit',
      ),
      ReferralInviteCreated(
        summary: _eligible,
        invite: const ReferralCreatedInviteDto(
          code: 'AB12',
          url: 'https://realunit.app/invite/AB12',
          guestName: 'Alice',
        ),
      ),
    ],
  );

  blocTest<ReferralCubit, ReferralState>(
    'openCreate moves from overview to the name-entry form',
    build: () => ReferralCubit(service),
    seed: () => ReferralOverviewLoaded(summary: _eligible, invites: const []),
    act: (cubit) => cubit.openCreate(),
    expect: () => [
      ReferralCreateReady(summary: _eligible),
    ],
  );

  blocTest<ReferralCubit, ReferralState>(
    'openCreate moves from a created invite back to the name-entry form',
    build: () => ReferralCubit(service),
    seed: () => ReferralInviteCreated(
      summary: _eligible,
      invite: const ReferralCreatedInviteDto(
        code: 'AB12',
        url: 'https://realunit.app/invite/AB12',
        guestName: 'Alice',
      ),
    ),
    act: (cubit) => cubit.openCreate(),
    expect: () => [
      ReferralCreateReady(summary: _eligible),
    ],
  );

  blocTest<ReferralCubit, ReferralState>(
    'acceptTerms still shows overview when the invite list is down',
    build: () {
      when(() => service.acceptTerms()).thenAnswer((_) async {});
      when(() => service.getSummary()).thenAnswer((_) async => _eligible);
      when(() => service.getInvites()).thenThrow(
        const ApiException(code: 'SERVER_ERROR', message: 'invites down'),
      );
      return ReferralCubit(service);
    },
    seed: () => ReferralNeedsTerms(summary: _needsTerms),
    act: (cubit) => cubit.acceptTerms(),
    expect: () => [
      ReferralTermsAccepting(summary: _needsTerms),
      ReferralOverviewLoaded(
        summary: _eligible,
        invites: const [],
        invitesError: referralUnavailableMessage,
      ),
    ],
  );

  blocTest<ReferralCubit, ReferralState>(
    'load shows overview counts when the invite list is down',
    build: () {
      when(() => service.getSummary()).thenAnswer((_) async => _eligible);
      when(() => service.getInvites()).thenThrow(
        const ApiException(code: 'SERVER_ERROR', message: 'invites down'),
      );
      return ReferralCubit(service);
    },
    act: (cubit) => cubit.load(),
    expect: () => [
      const ReferralLoading(),
      ReferralOverviewLoaded(
        summary: _eligible,
        invites: const [],
        invitesError: referralUnavailableMessage,
      ),
    ],
  );

  blocTest<ReferralCubit, ReferralState>(
    'reloadInvites replaces open-invite rows without hiding the summary',
    build: () {
      when(() => service.getInvites()).thenAnswer(
        (_) async => [
          ReferralInviteDto(
            id: 1,
            code: 'AAAA',
            url: 'https://realunit.app/invite/AAAA',
            guestName: 'Alice',
            status: 'Open',
            created: DateTime.utc(2026, 8, 1),
          ),
        ],
      );
      return ReferralCubit(service);
    },
    seed: () => ReferralOverviewLoaded(summary: _eligible, invites: const []),
    act: (cubit) => cubit.reloadInvites(),
    expect: () => [
      ReferralOverviewLoaded(
        summary: _eligible,
        invites: const [],
        invitesLoading: true,
      ),
      ReferralOverviewLoaded(
        summary: _eligible,
        invites: [
          ReferralInviteDto(
            id: 1,
            code: 'AAAA',
            url: 'https://realunit.app/invite/AAAA',
            guestName: 'Alice',
            status: 'Open',
            created: DateTime.utc(2026, 8, 1),
          ),
        ],
      ),
    ],
  );

  blocTest<ReferralCubit, ReferralState>(
    'reloadInvites keeps the current overview when the list is still down',
    build: () {
      when(() => service.getInvites()).thenThrow(
        const ApiException(code: 'SERVER_ERROR', message: 'invites down'),
      );
      return ReferralCubit(service);
    },
    seed: () => ReferralOverviewLoaded(summary: _eligible, invites: const []),
    act: (cubit) => cubit.reloadInvites(),
    expect: () => [
      ReferralOverviewLoaded(
        summary: _eligible,
        invites: const [],
        invitesLoading: true,
      ),
      ReferralOverviewLoaded(
        summary: _eligible,
        invites: const [],
        invitesError: referralUnavailableMessage,
      ),
    ],
  );

  blocTest<ReferralCubit, ReferralState>(
    'reloadInvites keeps a previous list error while the retry is in flight',
    build: () {
      when(() => service.getInvites()).thenAnswer((_) async => const []);
      return ReferralCubit(service);
    },
    seed: () => ReferralOverviewLoaded(
      summary: _eligible,
      invites: const [],
      invitesError: 'invites down',
    ),
    act: (cubit) => cubit.reloadInvites(),
    expect: () => [
      ReferralOverviewLoaded(
        summary: _eligible,
        invites: const [],
        invitesError: 'invites down',
        invitesLoading: true,
      ),
      ReferralOverviewLoaded(summary: _eligible, invites: const []),
    ],
  );

  blocTest<ReferralCubit, ReferralState>(
    'reloadInvites ignores a call while overview refresh is in flight',
    build: () {
      refreshRelease = Completer<ReferralSummaryDto>();
      when(() => service.getSummary()).thenAnswer((_) => refreshRelease.future);
      when(() => service.getInvites()).thenAnswer((_) async => []);
      return ReferralCubit(service);
    },
    seed: () => ReferralOverviewLoaded(summary: _eligible, invites: const []),
    act: (cubit) async {
      final refresh = cubit.refreshOverview();
      final reload = cubit.reloadInvites();
      refreshRelease.complete(_eligible);
      await refresh;
      await reload;
    },
    verify: (_) {
      verify(() => service.getInvites()).called(1);
    },
  );

  blocTest<ReferralCubit, ReferralState>(
    'reloadInvites discards a stale list after a later overview refresh',
    build: () {
      staleInvites = Completer<List<ReferralInviteDto>>();
      var inviteCalls = 0;
      when(() => service.getInvites()).thenAnswer((_) {
        inviteCalls += 1;
        if (inviteCalls == 1) return staleInvites.future;
        return Future<List<ReferralInviteDto>>.value(const []);
      });
      when(() => service.getSummary()).thenAnswer((_) async => _eligible);
      return ReferralCubit(service);
    },
    seed: () => ReferralOverviewLoaded(summary: _eligible, invites: const []),
    act: (cubit) async {
      final reload = cubit.reloadInvites();
      final refresh = cubit.refreshOverview();
      await refresh;
      staleInvites.complete([
        ReferralInviteDto(
          id: 9,
          code: 'STALE',
          url: 'https://realunit.app/invite/STALE',
          guestName: 'Old',
          status: 'Open',
          created: DateTime.utc(2026, 8, 1),
        ),
      ]);
      await reload;
    },
    expect: () => [
      ReferralOverviewLoaded(
        summary: _eligible,
        invites: const [],
        invitesLoading: true,
      ),
      ReferralOverviewLoaded(summary: _eligible, invites: const []),
    ],
  );

  blocTest<ReferralCubit, ReferralState>(
    'refreshOverview returns to terms when the API withdraws acceptance',
    build: () {
      when(() => service.getSummary()).thenAnswer((_) async => _needsTerms);
      return ReferralCubit(service);
    },
    seed: () => ReferralOverviewLoaded(summary: _eligible, invites: const []),
    act: (cubit) => cubit.refreshOverview(),
    expect: () => [
      ReferralNeedsTerms(summary: _needsTerms),
    ],
  );

  blocTest<ReferralCubit, ReferralState>(
    'acceptTerms hides the programme when the refreshed gate is closed',
    build: () {
      when(() => service.acceptTerms()).thenAnswer((_) async {});
      when(() => service.getSummary()).thenAnswer(
        (_) async => const ReferralSummaryDto(
          eligible: false,
          termsAccepted: true,
          openCount: 0,
          creditedCount: 0,
          realuSum: 0,
          chfSum: 0,
        ),
      );
      return ReferralCubit(service);
    },
    seed: () => ReferralNeedsTerms(summary: _needsTerms),
    act: (cubit) => cubit.acceptTerms(),
    expect: () => [
      ReferralTermsAccepting(summary: _needsTerms),
      const ReferralNotEligible(),
    ],
  );

  blocTest<ReferralCubit, ReferralState>(
    'refreshOverview hides the programme when the API gate closes',
    build: () {
      when(() => service.getSummary()).thenAnswer(
        (_) async => const ReferralSummaryDto(
          eligible: false,
          termsAccepted: true,
          openCount: 0,
          creditedCount: 0,
          realuSum: 0,
          chfSum: 0,
        ),
      );
      return ReferralCubit(service);
    },
    seed: () => ReferralOverviewLoaded(summary: _eligible, invites: const []),
    act: (cubit) => cubit.refreshOverview(),
    expect: () => const [ReferralNotEligible()],
  );

  blocTest<ReferralCubit, ReferralState>(
    'createInvite truncates a guest name to the field cap',
    build: () {
      when(
        () => service.createInvite(
          guestName: 'A' * maxReferralGuestNameLength,
        ),
      ).thenAnswer(
        (_) async => ReferralCreatedInviteDto(
          code: 'AB12',
          url: 'https://realunit.app/invite/AB12',
          guestName: 'A' * maxReferralGuestNameLength,
        ),
      );
      return ReferralCubit(service);
    },
    seed: () => ReferralCreateReady(summary: _eligible),
    act: (cubit) => cubit.createInvite(guestName: 'A' * 120),
    expect: () => [
      ReferralCreating(
        summary: _eligible,
        guestName: 'A' * maxReferralGuestNameLength,
      ),
      ReferralInviteCreated(
        summary: _eligible,
        invite: ReferralCreatedInviteDto(
          code: 'AB12',
          url: 'https://realunit.app/invite/AB12',
          guestName: 'A' * maxReferralGuestNameLength,
        ),
      ),
    ],
    verify: (_) {
      verify(
        () => service.createInvite(
          guestName: 'A' * maxReferralGuestNameLength,
        ),
      ).called(1);
    },
  );

  blocTest<ReferralCubit, ReferralState>(
    'createInvite collapses newlines in the guest name to a single line',
    build: () {
      when(() => service.createInvite(guestName: 'Alice Bob')).thenAnswer(
        (_) async => const ReferralCreatedInviteDto(
          code: 'AB12',
          url: 'https://realunit.app/invite/AB12',
          guestName: 'Alice Bob',
        ),
      );
      return ReferralCubit(service);
    },
    seed: () => ReferralCreateReady(summary: _eligible),
    act: (cubit) => cubit.createInvite(guestName: ' Alice\nBob\t '),
    expect: () => [
      const ReferralCreating(summary: _eligible, guestName: 'Alice Bob'),
      ReferralInviteCreated(
        summary: _eligible,
        invite: const ReferralCreatedInviteDto(
          code: 'AB12',
          url: 'https://realunit.app/invite/AB12',
          guestName: 'Alice Bob',
        ),
      ),
    ],
    verify: (_) {
      verify(() => service.createInvite(guestName: 'Alice Bob')).called(1);
    },
  );

  blocTest<ReferralCubit, ReferralState>(
    'createInvite ignores a blank guest name',
    build: () => ReferralCubit(service),
    seed: () => ReferralCreateReady(summary: _eligible),
    act: (cubit) => cubit.createInvite(guestName: '   '),
    expect: () => <ReferralState>[],
    verify: (_) {
      verifyNever(() => service.createInvite(guestName: any(named: 'guestName')));
    },
  );

  blocTest<ReferralCubit, ReferralState>(
    'load ignores a second call while summary is in flight',
    build: () {
      loadRelease = Completer<ReferralSummaryDto>();
      when(() => service.getSummary()).thenAnswer((_) => loadRelease.future);
      when(() => service.getInvites()).thenAnswer((_) async => []);
      return ReferralCubit(service);
    },
    act: (cubit) async {
      final first = cubit.load();
      final second = cubit.load();
      loadRelease.complete(_eligible);
      await first;
      await second;
    },
    expect: () => [
      const ReferralLoading(),
      ReferralOverviewLoaded(summary: _eligible, invites: const []),
    ],
    verify: (_) {
      verify(() => service.getSummary()).called(1);
    },
  );

  blocTest<ReferralCubit, ReferralState>(
    'retrying a failed load keeps the error instead of a blank spinner',
    build: () {
      when(() => service.getSummary()).thenAnswer((_) async => _eligible);
      when(() => service.getInvites()).thenAnswer((_) async => []);
      return ReferralCubit(service);
    },
    seed: () => const ReferralFailure(message: 'boom'),
    act: (cubit) => cubit.load(),
    expect: () => [
      const ReferralFailure(message: 'boom', retrying: true),
      ReferralOverviewLoaded(summary: _eligible, invites: const []),
    ],
  );

  blocTest<ReferralCubit, ReferralState>(
    'a second load while failure retry is in flight is ignored',
    build: () {
      loadRelease = Completer<ReferralSummaryDto>();
      when(() => service.getSummary()).thenAnswer((_) => loadRelease.future);
      when(() => service.getInvites()).thenAnswer((_) async => []);
      return ReferralCubit(service);
    },
    seed: () => const ReferralFailure(message: 'boom'),
    act: (cubit) async {
      final first = cubit.load();
      final second = cubit.load();
      loadRelease.complete(_eligible);
      await first;
      await second;
    },
    expect: () => [
      const ReferralFailure(message: 'boom', retrying: true),
      ReferralOverviewLoaded(summary: _eligible, invites: const []),
    ],
    verify: (_) {
      verify(() => service.getSummary()).called(1);
    },
  );

  blocTest<ReferralCubit, ReferralState>(
    'retrying needs-terms keeps the copy instead of a blank spinner',
    build: () {
      when(() => service.getSummary()).thenAnswer((_) async => _eligible);
      when(() => service.getInvites()).thenAnswer((_) async => []);
      return ReferralCubit(service);
    },
    seed: () => ReferralNeedsTerms(summary: _needsTerms),
    act: (cubit) => cubit.load(),
    expect: () => [
      ReferralNeedsTerms(summary: _needsTerms, retrying: true),
      ReferralOverviewLoaded(summary: _eligible, invites: const []),
    ],
  );

  blocTest<ReferralCubit, ReferralState>(
    'a second load while needs-terms retry is in flight is ignored',
    build: () {
      loadRelease = Completer<ReferralSummaryDto>();
      when(() => service.getSummary()).thenAnswer((_) => loadRelease.future);
      when(() => service.getInvites()).thenAnswer((_) async => []);
      return ReferralCubit(service);
    },
    seed: () => ReferralNeedsTerms(summary: _needsTerms),
    act: (cubit) async {
      final first = cubit.load();
      final second = cubit.load();
      loadRelease.complete(_eligible);
      await first;
      await second;
    },
    expect: () => [
      ReferralNeedsTerms(summary: _needsTerms, retrying: true),
      ReferralOverviewLoaded(summary: _eligible, invites: const []),
    ],
    verify: (_) {
      verify(() => service.getSummary()).called(1);
    },
  );

  blocTest<ReferralCubit, ReferralState>(
    'load surfaces API errors',
    build: () {
      when(() => service.getSummary()).thenThrow(
        const ApiException(code: 'SERVER_ERROR', message: 'boom'),
      );
      return ReferralCubit(service);
    },
    act: (cubit) => cubit.load(),
    expect: () => const [
      ReferralLoading(),
      ReferralFailure(message: referralUnavailableMessage),
    ],
  );

  blocTest<ReferralCubit, ReferralState>(
    'load maps a timed-out summary to the unavailable token',
    build: () {
      when(() => service.getSummary()).thenThrow(
        TimeoutException('summary'),
      );
      return ReferralCubit(service);
    },
    act: (cubit) => cubit.load(),
    expect: () => const [
      ReferralLoading(),
      ReferralFailure(message: referralUnavailableMessage),
    ],
  );

  blocTest<ReferralCubit, ReferralState>(
    'load maps an unmounted NestJS summary to the unavailable token',
    build: () {
      when(() => service.getSummary()).thenThrow(
        const ApiException(
          statusCode: 404,
          code: 'NOT_FOUND',
          message: 'Cannot GET /v1/realunit/referral/summary',
        ),
      );
      return ReferralCubit(service);
    },
    act: (cubit) => cubit.load(),
    expect: () => const [
      ReferralLoading(),
      ReferralFailure(message: referralUnavailableMessage),
    ],
  );

  blocTest<ReferralCubit, ReferralState>(
    'load maps 503 persist failure to the unavailable token',
    build: () {
      when(() => service.getSummary()).thenThrow(
        const ApiException(
          statusCode: 503,
          code: 'UNAVAILABLE',
          message: 'persist failed',
        ),
      );
      return ReferralCubit(service);
    },
    act: (cubit) => cubit.load(),
    expect: () => const [
      ReferralLoading(),
      ReferralFailure(message: referralUnavailableMessage),
    ],
  );

  blocTest<ReferralCubit, ReferralState>(
    'load maps 503 holding lookup failed to the unavailable token',
    build: () {
      when(() => service.getSummary()).thenThrow(
        const ApiException(
          statusCode: 503,
          code: 'UNAVAILABLE',
          message: 'holding lookup failed',
        ),
      );
      return ReferralCubit(service);
    },
    act: (cubit) => cubit.load(),
    expect: () => const [
      ReferralLoading(),
      ReferralFailure(message: referralUnavailableMessage),
    ],
  );

  blocTest<ReferralCubit, ReferralState>(
    'acceptTerms maps a timed-out POST back to the checkbox',
    build: () {
      when(() => service.acceptTerms()).thenThrow(TimeoutException('accept'));
      return ReferralCubit(service);
    },
    seed: () => ReferralNeedsTerms(summary: _needsTerms),
    act: (cubit) => cubit.acceptTerms(),
    expect: () => [
      ReferralTermsAccepting(summary: _needsTerms),
      ReferralNeedsTerms(
        summary: _needsTerms,
        errorMessage: referralUnavailableMessage,
      ),
    ],
  );

  blocTest<ReferralCubit, ReferralState>(
    'acceptTerms maps a failed summary refresh to the failure copy',
    build: () {
      when(() => service.acceptTerms()).thenAnswer((_) async {});
      when(() => service.getSummary()).thenThrow(
        const ApiException(code: 'SERVER_ERROR', message: 'down'),
      );
      return ReferralCubit(service);
    },
    seed: () => ReferralNeedsTerms(summary: _needsTerms),
    act: (cubit) => cubit.acceptTerms(),
    expect: () => [
      ReferralTermsAccepting(summary: _needsTerms),
      const ReferralFailure(message: referralUnavailableMessage),
    ],
  );

  blocTest<ReferralCubit, ReferralState>(
    'acceptTerms maps a timed-out summary refresh to the failure copy',
    build: () {
      when(() => service.acceptTerms()).thenAnswer((_) async {});
      when(() => service.getSummary()).thenThrow(TimeoutException('summary'));
      return ReferralCubit(service);
    },
    seed: () => ReferralNeedsTerms(summary: _needsTerms),
    act: (cubit) => cubit.acceptTerms(),
    expect: () => [
      ReferralTermsAccepting(summary: _needsTerms),
      const ReferralFailure(message: referralUnavailableMessage),
    ],
  );

  blocTest<ReferralCubit, ReferralState>(
    'createInvite maps a timed-out POST to the name-entry form',
    build: () {
      when(
        () => service.createInvite(guestName: 'Alice'),
      ).thenThrow(TimeoutException('create'));
      return ReferralCubit(service);
    },
    seed: () => ReferralCreateReady(summary: _eligible),
    act: (cubit) => cubit.createInvite(guestName: 'Alice'),
    expect: () => [
      ReferralCreating(summary: _eligible, guestName: 'Alice'),
      const ReferralCreateReady(
        summary: _eligible,
        errorMessage: referralUnavailableMessage,
      ),
    ],
  );

  blocTest<ReferralCubit, ReferralState>(
    'refreshOverview maps a failed summary to failure when tiles are not shown',
    build: () {
      when(() => service.getSummary()).thenThrow(
        const ApiException(code: 'SERVER_ERROR', message: 'down'),
      );
      return ReferralCubit(service);
    },
    seed: () => ReferralInviteCreated(
      summary: _eligible,
      invite: const ReferralCreatedInviteDto(
        code: 'AB12',
        url: 'https://realunit.app/invite/AB12',
        guestName: 'Alice',
      ),
    ),
    act: (cubit) => cubit.refreshOverview(),
    expect: () => const [
      ReferralFailure(message: referralUnavailableMessage),
    ],
  );

  blocTest<ReferralCubit, ReferralState>(
    'refreshOverview keeps overview tiles when summary times out',
    build: () {
      when(() => service.getSummary()).thenThrow(TimeoutException('summary'));
      return ReferralCubit(service);
    },
    seed: () => ReferralOverviewLoaded(summary: _eligible, invites: const []),
    act: (cubit) => cubit.refreshOverview(),
    expect: () => <ReferralState>[],
  );

  blocTest<ReferralCubit, ReferralState>(
    'refreshOverview maps a timed-out summary to failure when tiles are not shown',
    build: () {
      when(() => service.getSummary()).thenThrow(TimeoutException('summary'));
      return ReferralCubit(service);
    },
    seed: () => ReferralInviteCreated(
      summary: _eligible,
      invite: const ReferralCreatedInviteDto(
        code: 'AB12',
        url: 'https://realunit.app/invite/AB12',
        guestName: 'Alice',
      ),
    ),
    act: (cubit) => cubit.refreshOverview(),
    expect: () => const [
      ReferralFailure(message: referralUnavailableMessage),
    ],
  );

  blocTest<ReferralCubit, ReferralState>(
    'reloadInvites keeps the current overview when the list times out',
    build: () {
      when(() => service.getInvites()).thenThrow(TimeoutException('invites'));
      return ReferralCubit(service);
    },
    seed: () => ReferralOverviewLoaded(summary: _eligible, invites: const []),
    act: (cubit) => cubit.reloadInvites(),
    expect: () => [
      ReferralOverviewLoaded(
        summary: _eligible,
        invites: const [],
        invitesLoading: true,
      ),
      const ReferralOverviewLoaded(
        summary: _eligible,
        invites: [],
        invitesError: referralUnavailableMessage,
      ),
    ],
  );

  blocTest<ReferralCubit, ReferralState>(
    'load shows overview counts when the invite list times out',
    build: () {
      when(() => service.getSummary()).thenAnswer((_) async => _eligible);
      when(() => service.getInvites()).thenThrow(TimeoutException('invites'));
      return ReferralCubit(service);
    },
    act: (cubit) => cubit.load(),
    expect: () => [
      const ReferralLoading(),
      const ReferralOverviewLoaded(
        summary: _eligible,
        invites: [],
        invitesError: referralUnavailableMessage,
      ),
    ],
  );
}
