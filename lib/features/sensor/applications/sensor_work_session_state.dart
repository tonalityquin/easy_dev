import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sensor_debug_trace.dart';

class SensorWorkSessionState extends ChangeNotifier {
  static const String prefsKey = 'sensor_work_session_active';

  bool _isActive = true;
  bool _isReady = false;
  late final Future<void> _restoreFuture;

  SensorWorkSessionState() {
    _restoreFuture = _restore();
  }

  bool get isActive => _isActive;
  bool get isReady => _isReady;

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isActive = prefs.getBool(prefsKey) ?? true;
      SensorDebugTrace.record(
        'SensorWorkSession',
        'restored',
        <String, Object?>{
          'active': _isActive,
        },
      );
    } catch (error) {
      _isActive = true;
      SensorDebugTrace.record(
        'SensorWorkSession',
        'restore_failed',
        <String, Object?>{
          'error': error,
          'fallbackActive': true,
        },
      );
    } finally {
      _isReady = true;
      notifyListeners();
    }
  }

  Future<void> setActive(
    bool next, {
    String source = 'unknown',
  }) async {
    await _restoreFuture;
    if (_isActive == next && _isReady) {
      SensorDebugTrace.record(
        'SensorWorkSession',
        'change_skipped',
        <String, Object?>{
          'active': _isActive,
          'source': source,
        },
      );
      return;
    }

    final previous = _isActive;
    _isActive = next;
    notifyListeners();

    SensorDebugTrace.record(
      'SensorWorkSession',
      next ? 'started' : 'stopped',
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
        'SensorWorkSession',
        'saved',
        <String, Object?>{
          'active': next,
          'saved': saved,
          'source': source,
        },
      );
    } catch (error) {
      SensorDebugTrace.record(
        'SensorWorkSession',
        'save_failed',
        <String, Object?>{
          'active': next,
          'source': source,
          'error': error,
        },
      );
    }
  }

  Future<void> startWork({String source = 'unknown'}) async {
    await setActive(true, source: source);
  }

  Future<void> stopWork({String source = 'unknown'}) async {
    await setActive(false, source: source);
  }
}
