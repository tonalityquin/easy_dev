import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kDevModeEnabledKey = 'dev_mode_enabled_v1';
const _DEV_SALT_B64 = 'nWPSmnV2ktkgirphVlVCqw==';
const _DEV_HASH_HEX =
    '78f0a759b1da2b6570935e8a2b22e7ccde1d30ba91d688672726fcb40cd67677';
const prefsKeyMode = 'mode';
const _prefsKeyDevAuth = 'dev_auth';
const _prefsKeyDevAuthUntil = 'dev_auth_until';
const Duration devTtl = Duration(days: 7);

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

  static bool verifyDevCode(String input) {
    final salt = base64Decode(_DEV_SALT_B64);
    final bytes = <int>[...salt, ...utf8.encode(input)];
    final digestHex = sha256.convert(bytes).toString();

    if (digestHex.length != _DEV_HASH_HEX.length) return false;
    var diff = 0;
    for (var i = 0; i < digestHex.length; i++) {
      diff |= digestHex.codeUnitAt(i) ^ _DEV_HASH_HEX.codeUnitAt(i);
    }
    return diff == 0;
  }

  static Future<DevPrefs> restorePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString(prefsKeyMode);
    bool dev = prefs.getBool(_prefsKeyDevAuth) ?? false;
    final untilMs = prefs.getInt(_prefsKeyDevAuthUntil);

    if (dev) {
      final alive = untilMs != null &&
          DateTime.now().millisecondsSinceEpoch < untilMs;
      if (!alive) {
        await prefs.remove(_prefsKeyDevAuth);
        await prefs.remove(_prefsKeyDevAuthUntil);
        dev = false;
      }
    }

    return DevPrefs(savedMode: savedMode, devAuthorized: dev);
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

  static Future<bool> isDeveloperLoggedIn() async {
    try {
      final restored = await restorePrefs();
      final devModeEnabled = await isDevModeEnabled();
      return restored.devAuthorized || devModeEnabled;
    } catch (_) {
      return await isDevModeEnabled();
    }
  }

  static Future<void> setDevAuthorized(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value) {
      await prefs.setBool(_prefsKeyDevAuth, true);
      await prefs.setInt(
        _prefsKeyDevAuthUntil,
        DateTime.now().add(devTtl).millisecondsSinceEpoch,
      );
    } else {
      await prefs.remove(_prefsKeyDevAuth);
      await prefs.remove(_prefsKeyDevAuthUntil);
    }
  }

  static Future<void> setDevModeEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kDevModeEnabledKey, value);
    if (devModeEnabled.value != value) {
      devModeEnabled.value = value;
    }
  }

  static Future<void> resetDevAuth() => setDevAuthorized(false);

  static Future<void> resetDeveloperLogin() async {
    await resetDevAuth();
    await setDevModeEnabled(false);
  }
}
