import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/models/balance.dart';
import 'package:realunit_wallet/packages/repository/balance_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/screens/sell/cubits/sell_balance/sell_balance_cubit.dart';
import 'package:realunit_wallet/screens/send/cubits/send_amount/send_amount_cubit.dart';
import 'package:realunit_wallet/screens/send/send_confirm_page.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';

/// Second step: choose the whole-share REALU amount. The available balance is
/// read via the shared [SellBalanceCubit] (a generic REALU balance watcher) and
/// fed into [SendAmountCubit] for the local over-balance UX guard. REALU has
/// `decimals = 0`, so the raw balance equals whole shares.
class SendAmountPage extends StatelessWidget {
  final String recipient;

  const SendAmountPage({super.key, required this.recipient});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => SellBalanceCubit(getIt<BalanceRepository>(), getIt<AppStore>()),
        ),
        BlocProvider(create: (_) => SendAmountCubit()),
      ],
      child: SendAmountView(recipient: recipient),
    );
  }
}

class SendAmountView extends StatelessWidget {
  final String recipient;

  const SendAmountView({super.key, required this.recipient});

  @override
  Widget build(BuildContext context) {
    // The balance arrives over a stream; push every update into the amount
    // cubit so the available hint + over-balance guard track the live balance
    // (BlocProvider.create runs once, so the balance can't be captured there).
    return BlocListener<SellBalanceCubit, Balance>(
      listener: (context, balance) =>
          context.read<SendAmountCubit>().availableSharesChanged(balance.balance),
      child: _SendAmountBody(recipient: recipient),
    );
  }
}

class _SendAmountBody extends StatefulWidget {
  final String recipient;

  const _SendAmountBody({required this.recipient});

  @override
  State<_SendAmountBody> createState() => _SendAmountBodyState();
}

class _SendAmountBodyState extends State<_SendAmountBody> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncController(String text) {
    if (_controller.text == text) return;
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.of(context).sendAmountTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: BlocConsumer<SendAmountCubit, SendAmountState>(
            listenWhen: (previous, current) => previous.text != current.text,
            listener: (context, state) => _syncController(state.text),
            builder: (context, state) {
              // The available hint tracks the live balance directly so it stays
              // in sync with the stream.
              final available = context.watch<SellBalanceCubit>().state.balance;
              return ScrollableActionsLayout(
                body: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 16,
                  children: [
                    Text(
                      S.of(context).sendAmountAvailable(available.toString()),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: RealUnitColors.neutral500,
                      ),
                    ),
                    TextField(
                      controller: _controller,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: S.of(context).sendAmountLabel,
                        errorText: _errorText(context, state.status),
                        suffixIcon: TextButton(
                          onPressed: () => context.read<SendAmountCubit>().useMax(),
                          child: Text(S.of(context).max.toUpperCase()),
                        ),
                      ),
                      onChanged: (value) =>
                          context.read<SendAmountCubit>().amountChanged(value),
                    ),
                  ],
                ),
                actions: [
                  FilledButton(
                    onPressed: state.isValid
                        ? () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => SendConfirmPage(
                                recipient: widget.recipient,
                                amount: state.amount!,
                              ),
                            ),
                          )
                        : null,
                    child: Text(S.of(context).next),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  String? _errorText(BuildContext context, SendAmountStatus status) => switch (status) {
    SendAmountStatus.empty || SendAmountStatus.valid => null,
    SendAmountStatus.invalid => S.of(context).sendAmountInvalid,
    SendAmountStatus.insufficientBalance => S.of(context).sendAmountInsufficient,
  };
}
