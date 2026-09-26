import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tablet_debug_trace.dart';

class TabletSideDockState extends ChangeNotifier {
  static const String prefsKey = 'tablet_side_dock_open';
  static const String legacyPrefsKey = 'tablet_mobile_side_dock_open';

  bool _isOpen = false;
  bool _isReady = false;

  TabletSideDockState() {
    _restore();
  }

  bool get isReady => _isReady;
  bool get isOpen => _isOpen;

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final restored = prefs.getBool(prefsKey);
      final legacy = restored == null ? prefs.getBool(legacyPrefsKey) : null;
      _isOpen = restored ?? legacy ?? false;
      var migrated = false;
      if (restored == null && legacy != null) {
        migrated = await prefs.setBool(prefsKey, legacy);
      }
      TabletDebugTrace.record(
        'TabletSideDock',
        'restored',
        <String, Object?>{
          'storedValue': restored,
          'legacyValue': legacy,
          'sideDockOpen': _isOpen,
          'usedDefault': restored == null && legacy == null,
          'migratedLegacyValue': migrated,
        },
      );
    } catch (error) {
      _isOpen = false;
      TabletDebugTrace.record(
        'TabletSideDock',
        'restore_failed',
        <String, Object?>{
          'error': error,
          'fallbackSideDockOpen': false,
        },
      );
    } finally {
      _isReady = true;
      notifyListeners();
    }
  }

  Future<void> open({String source = 'unknown'}) async {
    await _setOpen(true, source: source);
  }

  Future<void> close({String source = 'unknown'}) async {
    await _setOpen(false, source: source);
  }

  Future<void> toggle({String source = 'unknown'}) async {
    await _setOpen(!_isOpen, source: source);
  }

  Future<void> _setOpen(
    bool next, {
    required String source,
  }) async {
    if (_isOpen == next && _isReady) {
      TabletDebugTrace.record(
        'TabletSideDock',
        'change_skipped',
        <String, Object?>{
          'sideDockOpen': _isOpen,
          'source': source,
        },
      );
      return;
    }

    final previous = _isOpen;
    _isOpen = next;
    notifyListeners();

    TabletDebugTrace.record(
      'TabletSideDock',
      next ? 'opened' : 'closed',
      <String, Object?>{
        'from': previous,
        'to': next,
        'source': source,
      },
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setBool(prefsKey, next);
      TabletDebugTrace.record(
        'TabletSideDock',
        'saved',
        <String, Object?>{
          'sideDockOpen': next,
          'saved': saved,
          'source': source,
        },
      );
    } catch (error) {
      TabletDebugTrace.record(
        'TabletSideDock',
        'save_failed',
        <String, Object?>{
          'sideDockOpen': next,
          'source': source,
          'error': error,
        },
      );
    }
  }
}
