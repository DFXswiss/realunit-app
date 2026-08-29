import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/screens/referral/referral_share_text.dart';

void main() {
  String fallback(String guestName, String hostName, String url) =>
      'Hey $guestName, $hostName: $url';

  test('uses the API share text when present', () {
    expect(
      referralShareText(
        fromApi: 'Hey Alice, Björn lädt dich ein: https://realunit.app/invite/AB',
        guestName: 'Alice',
        url: 'https://realunit.app/invite/AB',
        fallback: fallback,
      ),
      'Hey Alice, Björn lädt dich ein: https://realunit.app/invite/AB',
    );
  });

  test('folds www and http invite hosts onto the apex', () {
    expect(
      referralShareText(
        fromApi:
            'Hey Alice: https://www.realunit.app/invite/AB http://realunit.app/invite/AB //www.realunit.app/invite/AB',
        guestName: 'Alice',
        url: 'https://www.realunit.app/invite/AB',
        fallback: fallback,
      ),
      'Hey Alice: https://realunit.app/invite/AB https://realunit.app/invite/AB https://realunit.app/invite/AB',
    );
    expect(
      referralShareText(
        fromApi: 'Dev: https://dev.realunit.app/invite/AB',
        guestName: 'Alice',
        url: 'https://dev.realunit.app/invite/AB',
        fallback: fallback,
      ),
      'Dev: https://dev.realunit.app/invite/AB',
    );
    expect(
      referralShareText(
        fromApi: 'Hey Alice: www.realunit.app/invite/AB realunit.app/invite/AB',
        guestName: 'Alice',
        url: 'https://realunit.app/invite/AB',
        fallback: fallback,
      ),
      'Hey Alice: https://realunit.app/invite/AB https://realunit.app/invite/AB',
    );
  });

  test('falls back when the API share text is blank', () {
    expect(
      referralShareText(
        fromApi: '  ',
        guestName: 'Alice',
        url: 'https://realunit.app/invite/AB',
        fallback: fallback,
      ),
      'Hey Alice, RealUnit: https://realunit.app/invite/AB',
    );
  });

  test('fallback names the Empfehler when copyText is omitted', () {
    expect(
      referralShareText(
        fromApi: null,
        guestName: 'Alice',
        url: 'https://realunit.app/invite/AB',
        hostName: 'Björn',
        fallback: fallback,
      ),
      'Hey Alice, Björn: https://realunit.app/invite/AB',
    );
  });

  test('whitespace-only hostName still falls back to RealUnit', () {
    expect(
      referralShareText(
        fromApi: null,
        guestName: 'Alice',
        url: 'https://realunit.app/invite/AB',
        hostName: '   ',
        fallback: fallback,
      ),
      'Hey Alice, RealUnit: https://realunit.app/invite/AB',
    );
  });

  test('uses the nameless fallback when the guest name is blank', () {
    expect(
      referralShareText(
        fromApi: null,
        guestName: '  ',
        url: 'https://realunit.app/invite/AB',
        fallback: fallback,
        fallbackNoName: (hostName, url) => '$hostName: $url',
      ),
      'RealUnit: https://realunit.app/invite/AB',
    );
    expect(
      referralShareText(
        fromApi: null,
        guestName: '  ',
        url: 'https://realunit.app/invite/AB',
        hostName: 'Björn',
        fallback: fallback,
        fallbackNoName: (hostName, url) => '$hostName: $url',
      ),
      'Björn: https://realunit.app/invite/AB',
    );
  });
}
