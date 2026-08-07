// Responsive matrix gate for BitBox connect sheet CTAs.
//
// Proves every button-bearing state stays fully tappable across the full
// device × text-scale matrix (see test/helper/responsive_matrix.dart).
// This is the regression lock for the iOS pairing "Bestätigen not tappable"
// bug: long DE copy + real channel hash + home-indicator padding + sheet clip.
import 'package:bitbox_flutter/bitbox_flutter.dart' as sdk;
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/screens/hardware_connect_bitbox/bloc/connect_bitbox_cubit.dart';
import 'package:realunit_wallet/screens/hardware_connect_bitbox/connect_bitbox_view.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

import '../../helper/helper.dart';

class _MockCubit extends MockCubit<BitboxConnectionState> implements ConnectBitboxCubit {}

class _FakeDevice extends Fake implements sdk.BitboxDevice {}

class _MockWallet extends Mock implements BitboxWallet {}

/// Worst-case pairing code from production reports (two visual groups).
const _realChannelHash = 'SDP53 Z7GIS FUDJ3 OIEIV';

void main() {
  late _MockCubit cubit;
  late _FakeDevice device;
  late _MockWallet wallet;

  setUp(() {
    cubit = _MockCubit();
    device = _FakeDevice();
    wallet = _MockWallet();
  });

  void stubState(BitboxConnectionState state) {
    when(() => cubit.state).thenReturn(state);
    whenListen(
      cubit,
      const Stream<BitboxConnectionState>.empty(),
      initialState: state,
    );
  }

  Future<void> pumpSheet(WidgetTester tester, MatrixCell cell) async {
    await pumpClippedSheet(
      tester,
      widget: BlocProvider<ConnectBitboxCubit>.value(
        value: cubit,
        child: ConnectBitboxView(
          onFinish: (_) {},
          onCancel: () {},
        ),
      ),
      mediaQuery: cell.mediaQuery,
    );
  }

  /// Every state that shows at least one CTA must stay tappable on every cell.
  Map<String, BitboxConnectionState> buttonStates() => {
    'checkHash': BitboxCheckHash(device, _realChannelHash),
    'notInitialized': BitboxNotInitialized(device),
    'signatureFailed': BitboxSignatureFailed(wallet),
    'connected': BitboxConnected(wallet),
    'notConnected': BitboxNotConnected(),
  };

  group('ConnectBitboxView responsive matrix (full device × textScale)', () {
    for (final cell in kFullResponsiveMatrix) {
      // State keys are fixed; instances are built in setUp-time via buttonStates().
      for (final stateKey in const [
        'checkHash',
        'notInitialized',
        'signatureFailed',
        'connected',
        'notConnected',
      ]) {
        testWidgets('$stateKey · ${cell.id}', (tester) async {
          await withTargetPlatform(cell.device.platform, () async {
            stubState(buttonStates()[stateKey]!);
            when(() => cubit.confirmPairing()).thenAnswer((_) async {});
            when(() => cubit.recheckDeviceStatus()).thenAnswer((_) async {});
            when(() => cubit.retrySignatureCapture()).thenAnswer((_) async {});
            when(() => cubit.continueWithoutSignature()).thenReturn(null);
            when(() => cubit.finishSetup()).thenReturn(null);

            await expectNoLayoutOverflow(
              tester,
              () async {
                await pumpSheet(tester, cell);
              },
              reason: 'overflow on $stateKey / ${cell.label}',
            );

            final buttons = find.byType(AppFilledButton);
            expect(
              buttons,
              findsWidgets,
              reason: '$stateKey / ${cell.label}: expected CTA(s)',
            );

            // Primary CTA (first button) must be fully inside the sheet and
            // receive a real pointer event.
            final primary = buttons.first;
            await expectFullyTappable(
              tester,
              primary,
              within: find.byType(ConnectBitboxView),
              reason: '$stateKey / ${cell.label}: primary CTA not tappable',
            );
          });
        });
      }
    }
  });

  // Focused regression: the exact reported failure mode (iPhone 15 DE + real
  // hash) must invoke confirmPairing via tap — not via onPressed.call().
  testWidgets(
    'REGRESSION: iPhone 15 DE checkHash real hash — tap calls confirmPairing',
    (tester) async {
      final cell = MatrixCell(
        kIosDeviceProfiles.firstWhere((d) => d.id == 'iphone_15'),
        1.0,
      );
      await withTargetPlatform(cell.device.platform, () async {
        stubState(BitboxCheckHash(device, _realChannelHash));
        when(() => cubit.confirmPairing()).thenAnswer((_) async {});

        await pumpSheet(tester, cell);

        await expectFullyTappable(
          tester,
          find.text('Bestätigen'),
          within: find.byType(ConnectBitboxView),
        );
        verify(() => cubit.confirmPairing()).called(1);

        // Cancel must also be on-screen (was fully clipped in the bug report).
        await expectFullyTappable(
          tester,
          find.text('Abbrechen'),
          within: find.byType(ConnectBitboxView),
        );
      });
    },
  );

  testWidgets(
    'REGRESSION: iPhone SE + textScale 3.0 checkHash still tappable',
    (tester) async {
      final cell = MatrixCell(
        kIosDeviceProfiles.firstWhere((d) => d.id == 'iphone_se_3'),
        3.0,
      );
      await withTargetPlatform(cell.device.platform, () async {
        stubState(BitboxCheckHash(device, _realChannelHash));
        when(() => cubit.confirmPairing()).thenAnswer((_) async {});

        await expectNoLayoutOverflow(tester, () async {
          await pumpSheet(tester, cell);
        });
        await expectFullyTappable(
          tester,
          find.byType(AppFilledButton).first,
          within: find.byType(ConnectBitboxView),
        );
        verify(() => cubit.confirmPairing()).called(1);
      });
    },
  );
}
