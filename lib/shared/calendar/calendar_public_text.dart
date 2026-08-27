String calendarPublicLabel(
  String value, {
  String fallback = '캘린더',
}) {
  var text = value.trim();
  if (text.isEmpty) return fallback;
  final patterns = <RegExp>[
    RegExp(r'google\s*calendar', caseSensitive: false),
    RegExp(r'google\s*캘린더', caseSensitive: false),
    RegExp(r'구글\s*캘린더', caseSensitive: false),
  ];
  for (final pattern in patterns) {
    text = text.replaceAll(pattern, '캘린더');
  }
  text = text
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll('캘린더 캘린더', '캘린더')
      .trim();
  return text.isEmpty ? fallback : text;
}

String calendarPublicAccessLabel({
  required bool canEditEvents,
  required bool canManageSharing,
}) {
  if (canManageSharing) return '변경 및 공유 관리 가능';
  if (canEditEvents) return '일정 변경 가능';
  return '읽기 전용';
}
