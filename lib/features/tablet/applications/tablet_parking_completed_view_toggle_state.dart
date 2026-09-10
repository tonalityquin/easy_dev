import 'package:flutter/foundation.dart';

import 'tablet_debug_trace.dart';

class TabletParkingCompletedViewToggleState extends ChangeNotifier {
  bool _includeParkingCompletedView = false;

  bool get includeParkingCompletedView => _includeParkingCompletedView;
  bool get isReady => true;

  void setIncludeParkingCompletedView(bool next) {
    if (_includeParkingCompletedView == next) return;
    final previous = _includeParkingCompletedView;
    _includeParkingCompletedView = next;
    TabletDebugTrace.record(
      'TabletParkingCompletedView',
      'changed',
      <String, Object?>{
        'from': previous,
        'to': next,
      },
    );
    notifyListeners();
  }

  void toggle() {
    setIncludeParkingCompletedView(!_includeParkingCompletedView);
  }

  void reset() {
    setIncludeParkingCompletedView(false);
  }
}
