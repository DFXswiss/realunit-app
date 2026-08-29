import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/screens/referral/referral_limits.dart';

void main() {
  test('sanitizeReferralGuestName collapses whitespace and caps length', () {
    expect(sanitizeReferralGuestName(' Alice\nBob\t '), 'Alice Bob');
    expect(sanitizeReferralGuestName('Alice   Bob'), 'Alice Bob');
    expect(sanitizeReferralGuestName('Alice\u00A0Bob'), 'Alice Bob');
    expect(sanitizeReferralGuestName('Alice\u2003Bob'), 'Alice Bob');
    expect(sanitizeReferralGuestName('Alice\u3000Bob'), 'Alice Bob');
    expect(sanitizeReferralGuestName('\u2003\u3000'), isEmpty);
    expect(sanitizeReferralGuestName('Ali\u200Bce'), 'Alice');
    expect(sanitizeReferralGuestName('\u200EAlice'), 'Alice');
    expect(sanitizeReferralGuestName('   '), isEmpty);
    expect(
      sanitizeReferralGuestName('A' * 120),
      'A' * maxReferralGuestNameLength,
    );
  });
}
