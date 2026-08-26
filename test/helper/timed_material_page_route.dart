import 'package:flutter/material.dart';

/// [MaterialPageRoute] does not expose [transitionDuration] as a constructor
/// argument; override it so regression tests can drive a known slide duration.
class TimedMaterialPageRoute<T> extends MaterialPageRoute<T> {
  TimedMaterialPageRoute({
    required super.builder,
    required Duration transitionDuration,
  }) : _transitionDuration = transitionDuration;

  final Duration _transitionDuration;

  @override
  Duration get transitionDuration => _transitionDuration;
}
