import 'package:flutter/material.dart';

class InputState with ChangeNotifier {
  final Map<String, String> _inputFields = {
    'front3': '', // 앞 3자리
    'middle1': '', // 중간 1자리
    'back4': '', // 뒤 4자리
  };

  String get front3 => _inputFields['front3'] ?? '';

  String get middle1 => _inputFields['middle1'] ?? '';

  String get back4 => _inputFields['back4'] ?? '';

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
    if (field == 'front3' || field == 'back4') {
      return RegExp(r'^\d{0,3}$').hasMatch(value); // 최대 3자리 숫자
    } else if (field == 'middle1') {
      return RegExp(r'^\d{0,1}$').hasMatch(value); // 최대 1자리 숫자
    }
    return false;
  }

  void updateFieldWithValidation(String field, String value) {
    if (!_inputFields.containsKey(field)) {
      debugPrint('Error: Invalid field name: $field');
      throw ArgumentError('Invalid field name: $field');
    }

    if ((field == 'front3' || field == 'back4') && !RegExp(r'^\d{0,3}$').hasMatch(value)) {
      debugPrint('Error: Invalid value for field $field: $value');
      throw ArgumentError('Invalid value for field $field: $value');
    }

    if (field == 'middle1' && !RegExp(r'^\d{0,1}$').hasMatch(value)) {
      debugPrint('Error: Invalid value for field $field: $value');
      throw ArgumentError('Invalid value for field $field: $value');
    }

    updateField(field, value);
  }
}
