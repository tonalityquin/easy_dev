import 'package:flutter/foundation.dart';

/// **CustomDateUtils 클래스**
/// - 시간 및 날짜와 관련된 유틸리티 메서드를 제공하는 클래스
/// - Firebase Timestamp 대신 DateTime 객체를 직접 사용하여 다양한 포맷으로 변환
class CustomDateUtils {
  /// **UI에서 표시하기 위한 시간 포맷팅 함수**
  /// - [timestamp]: DateTime 객체
  /// - 반환값: `HH:mm:ss` 형식의 시간 문자열
  static String formatTimeForUI(DateTime dateTime) {
    return '${_twoDigits(dateTime.hour)}:${_twoDigits(dateTime.minute)}:${_twoDigits(dateTime.second)}';
  }

  /// **타임스탬프를 날짜 및 시간 형식으로 변환하는 함수**
  /// - [dateTime]: DateTime 객체
  /// - 반환값: `yyyy-MM-dd HH:mm:ss` 형식의 문자열
  static String formatTimestamp(DateTime dateTime) {
    return '${dateTime.year}-${_twoDigits(dateTime.month)}-${_twoDigits(dateTime.day)} '
        '${_twoDigits(dateTime.hour)}:${_twoDigits(dateTime.minute)}:${_twoDigits(dateTime.second)}';
  }

  /// **특정 타임스탬프로부터 경과된 시간 계산**
  /// - [dateTime]: DateTime 객체
  /// - 반환값: `N시간 N분` 형식의 경과 시간 문자열
  static String timeElapsed(DateTime dateTime) {
    Duration difference = DateTime.now().difference(dateTime);

    int hours = difference.inHours; // 경과된 시간
    int minutes = difference.inMinutes % 60; // 경과된 분

    // 디버그 정보 출력
    debugPrint('현재 시간: ${DateTime.now()}');
    debugPrint('요청 시간: $dateTime');
    debugPrint('경과 시간: $hours시간 $minutes분');
    return '$hours시간 $minutes분';
  }

  /// **숫자를 두 자리로 포맷팅**
  /// - [n]: 정수
  /// - 반환값: 두 자리 형식의 문자열 (예: `01`, `09`, `15`)
  static String _twoDigits(int n) {
    return n.toString().padLeft(2, '0'); // 한 자리는 앞에 0 추가
  }
}
