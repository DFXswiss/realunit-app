import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:realunit_wallet/styles/colors.dart';

class QRAddressWidget extends StatelessWidget {
  const QRAddressWidget({
    super.key,
    required this.uri,
    required this.subtitle,
  });

  final String uri;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    spacing: 12.0,
    children: [
      QrImageView(
        data: uri,
        size: 250,
        dataModuleStyle: const QrDataModuleStyle(
          color: RealUnitColors.realUnitBlack,
        ),
      ),
      InkWell(
        borderRadius: .circular(16.0),
        enableFeedback: false,
        onTap: _copyToClipboard,
        child: Container(
          padding: const .all(8.0),
          child: Row(
            crossAxisAlignment: .center,
            spacing: 20.0,
            children: [
              Flexible(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: _slice(subtitle, 0, 6),
                        style: const TextStyle(fontWeight: .bold),
                      ),
                      const TextSpan(text: ' '),
                      TextSpan(
                        text: _slice(subtitle, 6, 21),
                      ),
                      const TextSpan(text: '\n'),
                      TextSpan(
                        text: _slice(subtitle, 21, 36),
                      ),
                      const TextSpan(text: ' '),
                      TextSpan(
                        text: _slice(subtitle, 36),
                        style: const TextStyle(fontWeight: .bold),
                      ),
                    ],
                  ),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const Icon(
                Icons.copy_outlined,
                color: RealUnitColors.realUnitBlue,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    ],
  );

  Future<void> _copyToClipboard() => Clipboard.setData(ClipboardData(text: subtitle));

  // Clamp slice bounds to the string length so a short address can't throw RangeError.
  static String _slice(String value, int start, [int? end]) {
    if (start >= value.length) return '';
    final clampedEnd = end == null || end > value.length ? value.length : end;
    return value.substring(start, clampedEnd);
  }
}
