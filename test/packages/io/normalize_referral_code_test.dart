import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/packages/io/normalize_referral_code.dart';

void main() {
  test('trims, percent-decodes, and caps at 32 characters', () {
    expect(normalizeReferralCode('  AB12CD  '), 'AB12CD');
    expect(normalizeReferralCode('AB%2F12'), 'AB/12');
    expect(normalizeReferralCode('AB/12'), 'AB/12');
    expect(normalizeReferralCode('AB12CD/'), 'AB12CD');
    expect(normalizeReferralCode('AB12CD.'), 'AB12CD');
    expect(normalizeReferralCode('AB12CD!'), 'AB12CD');
    expect(normalizeReferralCode('AB12CD!?'), 'AB12CD');
    expect(normalizeReferralCode('AB/12/'), 'AB/12');
    expect(normalizeReferralCode('invite/AB12CD'), 'AB12CD');
    expect(normalizeReferralCode('prefixinvite/ab12cd'), 'AB12CD');
    expect(normalizeReferralCode('invite/AB%2F12'), 'AB/12');
    expect(normalizeReferralCode('%2Finvite%2FAB12CD'), 'AB12CD');
    expect(referralCodeFromInput('prefixinvite/AB12CD'), 'AB12CD');
    expect(normalizeReferralCode('!'), isNull);
    expect(normalizeReferralCode('!!!'), isNull);
    expect(normalizeReferralCode('https://example.com/campaign'), isNull);
    expect(normalizeReferralCode('utm_content=https://realunit.app'), isNull);
    expect(referralCodeFromInput('https://realunit.app/invite/AB12CD/'), 'AB12CD');
    final long = 'x' * 300;
    expect(normalizeReferralCode(long)!.length, kReferralCodeMaxLength);
    expect(kReferralCodeMaxLength, 32);
  });

  test('rejects missing, blank, and whitespace-only decoded values', () {
    expect(normalizeReferralCode(null), isNull);
    expect(normalizeReferralCode(''), isNull);
    expect(normalizeReferralCode('   '), isNull);
    expect(normalizeReferralCode('%20'), isNull);
  });

  test('strips zero-width characters messengers inject around copied codes', () {
    expect(normalizeReferralCode('AB\u200B12'), 'AB12');
    expect(normalizeReferralCode('AB 12'), 'AB12');
    expect(normalizeReferralCode('AB\u00A012'), 'AB12');
    expect(normalizeReferralCode('ＡＢ１２ＣＤ'), 'AB12CD');
    expect(normalizeReferralCode('AB\u200912'), 'AB12');
    expect(normalizeReferralCode('\uFEFFAB12CD\u200B'), 'AB12CD');
    expect(normalizeReferralCode('AB\u200E12'), 'AB12');
    expect(referralCodeFromInput('\u200Bhttps://realunit.app/invite/AB12'), 'AB12');
    expect(referralCodeFromInput('\u202Ahttps://realunit.app/invite/AB12\u202C'), 'AB12');
    expect(referralCodeFromInput('AB\u200B12CD'), 'AB12CD');
  });

  group('referralPasteFieldText', () {
    test('returns the extracted code from an invite URL', () {
      expect(
        referralPasteFieldText('https://realunit.app/invite/AB12CD'),
        'AB12CD',
      );
    });

    test('returns a bare code', () {
      expect(referralPasteFieldText('  AB12CD  '), 'AB12CD');
    });

    test('ignores a RealUnit invite URL that has no code', () {
      expect(referralPasteFieldText('https://realunit.app/invite'), isNull);
      expect(
        referralPasteFieldText(
          'https://realunit.app/invite?utm_content=summer-sale',
        ),
        isNull,
      );
      expect(referralPasteFieldText('/promo'), isNull);
    });

    test('ignores format-only clipboard', () {
      expect(referralPasteFieldText('\u200E\u200B\u202C'), isNull);
      expect(referralPasteFieldText(null), isNull);
      expect(referralPasteFieldText('   '), isNull);
    });
  });

  group('referralCodeFromInput', () {
    test('falls back to a bare code', () {
      expect(referralCodeFromInput('  AB12CD  '), 'AB12CD');
      expect(referralCodeFromInput('ab12cd'), 'AB12CD');
      expect(referralCodeFromInput('AB%2F12'), 'AB/12');
      expect(referralCodeFromInput('invite'), 'INVITE');
      expect(referralCodeFromInput('promo'), 'PROMO');
      expect(referralCodeFromInput(null), isNull);
      expect(referralCodeFromInput('   '), isNull);
    });

    test('extracts the code from https invite and promo URLs', () {
      expect(
        referralCodeFromInput('https://realunit.app/invite/AB12CD'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('https://realunit.app/invite/ab12cd'),
        'AB12CD',
      );
      expect(referralCodeFromInput('https://realunit.app#AB12CD'), 'AB12CD');
      expect(referralCodeFromInput('https://realunit.app/#AB12CD'), 'AB12CD');
      expect(referralCodeFromInput('realunit.app#AB12CD'), 'AB12CD');
      expect(
        referralCodeFromInput('https://www.realunit.app/promo/EVT1'),
        'EVT1',
      );
      expect(
        referralCodeFromInput('http://dev.realunit.app/invite/AB12CD'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('https://realunit.app/invite/AB%2F12'),
        'AB/12',
      );
      expect(
        referralCodeFromInput(
          'https://realunit.app/invite/https://realunit.app/invite/AB12CD',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'https://realunit.app/promo/https://realunit.app/promo/EVT1',
        ),
        'EVT1',
      );
      expect(
        referralCodeFromInput(
          'https://l.facebook.com/l.php?u=https%3A%2F%2Frealunit.app%2Finvite%2FAB12CD',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'https://www.google.com/url?q=https://realunit.app/promo/EVT1',
        ),
        'EVT1',
      );
      expect(
        referralCodeFromInput('https://l.facebook.com/l.php?u=https://example.com/'),
        isNull,
      );
      expect(
        referralCodeFromInput('https://example.com/?utm_content=summer-sale'),
        isNull,
      );
      expect(
        referralCodeFromInput(
          'https://href.li/?https://realunit.app/invite/AB12CD',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'whatsapp://send?text=https%3A%2F%2Frealunit.app%2Finvite%2FAB12CD',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'tg://msg?text=https%3A%2F%2Frealunit.app%2Fpromo%2FEVT1',
        ),
        'EVT1',
      );
      expect(
        referralCodeFromInput(
          'sms:?body=https%3A%2F%2Frealunit.app%2Finvite%2FAB12CD',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'whatsapp://send?text=Tritt%20RealUnit%20bei%3A%20https%3A%2F%2Frealunit.app%2Finvite%2FAB12CD',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'tg://msg_url?url=https%3A%2F%2Frealunit.app%2Finvite%2FAB12CD',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'smsto:+41791234567?body=https%3A%2F%2Frealunit.app%2Fpromo%2FEVT1',
        ),
        'EVT1',
      );
      expect(
        referralCodeFromInput(
          'mailto:?body=https%3A%2F%2Frealunit.app%2Finvite%2FAB12CD',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'fb-messenger://share/?link=https%3A%2F%2Frealunit.app%2Finvite%2FAB12CD',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'https://wa.me/?text=https%3A%2F%2Frealunit.app%2Finvite%2FAB12CD',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'https://t.me/share/url?url=https%3A%2F%2Frealunit.app%2Fpromo%2FEVT1',
        ),
        'EVT1',
      );
      expect(
        referralCodeFromInput(
          'threema://compose?text=https%3A%2F%2Frealunit.app%2Finvite%2FAB12CD',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'sgnl://send?text=https%3A%2F%2Frealunit.app%2Fpromo%2FEVT1',
        ),
        'EVT1',
      );
      expect(
        referralCodeFromInput(
          'viber://forward?text=https%3A%2F%2Frealunit.app%2Finvite%2FAB12CD',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'line://msg/text/?https%3A%2F%2Frealunit.app%2Finvite%2FAB12CD',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'line://msg/text/https%3A%2F%2Frealunit.app%2Finvite%2FAB12CD',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'https://nam12.safelinks.protection.outlook.com/?url=https%3A%2F%2Frealunit.app%2Finvite%2FAB12CD&data=05',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'https://urldefense.proofpoint.com/v2/url?u=https-3A__realunit.app_invite_AB12CD&d=Dw',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'https://urldefense.com/v3/__https://realunit.app/promo/EVT1__;!!abc\$',
        ),
        'EVT1',
      );
      expect(
        referralCodeFromInput(
          'https://example.com/r/https://realunit.app/invite/AB12CD',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'https://r.search.yahoo.com/_ylt=x/RU=https%3A%2F%2Frealunit.app%2Fpromo%2FEVT1/RK=2',
        ),
        'EVT1',
      );
      expect(
        referralCodeFromInput('https://example.com/invite/AB12CD'),
        isNull,
      );
      expect(
        referralCodeFromInput(
          'https://www.google.com/amp/s/realunit.app/invite/AB12CD',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'https://cdn.ampproject.org/c/s/www.realunit.app/promo/EVT1',
        ),
        'EVT1',
      );
      expect(
        referralCodeFromInput(
          'https://www.google.com/amp/s/example.com/invite/AB12CD',
        ),
        isNull,
      );
      expect(
        referralCodeFromInput(
          'https://realunit.app/invite/intent://realunit.app/invite/AB12CD#Intent;scheme=https;end',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'https://realunit.app/invite/realunit-wallet://invite/AB12CD',
        ),
        'AB12CD',
      );
    });

    test('extracts the code from scheme-less and relative URLs', () {
      expect(referralCodeFromInput('realunit.app/invite/AB12CD'), 'AB12CD');
      expect(referralCodeFromInput('/invite/AB12CD'), 'AB12CD');
      expect(referralCodeFromInput('/promo/EVT1'), 'EVT1');
      expect(referralCodeFromInput('invite/AB12CD'), 'AB12CD');
    });

    test('extracts the code from wallet and Chrome intent URLs', () {
      expect(
        referralCodeFromInput('realunit-wallet://invite/AB12CD'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('realunit-wallet:promo/EVT1'),
        'EVT1',
      );
      expect(
        referralCodeFromInput(
          'intent://realunit.app/invite/AB12CD#Intent;scheme=https;package=swiss.realunit.app;end',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'intent://invite/AB12CD#Intent;scheme=realunit-wallet;package=swiss.realunit.app;end',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'intent://realunit.app/invite?code=AB12CD#Intent;scheme=https;package=swiss.realunit.app;end',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'intent://send?text=https%3A%2F%2Frealunit.app%2Finvite%2FAB12CD#Intent;scheme=whatsapp;end',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'intent://msg?text=https%3A%2F%2Frealunit.app%2Fpromo%2FEVT1#Intent;scheme=tg;end',
        ),
        'EVT1',
      );
      expect(
        referralCodeFromInput(
          'intent://send/#Intent;scheme=whatsapp;S.text=https%3A%2F%2Frealunit.app%2Finvite%2FAB12CD;end',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'intent://send/#Intent;scheme=whatsapp;S.browser_fallback_url=https%3A%2F%2Frealunit.app%2Finvite%2FAB12CD;end',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'intent://send?text=Tritt%20RealUnit%20bei%3A%20https%3A%2F%2Frealunit.app%2Finvite%2FAB12CD#Intent;scheme=whatsapp;end',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'intent://send?text=https://example.com/#Intent;scheme=whatsapp;end',
        ),
        isNull,
      );
    });

    test('extracts the code from android-app and ios-app alternate links', () {
      expect(
        referralCodeFromInput(
          'android-app://swiss.realunit.app/https/realunit.app/invite/AB12CD',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'android-app://swiss.realunit.app/https/realunit.app/promo/EVT1',
        ),
        'EVT1',
      );
      expect(
        referralCodeFromInput(
          'ios-app://6759720010/realunit-wallet/invite/AB12CD',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('ios-app://6759720010/promo/EVT1'),
        'EVT1',
      );
      expect(
        referralCodeFromInput(
          'android-app://swiss.realunit.app/https/realunit.app/invite?code=AB12CD',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'ios-app://6759720010/realunit-wallet/invite?code=AB12CD',
        ),
        'AB12CD',
      );
    });

    test('reads ?code= on a path that omitted the segment', () {
      expect(
        referralCodeFromInput('https://realunit.app/invite?code=AB12CD'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('https://realunit.app/invite#AB12CD'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('https://realunit.app/promo/#EVT1'),
        'EVT1',
      );
      expect(
        referralCodeFromInput('realunit-wallet://invite#AB12CD'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('https://realunit.app/invite/AB12CD#section'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('/promo?promo=EVT1'),
        'EVT1',
      );
      expect(referralCodeFromInput('invite?code=AB12CD'), 'AB12CD');
      expect(referralCodeFromInput('promo?promo=EVT1'), 'EVT1');
      expect(referralCodeFromInput('invite#AB12CD'), 'AB12CD');
      expect(referralCodeFromInput('promo#EVT1'), 'EVT1');
      expect(
        referralCodeFromInput('https://realunit.app?invite=AB12CD'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('https://realunit.app/?promo=EVT1'),
        'EVT1',
      );
      expect(
        referralCodeFromInput(
          'https://www.realunit.app?utm_content=invite%3DAB12CD',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('https://realunit.app/other?invite=AB12CD'),
        isNull,
      );
      expect(
        referralCodeFromInput(
          'https://realunit.app/invite?code=https://realunit.app/invite/AB12CD',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'https://realunit.app?invite=https://realunit.app/promo/EVT1',
        ),
        'EVT1',
      );
    });

    test('unwraps app-argument, utm_content, and referrer on a path without a code', () {
      expect(
        referralCodeFromInput(
          'https://realunit.app/invite?app-argument=realunit-wallet://invite/AB12CD',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'https://realunit.app/invite?utm_content=invite%3DAB12CD',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'https://realunit.app/invite?utm_content=https://realunit.app/invite/AB12CD',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('/promo?referrer=promo%3DEVT1'),
        'EVT1',
      );
      expect(
        referralCodeFromInput('https://realunit.app/invite?utm_content=summer-sale'),
        isNull,
      );
      expect(
        referralCodeFromInput(
          'https://realunit.app/invite?utm_content=summer-sale&u=https://realunit.app/invite/AB12CD',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'https://realunit.app/invite?code=https://example.com/foo&invite=AB12CD',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'https://realunit.app/invite?utm_content=${Uri.encodeComponent('https://realunit.app/invite?code=https://example.com/foo&invite=AB12CD')}',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'https://realunit.app/invite?utm_content=${Uri.encodeComponent('code=https://example.com&invite=AB12CD')}',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'https://realunit.app/invite?referrer=${Uri.encodeComponent('invite=https://example.com&promo=EVT1')}',
        ),
        'EVT1',
      );
      expect(
        referralCodeFromInput('https://realunit.app/promo?code=&promo=EVT1'),
        'EVT1',
      );
      expect(
        referralCodeFromInput(
          'https://realunit.app/invite?link=https://realunit.app/invite/AB12CD',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'https://realunit.app/invite/AB12CD?utm_content=OTHER',
        ),
        'AB12CD',
      );
    });

    test('extracts the code from a pasted share message', () {
      expect(
        referralCodeFromInput(
          'Hey Alice, Björn lädt dich ein: https://realunit.app/invite/AB12CD',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('“https://realunit.app/invite/AB12CD”'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('«https://realunit.app/promo/EVT1»'),
        'EVT1',
      );
      expect(
        referralCodeFromInput(
          'Hey Alice: “https://realunit.app/invite/AB12CD”',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          '[Hey Alice](https://realunit.app/invite/AB12CD)',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('(https://realunit.app/promo/EVT1)'),
        'EVT1',
      );
      expect(
        referralCodeFromInput(
          '<a href="https://realunit.app/invite/AB12CD">Hey</a>',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('href="https://realunit.app/promo/EVT1"'),
        'EVT1',
      );
      expect(
        referralCodeFromInput(
          '&quot;https://realunit.app/invite/AB12CD&quot;',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'href=&quot;https://realunit.app/promo/EVT1&quot;',
        ),
        'EVT1',
      );
      expect(
        referralCodeFromInput('https&#58;//realunit.app/invite/AB12CD'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'https&#x3a;&#x2f;&#x2f;realunit.app&#x2f;invite&#x2f;AB12CD',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('https://realunit.app&#47;promo&#47;EVT1'),
        'EVT1',
      );
      expect(
        referralCodeFromInput(
          'https&colon;//realunit.app&sol;invite&sol;AB12CD',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'https&colon;&sol;&sol;realunit.app&sol;promo&sol;EVT1',
        ),
        'EVT1',
      );
      expect(
        referralCodeFromInput('https：／／realunit.app／invite／AB12CD'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('https：//realunit.app/promo/EVT1'),
        'EVT1',
      );
      expect(referralCodeFromInput('ＡＢ１２ＣＤ'), 'AB12CD');
      expect(
        referralCodeFromInput('https://realunit.app/invite/ＡＢ１２ＣＤ'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('https:⁄⁄realunit.app⁄invite⁄AB12CD'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('https:∕∕realunit.app∕promo∕EVT1'),
        'EVT1',
      );
      expect(
        referralCodeFromInput('https∶//realunit.app/invite/AB12CD'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('https://realunit。app/invite/AB12CD'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('https://www。realunit。app/promo/EVT1'),
        'EVT1',
      );
      expect(
        referralCodeFromInput('https:\\/\\/realunit.app\\/invite\\/AB12CD'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          r'https\u003a\u002f\u002frealunit.app\u002finvite\u002fAB12CD',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          r'{"url":"https:\/\/realunit.app\/promo\/EVT1"}',
        ),
        'EVT1',
      );
      expect(
        referralCodeFromInput('https://realunit.app/invite/\nAB12CD'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('https://realunit.app/promo/\r\nEVT1'),
        'EVT1',
      );
      expect(
        referralCodeFromInput('https://realunit.app/ invite/AB12CD'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('https://realunit.app/\u2009invite/AB12CD'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('https://realunit.app/\u00A0promo/EVT1'),
        'EVT1',
      );
      expect(referralCodeFromInput('AB12\u202FCD'), 'AB12CD');
      expect(
        referralCodeFromInput('https:// realunit.app/invite/AB12CD please'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('> https://realunit.app/invite/AB12CD'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('> https://realunit.app/invite/\n> AB12CD'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('https://realunit.app/invite/\\\nAB12CD'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('https://realunit.app/promo/\\ \r\nEVT1'),
        'EVT1',
      );
      expect(
        referralCodeFromInput('https://realunit.app/invite/AB12-\nCD'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('https://realunit.app/in-\nvite/AB12CD'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('https://realunit.app/in\u2010\nvite/AB12CD'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('https://realunit.app/in\u2011\nvite/AB12CD'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('https://realunit.app/in\u2013\nvite/AB12CD'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('https://realunit.app/invite/AB12=\nCD'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('https://realunit.app/inv=\nite/AB12CD'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('https://realunit.app/promo/EVT=\r\n1'),
        'EVT1',
      );
      expect(
        referralCodeFromInput('https://realunit.app/invite/AB12= \nCD'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('https=3A=2F=2Frealunit.app=2Finvite=2FAB12CD'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('https=3a=2f=2frealunit.app=2fpromo=2fEVT1'),
        'EVT1',
      );
      expect(
        referralCodeFromInput('https://realunit.app=2Finvite=2FAB12CD'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('https://realunit.app/invite?code=3DAB12CD'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('https://realunit.app/invite?code=AB12CD'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          '=?UTF-8?Q?https=3A=2F=2Frealunit.app=2Finvite=2FAB12CD?=',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          '=?utf-8?q?https=3A=2F=2Frealunit.app=2Fpromo=2FEVT1?=',
        ),
        'EVT1',
      );
      expect(
        referralCodeFromInput(
          '=?UTF-8?B?aHR0cHM6Ly9yZWFsdW5pdC5hcHAvaW52aXRlL0FCMTJDRA==?=',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          '=?UTF-8?Q?https=3A=2F=2Frealunit.app=2Finv?= =?UTF-8?Q?ite=2FAB12CD?=',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('*https://realunit.app/invite/AB12CD*'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('_https://realunit.app/promo/EVT1_'),
        'EVT1',
      );
      expect(
        referralCodeFromInput('Hey: https://realunit.app/invite/AB12CD*'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('`https://realunit.app/invite/AB12CD`'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('See `https://realunit.app/promo/EVT1`'),
        'EVT1',
      );
      expect(
        referralCodeFromInput('```https://realunit.app/invite/AB12CD```'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('```\nhttps://realunit.app/promo/EVT1\n```'),
        'EVT1',
      );
      expect(
        referralCodeFromInput('| https://realunit.app/invite/AB12CD |'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('|https://realunit.app/promo/EVT1|'),
        'EVT1',
      );
      expect(
        referralCodeFromInput(
          'Hey Alice: https://realunit.app/invite?code=AB12CD please.',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'Hey Alice: https://realunit.app?invite=AB12CD please.',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'Tap https://realunit.app/invite?utm_content=invite%3DAB12CD',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'Open realunit-wallet://invite?code=AB12CD after install.',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'Hey Alice, RealUnit: https://realunit.app/promo/EVT1.',
        ),
        'EVT1',
      );
      expect(
        referralCodeFromInput(
          'Open realunit-wallet://invite/AB12CD after install.',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'Open intent://realunit.app/invite/AB12CD#Intent;scheme=https;package=swiss.realunit.app;end after install.',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'Open intent://realunit.app/invite?code=AB12CD#Intent;scheme=https;end after install.',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'See android-app://swiss.realunit.app/https/realunit.app/invite/AB12CD here.',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'Tap ios-app://6759720010/realunit-wallet/promo/EVT1 please.',
        ),
        'EVT1',
      );
      expect(
        referralCodeFromInput(
          'See android-app://swiss.realunit.app/https/realunit.app/invite?code=AB12CD here.',
        ),
        'AB12CD',
      );
      expect(
        referralCodeFromInput(
          'Tap ios-app://6759720010/realunit-wallet/invite?code=AB12CD please.',
        ),
        'AB12CD',
      );
    });

    test('strips wrapping quotes and angle brackets', () {
      expect(
        referralCodeFromInput('"https://realunit.app/invite/AB12CD"'),
        'AB12CD',
      );
      expect(
        referralCodeFromInput('<realunit-wallet://invite/AB12CD>'),
        'AB12CD',
      );
    });

    test('path remainder unwraps nested URLs and share messages', () {
      expect(
        referralCodeFromPathRemainder('https://realunit.app/invite/AB12CD'),
        'AB12CD',
      );
      expect(
        referralCodeFromPathRemainder(
          'Hey Alice: https://realunit.app/invite/AB12CD',
        ),
        'AB12CD',
      );
      expect(referralCodeFromPathRemainder('AB12CD/extra'), 'AB12CD');
      expect(referralCodeFromPathRemainder('AB%2F12'), 'AB/12');
      expect(referralCodeFromPathRemainder(''), isNull);
    });

    test('does not look up a recognized URL that has no code', () {
      expect(referralCodeFromInput('https://realunit.app/invite/'), isNull);
      expect(referralCodeFromInput('https://realunit.app/invite'), isNull);
      expect(referralCodeFromInput('https://example.com/invite/AB12'), isNull);
      expect(
        referralCodeFromInput(
          'android-app://swiss.realunit.app/https/other.app/invite/AB12',
        ),
        isNull,
      );
      expect(
        referralCodeFromInput('ios-app://6759720010/realunit-wallet/invite/'),
        isNull,
      );
    });
  });
}
