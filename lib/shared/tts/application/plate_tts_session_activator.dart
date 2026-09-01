import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/init/startup_tasks.dart';
import '../services/plate/plate_tts_listener_service.dart';
import 'plate_tts_session_diagnostics.dart';
import 'plate_tts_session_protocol.dart';
import 'tts_ownership.dart';
import 'tts_user_filters.dart';

class PlateTtsSessionActivationResult {
  const PlateTtsSessionActivationResult({
    required this.foregroundServiceRunning,
    required this.foregroundOwner,
    required this.appFallbackListening,
    required this.area,
    required this.mode,
  });

  final bool foregroundServiceRunning;
  final bool foregroundOwner;
  final bool appFallbackListening;
  final String area;
  final String mode;

  bool get ready => foregroundOwner || appFallbackListening || area.isEmpty;
}

class PlateTtsSessionActivator {
  const PlateTtsSessionActivator._();

  static Future<PlateTtsSessionActivationResult> activate({
    required String area,
    required String mode,
    TtsUserFilters? filters,
    String source = 'unknown',
  }) async {
    PlateTtsSessionDiagnostics.ensureStarted();

    final normalizedArea = area.trim();
    final normalizedMode = mode.trim();
    final resolvedFilters = filters ?? await TtsUserFilters.load();
    final prefs = await SharedPreferences.getInstance();

    if (normalizedMode.isNotEmpty) {
      await prefs.setString('mode', normalizedMode);
    }

    PlateTtsSessionDiagnostics.noteActivationContext(
      area: normalizedArea,
      mode: normalizedMode,
      source: source,
    );
    PlateTtsSessionDiagnostics.record(
      'activation_start',
      meta: <String, Object?>{
        'source': source,
        'area': normalizedArea,
        'mode': normalizedMode,
        'filters': resolvedFilters.toMap(),
      },
    );

    if (normalizedMode.isEmpty) {
      final foregroundRunning = await FlutterForegroundTask.isRunningService;
      final foregroundOwner =
          (await TtsOwnership.getOwner()) == TtsOwner.foreground;
      await PlateTtsListenerService.stop();
      if (foregroundRunning) {
        FlutterForegroundTask.sendDataToTask(<String, dynamic>{
          'kind': PlateTtsSessionProtocol.commandKind,
          'area': normalizedArea,
          'mode': '',
          'clearMode': true,
          'forceRestart': true,
          'source': source,
        });
      }
      PlateTtsSessionDiagnostics.record(
        'activation_deferred',
        meta: <String, Object?>{
          'source': source,
          'area': normalizedArea,
          'reason': 'mode_not_selected',
          'clearMode': true,
          'foregroundCommandSent': foregroundRunning,
        },
      );
      PlateTtsSessionDiagnostics.noteActivationResult(
        foregroundServiceRunning: foregroundRunning,
        foregroundOwner: foregroundOwner,
        appFallbackListening: false,
      );
      return PlateTtsSessionActivationResult(
        foregroundServiceRunning: foregroundRunning,
        foregroundOwner: foregroundOwner,
        appFallbackListening: false,
        area: normalizedArea,
        mode: normalizedMode,
      );
    }

    final foregroundRunning =
        await StartupTasks.ensureForegroundServiceRunning();

    if (foregroundRunning) {
      await TtsOwnership.setOwner(TtsOwner.foreground);
      PlateTtsListenerService.setLocalRole(TtsOwner.app);
      await PlateTtsListenerService.stop();
      FlutterForegroundTask.sendDataToTask(<String, dynamic>{
        'kind': PlateTtsSessionProtocol.commandKind,
        'area': normalizedArea,
        'mode': normalizedMode,
        'ttsFilters': resolvedFilters.toMap(),
        'forceRestart': true,
        'source': source,
      });
      PlateTtsSessionDiagnostics.record(
        'foreground_command_sent',
        meta: <String, Object?>{
          'source': source,
          'area': normalizedArea,
          'mode': normalizedMode,
        },
      );
      PlateTtsSessionDiagnostics.noteActivationResult(
        foregroundServiceRunning: true,
        foregroundOwner: true,
        appFallbackListening: false,
      );
      return PlateTtsSessionActivationResult(
        foregroundServiceRunning: true,
        foregroundOwner: true,
        appFallbackListening: false,
        area: normalizedArea,
        mode: normalizedMode,
      );
    }

    await TtsOwnership.setOwner(TtsOwner.app);
    PlateTtsListenerService.setLocalRole(TtsOwner.app);
    final bool appListening;
    if (normalizedArea.isEmpty) {
      await PlateTtsListenerService.stop();
      appListening = false;
    } else {
      appListening = await PlateTtsListenerService.start(
        normalizedArea,
        force: true,
        mode: normalizedMode,
        filters: resolvedFilters,
      );
    }
    PlateTtsSessionDiagnostics.record(
      'app_fallback',
      meta: <String, Object?>{
        'source': source,
        'area': normalizedArea,
        'mode': normalizedMode,
        'listening': appListening,
      },
    );
    PlateTtsSessionDiagnostics.noteActivationResult(
      foregroundServiceRunning: false,
      foregroundOwner: false,
      appFallbackListening: appListening,
    );
    return PlateTtsSessionActivationResult(
      foregroundServiceRunning: false,
      foregroundOwner: false,
      appFallbackListening: appListening,
      area: normalizedArea,
      mode: normalizedMode,
    );
  }

  static Future<PlateTtsSessionActivationResult> sync({
    required String area,
    required TtsUserFilters filters,
    String source = 'settings',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final mode = (prefs.getString('mode') ?? '').trim();
    return activate(
      area: area,
      mode: mode,
      filters: filters,
      source: source,
    );
  }
}
