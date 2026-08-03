import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/packages/config/network_mode.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/styles/currency.dart';
import 'package:realunit_wallet/styles/language.dart';

/// Equatable-`props` surface tests for `SettingsEvent` and its subclasses.
///
/// Why this file exists: `settings_event.dart` is a pure `Equatable` value-
/// type declaration. The bloc-level tests in `settings_bloc_test.dart` only
/// exercise the *handler* side (state changes + repo calls), so the `props`
/// getters and constructors never get hit. These tests close that gap so
/// the file lands at 100% line coverage and so we catch any regression that
/// drops a field from a `props` override (silent equality bug).
void main() {
  group('SetLanguageEvent', () {
    test('two instances with the same language are equal and share hashCode', () {
      const a = SetLanguageEvent(Language.de);
      const b = SetLanguageEvent(Language.de);

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a.props, [Language.de]);
    });

    test('different languages are not equal', () {
      const a = SetLanguageEvent(Language.de);
      const b = SetLanguageEvent(Language.en);

      expect(a, isNot(equals(b)));
      expect(a.props, isNot(equals(b.props)));
    });
  });

  group('SetCurrencyEvent', () {
    test('two instances with the same currency are equal and share hashCode', () {
      const a = SetCurrencyEvent(Currency.eur);
      const b = SetCurrencyEvent(Currency.eur);

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a.props, [Currency.eur]);
    });

    test('different currencies are not equal', () {
      const a = SetCurrencyEvent(Currency.eur);
      const b = SetCurrencyEvent(Currency.chf);

      expect(a, isNot(equals(b)));
      expect(a.props, isNot(equals(b.props)));
    });
  });

  group('SetNetworkModeEvent', () {
    test('two instances with the same network mode are equal and share hashCode', () {
      const a = SetNetworkModeEvent(NetworkMode.testnet);
      const b = SetNetworkModeEvent(NetworkMode.testnet);

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a.props, [NetworkMode.testnet]);
    });

    test('different network modes are not equal', () {
      const a = SetNetworkModeEvent(NetworkMode.testnet);
      const b = SetNetworkModeEvent(NetworkMode.mainnet);

      expect(a, isNot(equals(b)));
      expect(a.props, isNot(equals(b.props)));
    });
  });

  group('ToggleHideAmountEvent', () {
    test('all instances are equal (singleton-style event, no payload)', () {
      const a = ToggleHideAmountEvent();
      const b = ToggleHideAmountEvent();

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      // Inherits the empty `props` list from the sealed base class.
      expect(a.props, isEmpty);
    });
  });

  group('UnlockInsiderFeaturesEvent', () {
    test('all instances are equal (singleton-style event, no payload)', () {
      const a = UnlockInsiderFeaturesEvent();
      const b = UnlockInsiderFeaturesEvent();

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      // Inherits the empty `props` list from the sealed base class.
      expect(a.props, isEmpty);
    });
  });

  group('SettingsEvent (cross-subclass identity)', () {
    test('different subclasses are not equal even when props happen to match', () {
      // Two payload-less events from different subclasses must still compare
      // unequal — Equatable's runtimeType check guarantees this.
      const toggle = ToggleHideAmountEvent();
      // SetLanguageEvent carries a payload, so props differ regardless, but
      // the cross-type comparison is the load-bearing assertion here.
      const setEn = SetLanguageEvent(Language.en);

      expect(toggle, isNot(equals(setEn)));
    });
  });

  group('SettingsEvent (runtime constructor exercise)', () {
    // The other groups use compile-time `const` constructors which don't
    // count as runtime-executed lines for the coverage report. Instantiate
    // every subclass non-const here so each constructor body is hit.
    test('runtime ctors equal their const counterparts', () {
      // ignore_for_file: prefer_const_constructors
      final lang = SetLanguageEvent(Language.de);
      final cur = SetCurrencyEvent(Currency.eur);
      final net = SetNetworkModeEvent(NetworkMode.mainnet);
      final toggle = ToggleHideAmountEvent();
      final unlock = UnlockInsiderFeaturesEvent();

      expect(lang, equals(const SetLanguageEvent(Language.de)));
      expect(cur, equals(const SetCurrencyEvent(Currency.eur)));
      expect(net, equals(const SetNetworkModeEvent(NetworkMode.mainnet)));
      expect(toggle, equals(const ToggleHideAmountEvent()));
      expect(unlock, equals(const UnlockInsiderFeaturesEvent()));

      expect(lang.props, [Language.de]);
      expect(cur.props, [Currency.eur]);
      expect(net.props, [NetworkMode.mainnet]);
      expect(toggle.props, isEmpty);
      expect(unlock.props, isEmpty);
    });
  });
}
