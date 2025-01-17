import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart'; // SharedPreferences 패키지 추가

/// **UserState 클래스**
/// 사용자 정보를 관리하고, SharedPreferences와 상태를 동기화하는 클래스
class UserState extends ChangeNotifier {
  String _name = ''; // 사용자 이름
  String _phone = ''; // 사용자 전화번호
  String _role = ''; // 사용자 역할
  String _area = ''; // 사용자 지역

  /// **상태값 게터 (Getter)**
  String get name => _name;
  String get phone => _phone;
  String get role => _role;
  String get area => _area;

  /// **지역 상태값 세터 (Setter)**
  /// - 지역 값 변경 시 상태를 갱신하고 알림
  set area(String newArea) {
    _area = newArea;
    notifyListeners(); // 상태 변경 알림
    debugPrint('Area setter triggered: newArea=$_area'); // 변경 시점 로그
  }

  /// **상태 변경 알림 로깅**
  @override
  void notifyListeners() {
    super.notifyListeners();
    debugPrint('UserState notifyListeners called: name=$_name, area=$_area'); // 상태 변경 로그
  }

  /// **사용자 정보를 업데이트**
  /// - 상태 변경 및 SharedPreferences 저장
  Future<void> updateUser({
    required String name,
    required String phone,
    required String role,
    required String area,
  }) async {
    _name = name;
    _phone = phone;
    _role = role;
    _area = area;

    notifyListeners(); // 상태 변경 알림

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('name', name);
    await prefs.setString('phone', phone);
    await prefs.setString('role', role);
    await prefs.setString('area', area);
    await prefs.setBool('isLoggedIn', true);

    debugPrint('After updateUser: name=$_name, area=$_area'); // 업데이트 로그
  }

  /// **사용자 정보 불러오기**
  /// - SharedPreferences에서 사용자 정보 로드
  Future<void> loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

    if (isLoggedIn) {
      _name = prefs.getString('name') ?? '';
      _phone = prefs.getString('phone') ?? '';
      _role = prefs.getString('role') ?? '';
      _area = prefs.getString('area') ?? '';
    } else {
      _name = '';
      _phone = '';
      _role = '';
      _area = '';
    }

    notifyListeners(); // 상태 변경 알림
    debugPrint('After loadUser: name=$_name, area=$_area'); // 불러온 상태 로그
  }

  /// **사용자 정보 초기화**
  /// - 상태 초기화 및 SharedPreferences 삭제
  Future<void> clearUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear(); // SharedPreferences 데이터 삭제

    _name = '';
    _phone = '';
    _role = '';
    _area = '';

    notifyListeners(); // 상태 변경 알림
    debugPrint('UserState cleared: name=$_name, area=$_area'); // 초기화 로그
  }
}
