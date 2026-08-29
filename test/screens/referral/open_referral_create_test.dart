import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/screens/referral/cubit/referral_cubit.dart';
import 'package:realunit_wallet/screens/referral/open_referral_create.dart';
import 'package:realunit_wallet/setup/routing/routes/settings_routes.dart';

class _MockReferralCubit extends MockCubit<ReferralState>
    implements ReferralCubit {}

void main() {
  late _MockReferralCubit cubit;

  setUp(() {
    debugResetOpeningReferralCreate();
    cubit = _MockReferralCubit();
    when(() => cubit.state).thenReturn(const ReferralInitial());
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: const ReferralInitial(),
    );
    when(() => cubit.refreshOverview()).thenAnswer((_) async {});
  });

  testWidgets('reloads overview when create pops true', (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => BlocProvider<ReferralCubit>.value(
            value: cubit,
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => openReferralCreateAndRefresh(context),
                child: const Text('go'),
              ),
            ),
          ),
          routes: [
            GoRoute(
              name: SettingsRoutes.referralCreate,
              path: 'create',
              builder: (context, _) => TextButton(
                onPressed: () => context.pop(true),
                child: const Text('done'),
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('done'));
    await tester.pumpAndSettle();

    verify(() => cubit.refreshOverview()).called(1);
  });

  testWidgets('does not reload overview when create pops without a result', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => BlocProvider<ReferralCubit>.value(
            value: cubit,
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => openReferralCreateAndRefresh(context),
                child: const Text('go'),
              ),
            ),
          ),
          routes: [
            GoRoute(
              name: SettingsRoutes.referralCreate,
              path: 'create',
              builder: (context, _) => TextButton(
                onPressed: () => context.pop(),
                child: const Text('back'),
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('back'));
    await tester.pumpAndSettle();

    verifyNever(() => cubit.refreshOverview());
  });

  testWidgets('ignores a second open while create is already in flight', (
    tester,
  ) async {
    var opens = 0;
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => BlocProvider<ReferralCubit>.value(
            value: cubit,
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  unawaited(openReferralCreateAndRefresh(context));
                  unawaited(openReferralCreateAndRefresh(context));
                },
                child: const Text('go'),
              ),
            ),
          ),
          routes: [
            GoRoute(
              name: SettingsRoutes.referralCreate,
              path: 'create',
              builder: (context, _) {
                opens++;
                return TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('back'),
                );
              },
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(opens, 1);
  });

  testWidgets(
    'a hung overview refresh after create does not block a second Create',
    (tester) async {
      when(() => cubit.refreshOverview()).thenAnswer(
        (_) => Completer<void>().future,
      );
      var opens = 0;
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => BlocProvider<ReferralCubit>.value(
              value: cubit,
              child: Builder(
                builder: (context) => TextButton(
                  onPressed: () =>
                      unawaited(openReferralCreateAndRefresh(context)),
                  child: const Text('go'),
                ),
              ),
            ),
            routes: [
              GoRoute(
                name: SettingsRoutes.referralCreate,
                path: 'create',
                builder: (context, _) {
                  opens++;
                  return TextButton(
                    onPressed: () => context.pop(true),
                    child: const Text('done'),
                  );
                },
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('done'));
      await tester.pump();
      expect(opens, 1);

      await tester.tap(find.text('go'));
      await tester.pump();
      expect(opens, 2);
    },
  );
}
