import 'package:flutter/foundation.dart';

enum TypeViewMode { table, status }

class TypeViewModeState extends ChangeNotifier {
  TypeViewModeState({
    TypeViewMode initial = TypeViewMode.table,
    bool statusEnabled = true,
  })  : _mode = !statusEnabled && initial == TypeViewMode.status
            ? TypeViewMode.table
            : initial,
        _statusEnabled = statusEnabled;

  TypeViewMode _mode;
  bool _statusEnabled;

  TypeViewMode get mode => _mode;

  bool get isTable => _mode == TypeViewMode.table;

  bool get statusEnabled => _statusEnabled;

  void setStatusEnabled(bool enabled) {
    final forceTable = !enabled && _mode == TypeViewMode.status;
    if (_statusEnabled == enabled && !forceTable) return;
    _statusEnabled = enabled;
    if (forceTable) {
      _mode = TypeViewMode.table;
    }
    debugPrint(
      '[TypeViewModeState] status_enabled=$enabled mode=${_mode.name} forceTable=$forceTable',
    );
    notifyListeners();
  }

  void setMode(TypeViewMode next) {
    if (next == TypeViewMode.status && !_statusEnabled) {
      debugPrint(
        '[TypeViewModeState] mode_change_blocked requested=${next.name} reason=status_disabled',
      );
      return;
    }
    if (_mode == next) return;
    _mode = next;
    notifyListeners();
  }

  void toggle() {
    if (_mode == TypeViewMode.table) {
      setMode(TypeViewMode.status);
      return;
    }
    setMode(TypeViewMode.table);
  }
}
