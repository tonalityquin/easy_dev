String normalizeVoiceAreaKey(String areaName) {
  final trimmed = areaName.trim().toLowerCase();
  final normalized = trimmed
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'[^a-z0-9_가-힣-]'), '');
  return normalized.isEmpty ? 'unknown_area' : normalized;
}
