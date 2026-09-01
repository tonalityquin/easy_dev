import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/init/work_schedule_prefs.dart';
import 'launcher_diagnostics.dart';

class LauncherDebugAccountOverrideStore {
  const LauncherDebugAccountOverrideStore._();

  static const String _activeKey =
      'launcher_debug_account_override_active_v1';
  static const String _snapshotKey =
      'launcher_debug_account_override_snapshot_v1';
  static const String _startedAtKey =
      'launcher_debug_account_override_started_at_v1';

  static const Set<String> _trackedKeys = <String>{
    'terminalAccountKind',
    'mode',
    'phone',
    'selectedArea',
    'englishSelectedAreaName',
    'division',
    'role',
    'position',
    'cachedUserJson',
    'handle',
    'tabletPhone',
    'personalAccountId',
    'personalName',
    'personalPhone',
    'personalEmail',
    'fixedHolidays',
    'startTime',
    'endTime',
    WorkSchedulePrefs.startMapKey,
    WorkSchedulePrefs.endMapKey,
    WorkSchedulePrefs.breakDaysKey,
  };

  static Future<bool> isActive() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_activeKey) ?? false;
  }

  static Future<bool> begin() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_activeKey) ?? false) {
      LauncherDiagnostics.record(
        'debug_account_override_snapshot_reused',
        meta: <String, Object?>{
          'startedAt': prefs.getString(_startedAtKey) ?? '',
          'trackedKeys': _trackedKeys.length,
        },
      );
      return false;
    }

    final snapshot = <String, Object?>{};
    for (final key in _trackedKeys) {
      final present = prefs.containsKey(key);
      snapshot[key] = <String, Object?>{
        'present': present,
        'value': present ? prefs.get(key) : null,
      };
    }

    final startedAt = DateTime.now().toIso8601String();
    await prefs.setString(_snapshotKey, jsonEncode(snapshot));
    await prefs.setString(_startedAtKey, startedAt);
    await prefs.setBool(_activeKey, true);

    LauncherDiagnostics.record(
      'debug_account_override_snapshot_started',
      meta: <String, Object?>{
        'startedAt': startedAt,
        'trackedKeys': _trackedKeys.length,
      },
    );
    debugPrint(
      '[LAUNCHER-DEBUG-OVERRIDE] snapshot_started startedAt=$startedAt trackedKeys=${_trackedKeys.length}',
    );
    return true;
  }

  static Future<void> clearAccountKindBinding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('terminalAccountKind');
    LauncherDiagnostics.record(
      'debug_account_override_account_binding_cleared',
      meta: const <String, Object?>{
        'key': 'terminalAccountKind',
      },
    );
    debugPrint(
      '[LAUNCHER-DEBUG-OVERRIDE] account_binding_cleared key=terminalAccountKind',
    );
  }

  static Future<bool> restoreIfNeeded({String source = 'unknown'}) async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_activeKey) ?? false)) return false;

    final raw = (prefs.getString(_snapshotKey) ?? '').trim();
    if (raw.isEmpty) {
      await _clearTrackedState(prefs);
      await _clearMetadata(prefs);
      await prefs.reload();
      LauncherDiagnostics.record(
        'debug_account_override_restore_failed',
        meta: <String, Object?>{
          'source': source,
          'reason': 'snapshot_missing',
          'fallback': 'startup_purpose',
        },
      );
      debugPrint(
        '[LAUNCHER-DEBUG-OVERRIDE] restore_failed source=$source reason=snapshot_missing fallback=startup_purpose',
      );
      return false;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException('snapshot_not_map');
      }

      for (final key in _trackedKeys) {
        await prefs.remove(key);
      }

      for (final key in _trackedKeys) {
        final entry = decoded[key];
        if (entry is! Map) continue;
        if (entry['present'] != true) continue;
        await _restoreValue(prefs, key, entry['value']);
      }

      final startedAt = prefs.getString(_startedAtKey) ?? '';
      await _clearMetadata(prefs);
      await prefs.reload();
      LauncherDiagnostics.record(
        'debug_account_override_snapshot_restored',
        meta: <String, Object?>{
          'source': source,
          'startedAt': startedAt,
          'trackedKeys': _trackedKeys.length,
        },
      );
      debugPrint(
        '[LAUNCHER-DEBUG-OVERRIDE] snapshot_restored source=$source startedAt=$startedAt trackedKeys=${_trackedKeys.length}',
      );
      return true;
    } catch (error, stackTrace) {
      await _clearTrackedState(prefs);
      await _clearMetadata(prefs);
      await prefs.reload();
      LauncherDiagnostics.record(
        'debug_account_override_restore_failed',
        meta: <String, Object?>{
          'source': source,
          'error': error,
          'stack': stackTrace,
          'fallback': 'startup_purpose',
        },
      );
      debugPrint(
        '[LAUNCHER-DEBUG-OVERRIDE] restore_failed source=$source error=$error fallback=startup_purpose\n$stackTrace',
      );
      return false;
    }
  }

  static Future<void> discardForLogout({String source = 'logout'}) async {
    final prefs = await SharedPreferences.getInstance();
    final active = prefs.getBool(_activeKey) ?? false;
    final startedAt = prefs.getString(_startedAtKey) ?? '';
    await _clearMetadata(prefs);
    LauncherDiagnostics.record(
      'debug_account_override_snapshot_discarded',
      meta: <String, Object?>{
        'source': source,
        'wasActive': active,
        'startedAt': startedAt,
      },
    );
    debugPrint(
      '[LAUNCHER-DEBUG-OVERRIDE] snapshot_discarded source=$source wasActive=$active startedAt=$startedAt',
    );
  }

  static Future<void> _clearTrackedState(SharedPreferences prefs) async {
    for (final key in _trackedKeys) {
      await prefs.remove(key);
    }
  }

  static Future<void> _clearMetadata(SharedPreferences prefs) async {
    await prefs.remove(_activeKey);
    await prefs.remove(_snapshotKey);
    await prefs.remove(_startedAtKey);
  }

  static Future<void> _restoreValue(
    SharedPreferences prefs,
    String key,
    Object? value,
  ) async {
    if (value is String) {
      await prefs.setString(key, value);
      return;
    }
    if (value is bool) {
      await prefs.setBool(key, value);
      return;
    }
    if (value is int) {
      await prefs.setInt(key, value);
      return;
    }
    if (value is double) {
      await prefs.setDouble(key, value);
      return;
    }
    if (value is List) {
      await prefs.setStringList(
        key,
        value.map((item) => item.toString()).toList(growable: false),
      );
    }
  }
}
