// lib/utils/overlay_mode_config.dart
import 'package:shared_preferences/shared_preferences.dart';

/// 오버레이 UI 모드:
/// - bubble  : 기존 플로팅 버블(QuickOverlay)
/// - topHalf : 화면 상단 50%를 덮는 포그라운드 패널
enum OverlayMode {
  bubble,
  topHalf,
}

class OverlayModeConfig {
  static const String _prefsKey = 'overlay_mode';

  /// 현재 저장된 모드를 가져온다.
  ///
  /// - 저장된 값이 없거나 알 수 없는 값이면 기본값은 **topHalf**.
  static Future<OverlayMode> getMode() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);

    if (raw == null) {
      // 아직 아무 값도 저장되지 않은 경우 → 기본값: 상단 50% 포그라운드
      return OverlayMode.topHalf;
    }

    switch (raw) {
      case 'topHalf':
        return OverlayMode.topHalf;
      case 'bubble':
        return OverlayMode.bubble;
      default:
      // 알 수 없는 값이 들어있는 경우도 안전하게 topHalf 로 폴백
        return OverlayMode.topHalf;
    }
  }

  /// 모드를 저장한다.
  static Future<void> setMode(OverlayMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, _modeToString(mode));
  }

  static String _modeToString(OverlayMode mode) {
    switch (mode) {
      case OverlayMode.topHalf:
        return 'topHalf';
      case OverlayMode.bubble:
        return 'bubble';
    }
  }
}
