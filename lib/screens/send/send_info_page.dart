import 'package:flutter/material.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/screens/send/send_recipient_page.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';

class SendInfoPage extends StatelessWidget {
  const SendInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.of(context).sendInfoTitle)),
      body: SafeArea(
        child: Padding(
          padding: const .symmetric(horizontal: 20, vertical: 16),
          child: ScrollableActionsLayout(
            centerBody: true,
            body: Text(
              S.of(context).sendInfoBody,
              textAlign: .center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SendRecipientPage(),
                  ),
                ),
                child: Text(S.of(context).next),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
