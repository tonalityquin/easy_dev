import 'package:flutter/material.dart';

class UserState extends ChangeNotifier {
  String? _name;
  String? _phone;
  String? _role;
  String? _area;

  String? get name => _name;

  String? get phone => _phone;

  String? get role => _role;

  String? get area => _area;

  void updateUser({
    required String name,
    required String phone,
    required String role,
    required String area,
  }) {
    _name = name;
    _phone = phone;
    _role = role;
    _area = area;
    notifyListeners();
  }


  /// 역할 업데이트
  void updateRole(String role) {
    _role = role;
    notifyListeners();
  }

  /// 지역 업데이트
  void updateArea(String area) {
    _area = area;
    notifyListeners();
  }

  /// 모든 사용자 상태 초기화
  void clearUser() {
    _name = null;
    _phone = null;
    _role = null;
    _area = null;
    notifyListeners();
  }
}
