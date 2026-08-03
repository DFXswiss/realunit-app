import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/user/dto/real_unit_user_data_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_registration_service.dart';
import 'package:realunit_wallet/screens/migrate_bitbox/cubits/migrate_bitbox/migrate_bitbox_cubit.dart';
import 'package:realunit_wallet/screens/migrate_bitbox/cubits/migrate_register/migrate_register_cubit.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';

class MigrateRegisterView extends StatelessWidget {
  const MigrateRegisterView({
    super.key,
    required this.userData,
    required this.bitboxAddress,
  });

  final RealUnitUserDataDto userData;
  final String bitboxAddress;

  @override
  Widget build(BuildContext context) {
    final parent = context.read<MigrateBitboxCubit>();
    return BlocProvider(
      create: (_) => MigrateRegisterCubit(
        getIt<RealUnitRegistrationService>(),
        account: parent.draftAccount,
        userData: userData,
        bearerToken: parent.linkedJwt,
      ),
      child: _MigrateRegisterBody(
        userData: userData,
        bitboxAddress: bitboxAddress,
      ),
    );
  }
}

class _MigrateRegisterBody extends StatelessWidget {
  const _MigrateRegisterBody({
    required this.userData,
    required this.bitboxAddress,
  });

  final RealUnitUserDataDto userData;
  final String bitboxAddress;

  @override
  Widget build(BuildContext context) => BlocConsumer<MigrateRegisterCubit, MigrateRegisterState>(
    listener: (context, state) {
      if (state is MigrateRegisterSuccess) {
        context.read<MigrateBitboxCubit>().onRegisterCompleted();
      }
      if (state is MigrateRegisterPending) {
        context.read<MigrateBitboxCubit>().onRegisterPending();
      }
    },
    builder: (context, state) => PopScope(
      canPop: state is! MigrateRegisterSubmitting,
      child: switch (state) {
        MigrateRegisterReady() => _MigrateRegisterForm(
          userData: userData,
          bitboxAddress: bitboxAddress,
          isSubmitting: false,
        ),
        MigrateRegisterSubmitting() => _MigrateRegisterForm(
          userData: userData,
          bitboxAddress: bitboxAddress,
          isSubmitting: true,
        ),
        MigrateRegisterFailure(:final reason, :final message, :final canRetry) =>
          _MigrateRegisterFailureView(
            reason: reason,
            message: message,
            canRetry: canRetry,
          ),
        MigrateRegisterPending() || MigrateRegisterSuccess() =>
          const Center(child: CupertinoActivityIndicator()),
      },
    ),
  );
}

class _MigrateRegisterForm extends StatelessWidget {
  const _MigrateRegisterForm({
    required this.userData,
    required this.bitboxAddress,
    required this.isSubmitting,
  });

  final RealUnitUserDataDto userData;
  final String bitboxAddress;
  final bool isSubmitting;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(S.of(context).migrateBitbox)),
    body: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SafeArea(
        child: ScrollableActionsLayout(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 16,
            children: [
              Text(
                S.of(context).migrateBitboxRegisterTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              Text(
                S.of(context).migrateBitboxRegisterDescription,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: RealUnitColors.neutral500),
              ),
              _MigrateRegisterInfoRow(
                label: S.of(context).name,
                value: userData.name,
              ),
              _MigrateRegisterInfoRow(
                label: S.of(context).walletAddress,
                value: _truncateAddress(bitboxAddress),
              ),
              Text(
                S.of(context).migrateBitboxRegisterConfirmHint,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: RealUnitColors.neutral500),
              ),
            ],
          ),
          actions: [
            AppFilledButton(
              label: S.of(context).migrateBitboxRegisterCta,
              state: isSubmitting
                  ? FilledButtonState.loading
                  : FilledButtonState.idle,
              onPressed: isSubmitting
                  ? null
                  : () => context.read<MigrateRegisterCubit>().submit(),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MigrateRegisterFailureView extends StatelessWidget {
  const _MigrateRegisterFailureView({
    required this.reason,
    required this.message,
    required this.canRetry,
  });

  final MigrateRegisterFailureReason reason;
  final String? message;
  final bool canRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(S.of(context).migrateBitbox)),
    body: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SafeArea(
        child: ScrollableActionsLayout(
          centerBody: true,
          body: Column(
            spacing: 16,
            children: [
              Icon(
                Icons.error_rounded,
                size: 64,
                color: RealUnitColors.status.red600,
              ),
              Text(
                _failureMessage(context, reason, message),
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: RealUnitColors.neutral500),
              ),
            ],
          ),
          actions: [
            AppFilledButton(
              label: S.of(context).retry,
              onPressed: canRetry
                  ? () => context.read<MigrateRegisterCubit>().retrySubmit()
                  : null,
            ),
            AppFilledButton(
              variant: FilledButtonVariant.secondary,
              label: S.of(context).close,
              onPressed: () => context.pop(),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MigrateRegisterInfoRow extends StatelessWidget {
  const _MigrateRegisterInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 4,
    children: [
      Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: RealUnitColors.neutral500),
      ),
      Text(value, style: Theme.of(context).textTheme.bodyLarge),
    ],
  );
}

String _failureMessage(
  BuildContext context,
  MigrateRegisterFailureReason reason,
  String? message,
) => switch (reason) {
  MigrateRegisterFailureReason.signatureCancelled =>
    S.of(context).sendFailureSignatureCancelled,
  MigrateRegisterFailureReason.bitboxNotConnected =>
    S.of(context).connectBitboxFailed,
  MigrateRegisterFailureReason.generic =>
    message ?? S.of(context).connectBitboxFailed,
};

String _truncateAddress(String address) {
  if (address.length <= 12) return address;
  return '${address.substring(0, 6)}…${address.substring(address.length - 4)}';
}
