import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

import '../../../../features/selector/application/dev_auth.dart';

class TypeAutoTransitionGuard extends ChangeNotifier {
  TypeAutoTransitionGuard() {
    unawaited(refreshDeveloperMode());
  }

  final Set<int> _activePointers = <int>{};
  final Map<String, int> _blockCounts = <String, int>{};
  final List<String> _debugLines = <String>[];

  Duration _countdownDuration = const Duration(seconds: 5);
  DateTime? _deadline;
  bool _countdownEnabled = false;
  String _disabledReason = '대기';
  bool _developerModeEnabled = false;
  int _lastPointerMoveLogAtMs = 0;
  int _lastActivityAtMs = 0;
  int _lastActivityLogAtMs = 0;
  bool _disposed = false;

  Duration get countdownDuration => _countdownDuration;
  bool get countdownEnabled => _countdownEnabled;
  bool get developerModeEnabled => _developerModeEnabled;
  bool get hasActivePointer => _activePointers.isNotEmpty;
  bool get hasExplicitBlock => _blockCounts.isNotEmpty;
  bool get isBlocked => hasActivePointer || hasExplicitBlock;
  String get disabledReason => _disabledReason;
  DateTime? get deadline => _deadline;
  List<String> get debugLines => List<String>.unmodifiable(_debugLines);

  String? get blockReason {
    if (hasActivePointer) return '화면 입력';
    if (_blockCounts.isEmpty) return null;
    return _blockCounts.keys.last;
  }

  bool get countdownRunning =>
      _countdownEnabled && !isBlocked && _deadline != null;

  Duration get remaining {
    final deadline = _deadline;
    if (!countdownRunning || deadline == null) return Duration.zero;
    final value = deadline.difference(DateTime.now());
    return value.isNegative ? Duration.zero : value;
  }

  double get progress {
    final totalMs = _countdownDuration.inMilliseconds;
    if (totalMs <= 0) return 0;
    return (remaining.inMilliseconds / totalMs).clamp(0.0, 1.0).toDouble();
  }

  bool get countdownElapsed =>
      countdownRunning && remaining <= Duration.zero;

  String get debugPrintCode {
    return _debugLines
        .map((line) => 'debugPrint(${jsonEncode(line)});')
        .join('\n');
  }

  Future<void> refreshDeveloperMode() async {
    final enabled = await DevAuth.isDevModeEnabled();
    if (_disposed) return;
    if (_developerModeEnabled == enabled) return;
    _developerModeEnabled = enabled;
    log('developer_mode_changed', <String, Object?>{'enabled': enabled});
    notifyListeners();
  }

  void setCountdownDuration(Duration duration) {
    if (_countdownDuration == duration) return;
    _countdownDuration = duration;
    log('countdown_duration_changed', <String, Object?>{
      'durationMs': duration.inMilliseconds,
    });
    if (_countdownEnabled && !isBlocked) {
      _restartCountdown('duration_changed');
    } else {
      notifyListeners();
    }
  }

  void setCountdownEnabled(
    bool enabled, {
    required String reason,
  }) {
    if (_countdownEnabled == enabled && _disabledReason == reason) return;
    _countdownEnabled = enabled;
    _disabledReason = reason;
    if (!enabled) {
      _deadline = null;
      log('countdown_disabled', <String, Object?>{'reason': reason});
      notifyListeners();
      return;
    }
    log('countdown_enabled', <String, Object?>{
      'durationMs': _countdownDuration.inMilliseconds,
      'reason': reason,
    });
    if (isBlocked) {
      _deadline = null;
      notifyListeners();
      return;
    }
    _restartCountdown('enabled');
  }

