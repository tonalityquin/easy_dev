// 📁 states/calendar/calendar_selection_state.dart
import 'package:flutter/material.dart';
import '../../models/user_model.dart';

class CalendarSelectionState extends ChangeNotifier {
  String? _selectedArea;
  UserModel? _selectedUser;

  String? get selectedArea => _selectedArea;
  UserModel? get selectedUser => _selectedUser;

  void setArea(String? area) {
    _selectedArea = area;
    notifyListeners();
  }

  void setUser(UserModel? user) {
    _selectedUser = user;
    notifyListeners();
  }

  void clear() {
    _selectedArea = null;
    _selectedUser = null;
    notifyListeners();
  }
}
