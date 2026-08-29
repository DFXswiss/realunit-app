import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/screens/pin/bloc/auth/pin_auth_cubit.dart';
import 'package:realunit_wallet/setup/routing/boot_navigation.dart';
import 'package:realunit_wallet/setup/routing/referral_pending_code.dart';
import 'package:realunit_wallet/setup/routing/routes/app_link_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockPinAuthCubit extends Mock implements PinAuthCubit {}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late _MockPinAuthCubit pinAuthCubit;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    debugSetPendingReferralCodeSync(null);
    pinAuthCubit = _MockPinAuthCubit();
    GetIt.instance.registerSingleton<PinAuthCubit>(pinAuthCubit);
    when(() => pinAuthCubit.state).thenReturn(const PinAuthState());
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  GoRouter buildRouter() {
    late final GoRouter router;
    router = GoRouter(
      initialLocation: '/dashboard',
      redirect: (context, state) => appLinkSchemeRedirect(
        state,
        effectiveLocation(router.routerDelegate.currentConfiguration),
        router,
      ),
      onException: appLinkOnException,
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('HOME', key: Key('home'))),
        ),
        GoRoute(
          path: '/dashboard',
          builder: (_, _) => const Scaffold(body: Text('DASH', key: Key('dashboard'))),
        ),
      ],
    );
    return router;
  }

  testWidgets('extracts invite and promo codes from https App Links', (tester) async {
    expect(
      extractReferralInviteCode(Uri.parse('https://realunit.app/invite/AbCd1234')),
      'ABCD1234',
    );
    expect(
      extractReferralInviteCode(Uri.parse('https://realunit.app/promo/EVT1')),
      'EVT1',
    );
    expect(
      extractReferralInviteCode(
        Uri.parse('realunit-wallet://invite/AB12CD'),
      ),
      'AB12CD',
    );
    expect(
      extractReferralInviteCode(Uri.parse('realunit-wallet://promo/EVT1')),
      'EVT1',
    );
  });

  testWidgets('locked in-app /invite App Link stashes the code', (tester) async {
    final router = buildRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dashboard')), findsOneWidget);

    router.go('https://realunit.app/invite/AB12CD');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dashboard')), findsOneWidget);
    expect(await peekPendingReferralCode(), 'AB12CD');
  });

  testWidgets('locked in-app /promo App Link stashes the code', (tester) async {
    final router = buildRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    router.go('https://realunit.app/promo/EVT1');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dashboard')), findsOneWidget);
    expect(await peekPendingReferralCode(), 'EVT1');
  });
}
