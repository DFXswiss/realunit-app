import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/setup/routing/referral_pending_code.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    debugSetPendingReferralCodeSync(null);
  });

  test('stash then peek then take: take clears, peek does not', () async {
    await stashPendingReferralCode('  AB12CD  ');
    expect(await peekPendingReferralCode(), 'AB12CD');
    expect(peekPendingReferralCodeSync(), 'AB12CD');

    expect(await takePendingReferralCode(), 'AB12CD');
    expect(await peekPendingReferralCode(), isNull);
    expect(await takePendingReferralCode(), isNull);
  });

  test('ignores empty stash and caps at 32 characters', () async {
    await stashPendingReferralCode('   ');
    expect(await peekPendingReferralCode(), isNull);

    final long = 'x' * 300;
    await stashPendingReferralCode(long);
    expect((await peekPendingReferralCode())!.length, 32);
  });

  test('percent-decodes a stashed code', () async {
    await stashPendingReferralCode('AB%2F12');
    expect(await peekPendingReferralCode(), 'AB/12');
  });

  test('extracts the code from a stashed invite URL', () async {
    await stashPendingReferralCode('https://realunit.app/invite/AB12CD');
    expect(await peekPendingReferralCode(), 'AB12CD');
    expect(await takePendingReferralCode(), 'AB12CD');
  });

  test('peek extracts a pre-normalize prefs invite URL', () async {
    debugSetPendingReferralCodeSync(null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      pendingReferralCodeKey,
      'android-app://swiss.realunit.app/https/realunit.app/promo/EVT1',
    );
    expect(await peekPendingReferralCode(), 'EVT1');
  });

  test('peek and take decode a pre-normalize prefs value', () async {
    debugSetPendingReferralCodeSync(null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(pendingReferralCodeKey, 'AB%2F12');
    expect(await peekPendingReferralCode(), 'AB/12');
    expect(await takePendingReferralCode(), 'AB/12');
    expect(await peekPendingReferralCode(), isNull);
  });

  test('clear drops both memory and prefs', () async {
    await stashPendingReferralCode('EVT1');
    await clearPendingReferralCode();
    expect(await peekPendingReferralCode(), isNull);
    expect(peekPendingReferralCodeSync(), isNull);
  });
}
