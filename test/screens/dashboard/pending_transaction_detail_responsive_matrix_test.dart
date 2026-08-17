import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/transactions/dto/transactions_dto.dart';
import 'package:realunit_wallet/screens/dashboard/cubits/pending_transaction_detail/pending_transaction_detail_cubit.dart';
import 'package:realunit_wallet/screens/dashboard/pending_transaction_detail_page.dart';
import 'package:realunit_wallet/styles/themes.dart';

import '../../helper/helper.dart';

class _MockDetailCubit extends MockCubit<PendingTransactionDetailState>
    implements PendingTransactionDetailCubit {}

Future<void> _pumpScreen(WidgetTester tester, MatrixCell cell, Widget child) async {
  await tester.binding.setSurfaceSize(cell.mediaQuery.size);
  addTearDown(() async => await tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MediaQuery(
      data: cell.mediaQuery,
      child: MaterialApp(
        theme: realUnitTheme,
        locale: const Locale('de'),
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        home: child,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  const buyWaiting = TransactionDto(
    id: 1,
    type: TransactionType.buy,
    state: TransactionState.waitingForPayment,
    inputAmount: 500,
    inputAsset: 'CHF',
    date: null,
  );

  late _MockDetailCubit cubit;

  setUp(() {
    cubit = _MockDetailCubit();
    when(() => cubit.state).thenReturn(const PendingTransactionDetailInitial());
    when(() => cubit.deactivate(any())).thenAnswer((_) async {});
  });

  setUpAll(() {
    registerFallbackValue(buyWaiting);
  });

  group('PendingTransactionDetailView responsive matrix (full device x textScale)', () {
    for (final cell in kFullResponsiveMatrix) {
      testWidgets(cell.id, (tester) async {
        await withTargetPlatform(cell.device.platform, () async {
          final subject = BlocProvider<PendingTransactionDetailCubit>.value(
            value: cubit,
            child: const PendingTransactionDetailView(transaction: buyWaiting),
          );

          await expectNoLayoutOverflow(
            tester,
            () => _pumpScreen(tester, cell, subject),
            reason: 'PendingTransactionDetailView overflow / ${cell.label}',
          );

          await expectFullyTappable(
            tester,
            find.text(S.current.pendingTransactionDeactivate),
            within: find.byType(PendingTransactionDetailView),
            reason:
                'PendingTransactionDetailView / ${cell.label}: deactivate CTA not tappable',
          );
        });
      });
    }
  });
}
