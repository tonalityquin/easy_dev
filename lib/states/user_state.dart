import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart'; // SharedPreferences 패키지 추가

class UserState extends ChangeNotifier {
  String _name = ''; // 사용자 이름
  String _phone = ''; // 사용자 전화번호
  String _role = ''; // 사용자 역할
  String _area = ''; // 사용자 지역

  // 게터(Getter) - 상태값을 읽어올 때 사용
  String get name => _name;
  String get phone => _phone;
  String get role => _role;
  String get area => _area;

  // 사용자 정보를 업데이트하고 SharedPreferences에 저장
  void updateUser({
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

    // SharedPreferences에 저장
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('name', name);
    await prefs.setString('phone', phone);
    await prefs.setString('role', role);
    await prefs.setString('area', area);
  }

  // 저장된 사용자 정보를 불러오기
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
    notifyListeners();
  }

  // 사용자 정보를 초기화하고 SharedPreferences에서 삭제
  Future<void> clearUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear(); // SharedPreferences 데이터 삭제
    _name = '';
    _phone = '';
    _role = '';
    _area = '';
    notifyListeners(); // 상태 변경 알림
  }
}
