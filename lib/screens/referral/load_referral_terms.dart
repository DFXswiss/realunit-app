import 'dart:async';

/// Local TB fallback should be instant. A hung asset must not leave the
/// terms page spinning after the API already failed.
const referralTermsAssetTimeout = Duration(seconds: 5);

/// Resolves TB markdown: API text 1:1, then the locale-bundled asset, then
/// the German TB 14.08 so an English load failure does not blank the page.
Future<String?> loadReferralTermsMarkdown({
  required String languageCode,
  required Future<String> Function(String assetPath) loadAsset,
  String? apiText,
}) async {
  if (apiText != null && apiText.trim().isNotEmpty) return apiText;
  final langs = <String>[
    languageCode,
    if (languageCode != 'de') 'de',
  ];
  for (final lang in langs) {
    try {
      final content = await loadAsset(
        'assets/legal/referral_terms_$lang.md',
      ).timeout(referralTermsAssetTimeout);
      if (content.trim().isNotEmpty) return content;
    } catch (_) {
      // Try the next language — EN asset missing still shows the DE TB.
    }
  }
  return null;
}
