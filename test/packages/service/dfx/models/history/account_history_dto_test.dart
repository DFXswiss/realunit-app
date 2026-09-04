import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/packages/service/dfx/models/history/dto/account_history_dto.dart';

void main() {
  group('$TransferDto.fromJson', () {
    test('parses from / to / value', () {
      final dto = TransferDto.fromJson({
        'from': '0xa',
        'to': '0xb',
        'value': '1000000',
      });

      expect(dto.from, '0xa');
      expect(dto.to, '0xb');
      // Value stays a string (downstream parses to BigInt where needed).
      expect(dto.value, '1000000');
    });
  });

  group('$HistoryEventDto.fromJson', () {
    test('parses an entry with a transfer object', () {
      final dto = HistoryEventDto.fromJson({
        'timestamp': '2026-05-15T10:00:00Z',
        'txHash': '0xabc',
        'transfer': {
          'from': '0xa',
          'to': '0xb',
          'value': '1',
        },
      });

      expect(dto.timestamp, DateTime.utc(2026, 5, 15, 10));
      expect(dto.txHash, '0xabc');
      expect(dto.transfer, isNotNull);
      expect(dto.transfer!.from, '0xa');
    });

    test('transfer is optional (null on the wire stays null)', () {
      final dto = HistoryEventDto.fromJson({
        'timestamp': '2026-05-15T10:00:00Z',
        'txHash': '0xabc',
        'transfer': null,
      });

      expect(dto.transfer, isNull);
    });

    test('parses a string category', () {
      final dto = HistoryEventDto.fromJson({
        'timestamp': '2026-05-15T10:00:00Z',
        'txHash': '0xabc',
        'category': 'transferIn',
      });

      expect(dto.category, 'transferIn');
    });
  });

  group('$AccountHistoryDto.fromJson', () {
    test('parses the wallet address + history list + totalCount', () {
      final dto = AccountHistoryDto.fromJson({
        'address': '0xwallet',
        'history': [
          {
            'timestamp': '2026-05-15T10:00:00Z',
            'txHash': '0xabc',
            'transfer': null,
          },
          {
            'timestamp': '2026-05-16T10:00:00Z',
            'txHash': '0xdef',
            'transfer': {'from': '0xa', 'to': '0xwallet', 'value': '50'},
          },
        ],
        'totalCount': 42,
      });

      expect(dto.address, '0xwallet');
      expect(dto.history, hasLength(2));
      expect(dto.history.last.transfer!.to, '0xwallet');
      expect(dto.totalCount, 42);
    });

    test('empty history list is allowed', () {
      final dto = AccountHistoryDto.fromJson({
        'address': '0xwallet',
        'history': <Map<String, dynamic>>[],
        'totalCount': 0,
      });

      expect(dto.history, isEmpty);
      expect(dto.totalCount, 0);
    });
  });
}
