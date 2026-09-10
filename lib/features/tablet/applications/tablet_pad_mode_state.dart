import 'package:flutter/foundation.dart';

import 'tablet_debug_trace.dart';

enum PadMode { big, small, show, mobile, gridPad, grid }

class TabletPadModeState extends ChangeNotifier {
  PadMode _mode = PadMode.mobile;

  PadMode get mode => _mode;

  bool get isBig => _mode == PadMode.big;
  bool get isSmall => _mode == PadMode.small;
  bool get isShow => _mode == PadMode.show;
  bool get isMobile => _mode == PadMode.mobile;
  bool get isGridPad => _mode == PadMode.gridPad;
  bool get isGrid => _mode == PadMode.grid;

  void setMode(PadMode next) {
    if (_mode == next) return;
    final previous = _mode;
    _mode = next;
    TabletDebugTrace.record(
      'TabletPadMode',
      'changed',
      <String, Object?>{
        'from': previous.name,
        'to': next.name,
      },
    );
    notifyListeners();
  }
}
