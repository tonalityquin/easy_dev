import 'app_start_debug_trace.dart';

class OverlayLifecycleGate {
  const OverlayLifecycleGate._();

  static bool _runtimeReady = false;
  static String _reason = 'app_start';
  static int _generation = 0;

  static bool get canAutoStart => _runtimeReady;
  static bool get runtimeReady => _runtimeReady;
  static String get reason => _reason;
  static String get stateLabel => _runtimeReady ? 'READY' : 'LOCKED';
  static int get generation => _generation;

  static void lock({required String reason}) {
    final changed = _runtimeReady || _reason != reason;
    _runtimeReady = false;
    _reason = reason;
    if (!changed) return;
    _generation += 1;
    AppStartDebugTrace.log(
      'overlay_lifecycle',
      'gate_locked',
      meta: <String, Object?>{
        'state': stateLabel,
        'reason': _reason,
        'generation': _generation,
      },
    );
  }

  static void markRuntimeReady({
    required String reason,
    required String targetRoute,
  }) {
    final changed = !_runtimeReady || _reason != reason;
    _runtimeReady = true;
    _reason = reason;
    if (!changed) return;
    _generation += 1;
    AppStartDebugTrace.log(
      'overlay_lifecycle',
      'gate_ready',
      meta: <String, Object?>{
        'state': stateLabel,
        'reason': _reason,
        'targetRoute': targetRoute,
        'generation': _generation,
      },
    );
  }

  static void recordAutoStartSkipped({
    required String reason,
    required String lifecycle,
    required String stage,
  }) {
    AppStartDebugTrace.log(
      'overlay_lifecycle',
      'auto_start_skipped',
      meta: <String, Object?>{
        'reason': reason,
        'gateState': stateLabel,
        'gateReason': _reason,
        'runtimeReady': _runtimeReady,
        'lifecycle': lifecycle,
        'stage': stage,
        'generation': _generation,
      },
    );
  }

  static Map<String, Object?> debugMeta() {
    return <String, Object?>{
      'overlayLifecycleState': stateLabel,
      'overlayLifecycleReason': _reason,
      'overlayRuntimeReady': _runtimeReady,
      'overlayLifecycleGeneration': _generation,
    };
  }
}
