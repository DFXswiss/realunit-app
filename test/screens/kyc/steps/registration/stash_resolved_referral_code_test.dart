import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/screens/kyc/steps/registration/stash_resolved_referral_code.dart';
import 'package:realunit_wallet/setup/routing/referral_pending_code.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    debugSetPendingReferralCodeSync(null);
  });

  test('null resolved leaves a deeplink stash in place', () async {
    await stashPendingReferralCode('AB12CD');
    await stashResolvedReferralCode(null);
    expect(await peekPendingReferralCode(), 'AB12CD');
  });

  test('a resolved code overwrites the stash for post-auth bind', () async {
    await stashPendingReferralCode('OLD1');
    await stashResolvedReferralCode('EVT1');
    expect(await peekPendingReferralCode(), 'EVT1');
  });
}
