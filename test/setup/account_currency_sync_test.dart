import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/kyc/kyc_level.dart';
import 'package:realunit_wallet/packages/service/dfx/models/user/dto/user_dto.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/setup/account_currency_sync.dart';
import 'package:realunit_wallet/styles/currency.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState> implements SettingsBloc {}

class _MockKycService extends Mock implements DfxKycService {}

class _MockWallet extends Mock implements AWallet {}

UserDto _user({Currency? currency}) => UserDto(
  kyc: const UserKycDto(hash: 'h', level: KycLevel.level0, dataComplete: false),
  currency: currency,
);

void main() {
  late _MockSettingsBloc settings;
  late _MockKycService kyc;
  late _MockWallet wallet;
  late AWallet? current;

  setUpAll(() {
    registerFallbackValue(const ApplyAccountCurrencyEvent(Currency.chf));
    registerFallbackValue(const ClearAccountCurrencyEvent());
  });

  setUp(() {
    settings = _MockSettingsBloc();
    kyc = _MockKycService();
    wallet = _MockWallet();
    current = wallet;
  });

  AccountCurrencySync build() => AccountCurrencySync(
    settings: settings,
    kyc: kyc,
    currentWallet: () => current,
  );

  test('onOpened applies GET /v2/user.currency when the wallet is still open', () async {
    when(() => kyc.getUser()).thenAnswer((_) async => _user(currency: Currency.chf));

    final sync = build();
    sync.onOpened(wallet);
    await untilCalled(() => settings.add(any()));

    verify(() => settings.add(const ApplyAccountCurrencyEvent(Currency.chf))).called(1);
    verifyNever(() => settings.add(const ClearAccountCurrencyEvent()));
  });

  test('onOpened does not dispatch when GET /v2/user has no currency', () async {
    when(() => kyc.getUser()).thenAnswer((_) async => _user());

    final sync = build();
    sync.onOpened(wallet);
    await Future<void>.delayed(Duration.zero);

    verifyNever(() => settings.add(any()));
  });

  test('onOpened swallows GET /v2/user failures', () async {
    when(() => kyc.getUser()).thenAnswer((_) async => throw Exception('offline'));

    final sync = build();
    sync.onOpened(wallet);
    await Future<void>.delayed(Duration.zero);

    verifyNever(() => settings.add(any()));
  });

  test('onClosed clears the unset account default', () {
    build().onClosed();

    verify(() => settings.add(const ClearAccountCurrencyEvent())).called(1);
  });

  test('a late apply after onClosed is dropped', () async {
    final held = Completer<UserDto>();
    when(() => kyc.getUser()).thenAnswer((_) => held.future);

    final sync = build();
    sync.onOpened(wallet);
    sync.onClosed();
    current = null;
    held.complete(_user(currency: Currency.chf));
    await Future<void>.delayed(Duration.zero);

    verify(() => settings.add(const ClearAccountCurrencyEvent())).called(1);
    verifyNever(() => settings.add(any(that: isA<ApplyAccountCurrencyEvent>())));
  });

  test('onSwitched clears then applies the new wallet currency', () async {
    final other = _MockWallet();
    when(() => kyc.getUser()).thenAnswer((_) async => _user(currency: Currency.eur));

    final sync = build();
    current = other;
    sync.onSwitched(other);
    await untilCalled(() => settings.add(any(that: isA<ApplyAccountCurrencyEvent>())));

    verifyInOrder([
      () => settings.add(const ClearAccountCurrencyEvent()),
      () => settings.add(const ApplyAccountCurrencyEvent(Currency.eur)),
    ]);
  });

  test('a late apply from wallet A is dropped after switch to B', () async {
    final held = Completer<UserDto>();
    when(() => kyc.getUser()).thenAnswer((_) => held.future);
    final other = _MockWallet();

    final sync = build();
    sync.onOpened(wallet);
    when(() => kyc.getUser()).thenAnswer((_) async => _user(currency: Currency.eur));
    current = other;
    sync.onSwitched(other);
    held.complete(_user(currency: Currency.chf));
    await untilCalled(() => settings.add(const ApplyAccountCurrencyEvent(Currency.eur)));

    verify(() => settings.add(const ClearAccountCurrencyEvent())).called(1);
    verifyNever(() => settings.add(const ApplyAccountCurrencyEvent(Currency.chf)));
    verify(() => settings.add(const ApplyAccountCurrencyEvent(Currency.eur))).called(1);
  });

  test('applyFromUser dispatches when captured is still the open wallet', () {
    build().applyFromUser(_user(currency: Currency.chf), captured: wallet);

    verify(() => settings.add(const ApplyAccountCurrencyEvent(Currency.chf))).called(1);
  });

  test('applyFromUser is ignored when captured is a different wallet', () {
    build().applyFromUser(_user(currency: Currency.chf), captured: _MockWallet());

    verifyNever(() => settings.add(any()));
  });
}
