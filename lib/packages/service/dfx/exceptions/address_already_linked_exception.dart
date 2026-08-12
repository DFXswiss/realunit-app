/// `POST /v1/auth` with a link token returned 409 — the address is already
/// attached to a DIFFERENT account and can therefore not be linked to the
/// current user (api-side ConflictException 'Address already linked to
/// another account').
class AddressAlreadyLinkedException implements Exception {
  const AddressAlreadyLinkedException();

  @override
  String toString() =>
      'AddressAlreadyLinkedException: address is already linked to another account';
}
