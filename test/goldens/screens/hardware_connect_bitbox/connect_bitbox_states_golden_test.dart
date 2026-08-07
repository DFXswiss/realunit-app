import 'package:bitbox_flutter/bitbox_flutter.dart' as sdk;
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/screens/hardware_connect_bitbox/bloc/connect_bitbox_cubit.dart';
import 'package:realunit_wallet/screens/hardware_connect_bitbox/connect_bitbox_view.dart';

import '../../../helper/helper.dart';

class _MockConnectBitboxCubit extends MockCubit<BitboxConnectionState>
    implements ConnectBitboxCubit {}

class _FakeBitboxDevice extends Fake implements sdk.BitboxDevice {}

class _MockBitboxWallet extends Mock implements BitboxWallet {}

void main() {
  // Sibling `connect_bitbox_golden_test.dart` covers the not-connected default
  // (Android copy), connecting, check-hash and signature-failed states. This
  // file adds the remaining rendered branches of `ConnectBitboxView`
  // (`connect_bitbox_view.dart`): the iOS copy variant, pairing,
  // not-initialized, capturing-signature and connected, plus the
  // `connectBitboxFailed` SnackBar the BlocListener shows on the transition
  // into `BitboxNotConnected`.
  //
  // The real `ConnectBitboxCubit` starts a USB scan timer in its constructor,
  // so — as in the sibling file — a mocked cubit drives the view directly
  // instead of the page + real cubit.
  late _MockConnectBitboxCubit cubit;
  late _FakeBitboxDevice device;
  late _MockBitboxWallet wallet;

  setUp(() {
    cubit = _MockConnectBitboxCubit();
    device = _FakeBitboxDevice();
    wallet = _MockBitboxWallet();
  });

  // Cross-test safety net for the iOS copy golden's `defaultTargetPlatform`
  // override (each golden also resets it in its own body — see below — but this
  // guarantees the override never leaks into a sibling test if a body throws
  // before it resets).
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  void stubState(BitboxConnectionState state) {
    when(() => cubit.state).thenReturn(state);
    whenListen(
      cubit,
      const Stream<BitboxConnectionState>.empty(),
      initialState: state,
    );
  }

  Widget buildSubject() => Scaffold(
        body: BlocProvider<ConnectBitboxCubit>.value(
          value: cubit,
          child: ConnectBitboxView(onFinish: (_) {}),
        ),
      );

  group('$ConnectBitboxView', () {
    // BitboxNotConnected on iOS: the default branch swaps `connectBitboxContent`
    // for `connectBitboxContentIos` (the extra "enable Bluetooth" line) via
    // `DeviceInfo.instance.isIOS` (view:188-190).
    goldenTest(
      'not connected default state — iOS copy variant',
      fileName: 'connect_bitbox_page_default_ios',
      constraints: phoneConstraints,
      // The default `pumpBeforeTest` (precacheImages) pumps while the iOS
      // override set in the builder is still active, so the snapshot renders the
      // iOS copy + SVG. `whilePerforming`'s returned cleanup runs AFTER the
      // golden is captured (override still iOS at capture time) but BEFORE the
      // framework's end-of-body `debugAssertAllFoundationVarsUnset` invariant —
      // the only hook that resets the global in time without a rebuild switching
      // the copy back to Android. (Resetting before capture rebuilds to the
      // Android copy; a plain tearDown runs too late, after the invariant.)
      whilePerforming: (tester) async {
        return () async {
          debugDefaultTargetPlatformOverride = null;
        };
      },
      builder: () {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        stubState(BitboxNotConnected());
        return wrapForGolden(buildSubject());
      },
    );

    // BitboxPairing: connected illustration + "check pairing code" copy +
    // spinner, no buttons (view:107-123). Freeze the CupertinoActivityIndicator
    // on its first frame — pumpAndSettle would time out on the endless spin.
    goldenTest(
      'pairing state — spinner, no buttons',
      fileName: 'connect_bitbox_page_pairing',
      constraints: phoneConstraints,
      pumpBeforeTest: pumpOnce,
      builder: () {
        stubState(BitboxPairing(device));
        return wrapForGolden(buildSubject());
      },
    );

    // BitboxNotInitialized: dedicated title + retry (confirm) and cancel buttons
    // (view:124-137).
    goldenTest(
      'device not initialized — retry + cancel',
      fileName: 'connect_bitbox_page_not_initialized',
      constraints: phoneConstraints,
      builder: () {
        stubState(BitboxNotInitialized(device));
        return wrapForGolden(buildSubject());
      },
    );

    // BitboxCapturingSignature: "confirm on device" title + spinner, no buttons
    // (view:138-154). Freeze the CupertinoActivityIndicator on its first frame.
    goldenTest(
      'capturing signature — spinner, no buttons',
      fileName: 'connect_bitbox_page_capturing_signature',
      constraints: phoneConstraints,
      pumpBeforeTest: pumpOnce,
      builder: () {
        stubState(BitboxCapturingSignature(wallet));
        return wrapForGolden(buildSubject());
      },
    );

    // BitboxConnected: "Verbunden" title + single confirm button, no cancel
    // (view:171-182).
    goldenTest(
      'connected — confirm only',
      fileName: 'connect_bitbox_page_connected',
      constraints: phoneConstraints,
      builder: () {
        stubState(BitboxConnected(wallet));
        return wrapForGolden(buildSubject());
      },
    );

    // The BlocListener shows the `connectBitboxFailed` SnackBar on any
    // transition into `BitboxNotConnected` (view:35-43) — the connect/pairing
    // failure path. Seed `BitboxConnecting` and emit `BitboxNotConnected` so the
    // listener fires; the single `pump` delivers the emission (leaving the
    // spinner-free default view) and `pumpAndSettle` runs the SnackBar entrance
    // to completion (the 4s auto-dismiss is a Timer, not a frame, so it stays
    // visible).
    goldenTest(
      'connect failure SnackBar (connectBitboxFailed)',
      fileName: 'connect_bitbox_page_failed_snackbar',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) async {
        await tester.pump();
        await tester.pumpAndSettle();
      },
      builder: () {
        whenListen(
          cubit,
          Stream<BitboxConnectionState>.value(BitboxNotConnected()),
          initialState: BitboxConnecting(device),
        );
        return wrapForGolden(buildSubject());
      },
    );
  });
}
