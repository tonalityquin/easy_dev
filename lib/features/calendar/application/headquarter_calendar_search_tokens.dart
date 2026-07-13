const int headquarterCalendarSearchTokenVersion = 1;

String normalizeHeadquarterCalendarSearchText(String input) {
  return input
      .toLowerCase()
      .replaceAll(RegExp(r'[^0-9a-z가-힣]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

List<String> buildHeadquarterCalendarSearchTokens({
  required String title,
  required String description,
  required String eventType,
  required String priority,
  required String createdByName,
  required Iterable<String> attendeeNames,
}) {
  final source = normalizeHeadquarterCalendarSearchText(
    '$title $description $eventType $priority $createdByName ${attendeeNames.join(' ')}',
  );
  if (source.isEmpty) return const <String>[];
  final result = <String>{};
  for (final word in source.split(' ')) {
    if (word.isEmpty) continue;
    result.add(word);
    final prefixLimit = word.length < 8 ? word.length : 8;
    for (var length = 2; length <= prefixLimit; length++) {
      result.add(word.substring(0, length));
      if (result.length >= 32) break;
    }
    final digits = word.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 4) {
      result.add(digits.substring(digits.length - 4));
    }
    if (result.length >= 32) break;
  }
  return result.take(32).toList(growable: false);
}
