import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/bank_account/bank_account.dart';
import 'package:realunit_wallet/screens/sell/cubits/sell_bank_accounts/sell_bank_accounts_cubit.dart';
import 'package:realunit_wallet/screens/sell/cubits/sell_selected_bank_account/sell_selected_bank_account_cubit.dart';
import 'package:realunit_wallet/screens/sell/widgets/sell_bank_account_selection_page.dart';

class _MockSellBankAccountsCubit extends MockCubit<SellBankAccountsState>
    implements SellBankAccountsCubit {}

class _MockSellSelectedBankAccountCubit extends MockCubit<BankAccount?>
    implements SellSelectedBankAccountCubit {}

void main() {
  late _MockSellBankAccountsCubit accountsCubit;
  late _MockSellSelectedBankAccountCubit selectedCubit;

  const accountActiveNonDefault1 = BankAccount(
    id: 1,
    iban: 'CH0000000000000000001',
    isActive: true,
  );
  const accountActiveNonDefault2 = BankAccount(
    id: 2,
    iban: 'CH0000000000000000002',
    isActive: true,
  );
  const accountDefault = BankAccount(
    id: 3,
    iban: 'CH0000000000000000003',
    isActive: true,
    isDefault: true,
  );
  const accountDefaultSecond = BankAccount(
    id: 5,
    iban: 'CH0000000000000000005',
    isActive: true,
    isDefault: true,
  );
  const accountDefaultButInactive = BankAccount(
    id: 6,
    iban: 'CH0000000000000000006',
    isDefault: true,
  );

  setUpAll(() {
    registerFallbackValue(accountActiveNonDefault1);
  });

  setUp(() {
    accountsCubit = _MockSellBankAccountsCubit();
    selectedCubit = _MockSellSelectedBankAccountCubit();
    when(() => selectedCubit.state).thenReturn(null);
  });

  // The page calls `context.pop()` when the accounts list grows, so we have
  // to wrap it in a GoRouter for those listeners to resolve. The router is
  // never actually navigated in these tests because we only assert on the
  // initial auto-selection listener.
  Future<void> pumpPage(WidgetTester tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => MultiBlocProvider(
            providers: [
              BlocProvider<SellBankAccountsCubit>.value(value: accountsCubit),
              BlocProvider<SellSelectedBankAccountCubit>.value(
                value: selectedCubit,
              ),
            ],
            child: const SellBankAccountSelectionPage(),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
      ),
    );
  }

  group('$SellBankAccountSelectionPage auto-selection on re-open', () {
    testWidgets(
      'prefers the default account, even after the page is re-opened',
      (tester) async {
        // Regression for V11: the previous active-last heuristic on this page
        // would overwrite the default chosen in BankAccountFieldView the
        // moment the user opened the selection page. We start from a Loading
        // state with the same accounts already populated (mirroring the
        // re-open flow where the cubit already has data) so the SAME length
        // is emitted afterwards — the `accounts.length` listener guards the
        // pop, but the selection listener fires unconditionally on Success.
        whenListen(
          accountsCubit,
          Stream.fromIterable(const [
            SellBankAccountsSuccess([
              accountActiveNonDefault1,
              accountDefault,
              accountActiveNonDefault2,
            ]),
          ]),
          initialState: const SellBankAccountsLoading([
            accountActiveNonDefault1,
            accountDefault,
            accountActiveNonDefault2,
          ]),
        );

        await pumpPage(tester);
        await tester.pump();

        verify(() => selectedCubit.selectBankAccount(accountDefault)).called(1);
      },
    );

    testWidgets(
      'selects null when no default is flagged (no active-fallback)',
      (tester) async {
        whenListen(
          accountsCubit,
          Stream.fromIterable(const [
            SellBankAccountsSuccess([
              accountActiveNonDefault1,
              accountActiveNonDefault2,
            ]),
          ]),
          initialState: const SellBankAccountsLoading([
            accountActiveNonDefault1,
            accountActiveNonDefault2,
          ]),
        );

        await pumpPage(tester);
        await tester.pump();

        verify(() => selectedCubit.selectBankAccount(null)).called(1);
      },
    );

    testWidgets(
      'selects null when the only default account is inactive',
      (tester) async {
        whenListen(
          accountsCubit,
          Stream.fromIterable(const [
            SellBankAccountsSuccess([
              accountActiveNonDefault1,
              accountDefaultButInactive,
            ]),
          ]),
          initialState: const SellBankAccountsLoading([
            accountActiveNonDefault1,
            accountDefaultButInactive,
          ]),
        );

        await pumpPage(tester);
        await tester.pump();

        verify(() => selectedCubit.selectBankAccount(null)).called(1);
      },
    );

    testWidgets(
      'picks the first default when multiple defaults are flagged',
      (tester) async {
        whenListen(
          accountsCubit,
          Stream.fromIterable(const [
            SellBankAccountsSuccess([
              accountActiveNonDefault1,
              accountDefault,
              accountDefaultSecond,
            ]),
          ]),
          initialState: const SellBankAccountsLoading([
            accountActiveNonDefault1,
            accountDefault,
            accountDefaultSecond,
          ]),
        );

        await pumpPage(tester);
        await tester.pump();

        verify(() => selectedCubit.selectBankAccount(accountDefault)).called(1);
        verifyNever(
          () => selectedCubit.selectBankAccount(accountDefaultSecond),
        );
      },
    );
  });
}
