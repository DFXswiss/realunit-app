/// Share copy from the API when present; otherwise the localised template.
/// Empty `copyText` / `copyTextEn` must not hide the fallback.
/// `http://`, protocol-relative `//`, `www.realunit.app`, and scheme-less
/// `realunit.app/…` in the message are folded onto `https://realunit.app`
/// so the pasted Universal Link host matches Offerte Entwurf 3.
/// `dev.realunit.app` is left unchanged.
String referralShareText({
  required String? fromApi,
  required String guestName,
  required String url,
  required String Function(String guestName, String hostName, String url)
  fallback,
  String Function(String hostName, String url)? fallbackNoName,
  String? hostName,
}) {
  final name = guestName.trim();
  final host = (hostName != null && hostName.trim().isNotEmpty)
      ? hostName.trim()
      : 'RealUnit';
  final text = (fromApi != null && fromApi.trim().isNotEmpty)
      ? fromApi.trim()
      : (name.isEmpty && fallbackNoName != null)
          ? fallbackNoName(host, url)
          : fallback(name, host, url);
  return text.replaceAllMapped(
    _apexInviteHost,
    (match) => '${match[1]}https://realunit.app',
  );
}

final _apexInviteHost = RegExp(
  r'(^|[^a-z0-9.-])(?:(?:https?:)?//)?(?:www\.)?realunit\.app(?=[/?#:]|$)',
  caseSensitive: false,
);
