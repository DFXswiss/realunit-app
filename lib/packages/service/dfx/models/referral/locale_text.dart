/// First string that still has content after trim. Empty API fields must not
/// block the DE/EN fallback chain (`""` is not null).
String? firstNonEmpty(Iterable<String?> values) {
  for (final value in values) {
    if (value != null && value.trim().isNotEmpty) return value;
  }
  return null;
}