  void markActivity(String source) {
    if (!_countdownEnabled) return;
    if (isBlocked) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastActivityAtMs < 80) return;
    _lastActivityAtMs = now;
    _deadline = DateTime.now().add(_countdownDuration);
    if (now - _lastActivityLogAtMs >= 1000) {
      _lastActivityLogAtMs = now;
      log('activity', <String, Object?>{
        'source': source,
        'durationMs': _countdownDuration.inMilliseconds,
      });
    }
    notifyListeners();
  }

  void pointerDown(PointerDownEvent event) {
    final added = _activePointers.add(event.pointer);
    if (!added) return;
    _deadline = null;
    log('pointer_down', <String, Object?>{
      'pointer': event.pointer,
      'activePointers': _activePointers.length,
    });
    notifyListeners();
  }

  void pointerMove(PointerMoveEvent event) {
    if (!_activePointers.contains(event.pointer)) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastPointerMoveLogAtMs < 1000) return;
    _lastPointerMoveLogAtMs = now;
    log('pointer_move', <String, Object?>{
      'pointer': event.pointer,
      'activePointers': _activePointers.length,
    });
  }

  void pointerUp(PointerUpEvent event) {
    _releasePointer(event.pointer, 'pointer_up');
  }

  void pointerCancel(PointerCancelEvent event) {
    _releasePointer(event.pointer, 'pointer_cancel');
  }

  void pointerSignal(PointerSignalEvent event) {
    markActivity('pointer_signal');
  }

  void beginScroll() {
    beginBlock('스크롤');
  }

  void endScroll() {
    endBlock('스크롤');
  }

  void beginBlock(String reason) {
    final normalized = reason.trim().isEmpty ? '작업 중' : reason.trim();
    _blockCounts[normalized] = (_blockCounts[normalized] ?? 0) + 1;
    _deadline = null;
    log('block_started', <String, Object?>{
      'reason': normalized,
      'depth': _blockCounts[normalized],
      'blocked': isBlocked,
    });
    notifyListeners();
  }

  void endBlock(String reason) {
    final normalized = reason.trim().isEmpty ? '작업 중' : reason.trim();
    final count = _blockCounts[normalized] ?? 0;
    if (count <= 1) {
      _blockCounts.remove(normalized);
    } else {
      _blockCounts[normalized] = count - 1;
    }
    log('block_ended', <String, Object?>{
      'reason': normalized,
      'remainingDepth': _blockCounts[normalized] ?? 0,
      'blocked': isBlocked,
    });
    if (_countdownEnabled && !isBlocked) {
      _restartCountdown('block_ended:$normalized');
    } else {
      notifyListeners();
    }
  }

  Future<T> runBlocked<T>(
    String reason,
    Future<T> Function() action,
  ) async {
    beginBlock(reason);
    try {
      return await action();
    } finally {
      endBlock(reason);
    }
  }

  void restartCountdown(String reason) {
    if (!_countdownEnabled || isBlocked) return;
    _restartCountdown(reason);
  }

  void log(
    String event, [
    Map<String, Object?> details = const <String, Object?>{},
  ]) {
    final buffer = StringBuffer()
      ..write('[TypeAutoTransition] ')
      ..write(DateTime.now().toIso8601String())
      ..write(' event=')
      ..write(event);
    for (final entry in details.entries) {
      if (entry.value == null) continue;
      buffer
        ..write(' ')
        ..write(entry.key)
        ..write('=')
        ..write(entry.value);
    }
    final line = buffer.toString();
    _debugLines.add(line);
    if (_debugLines.length > 120) {
      _debugLines.removeRange(0, _debugLines.length - 120);
    }
    debugPrint(line);
  }

  void _releasePointer(int pointer, String event) {
    final removed = _activePointers.remove(pointer);
    if (!removed) return;
    log(event, <String, Object?>{
      'pointer': pointer,
      'activePointers': _activePointers.length,
    });
    if (_countdownEnabled && !isBlocked) {
      _restartCountdown(event);
    } else {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _restartCountdown(String reason) {
    _deadline = DateTime.now().add(_countdownDuration);
    log('countdown_started', <String, Object?>{
      'durationMs': _countdownDuration.inMilliseconds,
      'reason': reason,
    });
    notifyListeners();
  }
}
