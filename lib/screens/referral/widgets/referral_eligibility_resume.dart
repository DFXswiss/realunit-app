import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:realunit_wallet/screens/referral/cubit/referral_eligibility_cubit.dart';

/// Reloads the Empfehler gate when the app returns to the foreground or
/// this route is current again (pop back from Settings) so an unmounted
/// summary can open the tile after the controller is mounted, without
/// hiding a tile that is already shown. While the last summary GET
/// failed, also poll so a later mount can open the tile without
/// backgrounding the app. Polling runs only while this route is
/// current and the app is in the foreground. A 200 `eligible: false`
/// does not poll.
class ReferralEligibilityResumeReloader extends StatefulWidget {
  final Widget child;

  /// Poll interval while summary is unavailable. Tests pass a short
  /// duration; `Duration.zero` disables the timer.
  final Duration unavailablePollInterval;

  const ReferralEligibilityResumeReloader({
    super.key,
    required this.child,
    this.unavailablePollInterval = const Duration(seconds: 15),
  });

  @override
  State<ReferralEligibilityResumeReloader> createState() =>
      _ReferralEligibilityResumeReloaderState();
}

class _ReferralEligibilityResumeReloaderState
    extends State<ReferralEligibilityResumeReloader>
    with WidgetsBindingObserver {
  GoRouterDelegate? _delegate;
  Timer? _poll;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final delegate = GoRouter.maybeOf(context)?.routerDelegate;
    if (delegate == _delegate) return;
    _delegate?.removeListener(_onRoute);
    _delegate = delegate;
    _delegate?.addListener(_onRoute);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _poll = null;
    _delegate?.removeListener(_onRoute);
    _delegate = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _syncPoll([ReferralEligibilityState? state]) {
    if (!mounted) return;
    final cubitState =
        state ?? context.read<ReferralEligibilityCubit>().state;
    final routeCurrent = ModalRoute.of(context)?.isCurrent == true;
    final foreground = _lifecycle == AppLifecycleState.resumed;
    final poll =
        foreground &&
        routeCurrent &&
        widget.unavailablePollInterval > Duration.zero &&
        cubitState is ReferralEligibilityLoaded &&
        !cubitState.eligible &&
        cubitState.unavailable;
    if (poll) {
      _poll ??= Timer.periodic(widget.unavailablePollInterval, (_) {
        if (!mounted) return;
        if (ModalRoute.of(context)?.isCurrent != true) return;
        if (_lifecycle != AppLifecycleState.resumed) return;
        context.read<ReferralEligibilityCubit>().reload();
      });
      return;
    }
    _poll?.cancel();
    _poll = null;
  }

  void _onRoute() {
    if (!mounted) return;
    _syncPoll();
    if (ModalRoute.of(context)?.isCurrent != true) return;
    context.read<ReferralEligibilityCubit>().reload();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (!mounted) return;
    _syncPoll();
    if (state != AppLifecycleState.resumed) return;
    context.read<ReferralEligibilityCubit>().reload();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ReferralEligibilityCubit, ReferralEligibilityState>(
      listener: (context, state) => _syncPoll(state),
      child: widget.child,
    );
  }
}
