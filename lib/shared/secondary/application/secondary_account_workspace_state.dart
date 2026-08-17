import 'package:flutter/foundation.dart';

enum SecondaryAccountMode { operation, delete }

class SecondaryAccountWorkspaceState extends ChangeNotifier {
  SecondaryAccountWorkspaceState({ValueChanged<String>? onDebug})
      : _onDebug = onDebug;

  final ValueChanged<String>? _onDebug;
  SecondaryAccountMode _mode = SecondaryAccountMode.operation;

  SecondaryAccountMode get mode => _mode;

  bool get isDeleteMode => _mode == SecondaryAccountMode.delete;

  void setMode(
    SecondaryAccountMode mode, {
    required String source,
  }) {
    if (_mode == mode) {
      log('mode_reselected mode=${mode.name} source=$source');
      return;
    }
    final previous = _mode;
    _mode = mode;
    log('mode_changed from=${previous.name} to=${mode.name} source=$source');
    notifyListeners();
  }

  void reset({required String source}) {
    setMode(SecondaryAccountMode.operation, source: source);
  }

  void log(String message) {
    final output = 'account_workspace $message';
    final logger = _onDebug;
    if (logger != null) {
      logger(output);
      return;
    }
    debugPrint('[SecondaryAccountWorkspace] $output');
  }
}
