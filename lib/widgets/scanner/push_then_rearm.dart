import 'package:flutter/material.dart';

/// Pushes [page] and calls [rearm] when [Navigator.push] completes — after
/// the route pops, or if the push throws — never in the same listener turn.
///
/// [QrScannerView] forwards every camera frame. Resetting a scanner cubit in
/// the same turn as the push drops the "already decoded" guard, so the next
/// frame pushes a second copy of [page].
Future<T?> pushThenRearm<T extends Object?>(
  BuildContext context, {
  required Widget page,
  required VoidCallback rearm,
}) async {
  try {
    return await Navigator.of(context).push<T>(
      MaterialPageRoute<T>(builder: (_) => page),
    );
  } finally {
    if (context.mounted) {
      rearm();
    }
  }
}
