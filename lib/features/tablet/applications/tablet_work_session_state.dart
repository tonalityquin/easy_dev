import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TabletWorkSessionState extends ChangeNotifier {
  static const String prefsKey = 'tablet_work_session_active';

  bool _isActive = true;
  bool _isReady = false;

  TabletWorkSessionState() {
    _restore();
  }

  bool get isActive => _isActive;
  bool get isReady => _isReady;

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isActive = prefs.getBool(prefsKey) ?? true;
    } catch (e) {
      debugPrint('TabletWorkSessionState restore failed: $e');
      _isActive = true;
    } finally {
      _isReady = true;
      notifyListeners();
    }
  }

  Future<void> setActive(bool next) async {
    if (_isActive == next && _isReady) return;
    _isActive = next;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefsKey, next);
    } catch (e) {
      debugPrint('TabletWorkSessionState save failed: $e');
    }
  }

  Future<void> startWork() async {
    await setActive(true);
  }

  Future<void> stopWork() async {
    await setActive(false);
  }
}
