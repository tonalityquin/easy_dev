import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  static const String prefsKey = 'tablet_plate_tail4_size_v1';

  TabletPlateTail4Size _size = TabletPlateTail4Size.standard;
  bool _isReady = false;
  Future<void> _persistQueue = Future<void>.value();

  TabletPlateTail4SizeState() {
    _restore();
  }

  TabletPlateTail4Size get size => _size;
  bool get isReady => _isReady;
  double get fontSize => _size.fontSize;

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = (prefs.getString(prefsKey) ?? '').trim();
      _size = TabletPlateTail4Size.values.firstWhere(
        (value) => value.name == raw,
        orElse: () => TabletPlateTail4Size.standard,
      );
      debugPrint(
        '[TabletPlateTail4Size] event=restored size=${_size.name} fontSize=${_size.fontSize}',
      );
    } catch (e) {
      _size = TabletPlateTail4Size.standard;
      debugPrint(
        '[TabletPlateTail4Size] event=restore_failed error=$e fallback=${_size.name}',
      );
    } finally {
      _isReady = true;
      notifyListeners();
    }
  }

  Future<void> setSize(TabletPlateTail4Size next) async {
    if (_size == next && _isReady) return;
    final previous = _size;
    _size = next;
    notifyListeners();
    debugPrint(
      '[TabletPlateTail4Size] event=changed from=${previous.name} to=${next.name} fontSize=${next.fontSize}',
    );

    _persistQueue = _persistQueue.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(prefsKey, next.name);
        debugPrint(
          '[TabletPlateTail4Size] event=saved size=${next.name} fontSize=${next.fontSize}',
        );
      } catch (e) {
        debugPrint(
          '[TabletPlateTail4Size] event=save_failed size=${next.name} error=$e',
        );
      }
    });
    await _persistQueue;
  }
}
