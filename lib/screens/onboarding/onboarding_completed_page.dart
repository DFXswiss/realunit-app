import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/screens/home/bloc/home_bloc.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';

class OnboardingCompletedPage extends StatelessWidget {
  const OnboardingCompletedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    return Scaffold(
      backgroundColor: RealUnitColors.brand700,
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const .symmetric(horizontal: 20.0),
          child: ScrollableActionsLayout(
            body: Column(
              mainAxisAlignment: .start,
              children: [
                Padding(
                  padding: const .all(32.0),
                  child: SvgPicture.asset(
                    'assets/images/illustrations/realu_token.svg',
                    height: 216,
                  ),
                ),
                const SizedBox(height: 40.0),
                Column(
                  spacing: 8.0,
                  children: [
                    Text(
                      s.onboardingCompletedTitle,
                      textAlign: .center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    Text(
                      s.onboardingCompletedSubtitle,
                      textAlign: .center,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(
                        color: RealUnitColors.neutral500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              Padding(
                padding: const .symmetric(vertical: 20),
                child: AppFilledButton(
                  onPressed: () =>
                      context.read<HomeBloc>().add(const CompleteOnboardingEvent()),
                  label: s.next,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
