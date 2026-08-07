import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'send_amount_state.dart';

/// Validates the REALU amount to send. REALU has `decimals = 0`, so the amount
/// is a whole number of shares. The available balance (also whole shares) is
/// tracked here so the field can be validated against it locally for UX; the
/// API remains the authority and re-checks the balance on `PUT /transfer`.
class SendAmountCubit extends Cubit<SendAmountState> {
  /// Available REALU shares in the wallet, or null when the balance is unknown
  /// (the available-balance hint and the over-balance guard are then skipped —
  /// the API still validates). Mutable because the balance arrives over a
  /// stream and may update after the cubit is built.
  BigInt? availableShares;

  SendAmountCubit({this.availableShares}) : super(const SendAmountState());

  /// Updates the tracked balance when a fresh value arrives from the balance
  /// stream, then re-evaluates the current input against it so an amount that
  /// was provisionally valid (unknown balance) is re-checked.
  void availableSharesChanged(BigInt shares) {
    if (availableShares == shares) return;
    availableShares = shares;
    if (state.text.isNotEmpty) amountChanged(state.text);
  }

  /// Re-evaluates [raw] on every keystroke and emits the parsed amount + a
  /// validity flag the confirm button binds to.
  void amountChanged(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      emit(SendAmountState(text: text, amount: null, status: SendAmountStatus.empty));
      return;
    }

    final parsed = int.tryParse(text);
    if (parsed == null || parsed < 1) {
      emit(SendAmountState(text: text, amount: parsed, status: SendAmountStatus.invalid));
      return;
    }

    final balance = availableShares;
    if (balance != null && BigInt.from(parsed) > balance) {
      emit(
        SendAmountState(text: text, amount: parsed, status: SendAmountStatus.insufficientBalance),
      );
      return;
    }

    emit(SendAmountState(text: text, amount: parsed, status: SendAmountStatus.valid));
  }

  /// Fills the field with the full available balance.
  void useMax() {
    final balance = availableShares;
    if (balance == null || balance < BigInt.one) return;
    amountChanged(balance.toString());
  }
}
