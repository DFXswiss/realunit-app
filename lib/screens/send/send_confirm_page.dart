import 'package:flutter/material.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/screens/send/send_process_page.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';

/// Third step: review the recipient + amount before signing. Confirming starts
/// the on-chain process step.
class SendConfirmPage extends StatefulWidget {
  final String recipient;
  final int amount;

  const SendConfirmPage({super.key, required this.recipient, required this.amount});

  @override
  State<SendConfirmPage> createState() => _SendConfirmPageState();
}

class _SendConfirmPageState extends State<SendConfirmPage> {
  /// Once true, permanently disables the confirm button on this route instance
  /// so a second transfer cannot be re-triggered after push+pop of the process
  /// page (terminal navigation pattern).
  bool _navigating = false;

  @override
  Widget build(BuildContext context) {
    final recipient = widget.recipient;
    final amount = widget.amount;

    return Scaffold(
      appBar: AppBar(title: Text(S.of(context).sendConfirmTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: ScrollableActionsLayout(
            centerBody: true,
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 24,
              children: [
                Text(
                  S.of(context).sendConfirmSummary(amount.toString()),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                _SummaryRow(
                  label: S.of(context).sendConfirmAmount,
                  value: S.of(context).sendShares(amount.toString()),
                ),
                _SummaryRow(
                  label: S.of(context).sendConfirmRecipient,
                  value: recipient,
                ),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: _navigating
                    ? null
                    : () {
                        if (_navigating) {
                          return;
                        }
                        setState(() => _navigating = true);
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => SendProcessPage(recipient: recipient, amount: amount),
                          ),
                        );
                      },
                child: Text(S.of(context).sendConfirmButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 16,
      children: [
        Flexible(
          child: Text(
            label,
            softWrap: true,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: RealUnitColors.neutral500,
            ),
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            softWrap: true,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ],
    );
  }
}
