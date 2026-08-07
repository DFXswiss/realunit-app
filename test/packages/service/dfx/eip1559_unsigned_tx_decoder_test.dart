import 'dart:typed_data';

import 'package:convert/convert.dart' as convert;
import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/packages/service/dfx/eip1559_unsigned_tx_decoder.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/payment/pay_exceptions.dart';

/// Independently verified (Python reference RLP round-trip) EIP-1559 type-2 unsigned
/// tx: chainId=11155111, to=0x1111…ac01, value=0, ERC20 transfer to 0x2222…bc02 for
/// amount=5000000000000000000.
const _validUnsignedTx =
    '0x02f87183aa36a7018459682f008504a817c800830186a094111111111111111111111111111111111111ac0180b844a9059cbb000000000000000000000000222222222222222222222222222222222222bc020000000000000000000000000000000000000000000000004563918244f40000c0';

const _validCalldataHex =
    'a9059cbb000000000000000000000000222222222222222222222222222222222222bc020000000000000000000000000000000000000000000000004563918244f40000';

void main() {
  group('Eip1559UnsignedTxDecoder.decode', () {
    test('decodes a valid EIP-1559 ERC20-transfer unsigned tx', () {
      final tx = Eip1559UnsignedTxDecoder.decode(_validUnsignedTx);

      expect(tx.chainId, BigInt.from(11155111));
      expect(tx.maxPriorityFeePerGas, BigInt.from(1500000000));
      expect(tx.maxFeePerGas, BigInt.from(20000000000));
      expect(tx.gasLimit, BigInt.from(100000));
      expect(tx.to, '0x111111111111111111111111111111111111ac01');
      expect(tx.value, BigInt.zero);
      expect(tx.data.length, 68);
      expect(convert.hex.encode(tx.data), _validCalldataHex);
    });

    test('rejects long-form RLP length-of-length > 4 with typed exception (not RangeError)', () {
      // type=0x02, then long-STRING prefix 0xbf (lengthOfLength = 0xbf - 0xb7 = 8)
      // followed by 8 length-bytes '7ffffffffffffffe' (0x7ffffffffffffffe = 9223372036854775806)
      // so start2+length overflows a signed 64-bit int and wraps negative; without the
      // length-of-length cap, _requireBytes lets it through and data.sublist throws a raw
      // RangeError; must stay typed as PayUnsignedTxMismatchException.
      expect(
        () => Eip1559UnsignedTxDecoder.decode('0x02bf7ffffffffffffffe'),
        throwsA(isA<PayUnsignedTxMismatchException>()),
      );
    });

    test('rejects a non-type-2 transaction', () {
      expect(
        () => Eip1559UnsignedTxDecoder.decode(
          '0x01f87183aa36a7018459682f008504a817c800830186a094111111111111111111111111111111111111ac0180b844a9059cbb000000000000000000000000222222222222222222222222222222222222bc020000000000000000000000000000000000000000000000004563918244f40000c0',
        ),
        throwsA(isA<PayUnsignedTxMismatchException>()),
      );
    });

    test('rejects trailing bytes after a complete RLP encoding', () {
      expect(
        () => Eip1559UnsignedTxDecoder.decode(
          '0x02f87183aa36a7018459682f008504a817c800830186a094111111111111111111111111111111111111ac0180b844a9059cbb000000000000000000000000222222222222222222222222222222222222bc020000000000000000000000000000000000000000000000004563918244f40000c0ff',
        ),
        throwsA(isA<PayUnsignedTxMismatchException>()),
      );
    });

    test('rejects a truncated encoding', () {
      expect(
        () => Eip1559UnsignedTxDecoder.decode(
          '0x02f87183aa36a7018459682f008504a817c800830186a094111111111111111111111111111111111111ac0180b844a9059cbb000000000000000000000000222222222222222222222222222222222222bc0200000000000000000000000000000000000000000000000045639182',
        ),
        throwsA(isA<PayUnsignedTxMismatchException>()),
      );
    });

    test('rejects a tx whose RLP root has the wrong field count (accessList stripped)', () {
      // Same tx as _validUnsignedTx but with the trailing accessList field (empty list `c0`)
      // removed and the outer list-length prefix corrected from 0x71 (113 bytes) to 0x70
      // (112 bytes) so the RLP still decodes cleanly with zero trailing bytes — root then has
      // 8 fields instead of 9. Verified byte-for-byte against a reference RLP decoder.
      expect(
        () => Eip1559UnsignedTxDecoder.decode(
          '0x02f87083aa36a7018459682f008504a817c800830186a094111111111111111111111111111111111111ac0180b844a9059cbb000000000000000000000000222222222222222222222222222222222222bc020000000000000000000000000000000000000000000000004563918244f40000',
        ),
        throwsA(
          isA<PayUnsignedTxMismatchException>().having(
            (e) => e.reason,
            'reason',
            'unsigned tx has 8 RLP fields, expected 9',
          ),
        ),
      );
    });

    test('rejects invalid hex', () {
      expect(
        () => Eip1559UnsignedTxDecoder.decode('0x02zzzz'),
        throwsA(isA<PayUnsignedTxMismatchException>()),
      );
    });

    test('rejects an empty string', () {
      expect(
        () => Eip1559UnsignedTxDecoder.decode(''),
        throwsA(isA<PayUnsignedTxMismatchException>()),
      );
    });

    test('rejects a non-empty access list', () {
      // Same as _validUnsignedTx but trailing empty accessList `c0` replaced with
      // `c180` (RLP list of one empty string) and the outer list-length prefix
      // bumped from 0x71 (113) to 0x72 (114) for the extra payload byte. Verified
      // by counting payload bytes after `f872` = 114.
      expect(
        () => Eip1559UnsignedTxDecoder.decode(
          '0x02f87283aa36a7018459682f008504a817c800830186a094111111111111111111111111111111111111ac0180b844a9059cbb000000000000000000000000222222222222222222222222222222222222bc020000000000000000000000000000000000000000000000004563918244f40000c180',
        ),
        throwsA(
          isA<PayUnsignedTxMismatchException>().having(
            (e) => e.reason,
            'reason',
            'unsigned tx "accessList" must be an empty RLP list',
          ),
        ),
      );
    });

    test('rejects a quantity field with a non-canonical leading zero byte', () {
      // Same as _validUnsignedTx but gasLimit `830186a0` (canonical 100000) replaced
      // with `84000186a0` (same magnitude, leading 0x00 — non-canonical RLP integer)
      // and outer list-length 0x71→0x72 for the extra byte. Verified: only the
      // gasLimit encoding and length prefix differ from _validUnsignedTx.
      expect(
        () => Eip1559UnsignedTxDecoder.decode(
          '0x02f87283aa36a7018459682f008504a817c80084000186a094111111111111111111111111111111111111ac0180b844a9059cbb000000000000000000000000222222222222222222222222222222222222bc020000000000000000000000000000000000000000000000004563918244f40000c0',
        ),
        throwsA(
          isA<PayUnsignedTxMismatchException>().having(
            (e) => e.reason,
            'reason',
            'unsigned tx "gasLimit" has a non-canonical leading zero byte',
          ),
        ),
      );
    });

    // Canonical bare-byte nonce `01` is already accepted by
    // 'decodes a valid EIP-1559 ERC20-transfer unsigned tx' above.
    test('rejects a non-canonical single-byte short string (nonce encoded as 8101 instead of bare 01)',
        () {
      // Same as _validUnsignedTx but the nonce field (RLP field index 1, right after chainId
      // `83aa36a7`) is re-encoded from the canonical bare byte `01` to the non-canonical length-1
      // short string `8101` (same decoded value, 1), and the outer list-length prefix is bumped
      // from 0x71 (113 bytes) to 0x72 (114 bytes) for the extra encoding byte. Independently
      // verified byte-for-byte against a reference RLP decoder (only the nonce encoding and the
      // outer list-length prefix differ from _validUnsignedTx; every other field decodes to the
      // identical value).
      expect(
        () => Eip1559UnsignedTxDecoder.decode(
          '0x02f87283aa36a781018459682f008504a817c800830186a094111111111111111111111111111111111111ac0180b844a9059cbb000000000000000000000000222222222222222222222222222222222222bc020000000000000000000000000000000000000000000000004563918244f40000c0',
        ),
        throwsA(
          isA<PayUnsignedTxMismatchException>().having(
            (e) => e.reason,
            'reason',
            'RLP: non-canonical single-byte short string (must be the bare byte, not a length-1 string)',
          ),
        ),
      );
    });

    test('rejects a quantity field that is an RLP list instead of a byte string', () {
      // RLP: type=0x02, long-form list (f8 65 = 101-byte body), fields:
      // chainId=<empty list c0> (invalid: must be a byte string), nonce=1,
      // maxPriorityFeePerGas=1, maxFeePerGas=1, gasLimit=100000 (830186a0),
      // to=20 zero-ish bytes (94 + 20x11), value=0 (80), data=68-byte ERC20
      // transfer calldata (b844...), accessList=<empty list c0>. Independently
      // constructed (not derived from _validUnsignedTx by truncation) and
      // verified byte-for-byte against a reference RLP encoder/decoder so that
      // every check before `_requireCanonicalInteger(root[chainId], 'chainId')`
      // passes, and that call is the first one reached — hitting exactly the
      // "field is not a Uint8List" branch for the chainId field.
      expect(
        () => Eip1559UnsignedTxDecoder.decode(
          '0x02f865c0010101830186a094111111111111111111111111111111111111111180b844a9059cbb000000000000000000000000222222222222222222222222222222222222bc020000000000000000000000000000000000000000000000004563918244f40000c0',
        ),
        throwsA(
          isA<PayUnsignedTxMismatchException>().having(
            (e) => e.reason,
            'reason',
            'unsigned tx "chainId" is not a byte string',
          ),
        ),
      );
    });

    test('rejects a non-minimal long-form string length encoding', () {
      // type=0x02, then long-form string prefix 0xb8 (lengthOfLength=1) with
      // length byte 0x01 (≤55) and one payload byte — must use short-form 0x81
      // instead. Hits the long-form string branch before root-type checks.
      expect(
        () => Eip1559UnsignedTxDecoder.decode('0x02b80101'),
        throwsA(
          isA<PayUnsignedTxMismatchException>().having(
            (e) => e.reason,
            'reason',
            'RLP: non-minimal long-form string length encoding',
          ),
        ),
      );
    });

    test('rejects a non-minimal long-form list length encoding', () {
      // type=0x02, then long-form list prefix 0xf8 (lengthOfLength=1) with
      // length byte 0x01 (≤55) and one payload byte `80` — must use short-form
      // 0xc1 instead. Hits the long-form list branch before field-count checks.
      expect(
        () => Eip1559UnsignedTxDecoder.decode('0x02f80180'),
        throwsA(
          isA<PayUnsignedTxMismatchException>().having(
            (e) => e.reason,
            'reason',
            'RLP: non-minimal long-form list length encoding',
          ),
        ),
      );
    });

    test('rejects a length-of-length encoding with a leading zero byte', () {
      // type=0x02, long-form string prefix 0xb9 (lengthOfLength=2) with length
      // bytes `00 40` (=64) — a minimal length-of-length never needs a leading
      // zero; must use a single length byte instead. Verified: lengthOfLength=2
      // and bytes[0]==0 hit the new _bytesToLength guard before the length≤55
      // check (which would also reject 64… wait, 64>55, so only the leading-zero
      // guard rejects this fixture).
      expect(
        () => Eip1559UnsignedTxDecoder.decode(
          '0x02b90040${'11' * 64}',
        ),
        throwsA(
          isA<PayUnsignedTxMismatchException>().having(
            (e) => e.reason,
            'reason',
            'RLP: non-minimal length-of-length encoding (leading zero byte)',
          ),
        ),
      );
    });
  });

  group('Erc20TransferCalldataDecoder.decode', () {
    test('decodes a valid transfer(address,uint256) call', () {
      final data = Uint8List.fromList(convert.hex.decode(_validCalldataHex));
      final transfer = Erc20TransferCalldataDecoder.decode(data);

      expect(transfer.recipient, '0x222222222222222222222222222222222222bc02');
      expect(transfer.amountWei, BigInt.parse('5000000000000000000'));
    });

    test('rejects a wrong function selector', () {
      final data = Uint8List.fromList(
        convert.hex.decode(
          'aaaaaaaa000000000000000000000000222222222222222222222222222222222222bc020000000000000000000000000000000000000000000000004563918244f40000',
        ),
      );
      expect(
        () => Erc20TransferCalldataDecoder.decode(data),
        throwsA(isA<PayUnsignedTxMismatchException>()),
      );
    });

    test('rejects wrong calldata length', () {
      final data = Uint8List.fromList(
        convert.hex.decode(
          'a9059cbb000000000000000000000000222222222222222222222222222222222222bc020000000000000000000000000000000000000000000000004563918244f400',
        ),
      );
      expect(
        () => Erc20TransferCalldataDecoder.decode(data),
        throwsA(isA<PayUnsignedTxMismatchException>()),
      );
    });

    test('rejects a non-zero-padded recipient address slot', () {
      final data = Uint8List.fromList(
        convert.hex.decode(
          'a9059cbb010000000000000000000000222222222222222222222222222222222222bc020000000000000000000000000000000000000000000000004563918244f40000',
        ),
      );
      expect(
        () => Erc20TransferCalldataDecoder.decode(data),
        throwsA(isA<PayUnsignedTxMismatchException>()),
      );
    });
  });
}
