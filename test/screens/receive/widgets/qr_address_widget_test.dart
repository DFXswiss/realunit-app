import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:realunit_wallet/screens/receive/widgets/qr_address_widget.dart';

const _address = '0x9F5713DEacB8e9CAB6c2d3FaE1AFc2715F8D2D71';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('$QRAddressWidget', () {
    testWidgets('renders a QrImageView for the uri', (tester) async {
      await tester.pumpWidget(_host(
        const QRAddressWidget(uri: 'ethereum:$_address', subtitle: _address),
      ));

      expect(find.byType(QrImageView), findsOneWidget);
    });

    testWidgets('renders the address as one Text.rich containing all chunks',
        (tester) async {
      await tester.pumpWidget(_host(
        const QRAddressWidget(uri: '', subtitle: _address),
      ));

      // RichText is rendered with concatenated text — find.textContaining
      // walks descendants, hitting the rendered TextSpan tree.
      expect(find.textContaining(_address.substring(0, 6)), findsAtLeastNWidgets(1));
      expect(find.textContaining(_address.substring(36)), findsAtLeastNWidgets(1));

      // Pin the exact 4-chunk grouping: 6 bold / 15 / 15 / 6 bold, joined by ' ', '\n', ' '.
      final text = tester.widget<Text>(find.byType(Text));
      expect(
        text.textSpan!.toPlainText(),
        '${_address.substring(0, 6)} ${_address.substring(6, 21)}\n'
        '${_address.substring(21, 36)} ${_address.substring(36)}',
      );
    });

    testWidgets('renders a copy icon next to the address', (tester) async {
      await tester.pumpWidget(_host(
        const QRAddressWidget(uri: '', subtitle: _address),
      ));

      expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
    });

    testWidgets('tapping the address row is wrapped in a tappable InkWell',
        (tester) async {
      await tester.pumpWidget(_host(
        const QRAddressWidget(uri: '', subtitle: _address),
      ));

      // Tapping should not throw (clipboard plugin is no-op in test bindings).
      await tester.tap(find.byType(InkWell));
      await tester.pump();
    });

    testWidgets(
        'renders a short/unexpected address without a RangeError '
        '(issue #657 P6 regression)', (tester) async {
      // A too-short subtitle used to crash on the fixed-index substring(6, 21)
      // etc. — it must now render gracefully on Receive and Settings.
      await tester.pumpWidget(_host(
        const QRAddressWidget(uri: '', subtitle: '0x1234'),
      ));

      expect(tester.takeException(), isNull);
      expect(find.textContaining('0x1234'), findsAtLeastNWidgets(1));

      // The extreme case: an empty address must also not throw.
      await tester.pumpWidget(_host(
        const QRAddressWidget(uri: '', subtitle: ''),
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('address row shrink-wraps so the parent Column can center it',
        (tester) async {
      await tester.pumpWidget(_host(
        const QRAddressWidget(uri: 'ethereum:$_address', subtitle: _address),
      ));

      final row = tester.widget<Row>(
        find.descendant(
          of: find.byType(InkWell),
          matching: find.byType(Row),
        ),
      );
      expect(row.mainAxisSize, MainAxisSize.min);

      final inkSize = tester.getSize(find.byType(InkWell));
      final screenWidth = tester.getSize(find.byType(Scaffold)).width;
      expect(inkSize.width, lessThan(screenWidth));
    });
  });
}
