import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sensor_debug_trace.dart';

class SensorSideDockState extends ChangeNotifier {
  static const String prefsKey = 'sensor_side_dock_open';

  bool _isOpen = false;
  bool _isReady = false;

  SensorSideDockState() {
    _restore();
  }

  bool get isReady => _isReady;
  bool get isOpen => _isOpen;

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isOpen = prefs.getBool(prefsKey) ?? false;
      SensorDebugTrace.record(
        'SensorSideDock',
        'restored',
        <String, Object?>{
          'sideDockOpen': _isOpen,
        },
      );
    } catch (error) {
      _isOpen = false;
      SensorDebugTrace.record(
        'SensorSideDock',
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
      SensorDebugTrace.record(
        'SensorSideDock',
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

    SensorDebugTrace.record(
      'SensorSideDock',
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
      SensorDebugTrace.record(
        'SensorSideDock',
        'saved',
        <String, Object?>{
          'sideDockOpen': next,
          'saved': saved,
          'source': source,
        },
      );
    } catch (error) {
      SensorDebugTrace.record(
        'SensorSideDock',
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
