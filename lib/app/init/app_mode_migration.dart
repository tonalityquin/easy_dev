import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../terminal/application/parkinworkin_terminal_diagnostics.dart';

class AppModeMigration {
  const AppModeMigration._();

  static const String _legacySingleMode = 'simple';
  static const String _singleMode = 'single';
  static const String _cachedUserKey = 'cachedUserJson';

  static Future<void> migrateLegacyMode() async {
    final prefs = await SharedPreferences.getInstance();
    var changed = false;

    final rawMode = (prefs.getString('mode') ?? '').trim().toLowerCase();
    if (rawMode == _legacySingleMode) {
      await prefs.setString('mode', _singleMode);
      changed = true;
      _record('app_mode_pref_migrated', <String, Object?>{
        'from': _legacySingleMode,
        'to': _singleMode,
      });
    }

    final cachedUserJson = prefs.getString(_cachedUserKey);
    if (cachedUserJson != null && cachedUserJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(cachedUserJson);
        if (decoded is Map<String, dynamic>) {
          final rawModes = decoded['modes'];
          if (rawModes is List) {
            final migratedModes = <String>[];
            var modesChanged = false;
            for (final value in rawModes) {
              final mode = value.toString().trim().toLowerCase();
              if (mode == _legacySingleMode) {
                migratedModes.add(_singleMode);
                modesChanged = true;
              } else {
                migratedModes.add(value.toString());
              }
            }
            if (modesChanged) {
              decoded['modes'] = migratedModes.toSet().toList(growable: false);
              await prefs.setString(_cachedUserKey, jsonEncode(decoded));
              changed = true;
              _record('cached_user_modes_migrated', <String, Object?>{
                'to': _singleMode,
                'count': migratedModes.length,
              });
            }
          }
        }
      } catch (error) {
        _record('cached_user_modes_migration_failed', <String, Object?>{
          'error': error.toString(),
        });
      }
    }

    _record('app_mode_migration_complete', <String, Object?>{
      'changed': changed,
      'mode': (prefs.getString('mode') ?? '').trim().toLowerCase(),
    });
  }

  static void _record(String event, Map<String, Object?> meta) {
    ParkinWorkinTerminalDiagnostics.record(
      event,
      context: 'app_mode_migration',
      meta: meta,
    );
  }
}
