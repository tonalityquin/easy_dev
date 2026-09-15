import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tts_user_filters.dart';

class PlateTtsSessionRecoverySnapshot {
  const PlateTtsSessionRecoverySnapshot({
    required this.area,
    required this.mode,
    required this.filters,
    required this.clearMode,
    required this.source,
    required this.updatedAt,
  });

  final String area;
  final String mode;
  final TtsUserFilters filters;
  final bool clearMode;
  final String source;
  final DateTime updatedAt;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'area': area,
      'mode': mode,
      'ttsFilters': filters.toMap(),
      'clearMode': clearMode,
      'source': source,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toTaskPayload({
    required String source,
    bool forceRestart = true,
  }) {
    return <String, dynamic>{
      'area': area,
      'mode': mode,
      'ttsFilters': filters.toMap(),
      'clearMode': clearMode,
      'forceRestart': forceRestart,
      'source': source,
    };
  }

  static PlateTtsSessionRecoverySnapshot? fromMap(Map<String, dynamic> map) {
    try {
      final rawFilters = map['ttsFilters'];
      final filters = rawFilters is Map
          ? TtsUserFilters.fromMap(rawFilters)
          : TtsUserFilters.defaults();
      final rawUpdatedAt = map['updatedAt']?.toString().trim() ?? '';
      final updatedAt = DateTime.tryParse(rawUpdatedAt) ?? DateTime.now();
      return PlateTtsSessionRecoverySnapshot(
        area: map['area']?.toString().trim() ?? '',
        mode: map['mode']?.toString().trim() ?? '',
        filters: filters,
        clearMode: map['clearMode'] == true,
        source: map['source']?.toString().trim() ?? '',
        updatedAt: updatedAt,
      );
    } catch (_) {
      return null;
    }
  }
}

class PlateTtsSessionRecoveryStore {
  const PlateTtsSessionRecoveryStore._();

  static const String _key = 'plate_tts_session_recovery_v1';
  static const int maxDebugLines = 120;
  static final List<String> _debugLines = <String>[];

  static List<String> get debugLines => List<String>.unmodifiable(_debugLines);

  static String get debugPrintCode {
    if (_debugLines.isEmpty) {
      return 'debugPrint(${jsonEncode('[PLATE_TTS_RECOVERY] 기록된 로그가 없습니다.')});';
    }
    return _debugLines
        .map((line) => 'debugPrint(${jsonEncode(line)});')
        .join('\n');
  }

  static Future<void> save({
    required String area,
    required String mode,
    required TtsUserFilters filters,
    required bool clearMode,
    required String source,
  }) async {
    final snapshot = PlateTtsSessionRecoverySnapshot(
      area: area.trim(),
      mode: mode.trim(),
      filters: filters,
      clearMode: clearMode,
      source: source.trim(),
      updatedAt: DateTime.now(),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(snapshot.toMap()));
    _log(
      'saved area=${jsonEncode(snapshot.area)} mode=${jsonEncode(snapshot.mode)} clearMode=${snapshot.clearMode} filters=${jsonEncode(snapshot.filters.toMap())} source=${jsonEncode(snapshot.source)}',
    );
  }

  static Future<PlateTtsSessionRecoverySnapshot?> load() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(_key)?.trim() ?? '';
    if (raw.isEmpty) {
      _log('load_empty');
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        _log('load_invalid_type type=${decoded.runtimeType}');
        return null;
      }
      final normalized = <String, dynamic>{};
      for (final entry in decoded.entries) {
        normalized[entry.key.toString()] = entry.value;
      }
      final snapshot = PlateTtsSessionRecoverySnapshot.fromMap(normalized);
      if (snapshot == null) {
        _log('load_invalid_payload');
        return null;
      }
      _log(
        'loaded area=${jsonEncode(snapshot.area)} mode=${jsonEncode(snapshot.mode)} clearMode=${snapshot.clearMode} source=${jsonEncode(snapshot.source)} updatedAt=${snapshot.updatedAt.toIso8601String()}',
      );
      return snapshot;
    } catch (error, stackTrace) {
      _log('load_error error=$error');
      _log('load_stack stack=$stackTrace');
      return null;
    }
  }

  static Future<void> clear({
    String source = 'clear',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    _log('cleared source=${jsonEncode(source)}');
  }

  static Future<String> statusDescription() async {
    final snapshot = await load();
    if (snapshot == null) {
      return <String>[
        'Recovery snapshot: NONE',
        'Recovery logs: ${_debugLines.length}',
      ].join('\n');
    }
    return <String>[
      'Recovery snapshot: PRESENT',
      'Recovery area: ${snapshot.area.isEmpty ? '-' : snapshot.area}',
      'Recovery mode: ${snapshot.mode.isEmpty ? '-' : snapshot.mode}',
      'Recovery clearMode: ${snapshot.clearMode}',
      'Recovery parking: ${snapshot.filters.parking}',
      'Recovery departure: ${snapshot.filters.departure}',
      'Recovery completed: ${snapshot.filters.completed}',
      'Recovery source: ${snapshot.source.isEmpty ? '-' : snapshot.source}',
      'Recovery updatedAt: ${snapshot.updatedAt.toIso8601String()}',
      'Recovery logs: ${_debugLines.length}',
    ].join('\n');
  }

  static void _log(String message) {
    final line =
        '[PLATE_TTS_RECOVERY][${DateTime.now().toIso8601String()}] $message';
    debugPrint(line);
    _debugLines.add(line);
    if (_debugLines.length > maxDebugLines) {
      _debugLines.removeRange(0, _debugLines.length - maxDebugLines);
    }
  }
}
