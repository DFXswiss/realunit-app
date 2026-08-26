import 'package:flutter/material.dart';

/// Pushes [page] and calls [rearm] after that route is fully gone — or
/// immediately if the push throws — never in the same listener turn.
///
/// [Navigator.push] completes when pop is *started*. Rearming then would let
/// a still-visible QR fire during the outgoing animation and push again.
/// Waiting on [Route.completed] closes that window.
///
/// [QrScannerView] forwards every camera frame. Resetting a scanner cubit in
/// the same turn as the push drops the "already decoded" guard, so the next
/// frame pushes a second copy of [page].
Future<T?> pushThenRearm<T extends Object?>(
  BuildContext context, {
  required Widget page,
  required VoidCallback rearm,
}) async {
  final route = MaterialPageRoute<T>(builder: (_) => page);
  try {
    final result = await Navigator.of(context).push<T>(route);
    await route.completed;
    return result;
  } finally {
    if (context.mounted) {
      rearm();
    }
  }
}
