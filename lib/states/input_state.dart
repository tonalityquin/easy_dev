import 'package:flutter/material.dart';

class InputState with ChangeNotifier {
  String _front3 = ''; // 앞 3자리
  String _middle1 = ''; // 중간 1자리
  String _back4 = ''; // 뒤 4자리

  String get front3 => _front3;
  String get middle1 => _middle1;
  String get back4 => _back4;

  void updateFront3(String value) {
    _front3 = value;
    notifyListeners();
  }

  void updateMiddle1(String value) {
    _middle1 = value;
    notifyListeners();
  }

  void updateBack4(String value) {
    _back4 = value;
    notifyListeners();
  }

  void clearInput() {
    _front3 = '';
    _middle1 = '';
    _back4 = '';
    notifyListeners();
  }
}
