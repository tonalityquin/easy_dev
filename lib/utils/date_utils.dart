import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; // debugPrint 사용을 위한 import

class CustomDateUtils {
  static String formatTimeForUI(dynamic timestamp) {
    DateTime? dateTime;
    if (timestamp is Timestamp) {
      dateTime = timestamp.toDate();
    } else if (timestamp is DateTime) {
      dateTime = timestamp;
    }
    if (dateTime != null) {
      return '${_twoDigits(dateTime.hour)}:${_twoDigits(dateTime.minute)}:${_twoDigits(dateTime.second)}';
    }
    debugPrint('Invalid timestamp in formatTimeForUI: $timestamp');
    return 'Unknown';
  }

  static String formatTimestamp(dynamic timestamp) {
    DateTime? dateTime;
    if (timestamp is Timestamp) {
      dateTime = timestamp.toDate();
    } else if (timestamp is DateTime) {
      dateTime = timestamp;
    }
    if (dateTime != null) {
      return '${dateTime.year}-${_twoDigits(dateTime.month)}-${_twoDigits(dateTime.day)} '
          '${_twoDigits(dateTime.hour)}:${_twoDigits(dateTime.minute)}:${_twoDigits(dateTime.second)}';
    }
    debugPrint('Invalid timestamp in formatTimestamp: $timestamp');
    return 'Unknown';
  }

  static String timeElapsed(dynamic timestamp) {
    DateTime? dateTime;
    if (timestamp is Timestamp) {
      dateTime = timestamp.toDate();
    } else if (timestamp is DateTime) {
      dateTime = timestamp;
    }
    if (dateTime != null) {
      Duration difference = DateTime.now().difference(dateTime);

      int hours = difference.inHours;
      int minutes = difference.inMinutes % 60;

      debugPrint('현재 시간: ${DateTime.now()}');
      debugPrint('요청 시간: $dateTime');
      debugPrint('경과 시간: $hours시간 $minutes분');
      return '$hours시간 $minutes분';
    }
    debugPrint('Invalid timestamp in timeElapsed: $timestamp');
    return 'Unknown';
  }

  static String _twoDigits(int n) {
    return n.toString().padLeft(2, '0');
  }
}
