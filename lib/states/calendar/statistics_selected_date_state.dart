import 'package:flutter/material.dart';

class StatisticsSelectedDateState extends ChangeNotifier {
  List<DateTime> _selectedDates = [];

  List<DateTime> get selectedDates => _selectedDates;

  void setSelectedDates(List<DateTime> dates) {
    _selectedDates = dates;
    notifyListeners();
  }

  void clearSelectedDates() {
    _selectedDates.clear();
    notifyListeners();
  }
}
