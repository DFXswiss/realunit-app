import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/payment/transfer_exceptions.dart';
import 'package:web3dart/web3dart.dart' show EthereumAddress;

part 'send_recipient_state.dart';

/// Captures the transfer recipient — either scanned from a QR code or pasted /
/// typed manually. Validation here is a client-side UX guard only (a malformed
/// address is rejected before the user can advance); the API remains the final
/// authority on the address. A scanned `ethereum:0x…` URI is normalized to the
/// bare address so a wallet QR that encodes an EIP-681 URI is accepted. EIP-681
/// function-call URIs of the form `…/transfer?address=0x…` extract the recipient
/// from the single non-empty `address` query parameter (never from the token
/// contract before `/`); zero, multiple, or empty `address=` values — and any
/// other function-call form — are rejected as unrecognized/ambiguous.
class SendRecipientCubit extends Cubit<SendRecipientState> {
  SendRecipientCubit() : super(const SendRecipientEmpty());

  /// Called once per detected barcode while the scanner is open. Guards against
  /// re-entry after a successful decode so a continuously-detecting scanner does
  /// not re-emit.
  void onCodeDetected(String raw) {
    if (state is SendRecipientValid) {
      return;
    }
    submit(raw);
  }

  /// Validates a manually entered / pasted / scanned [input]. Emits
  /// [SendRecipientValid] with the checksummed address on success, or
  /// [SendRecipientInvalid] otherwise. Parsing and decoding exceptions are
  /// caught and fail closed into [SendRecipientInvalid].
  void submit(String input) {
    try {
      final address = _extractAddress(input);
      if (address == null) {
        emit(SendRecipientInvalid(InvalidRecipientAddressException(input.trim())));
        return;
      }
      final checksummed = EthereumAddress.fromHex(address).hexEip55;
      emit(SendRecipientValid(checksummed));
    } catch (_) {
      emit(SendRecipientInvalid(InvalidRecipientAddressException(input.trim())));
    }
  }

  /// Clears the current selection so the field/scanner is ready for new input.
  void reset() => emit(const SendRecipientEmpty());

  /// Strips an optional `ethereum:` EIP-681 scheme and optional `pay-` payment
  /// marker, then extracts the recipient address. Simple form (`0x…[@chainId][?…]`,
  /// no `/`): the substring before the first `@` or `?`. Function-call form
  /// (`…/transfer?address=0x…`): exactly one non-empty `address` query value
  /// when the function name is `transfer`; zero, multiple, or empty values —
  /// and any other function-call form — return `null` (fail closed).
  static String? _extractAddress(String input) {
    var value = input.trim();
    if (value.toLowerCase().startsWith('ethereum:')) {
      value = value.substring('ethereum:'.length);
    }
    if (value.toLowerCase().startsWith('pay-')) {
      value = value.substring('pay-'.length);
    }

    final slash = value.indexOf('/');
    if (slash != -1) {
      // Function-call form: text after `/` up to `?` (or end) is the function name.
      final afterSlash = value.substring(slash + 1);
      final queryStart = afterSlash.indexOf('?');
      final functionName = queryStart == -1 ? afterSlash : afterSlash.substring(0, queryStart);

      if (functionName == 'transfer' && queryStart != -1) {
        final query = afterSlash.substring(queryStart + 1);
        final addresses = Uri(query: query).queryParametersAll['address'];
        if (addresses != null && addresses.length == 1 && addresses.first.trim().isNotEmpty) {
          return addresses.first.trim();
        }
      }
      // Unrecognized/ambiguous function-call form — do not guess an address.
      return null;
    }

    // Simple form: recipient is the substring before the first `@` or `?`.
    final at = value.indexOf('@');
    final query = value.indexOf('?');
    var end = value.length;
    if (at != -1) {
      end = at;
    }
    if (query != -1 && query < end) {
      end = query;
    }
    return value.substring(0, end).trim();
  }
}
