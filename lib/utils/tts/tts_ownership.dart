// lib/utils/tts_ownership.dart
import 'package:shared_preferences/shared_preferences.dart';

enum TtsOwner { app, foreground }

class TtsOwnership {
  static const _key = 'tts_owner';

  static Future<void> setOwner(TtsOwner owner) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, owner.name);
  }

  static Future<TtsOwner> getOwner() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_key);
    if (v == TtsOwner.foreground.name) return TtsOwner.foreground;
    return TtsOwner.app;
  }

  static Future<bool> isAppOwner() async =>
      (await getOwner()) == TtsOwner.app;

  static Future<bool> isForegroundOwner() async =>
      (await getOwner()) == TtsOwner.foreground;
}
