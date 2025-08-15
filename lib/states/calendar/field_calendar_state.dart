// lib/states/calendar/field_calendar_states.dart

import 'package:flutter/material.dart';

/// 달력 화면의 월/선택일 상태와 날짜 유틸을 관리
class FieldCalendarState extends ChangeNotifier {
  DateTime currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime selectedDate = DateTime.now();

  void selectDate(DateTime date) {
    selectedDate = date;
    notifyListeners();
  }

  void setCurrentMonth(DateTime date) {
    currentMonth = DateTime(date.year, date.month);
    notifyListeners();
  }

  String dateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String formatDate(DateTime date) {
    return '${date.year}년 ${date.month}월 ${date.day}일';
  }
}

/// 다른 모듈들이 공통으로 참고하는 "선택된 날짜" 전역 상태
class FieldSelectedDateState extends ChangeNotifier {
  DateTime? _selectedDate;

  DateTime? get selectedDate => _selectedDate;

  void setSelectedDate(DateTime date) {
    _selectedDate = date;
    notifyListeners();
  }
}
