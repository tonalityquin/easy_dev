import 'package:flutter/foundation.dart';

enum PadMode { big, small }

class PadModeState extends ChangeNotifier {
  PadMode _mode = PadMode.big; // 기본값: Big Pad
  PadMode get mode => _mode;

  bool get isBig => _mode == PadMode.big;
  bool get isSmall => _mode == PadMode.small;

  void setMode(PadMode next) {
    if (_mode != next) {
      _mode = next;
      notifyListeners();
    }
  }
}
