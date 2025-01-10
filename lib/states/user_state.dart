import 'package:flutter/material.dart';

class UserState with ChangeNotifier {
  String? _userName;

  String? get userName => _userName;

  void setUserName(String name) {
    _userName = name;
    notifyListeners();
  }
}
