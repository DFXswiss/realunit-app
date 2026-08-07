import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_country_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/country/country.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/registration_user_type.dart';
import 'package:realunit_wallet/screens/kyc/steps/registration/cubits/registration_step/kyc_registration_step_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/registration/steps/kyc_registration_personal_step.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/form/dropdown_field.dart';

import '../../../../../helper/country_fixture.dart';
import '../../../../../helper/pump_app.dart';

class _MockKycRegistrationStepCubit extends MockCubit<KycRegistrationStepState>
    implements KycRegistrationStepCubit {}

// Matches the 'CH' entry in the committed country fixture so CountryField
// pre-selects it (and propagates it into the nationality controller).
const _switzerland = Country(id: 41, symbol: 'CH', name: 'Switzerland', kycAllowed: true);

void main() {
  late _MockKycRegistrationStepCubit stepCubit;

  setUp(() {
    GetIt.instance.registerSingleton<DfxCountryService>(fixtureCountryService());

    stepCubit = _MockKycRegistrationStepCubit();
    when(() => stepCubit.state).thenReturn(
      const KycRegistrationStepState(
        step: KycRegistrationStep.personal,
        steps: [
          KycRegistrationStep.personal,
          KycRegistrationStep.address,
          KycRegistrationStep.taxResidence,
        ],
      ),
    );
  });

  tearDown(() async => GetIt.instance.reset());

  // Prefill every field with a valid value so the only variable under test is
  // the first/last-name input. Birthday and phone seed their sub-widgets from
  // the passed controllers; the nationality picker pre-selects from the country
  // fixture — leaving the name validators as the sole outstanding gate.
  Future<_Harness> pump(
    WidgetTester tester, {
    String firstName = 'Ada',
    String lastName = 'Lovelace',
    bool withNationality = true,
  }) async {
    final harness = _Harness(firstName: firstName, lastName: lastName);

    await tester.pumpApp(
      BlocProvider<KycRegistrationStepCubit>.value(
        value: stepCubit,
        child: Scaffold(
          body: KycRegistrationPersonalStep(
            typeCtrl: harness.typeCtrl,
            firstNameCtrl: harness.firstNameCtrl,
            lastNameCtrl: harness.lastNameCtrl,
            phoneCtrl: harness.phoneCtrl,
            nationalityCtrl: harness.nationalityCtrl,
            birthdayCtrl: harness.birthdayCtrl,
            initialNationality: withNationality ? _switzerland : null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return harness;
  }

  Finder scrollable() => find.byType(Scrollable).first;

  Future<void> tapNext(WidgetTester tester) async {
    final button = find.byType(AppFilledButton);
    await tester.scrollUntilVisible(button, 100, scrollable: scrollable());
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  group('$KycRegistrationPersonalStep', () {
    testWidgets('renders the personal fields and a next button', (tester) async {
      await pump(tester);

      expect(find.byType(DropdownField<RegistrationUserType>), findsOneWidget);
      expect(find.byType(AppFilledButton), findsOneWidget);
    });

    testWidgets('advances to the next step once every field is valid', (tester) async {
      await pump(tester);

      await tapNext(tester);

      verify(() => stepCubit.next()).called(1);
    });

    testWidgets('does not advance while the names are empty', (tester) async {
      await pump(tester, firstName: '', lastName: '');

      // Empty first/last name → the validators return the empty sentinel and
      // keep the form invalid, so the step must not advance.
      await tapNext(tester);

      verifyNever(() => stepCubit.next());
    });

    testWidgets('does not advance while the names are not Swiss-payment text', (tester) async {
      // Cyrillic sample ("Test"): non-empty but outside the SwissPaymentText
      // character set, so the validators reject it client-side.
      await pump(tester, firstName: 'Тест', lastName: 'Тест');

      await tapNext(tester);

      verifyNever(() => stepCubit.next());
    });

    testWidgets('updates the account-type controller when the dropdown changes', (tester) async {
      final harness = await pump(tester);

      final dropdown = tester.widget<DropdownField<RegistrationUserType>>(
        find.byType(DropdownField<RegistrationUserType>),
      );
      // A null selection is ignored (guard) and leaves the initial value; a
      // concrete value replaces it, so assert the observable transition to the
      // other enum value (fails if the set-branch assignment is removed).
      dropdown.onChanged!(null);
      expect(harness.typeCtrl.value, RegistrationUserType.human);

      dropdown.onChanged!(RegistrationUserType.corporation);
      expect(harness.typeCtrl.value, RegistrationUserType.corporation);
    });

    testWidgets('dismisses the keyboard when tapping outside the fields', (tester) async {
      await pump(tester);

      // Focus the first text field so there is a primary focus to clear.
      final firstField = find
          .descendant(
            of: find.byType(KycRegistrationPersonalStep),
            matching: find.byType(EditableText),
          )
          .first;
      final firstFocus = tester.widget<EditableText>(firstField).focusNode;
      await tester.tap(firstField);
      await tester.pump();
      expect(firstFocus.hasFocus, isTrue);

      // The opaque GestureDetector wrapping the form clears focus on tap — it is
      // the only opaque GestureDetector that is an ancestor of the Form (field
      // and button gesture handlers are descendants of the Form).
      final dismissArea = find.ancestor(
        of: find.descendant(
          of: find.byType(KycRegistrationPersonalStep),
          matching: find.byType(Form),
        ),
        matching: find.byWidgetPredicate(
          (w) => w is GestureDetector && w.behavior == HitTestBehavior.opaque && w.onTap != null,
        ),
      );
      expect(dismissArea, findsOneWidget);
      tester.widget<GestureDetector>(dismissArea).onTap!();
      await tester.pump();

      expect(firstFocus.hasFocus, isFalse);
    });
  });
}

class _Harness {
  _Harness({required String firstName, required String lastName})
    : firstNameCtrl = TextEditingController(text: firstName),
      lastNameCtrl = TextEditingController(text: lastName);

  final typeCtrl = ValueNotifier<RegistrationUserType>(RegistrationUserType.human);
  final TextEditingController firstNameCtrl;
  final TextEditingController lastNameCtrl;
  final phoneCtrl = ValueNotifier<String?>('+41791234567');
  final nationalityCtrl = ValueNotifier<Country?>(null);
  final birthdayCtrl = ValueNotifier<String?>('1990-05-15');
}
