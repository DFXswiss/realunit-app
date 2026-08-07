import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_brokerbot_service.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_buy_payment_info_service.dart';
import 'package:realunit_wallet/screens/buy/cubits/buy_converter/buy_converter_cubit.dart';
import 'package:realunit_wallet/screens/buy/cubits/buy_payment_info/buy_payment_info_cubit.dart';
import 'package:realunit_wallet/screens/buy/widgets/payment_action_button.dart';
import 'package:realunit_wallet/screens/buy/widgets/payment_converter.dart';
import 'package:realunit_wallet/screens/buy/widgets/payment_information.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';

class BuyPage extends StatelessWidget {
  const BuyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => BuyConverterCubit(
            getIt<DfxBrokerbotService>(),
          )..onFiatChanged('300'),
        ),
        BlocProvider(
          create: (_) => BuyPaymentInfoCubit(
            getIt<RealUnitBuyPaymentInfoService>(),
          ),
        ),
      ],
      child: const BuyView(),
    );
  }
}

class BuyView extends StatefulWidget {
  const BuyView({super.key});

  @override
  State<BuyView> createState() => _BuyViewState();
}

class _BuyViewState extends State<BuyView> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _resultController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          S.of(context).buyRealu,
        ),
      ),
      body: BlocConsumer<BuyConverterCubit, BuyConverterState>(
        listenWhen: (prev, next) => prev.loading && !next.loading,
        listener: (context, state) {
          _syncController(_amountController, state.fiatText);
          _syncController(_resultController, state.sharesText);
          context.read<BuyPaymentInfoCubit>().getPaymentInfo(
            amount: _amountController.text,
            currency: state.currency,
          );
        },
        builder: (context, state) {
          return GestureDetector(
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            child: Padding(
              padding: const .symmetric(horizontal: 20.0),
              child: SafeArea(
                child: ScrollableActionsLayout(
                  centerBody: false,
                  body: Column(
                    crossAxisAlignment: .start,
                    mainAxisAlignment: .start,
                    children: [
                      PaymentConverter(
                        amountController: _amountController,
                        resultController: _resultController,
                      ),
                      const SizedBox(height: 32),
                      const PaymentInformation(),
                    ],
                  ),
                  actions: [
                    PaymentActionButton(
                      amountController: _amountController,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _resultController.dispose();
    super.dispose();
  }

  void _syncController(TextEditingController controller, String newValue) {
    if (controller.text == newValue) return;

    controller.value = controller.value.copyWith(
      text: newValue,
      selection: .collapsed(offset: newValue.length),
      composing: .empty,
    );
  }
}
