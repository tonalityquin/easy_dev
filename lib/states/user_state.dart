import 'package:flutter/material.dart';

class UserState extends ChangeNotifier {
  String? _name;
  String? _phone;

  String? get name => _name;

  String? get phone => _phone;

  void updateUser({required String name, required String phone}) {
    _name = name;
    _phone = phone;
    notifyListeners(); // 상태 변경 알림
  }
}
