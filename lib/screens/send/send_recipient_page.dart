import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/screens/send/cubits/send_recipient/send_recipient_cubit.dart';
import 'package:realunit_wallet/screens/send/send_amount_page.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/scanner/qr_scanner_view.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';

/// First step of the wallet-to-wallet send flow: pick the recipient by scanning
/// a wallet QR or pasting/typing the address. Reuses the shared
/// [QrScannerView] (same camera wrapper the OCP pay flow uses) so the scanner is
/// not duplicated; the EVM-address decode lives in [SendRecipientCubit].
class SendRecipientPage extends StatelessWidget {
  const SendRecipientPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SendRecipientCubit(),
      child: const SendRecipientView(),
    );
  }
}

class SendRecipientView extends StatefulWidget {
  const SendRecipientView({super.key});

  @override
  State<SendRecipientView> createState() => _SendRecipientViewState();
}

class _SendRecipientViewState extends State<SendRecipientView> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<SendRecipientCubit, SendRecipientState>(
      listener: (context, state) {
        if (state is SendRecipientValid) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SendAmountPage(recipient: state.address),
            ),
          );
          context.read<SendRecipientCubit>().reset();
        }
        if (state is SendRecipientInvalid) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(S.of(context).sendRecipientInvalid),
              backgroundColor: RealUnitColors.status.red600,
            ),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(S.of(context).sendRecipientTitle)),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => Column(
              children: [
                Expanded(
                  child: QrScannerView(
                    onDetect: (raw) => context.read<SendRecipientCubit>().onCodeDetected(raw),
                  ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: constraints.maxHeight),
                  child: ScrollableActionsLayout(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    body: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 12,
                      children: [
                        Text(
                          S.of(context).sendRecipientManualHint,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: RealUnitColors.neutral500,
                          ),
                        ),
                        TextField(
                          controller: _controller,
                          autocorrect: false,
                          decoration: InputDecoration(
                            labelText: S.of(context).sendRecipientLabel,
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.paste_rounded),
                              tooltip: S.of(context).sendPaste,
                              onPressed: () async {
                                final data = await Clipboard.getData(Clipboard.kTextPlain);
                                final text = data?.text;
                                if (text != null) _controller.text = text.trim();
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      FilledButton(
                        onPressed: () =>
                            context.read<SendRecipientCubit>().submit(_controller.text),
                        child: Text(S.of(context).next),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
