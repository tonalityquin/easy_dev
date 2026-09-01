import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kDevModeEnabledKey = 'dev_mode_enabled_v1';
const prefsKeyMode = 'mode';
const _prefsKeyDevAuth = 'dev_auth';
const _prefsKeyDevAuthUntil = 'dev_auth_until';

class DevPrefs {
  final String? savedMode;
  final bool devAuthorized;

  const DevPrefs({
    required this.savedMode,
    required this.devAuthorized,
  });
}

class DevAuth {
  static final ValueNotifier<bool> devModeEnabled = ValueNotifier<bool>(false);

  static Future<DevPrefs> restorePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString(prefsKeyMode);
    if (prefs.containsKey(_prefsKeyDevAuth)) {
      await prefs.remove(_prefsKeyDevAuth);
    }
    if (prefs.containsKey(_prefsKeyDevAuthUntil)) {
      await prefs.remove(_prefsKeyDevAuthUntil);
    }
    final enabled = prefs.getBool(kDevModeEnabledKey) ?? false;
    if (devModeEnabled.value != enabled) {
      devModeEnabled.value = enabled;
    }
    return DevPrefs(savedMode: savedMode, devAuthorized: enabled);
  }

  static Future<bool> isDevModeEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(kDevModeEnabledKey) ?? false;
      if (devModeEnabled.value != enabled) {
        devModeEnabled.value = enabled;
      }
      return enabled;
    } catch (_) {
      if (devModeEnabled.value) {
        devModeEnabled.value = false;
      }
      return false;
    }
  }

  static Future<bool> isDeveloperLoggedIn() => isDevModeEnabled();

  static Future<void> setDevAuthorized(bool value) => setDevModeEnabled(value);

  static Future<void> setDevModeEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kDevModeEnabledKey, value);
    if (prefs.containsKey(_prefsKeyDevAuth)) {
      await prefs.remove(_prefsKeyDevAuth);
    }
    if (prefs.containsKey(_prefsKeyDevAuthUntil)) {
      await prefs.remove(_prefsKeyDevAuthUntil);
    }
    if (devModeEnabled.value != value) {
      devModeEnabled.value = value;
    }
  }

  static Future<void> resetDevAuth() => setDevModeEnabled(false);

  static Future<void> resetDeveloperLogin() => setDevModeEnabled(false);
}
