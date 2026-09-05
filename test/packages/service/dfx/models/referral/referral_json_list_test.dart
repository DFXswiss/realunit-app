import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/referral_json_list.dart';

void main() {
  test('reads a bare JSON array of objects', () {
    expect(
      referralJsonList([
        {'id': 1},
        'skip',
        {'id': 2},
      ]),
      [
        {'id': 1},
        {'id': 2},
      ],
    );
  });

  test('unwraps invites, payouts, data, and items wrappers', () {
    expect(
      referralJsonList({
        'invites': [
          {'code': 'AB12'},
        ],
      }),
      [
        {'code': 'AB12'},
      ],
    );
    expect(
      referralJsonList({
        'payouts': [
          {'id': 9},
        ],
      }),
      [
        {'id': 9},
      ],
    );
    expect(
      referralJsonList({
        'data': [
          {'id': 1},
        ],
      }),
      [
        {'id': 1},
      ],
    );
    expect(
      referralJsonList({
        'items': [
          {'id': 2},
        ],
      }),
      [
        {'id': 2},
      ],
    );
  });

  test('unknown shapes yield an empty list', () {
    expect(referralJsonList(null), isEmpty);
    expect(referralJsonList('nope'), isEmpty);
    expect(referralJsonList({'count': 0}), isEmpty);
  });

  test('referralJsonNum reads JSON numbers and numeric strings', () {
    expect(referralJsonNum(20), 20);
    expect(referralJsonNum(246.5), 246.5);
    expect(referralJsonNum('20'), 20);
    expect(referralJsonNum(' 246.50 '), 246.5);
    expect(referralJsonNum('246,5'), 246.5);
    expect(referralJsonNum("1'246.50"), 1246.5);
    expect(referralJsonNum('1,246.50'), 1246.5);
    expect(referralJsonNum('1.246,50'), 1246.5);
    expect(referralJsonNum('CHF 246.50'), 246.5);
    expect(referralJsonNum(''), isNull);
    expect(referralJsonNum(null), isNull);
    expect(referralJsonInt('3'), 3);
    expect(referralJsonInt(null), 0);
  });

  test('referralJsonDate reads ISO strings and Unix seconds or milliseconds', () {
    expect(
      referralJsonDate('2026-08-24T10:00:00Z'),
      DateTime.utc(2026, 8, 24, 10),
    );
    expect(
      referralJsonDate(1787565600),
      DateTime.utc(2026, 8, 24, 10),
    );
    expect(
      referralJsonDate(1787565600000),
      DateTime.utc(2026, 8, 24, 10),
    );
    expect(referralJsonDate(' 1787565600 '), DateTime.utc(2026, 8, 24, 10));
    expect(referralJsonDate(null), isNull);
    expect(referralJsonDate(''), isNull);
    expect(referralJsonDate('nope'), isNull);
  });

  test(
    'referralJsonDate treats a zoneless MySQL DATETIME as UTC credit time',
    () {
      expect(
        referralJsonDate('2026-08-24 10:00:00'),
        DateTime.utc(2026, 8, 24, 10),
      );
      expect(
        referralJsonDate('2026-08-24T10:00:00'),
        DateTime.utc(2026, 8, 24, 10),
      );
      expect(
        referralJsonDate('2026-08-24T10:00:00.000'),
        DateTime.utc(2026, 8, 24, 10),
      );
      final local = DateTime(2026, 8, 24, 10);
      expect(referralJsonDate(local), local.toUtc());
      expect(
        referralJsonDate(DateTime.utc(2026, 8, 24, 10)),
        DateTime.utc(2026, 8, 24, 10),
      );
    },
  );

  test('referralJsonBool is fail-closed except true/1/yes', () {
    expect(referralJsonBool(true), isTrue);
    expect(referralJsonBool(false), isFalse);
    expect(referralJsonBool(1), isTrue);
    expect(referralJsonBool(0), isFalse);
    expect(referralJsonBool('true'), isTrue);
    expect(referralJsonBool('  YES  '), isTrue);
    expect(referralJsonBool('1'), isTrue);
    expect(referralJsonBool('false'), isFalse);
    expect(referralJsonBool('0'), isFalse);
    expect(referralJsonBool('no'), isFalse);
    expect(referralJsonBool(''), isFalse);
    expect(referralJsonBool('maybe'), isFalse);
    expect(referralJsonBool(null), isFalse);
  });

  test('referralJsonObject unwraps summary/data/item/result maps', () {
    expect(referralJsonObject(null), isEmpty);
    expect(referralJsonObject(['x']), isEmpty);
    expect(
      referralJsonObject({
        'summary': {'eligible': true},
      }),
      {'eligible': true},
    );
    expect(
      referralJsonObject({
        'data': {'kind': 'Promo'},
      }),
      {'kind': 'Promo'},
    );
    expect(referralJsonObject({'eligible': true}), {'eligible': true});
    expect(
      referralJsonObject({
        'data': ['not-a-map'],
        'eligible': true,
      }),
      {
        'data': ['not-a-map'],
        'eligible': true,
      },
    );
    expect(
      referralJsonObject(
        {
          'eligible': true,
          'data': {'kind': 'Promo'},
        },
        markers: const ['eligible'],
      ),
      {
        'eligible': true,
        'data': {'kind': 'Promo'},
      },
    );
    expect(
      referralJsonObject(
        {
          'invite': {
            'code': 'AB12',
            'url': 'https://realunit.app/invite/AB12',
            'guestName': 'Alice',
          },
        },
        markers: const ['code', 'url', 'guestName'],
      ),
      {
        'code': 'AB12',
        'url': 'https://realunit.app/invite/AB12',
        'guestName': 'Alice',
      },
    );
  });

  test('referralJsonString trims, stringifies numbers, and drops blanks', () {
    expect(referralJsonString('  AB12  '), 'AB12');
    expect(referralJsonString(12), '12');
    expect(referralJsonString('   '), isNull);
    expect(referralJsonString(null), isNull);
    expect(referralJsonString(true), isNull);
  });

  test('referralInviteUrl resolves relative and missing urls', () {
    expect(
      referralInviteUrl(url: 'https://realunit.app/invite/AB12'),
      'https://realunit.app/invite/AB12',
    );
    expect(
      referralInviteUrl(url: '/invite/AB12'),
      'https://realunit.app/invite/AB12',
    );
    expect(
      referralInviteUrl(url: 'http://realunit.app/invite/AB12'),
      'https://realunit.app/invite/AB12',
    );
    expect(
      referralInviteUrl(url: 'https://www.realunit.app/invite/AB12'),
      'https://realunit.app/invite/AB12',
    );
    expect(
      referralInviteUrl(url: 'http://www.realunit.app/invite/AB12'),
      'https://realunit.app/invite/AB12',
    );
    expect(
      referralInviteUrl(code: 'AB12'),
      'https://realunit.app/invite/AB12',
    );
    expect(
      referralInviteUrl(url: 'https://dev.realunit.app/invite/AB12'),
      'https://dev.realunit.app/invite/AB12',
    );
    expect(
      referralInviteUrl(url: '//realunit.app/invite/AB12'),
      'https://realunit.app/invite/AB12',
    );
    expect(
      referralInviteUrl(url: '//www.realunit.app/promo/EVT1'),
      'https://realunit.app/promo/EVT1',
    );
    expect(
      referralInviteUrl(url: 'realunit.app/invite/AB12'),
      'https://realunit.app/invite/AB12',
    );
    expect(
      referralInviteUrl(url: 'www.realunit.app/promo/EVT1'),
      'https://realunit.app/promo/EVT1',
    );
    expect(
      referralInviteUrl(url: '//dev.realunit.app/invite/AB12'),
      'https://dev.realunit.app/invite/AB12',
    );
    expect(
      referralInviteUrl(url: '//cdn.example/invite/AB12', code: 'AB12'),
      'https://cdn.example/invite/AB12',
    );
    expect(referralInviteUrl(), isNull);
  });

  test('referralPersonName keeps people and drops wallets and numeric ids', () {
    expect(referralPersonName('Björn'), 'Björn');
    expect(referralPersonName('  Alice  '), 'Alice');
    expect(referralPersonName('   '), isNull);
    expect(
      referralPersonName('0x553C7f9C780316FC1D34b8e14ac2465Ab22a090B'),
      isNull,
    );
    expect(referralPersonName('12345'), isNull);
    expect(referralPersonName(12345), isNull);
  });
}
