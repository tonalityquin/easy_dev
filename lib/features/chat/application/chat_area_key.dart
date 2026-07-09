const String headquarterChatAreaName = '본사';
const String headquarterChatAreaKey = 'headquarters';

String normalizeChatAreaKey(String areaName) {
  final trimmed = areaName.trim().toLowerCase();
  if (trimmed == '본사' ||
      trimmed == 'hq' ||
      trimmed == 'headquarter' ||
      trimmed == 'headquarters') {
    return headquarterChatAreaKey;
  }
  final normalized = trimmed
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'[^a-z0-9_가-힣-]'), '');
  return normalized.isEmpty ? 'unknown_area' : normalized;
}
