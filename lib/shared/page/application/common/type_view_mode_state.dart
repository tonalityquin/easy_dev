import 'package:flutter/foundation.dart';

enum TypeViewMode { table, status }

class TypeViewModeState extends ChangeNotifier {
  TypeViewModeState({TypeViewMode initial = TypeViewMode.table}) : _mode = initial;

  TypeViewMode _mode;

  TypeViewMode get mode => _mode;

  bool get isTable => _mode == TypeViewMode.table;

  void setMode(TypeViewMode next) {
    if (_mode == next) return;
    _mode = next;
    notifyListeners();
  }

  void toggle() {
    setMode(_mode == TypeViewMode.table ? TypeViewMode.status : TypeViewMode.table);
  }
}
