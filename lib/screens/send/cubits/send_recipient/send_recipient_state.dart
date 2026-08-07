part of 'send_recipient_cubit.dart';

sealed class SendRecipientState extends Equatable {
  const SendRecipientState();

  @override
  List<Object?> get props => [];
}

/// No recipient entered yet.
class SendRecipientEmpty extends SendRecipientState {
  const SendRecipientEmpty();
}

/// A syntactically valid EVM address, normalized to its EIP-55 checksum form.
class SendRecipientValid extends SendRecipientState {
  final String address;

  const SendRecipientValid(this.address);

  @override
  List<Object?> get props => [address];
}

/// The entered/scanned value is not a valid EVM address (client-side UX guard).
class SendRecipientInvalid extends SendRecipientState {
  final InvalidRecipientAddressException error;

  const SendRecipientInvalid(this.error);

  @override
  List<Object?> get props => [error.input];
}
