import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_created_invite_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_summary_dto.dart';
import 'package:realunit_wallet/screens/referral/cubit/referral_cubit.dart';
import 'package:realunit_wallet/screens/referral/referral_create_page.dart';
import 'package:realunit_wallet/styles/themes.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

class _MockReferralCubit extends MockCubit<ReferralState> implements ReferralCubit {}

const _summary = ReferralSummaryDto(
  eligible: true,
  termsAccepted: true,
  openCount: 0,
  creditedCount: 0,
  realuSum: 0,
  chfSum: 0,
);

const _shareChannel = MethodChannel('dev.fluttercommunity.plus/share');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late _MockReferralCubit cubit;

  setUp(() {
    cubit = _MockReferralCubit();
    when(() => cubit.isClosed).thenReturn(false);
  });

  Future<void> pumpCreated(
    WidgetTester tester, {
    required ReferralCreatedInviteDto invite,
  }) {
    when(() => cubit.state).thenReturn(
      ReferralInviteCreated(summary: _summary, invite: invite),
    );
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: ReferralInviteCreated(summary: _summary, invite: invite),
    );
    return tester.pumpWidget(
      MaterialApp(
        theme: realUnitTheme,
        locale: const Locale('de'),
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        home: BlocProvider<ReferralCubit>.value(
          value: cubit,
          child: const ReferralCreateView(),
        ),
      ),
    );
  }

  testWidgets('copy writes the invite URL and shows Kopiert', (tester) async {
    String? copied;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await pumpCreated(
      tester,
      invite: const ReferralCreatedInviteDto(
        code: 'AB12CD',
        url: 'https://realunit.app/invite/AB12CD',
        guestName: 'Alice',
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Einladungslink kopieren'));
    await tester.pump();

    expect(
      copied,
      'Hey Alice, RealUnit lädt dich ein zu RealUnit: https://realunit.app/invite/AB12CD',
    );
    expect(find.text('Kopiert'), findsOneWidget);
  });

  testWidgets('copy stays tappable when the clipboard write fails', (tester) async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        throw PlatformException(code: 'denied');
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await pumpCreated(
      tester,
      invite: const ReferralCreatedInviteDto(
        code: 'AB12CD',
        url: 'https://realunit.app/invite/AB12CD',
        guestName: 'Alice',
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Einladungslink kopieren'));
    await tester.pump();

    expect(find.text('Kopiert'), findsNothing);
    expect(find.text('Einladungslink kopieren'), findsOneWidget);
    expect(
      tester
          .widget<AppFilledButton>(
            find.widgetWithText(AppFilledButton, 'Einladungslink kopieren'),
          )
          .state,
      FilledButtonState.error,
    );
  });

  testWidgets('share sends the API copyText 1:1', (tester) async {
    String? shared;
    String? subject;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _shareChannel,
      (call) async {
        if (call.method == 'share') {
          final args = call.arguments;
          if (args is Map) {
            shared = args['text'] as String?;
            subject = args['subject'] as String?;
          }
        }
        return '';
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _shareChannel,
        null,
      );
    });

    await pumpCreated(
      tester,
      invite: const ReferralCreatedInviteDto(
        code: 'AB12CD',
        url: 'https://realunit.app/invite/AB12CD',
        guestName: 'Alice',
        copyText: 'Hey Alice, Björn lädt dich ein: https://realunit.app/invite/AB12CD',
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Einladungslink versenden'));
    await tester.pump();

    expect(
      shared,
      'Hey Alice, Björn lädt dich ein: https://realunit.app/invite/AB12CD',
    );
    expect(subject, 'Persönlicher Einladungslink');
  });
}
