import 'package:flutter/material.dart';

class BreakLog {
  final String name;
  final DateTime timestamp;

  BreakLog({required this.name, required this.timestamp});
}

class BreakLogState extends ChangeNotifier {
  final List<BreakLog> _logs = [];

  List<BreakLog> get logs => List.unmodifiable(_logs);

  void addLog(String name) {
    _logs.add(BreakLog(name: name, timestamp: DateTime.now()));
    notifyListeners();
  }
}
