import 'package:flutter/material.dart';

class UIState with ChangeNotifier {
  bool _showKeypad = true;
  bool _isLoading = false;
  final Map<String, InputFieldState> _inputFields = {};

  bool get showKeypad => _showKeypad;

  bool get isLoading => _isLoading;

  InputFieldState? getFieldState(String fieldName) => _inputFields[fieldName];

  void toggleKeypad(bool value) {
    if (_showKeypad != value) {
      _showKeypad = value;
      notifyListeners();
    }
  }

  void setLoading(bool value) {
    if (_isLoading != value) {
      _isLoading = value;
      notifyListeners();
    }
  }

  void setFieldState(String fieldName, InputFieldState state) {
    _inputFields[fieldName] = state;
    notifyListeners();
  }

  void activateField(String fieldName) {
    _inputFields.forEach((key, fieldState) {
      fieldState.isActive = (key == fieldName);
    });
    notifyListeners();
  }

  void resetState() {
    _showKeypad = true;
    _isLoading = false;
    _inputFields.clear();
    notifyListeners();
  }
}

class InputFieldState {
  bool isActive;
  bool isValid;
  String value;

  InputFieldState({
    this.isActive = false,
    this.isValid = true,
    this.value = '',
  });
}
