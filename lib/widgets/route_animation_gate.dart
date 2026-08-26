import 'dart:async';

import 'package:flutter/material.dart';

/// Calls [onSettled] once the incoming [ModalRoute] animation is the real
/// controller and has completed. Ignores the first-frame
/// [kAlwaysCompleteAnimation] placeholder. A first/home route fires after
/// one frame.
class RouteAnimationGate extends StatefulWidget {
  const RouteAnimationGate({
    super.key,
    required this.onSettled,
    required this.child,
  });

  final void Function(BuildContext context) onSettled;
  final Widget child;

  @override
  State<RouteAnimationGate> createState() => _RouteAnimationGateState();
}

class _RouteAnimationGateState extends State<RouteAnimationGate> {
  bool _started = false;
  bool _postedFrame = false;
  Animation<double>? _animation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) {
      return;
    }

    final animation = ModalRoute.of(context)?.animation;
    if (_animation != null && identical(animation, _animation)) {
      return;
    }

    _detach();
    _animation = animation;
    _arm(animation);
  }

  /// [ModalRoute.animation] is a [ProxyAnimation] that starts as
  /// [kAlwaysCompleteAnimation] until the navigator attaches the real
  /// controller. Treating that placeholder as "already completed" would
  /// fire [onSettled] on the first frame of a push (split-screen + error sheet).
  bool _isUnresolved(Animation<double>? animation) {
    if (animation == null) {
      return true;
    }
    if (identical(animation, kAlwaysCompleteAnimation)) {
      return true;
    }
    if (animation is ProxyAnimation) {
      final parent = animation.parent;
      if (parent == null || identical(parent, kAlwaysCompleteAnimation)) {
        return true;
      }
    }
    return false;
  }

  void _arm(Animation<double>? animation) {
    if (animation == null || _isUnresolved(animation)) {
      animation?.addListener(_onProxyChanged);
      animation?.addStatusListener(_onAnimationStatus);
      if (_postedFrame) {
        return;
      }
      _postedFrame = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _started) {
          return;
        }
        final next = ModalRoute.of(context)?.animation;
        if (identical(next, _animation) && _isUnresolved(next)) {
          // Home / first route: there is no incoming slide to wait for.
          if (ModalRoute.of(context)?.isFirst ?? true) {
            _startOnce();
          }
          return;
        }
        _detach();
        _animation = next;
        _arm(next);
      });
      return;
    }

    animation.addStatusListener(_onAnimationStatus);
    if (animation.status == AnimationStatus.completed || animation.value >= 1.0) {
      _startOnce();
    }
  }

  void _onProxyChanged() {
    if (_started || !mounted) {
      return;
    }
    final animation = _animation;
    if (animation == null || _isUnresolved(animation)) {
      return;
    }
    _detach();
    _animation = animation;
    _arm(animation);
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _startOnce();
    }
  }

  void _startOnce() {
    if (_started || !mounted) {
      return;
    }
    _started = true;
    _detach();
    widget.onSettled(context);
  }

  void _detach() {
    _animation?.removeListener(_onProxyChanged);
    _animation?.removeStatusListener(_onAnimationStatus);
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// Completes when the route animation is null or [AnimationStatus.completed]
/// (including the placeholder). Otherwise waits for completed/dismissed.
/// Used before sheets; the gate is what delays *start*.
Future<void> waitForIncomingRouteAnimation(BuildContext context) {
  final animation = ModalRoute.of(context)?.animation;
  if (animation == null || animation.status == AnimationStatus.completed) {
    return Future<void>.value();
  }

  final completer = Completer<void>();

  void listener(AnimationStatus status) {
    if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
      animation.removeStatusListener(listener);
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }

  animation.addStatusListener(listener);

  // Race: status may flip between the first check and addStatusListener.
  if (animation.status == AnimationStatus.completed ||
      animation.status == AnimationStatus.dismissed) {
    animation.removeStatusListener(listener);
    if (!completer.isCompleted) {
      completer.complete();
    }
  }

  return completer.future;
}
