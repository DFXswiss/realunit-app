import 'package:flutter/material.dart';
import 'package:realunit_wallet/styles/colors.dart';

class PaymentActionRequired extends StatelessWidget {
  final String title;
  final String description;

  const PaymentActionRequired({
    super.key,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: 20,
      crossAxisAlignment: .center,
      children: [
        Row(
          spacing: 12,
          children: [
            const Icon(
              Icons.info,
              size: 24,
              color: RealUnitColors.realUnitBlue,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: .w600,
                    ),
                  ),
                  if (description.isNotEmpty)
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
