import 'package:flutter/foundation.dart';

class CustomDateUtils {
  static String formatTimeForUI(DateTime dateTime) {
    return '${_twoDigits(dateTime.hour)}:${_twoDigits(dateTime.minute)}:${_twoDigits(dateTime.second)}';
  }

  static String formatTimestamp(DateTime dateTime) {
    return '${dateTime.year}-${_twoDigits(dateTime.month)}-${_twoDigits(dateTime.day)} '
        '${_twoDigits(dateTime.hour)}:${_twoDigits(dateTime.minute)}:${_twoDigits(dateTime.second)}';
  }

  static String timeElapsed(DateTime dateTime) {
    Duration difference = DateTime.now().difference(dateTime);

    int hours = difference.inHours;
    int minutes = difference.inMinutes % 60;
    debugPrint('현재 시간: ${DateTime.now()}');
    debugPrint('요청 시간: $dateTime');
    debugPrint('경과 시간: $hours시간 $minutes분');
    return '$hours시간 $minutes분';
  }

  static String _twoDigits(int n) {
    return n.toString().padLeft(2, '0');
  }
}
