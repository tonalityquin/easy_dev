import 'package:flutter/foundation.dart';

class VoiceAppbarUiState extends ChangeNotifier {
  bool _enabled = false;

  bool get enabled => _enabled;

  void toggle() {
    _enabled = !_enabled;
    notifyListeners();
  }

  void setEnabled(bool value) {
    if (_enabled == value) {
      return;
    }
    _enabled = value;
    notifyListeners();
  }
}
