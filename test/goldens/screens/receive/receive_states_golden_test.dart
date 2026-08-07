import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/screens/receive/receive_page.dart';

import '../../../helper/helper.dart';

// `receive_page_default` (bottom-sheet variant: handlebar, no AppBar) lives in
// `receive_golden_test.dart`. The router actually pushes the full-page variant
// (`router_config.dart:210` → `ReceivePage(isBottomSheet: false)`): an AppBar
// with a back arrow and no handlebar. This file covers that routed surface.
void main() {
  setUpAll(() {
    final getIt = GetIt.instance;
    final appStore = MockAppStore();
    when(() => appStore.primaryAddress)
        .thenReturn('0xcabd3f4b10a7089986e708d19140bfc98e5880c0');
    getIt.registerSingleton<AppStore>(appStore);
  });

  tearDownAll(() async => GetIt.instance.reset());

  group('$ReceivePage', () {
    goldenTest(
      'full page — AppBar with back arrow, no handlebar',
      fileName: 'receive_page_full_page',
      constraints: phoneConstraints,
      builder: () => wrapForGolden(const ReceivePage(isBottomSheet: false)),
    );
  });
}
