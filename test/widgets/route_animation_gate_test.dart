import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/widgets/route_animation_gate.dart';

import '../helper/helper.dart';

void main() {
  testWidgets('onSettled fires only after the incoming route animation completes', (
    tester,
  ) async {
    final settledCount = ValueNotifier<int>(0);
    addTearDown(settledCount.dispose);

    await tester.pumpApp(
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  TimedMaterialPageRoute<void>(
                    transitionDuration: const Duration(milliseconds: 300),
                    builder: (_) => RouteAnimationGate(
                      onSettled: (_) => settledCount.value++,
                      child: const Scaffold(body: Text('gated')),
                    ),
                  ),
                );
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(); // flush the post-frame callback
    await tester.pump(const Duration(milliseconds: 50));

    expect(settledCount.value, 0);
    expect(find.text('gated'), findsOne);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(settledCount.value, 1);
  });
}
