import 'package:cloud_firestore/cloud_firestore.dart';

class CustomDateUtils {
  // UI에 표시할 시간 (시간, 분, 초)
  static String formatTimeForUI(dynamic timestamp) {
    if (timestamp != null && timestamp is Timestamp) {
      DateTime dateTime = timestamp.toDate();
      return '${_twoDigits(dateTime.hour)}:${_twoDigits(dateTime.minute)}:${_twoDigits(dateTime.second)}';
    }
    return 'Unknown'; // null 처리
  }

  // 로그용 전체 시간 (연, 월, 일 포함)
  static String formatTimestamp(dynamic timestamp) {
    if (timestamp != null && timestamp is Timestamp) {
      DateTime dateTime = timestamp.toDate();
      return '${dateTime.year}-${_twoDigits(dateTime.month)}-${_twoDigits(dateTime.day)} '
          '${_twoDigits(dateTime.hour)}:${_twoDigits(dateTime.minute)}:${_twoDigits(dateTime.second)}';
    }
    return 'Unknown'; // null 처리
  }

  // 경과 시간 계산 (시간, 분)
  static String timeElapsed(dynamic timestamp) {
    if (timestamp != null && timestamp is Timestamp) {
      DateTime dateTime = timestamp.toDate();
      Duration difference = DateTime.now().difference(dateTime);

      int hours = difference.inHours;
      int minutes = difference.inMinutes % 60; // 시간 제외 분 계산

      print('현재 시간: ${DateTime.now()}'); // 디버깅 로그
      print('요청 시간: $timestamp'); // 디버깅 로그
      print('경과 시간: ${hours}시간 ${minutes}분'); // 디버깅 로그

      return '${hours}시간 ${minutes}분';
    }
    return 'Unknown'; // null 처리
  }

  // 숫자를 두 자리로 포맷팅 (예: 1 -> 01)
  static String _twoDigits(int n) {
    return n.toString().padLeft(2, '0');
  }
}
