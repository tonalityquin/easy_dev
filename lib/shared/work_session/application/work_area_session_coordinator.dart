import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../tts/application/plate_tts_session_activator.dart';
import '../../tts/application/plate_tts_session_diagnostics.dart';
import '../../tts/application/tts_user_filters.dart';

class WorkAreaSessionActivationResult {
  const WorkAreaSessionActivationResult({
    required this.division,
    required this.homeArea,
    required this.currentArea,
    required this.mode,
    required this.currentIsHeadquarter,
    required this.homeIsHeadquarter,
    required this.source,
    required this.tts,
  });

  final String division;
  final String homeArea;
  final String currentArea;
  final String mode;
  final bool? currentIsHeadquarter;
  final bool? homeIsHeadquarter;
  final String source;
  final PlateTtsSessionActivationResult tts;

  bool get foregroundServiceRunning => tts.foregroundServiceRunning;
  bool get foregroundOwner => tts.foregroundOwner;
  bool get appFallbackListening => tts.appFallbackListening;
  bool get ready => tts.ready;
}

class WorkAreaSessionCoordinator {
  const WorkAreaSessionCoordinator._();

  static Future<void> _queue = Future<void>.value();
  static int _sequence = 0;

  static Future<WorkAreaSessionActivationResult> activate({
    required String currentArea,
    String division = '',
    String homeArea = '',
    String mode = '',
    bool? currentIsHeadquarter,
    bool? homeIsHeadquarter,
    TtsUserFilters? filters,
    String source = 'unknown',
    bool persistMode = true,
    bool useStoredModeFallback = true,
  }) {
    final completer = Completer<WorkAreaSessionActivationResult>();
    final requestId = ++_sequence;
    _queue = _queue.then((_) async {
      try {
        final result = await _activateNow(
          requestId: requestId,
          currentArea: currentArea,
          division: division,
          homeArea: homeArea,
          mode: mode,
          currentIsHeadquarter: currentIsHeadquarter,
          homeIsHeadquarter: homeIsHeadquarter,
          filters: filters,
          source: source,
          persistMode: persistMode,
          useStoredModeFallback: useStoredModeFallback,
        );
        if (!completer.isCompleted) completer.complete(result);
      } catch (error, stackTrace) {
        PlateTtsSessionDiagnostics.record(
          'work_area_activation_failed',
          meta: <String, Object?>{
            'requestId': requestId,
            'source': source,
            'division': division.trim(),
            'homeArea': homeArea.trim(),
            'currentArea': currentArea.trim(),
            'mode': mode.trim(),
            'currentIsHeadquarter': currentIsHeadquarter,
            'persistMode': persistMode,
            'useStoredModeFallback': useStoredModeFallback,
            'error': error,
            'stack': stackTrace,
          },
        );
        debugPrint(
          '[WorkAreaSession] activation_failed requestId=$requestId source=$source area=${currentArea.trim()} mode=${mode.trim()} error=$error\n$stackTrace',
        );
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }
    });
    return completer.future;
  }

