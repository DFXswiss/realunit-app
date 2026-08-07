import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/repository/balance_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_brokerbot_service.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_sell_payment_info_service.dart';
import 'package:realunit_wallet/screens/sell/cubits/sell_balance/sell_balance_cubit.dart';
import 'package:realunit_wallet/screens/sell/cubits/sell_converter/sell_converter_cubit.dart';
import 'package:realunit_wallet/screens/sell/cubits/sell_payment_info/sell_payment_info_cubit.dart';
import 'package:realunit_wallet/screens/sell/cubits/sell_selected_bank_account/sell_selected_bank_account_cubit.dart';
import 'package:realunit_wallet/screens/sell/widgets/sell_bank_account_field.dart';
import 'package:realunit_wallet/screens/sell/widgets/sell_button.dart';
import 'package:realunit_wallet/screens/sell/widgets/sell_converter.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';

class SellPage extends StatelessWidget {
  const SellPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => SellBalanceCubit(
            getIt<BalanceRepository>(),
            getIt<AppStore>(),
          ),
        ),
        BlocProvider(
          create: (context) => SellConverterCubit(
            getIt<DfxBrokerbotService>(),
          )..onSharesChanged('100'),
        ),
        BlocProvider(
          create: (context) => SellPaymentInfoCubit(
            getIt<RealUnitSellPaymentInfoService>(),
            getIt<AppStore>(),
          ),
        ),
        BlocProvider(
          create: (context) => SellSelectedBankAccountCubit(),
        ),
      ],
      child: const SellView(),
    );
  }
}

class SellView extends StatefulWidget {
  const SellView({super.key});

  @override
  State<SellView> createState() => _SellViewState();
}

class _SellViewState extends State<SellView> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _resultController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          S.of(context).sellRealu,
        ),
      ),
      body: BlocConsumer<SellConverterCubit, SellConverterState>(
        listenWhen: (prev, next) => prev.loading && !next.loading,
        listener: (context, state) {
          _syncController(_amountController, state.sharesText);
          _syncController(_resultController, state.fiatText);
        },
        builder: (context, state) {
          return SafeArea(
            child: GestureDetector(
              behavior: .opaque,
              onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              child: ScrollableActionsLayout(
                centerBody: false,
                // Horizontal 20 applied to body + sticky actions so the CTA
                // stays inset like the pre-migration Column-wide Padding.
                padding: const .symmetric(horizontal: 20.0),
                body: Column(
                  mainAxisAlignment: .start,
                  spacing: 32,
                  children: [
                    SellConverter(
                      amountController: _amountController,
                      resultController: _resultController,
                    ),
                    const SellBankAccountField(),
                  ],
                ),
                actions: [
                  SellButton(
                    amount: _amountController.text,
                    bankAccount: context.watch<SellSelectedBankAccountCubit>().state,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _syncController(TextEditingController controller, String newValue) {
    if (controller.text == newValue) return;

    controller.value = controller.value.copyWith(
      text: newValue,
      selection: TextSelection.collapsed(offset: newValue.length),
      composing: TextRange.empty,
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _resultController.dispose();
    super.dispose();
  }
}
