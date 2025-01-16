import 'package:flutter/material.dart';

class UserState extends ChangeNotifier {
  String _name = ''; // 빈 문자열로 초기화
  String _phone = '';
  String _role = '';
  String _area = '';

  String get name => _name;

  String get phone => _phone;

  String get role => _role;

  String get area => _area;

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

  void clearUser() {
    _name = '';
    _phone = '';
    _role = '';
    _area = '';
    notifyListeners();
  }
}
