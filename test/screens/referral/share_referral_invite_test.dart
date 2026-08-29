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

  testWidgets('falls back to the screen when the box is empty', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late Rect origin;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 0,
              height: 0,
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
    expect(origin, const Rect.fromLTWH(0, 0, 320, 568));
  });

  testWidgets('falls back to the screen when the render box is missing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late Rect origin;
    late RenderBox? box;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(320, 568)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              box = context.findRenderObject() as RenderBox?;
              origin = shareReferralInviteOrigin(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    expect(box, isNull);
    expect(origin, const Rect.fromLTWH(0, 0, 320, 568));
  });
}
