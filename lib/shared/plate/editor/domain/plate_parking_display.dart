String plateParkingOverviewLocation(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '';
  final segments = value
      .split(' - ')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (segments.length < 3) return value;
  final slotMatch = RegExp(r'(\d+)').firstMatch(segments[2]);
  if (slotMatch == null) {
    final slotSegment = segments[2].split('·').first.trim();
    return '${segments[0]} - ${segments[1]} - $slotSegment';
  }
  return '${segments[0]} - ${segments[1]} - 슬롯 ${slotMatch.group(1)}';
}
