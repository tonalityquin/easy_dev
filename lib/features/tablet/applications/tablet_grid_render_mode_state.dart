import 'package:flutter/foundation.dart';

import 'tablet_debug_trace.dart';

enum TabletGridRenderMode { twoD, threeD }

class TabletGridRenderModeState extends ChangeNotifier {
  TabletGridRenderMode _mode = TabletGridRenderMode.twoD;

  TabletGridRenderMode get mode => _mode;
  bool get isReady => true;
  bool get isTwoD => _mode == TabletGridRenderMode.twoD;
  bool get isThreeD => _mode == TabletGridRenderMode.threeD;

  void setMode(TabletGridRenderMode next) {
    if (_mode == next) return;
    final previous = _mode;
    _mode = next;
    TabletDebugTrace.record(
      'TabletGridRenderMode',
      'changed',
      <String, Object?>{
        'from': previous.name,
        'to': next.name,
      },
    );
    notifyListeners();
  }

  void toggle() {
    setMode(
      _mode == TabletGridRenderMode.twoD
          ? TabletGridRenderMode.threeD
          : TabletGridRenderMode.twoD,
    );
  }

  void reset() {
    setMode(TabletGridRenderMode.twoD);
  }
}
