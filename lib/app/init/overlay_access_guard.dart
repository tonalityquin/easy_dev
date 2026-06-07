import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OverlayAccessGuard {
  OverlayAccessGuard._();

  static const String modePrefsKey = 'mode';
  static const Set<String> blockedModes = <String>{
    'personal',
    'tablet',
    'mobile',
    'direct',
  };

  static String normalizeMode(String? mode) {
    return (mode ?? '').trim().toLowerCase();
  }

  static bool isBlockedMode(String? mode) {
    return blockedModes.contains(normalizeMode(mode));
  }

  static Future<String> currentMode() async {
    final prefs = await SharedPreferences.getInstance();
    return normalizeMode(prefs.getString(modePrefsKey));
  }

  static Future<bool> isBlocked() async {
    return isBlockedMode(await currentMode());
  }

  static Future<bool> closeIfBlocked() async {
    if (!await isBlocked()) return false;
    try {
      if (await FlutterOverlayWindow.isActive()) {
        await FlutterOverlayWindow.closeOverlay();
      }
    } catch (_) {}
    return true;
  }
}
