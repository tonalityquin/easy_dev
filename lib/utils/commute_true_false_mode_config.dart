import 'package:shared_preferences/shared_preferences.dart';

/// ✅ 기기(로컬) 단위로 commute_true_false(출근시각 Timestamp 기록) Firestore 업데이트를
/// On/Off 하는 설정.
///
/// - ON: 출근 시 commute_true_false 컬렉션에 Timestamp 기록
/// - OFF: commute_true_false 업데이트를 전부 스킵(= SQLite만 기록)
class CommuteTrueFalseModeConfig {
  CommuteTrueFalseModeConfig._();

  static const String _key = 'commute_true_false_enabled_v1';

  /// 기본값은 기존 동작 유지(ON)
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? true;
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, enabled);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
