import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/country/country.dart';
import 'package:realunit_wallet/screens/kyc/cubits/kyc/kyc_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/nationality/cubit/kyc_nationality/kyc_nationality_cubit.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/form/country_field.dart';

class KycNationalityPage extends StatelessWidget {
  final String url;

  const KycNationalityPage({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => KycNationalityCubit(
        getIt<DfxKycService>(),
      ),
      child: KycNationalityView(url: url),
    );
  }
}

class KycNationalityView extends StatefulWidget {
  final String url;

  const KycNationalityView({super.key, required this.url});

  @override
  State<KycNationalityView> createState() => _KycNationalityViewState();
}

class _KycNationalityViewState extends State<KycNationalityView> {
  final _formKey = GlobalKey<FormState>();
  final nationalityCtrl = ValueNotifier<Country?>(null);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.of(context).registerCitizenship)),
      body: BlocListener<KycNationalityCubit, KycNationalityState>(
        listener: (context, state) {
          if (state is KycNationalitySuccess) {
            context.read<KycCubit>().checkKyc();
          }
          if (state is KycNationalityFailure) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: RealUnitColors.status.red600,
              ),
            );
          }
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SafeArea(
            child: GestureDetector(
              onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              behavior: HitTestBehavior.opaque,
              child: Form(
                key: _formKey,
                child: Column(
                  spacing: 16,
                  children: [
                    CountryField(
                      label: S.of(context).registerCitizenship,
                      purpose: CountryFieldPurpose.nationality,
                      onChanged: (country) => nationalityCtrl.value = country,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16.0),
                      child: BlocBuilder<KycNationalityCubit, KycNationalityState>(
                        builder: (context, state) {
                          return AppFilledButton(
                            state: state is KycNationalityLoading ? .loading : .idle,
                            onPressed: () {
                              if (_formKey.currentState?.validate() ?? false) {
                                context.read<KycNationalityCubit>().registerNationality(
                                  url: widget.url,
                                  nationality: nationalityCtrl.value!,
                                );
                              }
                            },
                            label: S.of(context).next,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    nationalityCtrl.dispose();
    super.dispose();
  }
}
