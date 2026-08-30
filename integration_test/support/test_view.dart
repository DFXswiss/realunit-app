import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void configureHeadlessDesktopView(WidgetTester tester) {
  if (tester.view.physicalSize != Size.zero) {
    return;
  }

  tester.view
    ..physicalSize = const Size(1280, 1200)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
