import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/screens/migrate_bitbox/cubits/migrate_bitbox/migrate_bitbox_cubit.dart';
import 'package:realunit_wallet/setup/routing/routes/app_routes.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';

class MigrateBitboxRegistrationPendingPage extends StatelessWidget {
  const MigrateBitboxRegistrationPendingPage({super.key});

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
              const Icon(
                Icons.hourglass_top_rounded,
                size: 64,
                color: RealUnitColors.realUnitBlue,
              ),
              Text(
                S.of(context).migrateBitboxRegistrationPendingInfo,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: RealUnitColors.neutral500),
              ),
            ],
          ),
          actions: [
            AppFilledButton(
              label: S.of(context).close,
              onPressed: () => context.pop(),
            ),
          ],
        ),
      ),
    ),
  );
}

class MigrateBitboxSettlingTimeoutPage extends StatelessWidget {
  const MigrateBitboxSettlingTimeoutPage({super.key});

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
              const Icon(
                Icons.hourglass_top_rounded,
                size: 64,
                color: RealUnitColors.realUnitBlue,
              ),
              Text(
                S.of(context).migrateBitboxSettlingTimeoutInfo,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: RealUnitColors.neutral500),
              ),
            ],
          ),
          actions: [
            AppFilledButton(
              label: S.of(context).close,
              onPressed: () => context.pop(),
            ),
          ],
        ),
      ),
    ),
  );
}

class MigrateBitboxSuccessPage extends StatelessWidget {
  const MigrateBitboxSuccessPage({super.key});

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
              const Icon(
                Icons.check_circle_rounded,
                size: 64,
                color: RealUnitColors.realUnitBlue,
              ),
              Text(
                S.of(context).migrateBitboxSuccessTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              Text(
                S.of(context).migrateBitboxSuccessDescription,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: RealUnitColors.neutral500),
              ),
            ],
          ),
          actions: [
            AppFilledButton(
              label: S.of(context).done,
              onPressed: () => context.goNamed(AppRoutes.dashboard),
            ),
          ],
        ),
      ),
    ),
  );
}

class MigrateBitboxFailurePage extends StatelessWidget {
  const MigrateBitboxFailurePage({
    super.key,
    required this.reason,
    this.message,
    required this.canRetry,
  });

  final MigrateBitboxFailureReason reason;
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
                message ?? _failureMessage(context, reason),
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: RealUnitColors.neutral500),
              ),
            ],
          ),
          actions: [
            if (canRetry)
              AppFilledButton(
                label: S.of(context).retry,
                onPressed: () => context.read<MigrateBitboxCubit>().retry(),
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

String _failureMessage(BuildContext context, MigrateBitboxFailureReason reason) => switch (reason) {
  MigrateBitboxFailureReason.addressAlreadyLinked =>
    S.of(context).migrateBitboxAlreadyLinkedError,
  MigrateBitboxFailureReason.registrationMissing =>
    S.of(context).migrateBitboxRegistrationMissingError,
  MigrateBitboxFailureReason.signatureCancelled => S.of(context).sendFailureSignatureCancelled,
  MigrateBitboxFailureReason.bitboxNotConnected => S.of(context).connectBitboxFailed,
  MigrateBitboxFailureReason.generic => S.of(context).connectBitboxFailed,
};
