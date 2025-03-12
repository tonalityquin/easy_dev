import 'package:flutter/material.dart';

enum InputField { front3, middle1, back4 }

class InputState with ChangeNotifier {
  final List<InputField> _fields = InputField.values;
  final Map<InputField, RegExp> _validationRules = {
    InputField.front3: RegExp(r'^\d{0,3}$'),
    InputField.middle1: RegExp(r'^\d{0,1}$'),
    InputField.back4: RegExp(r'^\d{0,4}$'),
  };
  late final Map<InputField, String> _inputFields = {
    for (var field in _fields) field: '',
  };

  String get front3 => _inputFields[InputField.front3] ?? '';

  String get middle1 => _inputFields[InputField.middle1] ?? '';

  String get back4 => _inputFields[InputField.back4] ?? '';

  void updateField(InputField field, String value) {
    if (_inputFields[field] == value) return;
    _inputFields[field] = value;
    notifyListeners();
  }

  bool isValidField(InputField field, String value) {
    if (value.isEmpty) return true;
    return _validationRules[field]?.hasMatch(value) ?? false;
  }

  void updateFieldWithValidation(InputField field, String value, {required void Function(String) onError}) {
    if (!isValidField(field, value)) {
      final error = '⚠️ 잘못된 값 입력 ($field): $value';
      debugPrint(error);
      onError(error);
      return;
    }
    updateField(field, value);
  }

  void clearInput() {
    bool hasChanged = false;
    _inputFields.updateAll((key, value) {
      if (value.isNotEmpty) {
        hasChanged = true;
        return '';
      }
      return value;
    });
    if (hasChanged) {
      notifyListeners(); // 🚀 값이 변경된 경우에만 UI 업데이트
    }
  }
}
