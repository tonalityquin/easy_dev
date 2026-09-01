import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/utils/status_dialog.dart';
import '../../../features/selector/application/dev_auth.dart';
import 'plate_tts_session_protocol.dart';
import 'tts_ownership.dart';
import 'tts_user_filters.dart';

class PlateTtsSessionDiagnostics {
  const PlateTtsSessionDiagnostics._();

  static final List<String> _lines = <String>[];
  static bool _taskCallbackAttached = false;
  static Map<String, Object?> _lastForegroundStatus = <String, Object?>{};
  static String _lastArea = '';
  static String _lastMode = '';
  static String _lastSource = '';
  static bool? _lastForegroundServiceRunning;
  static bool? _lastForegroundOwner;
  static bool? _lastAppFallbackListening;
  static String _lastDivision = '';
  static String _lastHomeArea = '';
  static String _lastCurrentArea = '';
  static String _lastWorkContextSource = '';
  static bool? _lastHomeIsHeadquarter;
  static bool? _lastCurrentIsHeadquarter;
  static String _lastAreaSyncState = '';
  static String _lastAreaSyncSource = '';
  static String _lastAreaSyncArea = '';

  static List<String> get lines => List<String>.unmodifiable(_lines);

  static String get debugPrintCode {
    if (_lines.isEmpty) {
      return 'debugPrint(${jsonEncode('[PlateTtsSession] 기록된 로그가 없습니다.')});';
    }
    return _lines
        .map((line) => 'debugPrint(${jsonEncode(line)});')
        .join('\n');
  }

  static void ensureStarted() {
    if (_taskCallbackAttached) return;
    _taskCallbackAttached = true;
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    record('task_callback_attached');
  }

  static void record(
    String event, {
    Map<String, Object?> meta = const <String, Object?>{},
  }) {
    final fields = <String>[
      '[PlateTtsSession]',
      'timestamp=${DateTime.now().toIso8601String()}',
      'event=$event',
    ];
    for (final entry in meta.entries) {
      fields.add('${entry.key}=${entry.value}');
    }
    final line = fields.join(' ');
    debugPrint(line);
    _lines.add(line);
    if (_lines.length > 240) {
      _lines.removeRange(0, _lines.length - 240);
    }
  }

  static void noteActivationContext({
    required String area,
    required String mode,
    required String source,
  }) {
    _lastArea = area.trim();
    _lastMode = mode.trim();
    _lastSource = source.trim();
  }

  static void noteActivationResult({
    required bool foregroundServiceRunning,
    required bool foregroundOwner,
    required bool appFallbackListening,
  }) {
    _lastForegroundServiceRunning = foregroundServiceRunning;
    _lastForegroundOwner = foregroundOwner;
    _lastAppFallbackListening = appFallbackListening;
  }

  static void noteWorkContext({
    required String division,
    required String homeArea,
    required String currentArea,
    required bool? homeIsHeadquarter,
    required bool? currentIsHeadquarter,
    required String source,
  }) {
    final normalizedDivision = division.trim();
    final normalizedHomeArea = homeArea.trim();
    final normalizedCurrentArea = currentArea.trim();
    final normalizedSource = source.trim();
    if (normalizedDivision.isNotEmpty) {
      _lastDivision = normalizedDivision;
    }
    if (normalizedHomeArea.isNotEmpty) {
      _lastHomeArea = normalizedHomeArea;
    }
    if (homeIsHeadquarter != null) {
      _lastHomeIsHeadquarter = homeIsHeadquarter;
    }
    _lastCurrentArea = normalizedCurrentArea;
    _lastCurrentIsHeadquarter = currentIsHeadquarter;
    if (normalizedSource.isNotEmpty) {
      _lastWorkContextSource = normalizedSource;
    }
  }


  static void noteAreaSync({
    required String state,
    required String source,
    required String area,
  }) {
    _lastAreaSyncState = state.trim();
    _lastAreaSyncSource = source.trim();
    _lastAreaSyncArea = area.trim();
  }

