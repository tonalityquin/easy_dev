import 'package:flutter/material.dart';

class StatisticsCalendarState extends ChangeNotifier {
  DateTime currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
  List<DateTime> selectedDates = [];

  void moveToNextMonth() {
    currentMonth = DateTime(currentMonth.year, currentMonth.month + 1);
    notifyListeners();
  }

  void moveToPreviousMonth() {
    currentMonth = DateTime(currentMonth.year, currentMonth.month - 1);
    notifyListeners();
  }

  void selectDate(DateTime date) {
    if (selectedDates.isEmpty) {
      // 첫 선택이면 추가
      selectedDates.add(date);
    } else if (_isSameWeek(selectedDates.first, date)) {
      // 같은 주면 토글
      if (_contains(date)) {
        selectedDates.removeWhere((d) => _isSameDay(d, date));
      } else {
        selectedDates.add(date);
      }
    } else {
      // 다른 주면 기존 선택 해제하고 새 주로 시작
      selectedDates = [date];
    }
    notifyListeners();
  }

  void clearSelectedDates() {
    selectedDates.clear();
    notifyListeners();
  }

  bool isSelected(DateTime date) {
    return selectedDates.any((d) => _isSameDay(d, date));
  }

  bool _contains(DateTime date) {
    return selectedDates.any((d) => _isSameDay(d, date));
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _isSameWeek(DateTime a, DateTime b) {
    final aStartOfWeek = a.subtract(Duration(days: a.weekday % 7));
    final bStartOfWeek = b.subtract(Duration(days: b.weekday % 7));
    return _isSameDay(aStartOfWeek, bStartOfWeek);
  }

  String get formattedMonth => "${currentMonth.year}년 ${currentMonth.month}월";

  String dateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String formatDate(DateTime date) {
    return '${date.year}년 ${date.month}월 ${date.day}일';
  }
}
