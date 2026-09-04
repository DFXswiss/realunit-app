import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/packages/io/format_frozen_chf.dart';

void main() {
  test('formats a frozen CHF amount to two decimals', () {
    expect(formatFrozenChfAmount('246.5'), '246.50');
    expect(formatFrozenChfAmount('20'), '20.00');
    expect(formatFrozenChfAmount('246,5'), '246.50');
    expect(formatFrozenChfAmount(' 512.4 '), '512.40');
    expect(formatFrozenChfAmount("1'246.5"), '1246.50');
    expect(formatFrozenChfAmount('1.246,50'), '1246.50');
    expect(formatFrozenChfAmount('CHF 246,5'), '246.50');
    expect(formatFrozenChfAmount('not-a-number'), 'not-a-number');
  });

  test('referralPayoutSemanticsLabel joins title, date, CHF and amount', () {
    expect(
      referralPayoutSemanticsLabel(
        title: 'Empfehlungsprämie',
        date: '24.08.2026 | 12:00',
        amount: '+ 20 REALU',
        chfLine: 'CHF 246.50 zum Zeitpunkt der Gutschrift',
      ),
      'Empfehlungsprämie. 24.08.2026 | 12:00. CHF 246.50 zum Zeitpunkt der Gutschrift. + 20 REALU',
    );
    expect(
      referralPayoutAmountText(
        hideAmounts: false,
        amount: BigInt.from(20),
        decimals: 0,
        symbol: 'REALU',
      ),
      '+ 20 REALU',
    );
    expect(
      referralPayoutAmountText(
        hideAmounts: true,
        amount: BigInt.from(20),
        decimals: 0,
        symbol: 'REALU',
      ),
      '+ ***.**',
    );
  });
}
