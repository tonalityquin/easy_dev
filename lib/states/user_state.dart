import 'package:flutter/material.dart';

/// **UserState 클래스**
/// - 사용자 이름을 관리하는 상태 클래스
/// - 사용자 이름의 설정 및 변경 알림을 처리
class UserState with ChangeNotifier {
  String? _userName; // 현재 사용자 이름

  /// **사용자 이름 가져오기**
  /// - 현재 설정된 사용자 이름 반환
  /// - 이름이 없으면 `null` 반환
  String? get userName => _userName;

  /// **사용자 이름 설정**
  /// - [name]: 새로 설정할 사용자 이름
  /// - 이름 설정 후 상태 변경 알림
  void setUserName(String name) {
    _userName = name; // 사용자 이름 업데이트
    notifyListeners(); // 상태 변경 알림
  }
}
