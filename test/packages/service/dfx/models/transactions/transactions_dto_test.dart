import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/packages/service/dfx/models/transactions/dto/transactions_dto.dart';

void main() {
  group('$TransactionType.fromString', () {
    test('resolves Buy / Sell / Swap / Referral', () {
      expect(TransactionType.fromString('Buy'), TransactionType.buy);
      expect(TransactionType.fromString('Sell'), TransactionType.sell);
      expect(TransactionType.fromString('Swap'), TransactionType.swap);
      expect(TransactionType.fromString('Referral'), TransactionType.referral);
    });

    test('returns null for null input', () {
      expect(TransactionType.fromString(null), isNull);
    });

    test('returns null for unknown value (no throw)', () {
      // The factory uses firstWhere with `orElse: () => null` — pinned so
      // a new server-side type doesn't crash deserialisation.
      expect(TransactionType.fromString('NewType'), isNull);
    });
  });

  group('$TransactionState', () {
    group('fromString', () {
      test('resolves several canonical states', () {
        expect(TransactionState.fromString('Created'), TransactionState.created);
        expect(TransactionState.fromString('Completed'), TransactionState.completed);
        expect(TransactionState.fromString('Failed'), TransactionState.failed);
        expect(TransactionState.fromString('Returned'), TransactionState.returned);
      });

      test('returns null on null and unknown', () {
        expect(TransactionState.fromString(null), isNull);
        expect(TransactionState.fromString('NotAState'), isNull);
      });
    });

    group('isPending', () {
      test('completed / failed / returned are NOT pending', () {
        expect(TransactionState.completed.isPending, isFalse);
        expect(TransactionState.failed.isPending, isFalse);
        expect(TransactionState.returned.isPending, isFalse);
      });

      test('all other states ARE pending', () {
        for (final s in TransactionState.values) {
          final shouldBePending =
              s != TransactionState.completed &&
              s != TransactionState.failed &&
              s != TransactionState.returned;
          expect(s.isPending, shouldBePending, reason: 'state=$s');
        }
      });
    });
  });

  group('$TransactionDto.fromJson', () {
    test('parses a complete row with all fields populated', () {
      final dto = TransactionDto.fromJson({
        'id': 42,
        'uid': 'quote-uid-42',
        'type': 'Buy',
        'state': 'Processing',
        'rate': 1.05,
        'inputAmount': 100.0,
        'inputAsset': 'CHF',
        'inputTxId': '0xin',
        'outputAmount': 95.0,
        'outputAsset': 'REALU',
        'outputTxId': '0xout',
        'date': '2026-05-15T10:00:00Z',
        'sourceAccount': '0xsrc',
        'targetAccount': '0xtgt',
      });

      expect(dto.id, 42);
      expect(dto.uid, 'quote-uid-42');
      expect(dto.type, TransactionType.buy);
      expect(dto.state, TransactionState.processing);
      expect(dto.rate, 1.05);
      expect(dto.inputAmount, 100.0);
      expect(dto.inputAsset, 'CHF');
      expect(dto.inputTxId, '0xin');
      expect(dto.outputTxId, '0xout');
      expect(dto.date, DateTime.utc(2026, 5, 15, 10));
      expect(dto.sourceAccount, '0xsrc');
      expect(dto.targetAccount, '0xtgt');
    });

    test('every field is optional (all nulls produce all-null dto)', () {
      final dto = TransactionDto.fromJson({
        'id': null,
        'uid': null,
        'type': null,
        'state': null,
        'rate': null,
        'inputAmount': null,
        'inputAsset': null,
        'inputTxId': null,
        'outputAmount': null,
        'outputAsset': null,
        'outputTxId': null,
        'date': null,
        'sourceAccount': null,
        'targetAccount': null,
      });

      expect(dto.id, isNull);
      expect(dto.uid, isNull);
      expect(dto.type, isNull);
      expect(dto.state, isNull);
      expect(dto.rate, isNull);
      expect(dto.date, isNull);
    });

    test('waiting quote has null id and a uid', () {
      final dto = TransactionDto.fromJson({
        'id': null,
        'uid': 'waiting-uid',
        'type': 'Buy',
        'state': 'WaitingForPayment',
      });

      expect(dto.id, isNull);
      expect(dto.uid, 'waiting-uid');
      expect(dto.type, TransactionType.buy);
      expect(dto.state, TransactionState.waitingForPayment);
    });

    test('integer numeric fields are widened to double', () {
      final dto = TransactionDto.fromJson({
        'rate': 1, // integer on the wire
        'inputAmount': 100,
        'outputAmount': 95,
      });

      expect(dto.rate, 1.0);
      expect(dto.inputAmount, 100.0);
      expect(dto.outputAmount, 95.0);
    });
  });

  group('$TransactionDto behaviour helpers', () {
    test('isPending mirrors the state.isPending (false when state is null)', () {
      final dto = TransactionDto.fromJson({'state': null});

      expect(dto.isPending, isFalse);
    });

    test('belongsToWallet matches sourceAccount (case-insensitive)', () {
      final dto = TransactionDto.fromJson({
        'sourceAccount': '0xABCDEF',
        'targetAccount': null,
      });

      expect(dto.belongsToWallet('0xabcdef'), isTrue);
      expect(dto.belongsToWallet('0xABCDEF'), isTrue);
      expect(dto.belongsToWallet('0xother'), isFalse);
    });

    test('belongsToWallet matches targetAccount when source is null', () {
      final dto = TransactionDto.fromJson({
        'sourceAccount': null,
        'targetAccount': '0xWALLET',
      });

      expect(dto.belongsToWallet('0xwallet'), isTrue);
    });

    test('belongsToWallet returns false when both source and target are null', () {
      final dto = TransactionDto.fromJson({});

      expect(dto.belongsToWallet('0xany'), isFalse);
    });
  });
}
