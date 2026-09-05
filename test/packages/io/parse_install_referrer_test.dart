import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/packages/io/parse_install_referrer.dart';

void main() {
  group('parseInviteCodeFromReferrer', () {
    test('reads invite=<code> as Play delivers it', () {
      expect(parseInviteCodeFromReferrer('invite=AB12CD'), 'AB12CD');
    });

    test('strips bidi marks so invite= is still the key', () {
      expect(parseInviteCodeFromReferrer('\u200Einvite=AB12CD'), 'AB12CD');
      expect(parseInviteCodeFromReferrer('invite=\u202AAB12CD\u202C'), 'AB12CD');
    });

    test('decodes a percent-encoded referrer', () {
      expect(parseInviteCodeFromReferrer('invite%3DAB12CD'), 'AB12CD');
    });

    test('decodes a double-encoded Play referrer', () {
      expect(parseInviteCodeFromReferrer('invite%253DAB12CD'), 'AB12CD');
      expect(parseInviteCodeFromReferrer('promo%253DEVT1'), 'EVT1');
      expect(
        parseInviteCodeFromReferrer(
          'utm_source=google-play%26invite%253DEVT1',
        ),
        'EVT1',
      );
    });

    test('keeps the code when extra utm fields are present', () {
      expect(
        parseInviteCodeFromReferrer('utm_source=google-play&invite=EVT1'),
        'EVT1',
      );
    });

    test('unwraps invite= or a landing URL nested in utm_content', () {
      expect(
        parseInviteCodeFromReferrer('utm_content=invite%3DAB12CD'),
        'AB12CD',
      );
      expect(
        parseInviteCodeFromReferrer(
          'utm_source=google-play&utm_content=https://realunit.app/invite/AB12CD',
        ),
        'AB12CD',
      );
      expect(
        parseInviteCodeFromReferrer('utm_content=promo%3DEVT1'),
        'EVT1',
      );
      expect(parseInviteCodeFromReferrer('utm_content=summer-sale'), isNull);
      expect(
        parseInviteCodeFromReferrer(
          'utm_content=summer-sale&u=invite%3DAB12CD',
        ),
        'AB12CD',
      );
      expect(
        parseInviteCodeFromReferrer(
          'utm_content=summer-sale&link=https://realunit.app/invite/AB12CD',
        ),
        'AB12CD',
      );
      expect(
        parseInviteCodeFromReferrer(
          'utm_content=https://realunit.app&u=invite%3DAB12CD',
        ),
        'AB12CD',
      );
      expect(
        parseInviteCodeFromReferrer(
          'utm_source=https://realunit.app/&link=https://realunit.app/promo/EVT1',
        ),
        'EVT1',
      );
    });

    test('unwraps invite= or a landing URL nested in referrer=', () {
      expect(
        parseInviteCodeFromReferrer('utm_source=google-play&referrer=invite%3DAB12CD'),
        'AB12CD',
      );
      expect(
        parseInviteCodeFromReferrer(
          'utm_source=google-play&referrer=https://realunit.app/invite/AB12CD',
        ),
        'AB12CD',
      );
      expect(
        parseInviteCodeFromReferrer('referrer=promo%3DEVT1'),
        'EVT1',
      );
      expect(parseInviteCodeFromReferrer('referrer=summer-sale'), isNull);
    });

    test('unwraps invite= or a landing URL nested in u= / q= / url= / link=', () {
      expect(parseInviteCodeFromReferrer('u=invite%3DAB12CD'), 'AB12CD');
      expect(parseInviteCodeFromReferrer('q=promo%3DEVT1'), 'EVT1');
      expect(
        parseInviteCodeFromReferrer('url=https://realunit.app/invite/AB12CD'),
        'AB12CD',
      );
      expect(
        parseInviteCodeFromReferrer('link=https://realunit.app/promo/EVT1'),
        'EVT1',
      );
      expect(parseInviteCodeFromReferrer('u=hello'), isNull);
      expect(parseInviteCodeFromReferrer('link=summer-sale'), isNull);
    });

    test('reads promo=<code> and code=<code>', () {
      expect(parseInviteCodeFromReferrer('promo=EVT1'), 'EVT1');
      expect(parseInviteCodeFromReferrer('code=AB12CD'), 'AB12CD');
      expect(parseInviteCodeFromReferrer('invite=&promo=EVT1'), 'EVT1');
      expect(
        parseInviteCodeFromReferrer('invite=https://example.com&code=AB12CD'),
        'AB12CD',
      );
    });

    test('returns null for missing, empty, or unrelated referrers', () {
      expect(parseInviteCodeFromReferrer(null), isNull);
      expect(parseInviteCodeFromReferrer(''), isNull);
      expect(parseInviteCodeFromReferrer('utm_source=google-play'), isNull);
      expect(parseInviteCodeFromReferrer('invite='), isNull);
      expect(parseInviteCodeFromReferrer('invite=   '), isNull);
    });

    test('caps at 32 characters', () {
      final long = 'x' * 300;
      expect(parseInviteCodeFromReferrer('invite=$long')!.length, 32);
    });

    test('percent-decodes a slash in the code', () {
      expect(parseInviteCodeFromReferrer('invite=AB%2F12'), 'AB/12');
      expect(parseInviteCodeFromReferrer('promo=AB%2F12'), 'AB/12');
    });

    test('extracts the code when the referrer value is an invite URL', () {
      expect(
        parseInviteCodeFromReferrer('https://realunit.app?invite=AB12CD'),
        'AB12CD',
      );
      expect(
        parseInviteCodeFromReferrer(
          'https://l.facebook.com/l.php?u=https%3A%2F%2Frealunit.app%2Finvite%2FAB12CD',
        ),
        'AB12CD',
      );
      expect(
        parseInviteCodeFromReferrer(
          'https://www.google.com/url?q=https://realunit.app/promo/EVT1',
        ),
        'EVT1',
      );
      expect(
        parseInviteCodeFromReferrer(
          'https://href.li/?https://realunit.app/invite/AB12CD',
        ),
        'AB12CD',
      );
      expect(
        parseInviteCodeFromReferrer(
          'https://nam12.safelinks.protection.outlook.com/?url=https%3A%2F%2Frealunit.app%2Finvite%2FAB12CD',
        ),
        'AB12CD',
      );
      expect(
        parseInviteCodeFromReferrer(
          'https://urldefense.proofpoint.com/v2/url?u=https-3A__realunit.app_invite_EVT1',
        ),
        'EVT1',
      );
      expect(
        parseInviteCodeFromReferrer(
          'https://example.com/r/https://realunit.app/invite/AB12CD',
        ),
        'AB12CD',
      );
      expect(
        parseInviteCodeFromReferrer(
          'https://r.search.yahoo.com/_ylt=x/RU=https%3A%2F%2Frealunit.app%2Finvite%2FAB12CD/RK=2',
        ),
        'AB12CD',
      );
      expect(
        parseInviteCodeFromReferrer(
          'https://www.google.com/amp/s/realunit.app/invite/AB12CD',
        ),
        'AB12CD',
      );
      expect(
        parseInviteCodeFromReferrer('invite=https://realunit.app/invite/AB12CD'),
        'AB12CD',
      );
      expect(parseInviteCodeFromReferrer('invite#AB12CD'), 'AB12CD');
      expect(
        parseInviteCodeFromReferrer('promo=https://realunit.app/promo/EVT1'),
        'EVT1',
      );
    });

    test('extracts the code from a share-message or URL-only referrer', () {
      expect(
        parseInviteCodeFromReferrer(
          'Hey Alice, Björn lädt dich ein: https://realunit.app/invite/AB12CD',
        ),
        'AB12CD',
      );
      expect(
        parseInviteCodeFromReferrer('https://realunit.app/promo/EVT1'),
        'EVT1',
      );
      expect(
        parseInviteCodeFromReferrer('https://realunit。app/invite/AB12CD'),
        'AB12CD',
      );
      expect(
        parseInviteCodeFromReferrer(
          'ｈｔｔｐｓ：／／ｒｅａｌｕｎｉｔ．ａｐｐ／ｉｎｖｉｔｅ／ＡＢ１２ＣＤ',
        ),
        'AB12CD',
      );
      expect(
        parseInviteCodeFromReferrer('https://realunit&#46;app/promo/EVT1'),
        'EVT1',
      );
      expect(
        parseInviteCodeFromReferrer(
          'intent://realunit.app/invite/AB12CD#Intent;scheme=https;end',
        ),
        'AB12CD',
      );
      expect(parseInviteCodeFromReferrer('AB12CD'), isNull);
      expect(parseInviteCodeFromReferrer('invite?code=AB12CD'), 'AB12CD');
      expect(parseInviteCodeFromReferrer('promo?promo=EVT1'), 'EVT1');
      expect(parseInviteCodeFromReferrer('invite/AB12CD'), 'AB12CD');
      expect(parseInviteCodeFromReferrer('/promo/EVT1'), 'EVT1');
    });
  });
}
