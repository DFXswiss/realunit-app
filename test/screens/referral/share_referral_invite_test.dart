import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/screens/referral/share_referral_invite.dart';

void main() {
  testWidgets('uses the button box when it has a size', (tester) async {
    late Rect origin;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 80,
              height: 40,
              child: Builder(
                builder: (context) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    origin = shareReferralInviteOrigin(context);
                  });
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(origin, const Rect.fromLTWH(0, 0, 80, 40));
  });

  testWidgets('falls back to the screen when the box has no size', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late Rect origin;
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(size: Size(320, 568)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: _UnsizedOriginProbe(),
        ),
      ),
    );
    origin = tester
        .state<_UnsizedOriginProbeState>(find.byType(_UnsizedOriginProbe))
        .origin;
    expect(origin, const Rect.fromLTWH(0, 0, 320, 568));
  });
}

class _UnsizedOriginProbe extends StatefulWidget {
  const _UnsizedOriginProbe();

  @override
  State<_UnsizedOriginProbe> createState() => _UnsizedOriginProbeState();
}

class _UnsizedOriginProbeState extends State<_UnsizedOriginProbe> {
  late final Rect origin = shareReferralInviteOrigin(context);

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
