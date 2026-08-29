/// Boundary in front of the Play Install Referrer API so callers can be
/// unit-tested without a platform channel.
///
/// Production wiring is [InstallReferrerAdapter]. On Android it reads the
/// referrer string Play attached to this install; everywhere else it returns
/// null. Tests supply a fake.
abstract class InstallReferrerPort {
  /// Raw Play referrer (e.g. `invite=AB12CD`), or null when none is available.
  Future<String?> readInstallReferrer();
}
