String formatRealTimeElapsed(
  DateTime? value, {
  required DateTime now,
}) {
  if (value == null) return '—';
  final elapsed = now.difference(value);
  if (elapsed.isNegative || elapsed.inSeconds < 10) return '방금';
  if (elapsed.inSeconds < 60) return '${elapsed.inSeconds}초';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}분';
  if (elapsed.inHours < 24) {
    final minutes = elapsed.inMinutes.remainder(60);
    if (minutes == 0) return '${elapsed.inHours}시간';
    return '${elapsed.inHours}시간 ${minutes}분';
  }
  if (elapsed.inDays >= 100) return '99일+';
  final hours = elapsed.inHours.remainder(24);
  if (hours == 0) return '${elapsed.inDays}일';
  return '${elapsed.inDays}일 ${hours}시간';
}

Duration? nextRealTimeElapsedTick({
  required Iterable<DateTime?> values,
  required DateTime now,
}) {
  final timestamps = values.whereType<DateTime>().toList(growable: false);
  if (timestamps.isEmpty) return null;
  final hasSecondPrecision = timestamps.any((value) {
    final age = now.difference(value);
    return age.isNegative || age.inSeconds < 60;
  });
  if (hasSecondPrecision) return const Duration(seconds: 1);
  final hasMinutePrecision = timestamps.any((value) {
    final age = now.difference(value);
    return !age.isNegative && age.inHours < 24;
  });
  if (hasMinutePrecision) {
    final seconds = 60 - now.second;
    return Duration(seconds: seconds == 0 ? 60 : seconds);
  }
  final minutes = 59 - now.minute;
  final seconds = 60 - now.second;
  final delay = Duration(minutes: minutes, seconds: seconds);
  return delay <= Duration.zero ? const Duration(hours: 1) : delay;
}