  static Future<WorkAreaSessionActivationResult> _activateNow({
    required int requestId,
    required String currentArea,
    required String division,
    required String homeArea,
    required String mode,
    required bool? currentIsHeadquarter,
    required bool? homeIsHeadquarter,
    required TtsUserFilters? filters,
    required String source,
    required bool persistMode,
    required bool useStoredModeFallback,
  }) async {
    final normalizedDivision = division.trim();
    final normalizedCurrentArea = currentArea.trim();
    final normalizedHomeArea = homeArea.trim();
    final normalizedSource = source.trim().isEmpty ? 'unknown' : source.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final storedMode = (prefs.getString('mode') ?? '').trim();
    final requestedMode = mode.trim();
    final headquarterModeIsolation = currentIsHeadquarter == true;
    final effectivePersistMode = headquarterModeIsolation ? false : persistMode;
    final effectiveUseStoredModeFallback =
        headquarterModeIsolation ? false : useStoredModeFallback;
    var removedStoredMode = false;

    if (headquarterModeIsolation && storedMode.isNotEmpty) {
      await prefs.remove('mode');
      removedStoredMode = true;
      PlateTtsSessionDiagnostics.record(
        'work_area_headquarter_mode_storage_cleared',
        meta: <String, Object?>{
          'requestId': requestId,
          'source': normalizedSource,
          'division': normalizedDivision,
          'currentArea': normalizedCurrentArea,
          'previousStoredMode': storedMode,
          'requestedMode': requestedMode,
          'currentIsHeadquarter': currentIsHeadquarter,
          'persistModeRequested': persistMode,
          'persistModeEffective': effectivePersistMode,
          'storedModeFallbackRequested': useStoredModeFallback,
          'storedModeFallbackEffective': effectiveUseStoredModeFallback,
        },
      );
      debugPrint(
        '[WorkAreaSession] headquarter_mode_storage_cleared requestId=$requestId source=$normalizedSource area=$normalizedCurrentArea previousMode=$storedMode requestedMode=$requestedMode persistModeEffective=$effectivePersistMode storedModeFallbackEffective=$effectiveUseStoredModeFallback',
      );
    }

    final resolvedMode = headquarterModeIsolation
        ? ''
        : _normalizeMode(
            requestedMode.isNotEmpty
                ? requestedMode
                : effectiveUseStoredModeFallback
                    ? storedMode
                    : '',
          );

    if (effectivePersistMode &&
        resolvedMode.isNotEmpty &&
        storedMode != resolvedMode) {
      await prefs.setString('mode', resolvedMode);
    }

    PlateTtsSessionDiagnostics.noteWorkContext(
      division: normalizedDivision,
      homeArea: normalizedHomeArea,
      currentArea: normalizedCurrentArea,
      homeIsHeadquarter: homeIsHeadquarter,
      currentIsHeadquarter: currentIsHeadquarter,
      source: normalizedSource,
    );
    PlateTtsSessionDiagnostics.record(
      'work_area_activation_start',
      meta: <String, Object?>{
        'requestId': requestId,
        'source': normalizedSource,
        'division': normalizedDivision,
        'homeArea': normalizedHomeArea,
        'currentArea': normalizedCurrentArea,
        'homeIsHeadquarter': homeIsHeadquarter,
        'currentIsHeadquarter': currentIsHeadquarter,
        'mode': resolvedMode,
        'requestedMode': requestedMode,
        'headquarterModeIsolation': headquarterModeIsolation,
        'storedModeBefore': storedMode,
        'storedModeRemoved': removedStoredMode,
        'persistModeRequested': persistMode,
        'persistModeEffective': effectivePersistMode,
        'storedModeFallbackRequested': useStoredModeFallback,
        'storedModeFallbackEffective': effectiveUseStoredModeFallback,
      },
    );

    final tts = await PlateTtsSessionActivator.activate(
      area: normalizedCurrentArea,
      mode: resolvedMode,
      filters: filters,
      source: 'work_area:$normalizedSource',
    );

    PlateTtsSessionDiagnostics.record(
      'work_area_activation_complete',
      meta: <String, Object?>{
        'requestId': requestId,
        'source': normalizedSource,
        'division': normalizedDivision,
        'homeArea': normalizedHomeArea,
        'currentArea': normalizedCurrentArea,
        'homeIsHeadquarter': homeIsHeadquarter,
        'currentIsHeadquarter': currentIsHeadquarter,
        'mode': tts.mode,
        'requestedMode': requestedMode,
        'headquarterModeIsolation': headquarterModeIsolation,
        'storedModeBefore': storedMode,
        'storedModeRemoved': removedStoredMode,
        'persistModeRequested': persistMode,
        'persistModeEffective': effectivePersistMode,
        'storedModeFallbackRequested': useStoredModeFallback,
        'storedModeFallbackEffective': effectiveUseStoredModeFallback,
        'foregroundServiceRunning': tts.foregroundServiceRunning,
        'foregroundOwner': tts.foregroundOwner,
        'appFallbackListening': tts.appFallbackListening,
        'ready': tts.ready,
      },
    );
    debugPrint(
      '[WorkAreaSession] activation_complete requestId=$requestId source=$normalizedSource division=$normalizedDivision homeArea=$normalizedHomeArea currentArea=$normalizedCurrentArea homeIsHeadquarter=$homeIsHeadquarter currentIsHeadquarter=$currentIsHeadquarter mode=${tts.mode} requestedMode=$requestedMode headquarterModeIsolation=$headquarterModeIsolation storedModeRemoved=$removedStoredMode persistModeRequested=$persistMode persistModeEffective=$effectivePersistMode storedModeFallbackRequested=$useStoredModeFallback storedModeFallbackEffective=$effectiveUseStoredModeFallback foreground=${tts.foregroundServiceRunning} foregroundOwner=${tts.foregroundOwner} appFallback=${tts.appFallbackListening}',
    );

    return WorkAreaSessionActivationResult(
      division: normalizedDivision,
      homeArea: normalizedHomeArea,
      currentArea: normalizedCurrentArea,
      mode: tts.mode,
      currentIsHeadquarter: currentIsHeadquarter,
      homeIsHeadquarter: homeIsHeadquarter,
      source: normalizedSource,
      tts: tts,
    );
  }

  static String _normalizeMode(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'double') return 'lite';
    return normalized;
  }
}
