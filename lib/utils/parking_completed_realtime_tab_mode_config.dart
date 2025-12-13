import 'package:shared_preferences/shared_preferences.dart';

/// ✅ "입차 완료 테이블"의 실시간 탭 진입(표시) 여부 제어
/// - 기기 로컬(SharedPreferences)로 저장
/// - 기본값: OFF(false)
/// - 앱 재실행 후에도 유지
class ParkingCompletedRealtimeTabModeConfig {
  static const String _prefsKey = 'parking_completed_realtime_tab_enabled_v1';

  static SharedPreferences? _prefs;
  static bool _loaded = false;
  static bool _enabled = false; // 기본 OFF

  static Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _prefs = await SharedPreferences.getInstance();
    _enabled = _prefs!.getBool(_prefsKey) ?? false; // 기본 OFF
    _loaded = true;
  }

  /// 비동기 로드 포함
  static Future<bool> isEnabled() async {
    await _ensureLoaded();
    return _enabled;
  }

  /// 저장 + 캐시 갱신
  static Future<void> setEnabled(bool v) async {
    await _ensureLoaded();
    _enabled = v;
    await _prefs!.setBool(_prefsKey, v);
  }

  /// (선택) 동기 접근: 로드 전이면 false로 간주
  static bool get isEnabledSync => _loaded ? _enabled : false;
}
