import 'package:shared_preferences/shared_preferences.dart';

enum OverlayMode {
  bubble,
  topHalf,
}

class OverlayModeConfig {
  static const String _prefsKey = 'overlay_mode';

  static Future<OverlayMode> getMode() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);

    if (raw == null) {
      return OverlayMode.bubble;
    }

    switch (raw) {
      case 'topHalf':
        return OverlayMode.topHalf;
      case 'bubble':
        return OverlayMode.bubble;
      default:
        return OverlayMode.bubble;
    }
  }

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
