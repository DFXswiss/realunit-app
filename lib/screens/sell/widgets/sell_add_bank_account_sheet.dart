import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/screens/sell/cubits/sell_bank_accounts/sell_bank_accounts_cubit.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/iban_input_formatter.dart';

class SellAddBankAccountSheet extends StatefulWidget {
  const SellAddBankAccountSheet({super.key});

  @override
  State<SellAddBankAccountSheet> createState() => _SellAddBankAccountSheetState();
}

class _SellAddBankAccountSheetState extends State<SellAddBankAccountSheet> {
  final _ibanController = TextEditingController();
  final _nameController = TextEditingController();

  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    return BlocListener<SellBankAccountsCubit, SellBankAccountsState>(
      listenWhen: (previous, current) =>
          previous is SellBankAccountsLoading &&
          (current is SellBankAccountsAddFailure || current is SellBankAccountsSuccess),
      listener: (context, state) {
        if (state is SellBankAccountsAddFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: RealUnitColors.status.red600,
            ),
          );
        }
        context.pop();
      },
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SizedBox(
              width: double.infinity,
              height: constraints.maxHeight * 0.87,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
                    child: AppBar(
                      title: Text(
                        S.of(context).payoutAccountAdd,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20.0,
                      vertical: 12.0,
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        spacing: 16,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                child: Text(
                                  S.of(context).iban,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    height: 18 / 13,
                                  ),
                                ),
                              ),
                              TextFormField(
                                controller: _ibanController,
                                autocorrect: false,
                                enableSuggestions: false,
                                textInputAction: TextInputAction.next,
                                textCapitalization: TextCapitalization.characters,
                                inputFormatters: [IbanInputFormatter()],
                                decoration: InputDecoration(
                                  hintText: 'CHXX XXXX XXXX XXXX XXXX X',
                                  enabledBorder: const OutlineInputBorder(
                                    borderRadius: BorderRadius.all(Radius.circular(8.0)),
                                    borderSide: BorderSide(color: RealUnitColors.neutral300),
                                  ),
                                  focusedBorder: const OutlineInputBorder(
                                    borderRadius: BorderRadius.all(Radius.circular(8.0)),
                                    borderSide: BorderSide(
                                      color: RealUnitColors.realUnitBlue,
                                      width: 2,
                                    ),
                                  ),
                                  errorBorder: OutlineInputBorder(
                                    borderRadius: const BorderRadius.all(Radius.circular(8.0)),
                                    borderSide: BorderSide(color: RealUnitColors.status.red600),
                                  ),
                                  focusedErrorBorder: OutlineInputBorder(
                                    borderRadius: const BorderRadius.all(Radius.circular(8.0)),
                                    borderSide: BorderSide(
                                      color: RealUnitColors.status.red600,
                                      width: 2,
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 14,
                                  ),
                                  hintStyle: const TextStyle(color: RealUnitColors.neutral400),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return S.of(context).ibanRequired;
                                  }
                                  if (!_isIban(value)) return S.of(context).ibanInvalid;
                                  return null;
                                },
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                child: Text(
                                  '${S.of(context).label} (${S.of(context).optional})',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    height: 18 / 13,
                                  ),
                                ),
                              ),
                              TextFormField(
                                controller: _nameController,
                                autocorrect: false,
                                enableSuggestions: false,
                                textInputAction: TextInputAction.next,
                                textCapitalization: TextCapitalization.words,
                                decoration: InputDecoration(
                                  hintText: 'Raiffeisenbank',
                                  enabledBorder: const OutlineInputBorder(
                                    borderRadius: BorderRadius.all(Radius.circular(8.0)),
                                    borderSide: BorderSide(color: RealUnitColors.neutral300),
                                  ),
                                  focusedBorder: const OutlineInputBorder(
                                    borderRadius: BorderRadius.all(Radius.circular(8.0)),
                                    borderSide: BorderSide(
                                      color: RealUnitColors.realUnitBlue,
                                      width: 2,
                                    ),
                                  ),
                                  errorBorder: OutlineInputBorder(
                                    borderRadius: const BorderRadius.all(Radius.circular(8.0)),
                                    borderSide: BorderSide(color: RealUnitColors.status.red600),
                                  ),
                                  focusedErrorBorder: OutlineInputBorder(
                                    borderRadius: const BorderRadius.all(Radius.circular(8.0)),
                                    borderSide: BorderSide(
                                      color: RealUnitColors.status.red600,
                                      width: 2,
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 14,
                                  ),
                                  hintStyle: const TextStyle(color: RealUnitColors.neutral400),
                                ),
                                keyboardType: TextInputType.text,
                              ),
                            ],
                          ),
                          AppFilledButton(
                            fullWidth: false,
                            onPressed: () {
                              if (_formKey.currentState?.validate() ?? false) {
                                context.read<SellBankAccountsCubit>().add(
                                  iban: _ibanController.text,
                                  label: _nameController.text.isNotEmpty
                                      ? _nameController.text
                                      : null,
                                );
                              }
                            },
                            label: S.of(context).next,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  bool _isIban(String value) {
    return RegExp(
      r'^[A-Z]{2}\d{2}[A-Z0-9]{11,30}$',
    ).hasMatch(value.replaceAll(' ', '').toUpperCase());
  }
}