  static void _onTaskData(dynamic data) {
    if (data is! Map) return;
    final kind = data['kind'];
    if (kind == PlateTtsSessionProtocol.statusKind) {
      final normalized = <String, Object?>{};
      for (final entry in data.entries) {
        normalized[entry.key.toString()] = entry.value;
      }
      _lastForegroundStatus = normalized;
      record(
        'foreground_status',
        meta: <String, Object?>{
          'event': normalized['event'] ?? '',
          'area': normalized['area'] ?? '',
          'mode': normalized['mode'] ?? '',
          'listening': normalized['listening'] ?? false,
          'masterOn': normalized['masterOn'] ?? false,
          'reason': normalized['reason'] ?? '',
        },
      );
      return;
    }
    if (kind == 'plate_tts_event_v1') {
      final plate = (data['plateNumber'] ?? '').toString().trim();
      final tail = plate.length <= 4 ? plate : plate.substring(plate.length - 4);
      record(
        'foreground_plate_event',
        meta: <String, Object?>{
          'area': data['area'] ?? '',
          'type': data['type'] ?? '',
          'docId': data['docId'] ?? '',
          'plateTail': tail,
          'location': data['location'] ?? '',
        },
      );
    }
  }

  static Future<String> statusDescription({
    String? area,
    TtsUserFilters? filters,
  }) async {
    ensureStarted();
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final storedMode = (prefs.getString('mode') ?? '').trim();
    final owner = await TtsOwnership.getOwner();
    final running = await FlutterForegroundTask.isRunningService;
    final resolvedFilters = filters ?? await TtsUserFilters.load();
    final status = _lastForegroundStatus;
    return <String>[
      'Division: ${_lastDivision.isEmpty ? '-' : _lastDivision}',
      'Home area: ${_lastHomeArea.isEmpty ? '-' : _lastHomeArea}',
      'Home area type: ${_headquarterLabel(_lastHomeIsHeadquarter)}',
      'Current work area: ${_lastCurrentArea.isEmpty ? ((area ?? _lastArea).trim().isEmpty ? '-' : (area ?? _lastArea).trim()) : _lastCurrentArea}',
      'Current area type: ${_headquarterLabel(_lastCurrentIsHeadquarter)}',
      'Work context source: ${_lastWorkContextSource.isEmpty ? '-' : _lastWorkContextSource}',
      'Area sync state: ${_lastAreaSyncState.isEmpty ? '-' : _lastAreaSyncState}',
      'Area sync source: ${_lastAreaSyncSource.isEmpty ? '-' : _lastAreaSyncSource}',
      'Area sync area: ${_lastAreaSyncArea.isEmpty ? '-' : _lastAreaSyncArea}',
      'Foreground service: ${running ? 'ACTIVE' : 'OFF'}',
      'TTS owner: ${owner.name}',
      'Stored mode: ${storedMode.isEmpty ? '-' : storedMode}',
      'Activation mode: ${_lastMode.isEmpty ? '-' : _lastMode}',
      'TTS area: ${(area ?? _lastArea).trim().isEmpty ? '-' : (area ?? _lastArea).trim()}',
      'Activation source: ${_lastSource.isEmpty ? '-' : _lastSource}',
      'Last FG service result: ${_lastForegroundServiceRunning ?? '-'}',
      'Last foreground owner: ${_lastForegroundOwner ?? '-'}',
      'App fallback listening: ${_lastAppFallbackListening ?? '-'}',
      'Parking filter: ${resolvedFilters.parking}',
      'Departure filter: ${resolvedFilters.departure}',
      'Completed filter: ${resolvedFilters.completed}',
      'FG event: ${status['event'] ?? '-'}',
      'FG area: ${status['area'] ?? '-'}',
      'FG mode: ${status['mode'] ?? '-'}',
      'FG listening: ${status['listening'] ?? false}',
      'FG masterOn: ${status['masterOn'] ?? false}',
      'FG reason: ${status['reason'] ?? '-'}',
      'Debug lines: ${_lines.length}',
    ].join('\n');
  }

  static String _headquarterLabel(bool? value) {
    if (value == null) return '-';
    return value ? 'HEADQUARTER' : 'BRANCH';
  }

  static Future<void> showStatus(
    BuildContext context, {
    String? area,
    TtsUserFilters? filters,
  }) async {
    final enabled = await DevAuth.isDevModeEnabled();
    if (!enabled || !context.mounted) return;
    final description = await statusDescription(area: area, filters: filters);
    if (!context.mounted) return;
    record('developer_status_open');
    await StatusDialog.showSuccess(
      context,
      title: 'Plate TTS Status',
      description: description,
      copyText: debugPrintCode,
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: Duration.zero,
      useCommonUi: true,
      awaitManualClose: true,
    );
  }
}
