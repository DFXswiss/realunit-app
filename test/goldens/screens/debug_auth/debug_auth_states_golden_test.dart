import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/screens/debug_auth/cubit/debug_auth_cubit.dart';
import 'package:realunit_wallet/screens/debug_auth/debug_auth_view.dart';

import '../../../helper/helper.dart';

class _MockDebugAuthCubit extends MockCubit<DebugAuthState>
    implements DebugAuthCubit {}

// Deterministic fixtures — a fixed address, sign-message challenge and saved
// signature so the loaded/loading/error goldens stay byte-stable across regens.
const _address = '0x9F5713DEacB8e9CAB6c2d3FaE1AFc2715F8D2D71';
const _signMessage =
    'Sign this message to authenticate with RealUnit.\nNonce: 4f8c1a2b9d3e';
const _signature =
    '0x1babe187a5c3f0d29e4c8b7a6f5e4d3c2b1a0f9e8d7c6b5a4938271605f4e3d2';

void main() {
  // Sibling `debug_auth_golden_test.dart` covers the default (address field +
  // get-message button only). This file adds the sign-message block, the error
  // box, both loading branches and the copy-to-clipboard SnackBar of
  // `DebugAuthView` (`debug_auth_view.dart`).
  late _MockDebugAuthCubit cubit;

  setUp(() {
    cubit = _MockDebugAuthCubit();
    // Stub `Clipboard.setData` (routed over SystemChannels.platform) so the
    // copy tap does not throw MissingPluginException headless. Returning null
    // is the correct no-op for every platform call in this tree.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Widget buildSubject() => wrapForGolden(
        BlocProvider<DebugAuthCubit>.value(
          value: cubit,
          child: const DebugAuthView(),
        ),
      );

  group('$DebugAuthView', () {
    // signMessage present: Divider + "Signierte Nachricht:" label + copyable
    // box + signature field + Authenticate button (view:66-111).
    goldenTest(
      'sign message fetched',
      fileName: 'debug_auth_page_sign_message',
      constraints: phoneConstraints,
      builder: () {
        when(() => cubit.state).thenReturn(
          const DebugAuthState(
            address: _address,
            signMessage: _signMessage,
            savedSignature: _signature,
          ),
        );
        return buildSubject();
      },
    );

    // errorMessage present: red error box below the get-message button
    // (view:112-125).
    goldenTest(
      'error message',
      fileName: 'debug_auth_page_error',
      constraints: phoneConstraints,
      builder: () {
        when(() => cubit.state).thenReturn(
          const DebugAuthState(
            address: _address,
            errorMessage: 'Authentifizierung fehlgeschlagen (401).',
          ),
        );
        return buildSubject();
      },
    );

    // isLoading with signMessage present: the Authenticate AppFilledButton
    // switches to its loading spinner (view:104-110). Freeze the
    // CupertinoActivityIndicator on its first frame.
    goldenTest(
      'authenticating — filled button loading',
      fileName: 'debug_auth_page_authenticating',
      constraints: phoneConstraints,
      pumpBeforeTest: pumpOnce,
      builder: () {
        when(() => cubit.state).thenReturn(
          const DebugAuthState(
            address: _address,
            signMessage: _signMessage,
            savedSignature: _signature,
            isLoading: true,
          ),
        );
        return buildSubject();
      },
    );

    // isLoading with no signMessage yet: the get-sign-message TextButton is
    // disabled (view:58-65) and the sign-message block is absent.
    goldenTest(
      'fetching sign message — text button disabled',
      fileName: 'debug_auth_page_fetching',
      constraints: phoneConstraints,
      builder: () {
        when(() => cubit.state).thenReturn(
          const DebugAuthState(address: _address, isLoading: true),
        );
        return buildSubject();
      },
    );

    // Tapping the copyable message box copies to the clipboard and shows the
    // green "In die Zwischenablage kopiert" SnackBar (view:74-97). The box's
    // GestureDetector and the SelectableText's own selection recognizer overlap,
    // so tap the box's top padding — just above the SelectableText — to land on
    // the box's GestureDetector rather than the text's caret handler.
    goldenTest(
      'copied-to-clipboard SnackBar (green)',
      fileName: 'debug_auth_page_clipboard_snackbar',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) async {
        await tester.pumpAndSettle();
        final messageRect = tester.getRect(find.byType(SelectableText));
        await tester.tapAt(Offset(messageRect.center.dx, messageRect.top - 4));
        await tester.pumpAndSettle();
      },
      builder: () {
        when(() => cubit.state).thenReturn(
          const DebugAuthState(
            address: _address,
            signMessage: _signMessage,
            savedSignature: _signature,
          ),
        );
        return buildSubject();
      },
    );
  });
}
