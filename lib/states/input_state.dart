import 'package:flutter/material.dart';

class InputState with ChangeNotifier {
  static const String front_3 = 'front3';
  static const String middle_1 = 'middle1';
  static const String back_4 = 'back4';

  final Map<String, String> _inputFields = {
    front_3: '',
    middle_1: '',
    back_4: '',
  };

  String get front3 => _inputFields[front_3] ?? '';

  String get middle1 => _inputFields[middle_1] ?? '';

  String get back4 => _inputFields[back_4] ?? '';

  void updateField(String field, String value) {
    if (_inputFields.containsKey(field)) {
      _inputFields[field] = value;
      notifyListeners();
    } else {
      throw ArgumentError('Invalid field name: $field');
    }
  }

  void clearInput() {
    _inputFields.updateAll((key, value) => '');
    notifyListeners();
  }

  bool isValidField(String field, String value) {
    switch (field) {
      case front_3:
      case back_4:
        return RegExp(r'^\d{0,3}$').hasMatch(value); // 최대 3자리 숫자
      case middle_1:
        return RegExp(r'^\d{0,1}$').hasMatch(value); // 최대 1자리 숫자
      default:
        return false;
    }
  }

  void updateFieldWithValidation(String field, String value) {
    if (!_inputFields.containsKey(field)) {
      debugPrint('Error: Invalid field name: $field');
      throw ArgumentError('Invalid field name: $field');
    }

    if (!isValidField(field, value)) {
      debugPrint('Error: Invalid value for field $field: $value');
      throw ArgumentError('Invalid value for field $field: $value');
    }

    updateField(field, value);
  }
}
