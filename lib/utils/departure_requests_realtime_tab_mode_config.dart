import 'package:shared_preferences/shared_preferences.dart';

class DepartureRequestsRealtimeTabModeConfig {
  static const String _prefsKey = 'departure_requests_realtime_tab_enabled_v1';

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKey) ?? false; // 기본 OFF
  }

  static Future<void> setEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, v);
  }
}
