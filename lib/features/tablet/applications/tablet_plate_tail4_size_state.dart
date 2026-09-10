import 'package:flutter/foundation.dart';

import 'tablet_debug_trace.dart';

enum TabletPlateTail4Size {
  compact,
  small,
  standard,
  large,
  extraLarge,
}

extension TabletPlateTail4SizeSpec on TabletPlateTail4Size {
  double get fontSize {
    switch (this) {
      case TabletPlateTail4Size.compact:
        return 24;
      case TabletPlateTail4Size.small:
        return 28;
      case TabletPlateTail4Size.standard:
        return 32;
      case TabletPlateTail4Size.large:
        return 36;
      case TabletPlateTail4Size.extraLarge:
        return 40;
    }
  }

  String get label {
    switch (this) {
      case TabletPlateTail4Size.compact:
        return '24';
      case TabletPlateTail4Size.small:
        return '28';
      case TabletPlateTail4Size.standard:
        return '32';
      case TabletPlateTail4Size.large:
        return '36';
      case TabletPlateTail4Size.extraLarge:
        return '40';
    }
  }
}

class TabletPlateTail4SizeState extends ChangeNotifier {
  TabletPlateTail4Size _size = TabletPlateTail4Size.standard;

  TabletPlateTail4Size get size => _size;
  bool get isReady => true;
  double get fontSize => _size.fontSize;

  void setSize(TabletPlateTail4Size next) {
    if (_size == next) return;
    final previous = _size;
    _size = next;
    TabletDebugTrace.record(
      'TabletPlateTail4Size',
      'changed',
      <String, Object?>{
        'from': previous.name,
        'to': next.name,
        'fontSize': next.fontSize,
      },
    );
    notifyListeners();
  }

  void next() {
    final nextSize = switch (_size) {
      TabletPlateTail4Size.standard => TabletPlateTail4Size.large,
      TabletPlateTail4Size.large => TabletPlateTail4Size.extraLarge,
      TabletPlateTail4Size.extraLarge => TabletPlateTail4Size.compact,
      TabletPlateTail4Size.compact => TabletPlateTail4Size.small,
      TabletPlateTail4Size.small => TabletPlateTail4Size.standard,
    };
    setSize(nextSize);
  }

  void reset() {
    setSize(TabletPlateTail4Size.standard);
  }
}
