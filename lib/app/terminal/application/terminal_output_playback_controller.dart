import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../command/application/terminal_line.dart';
import 'parkinworkin_terminal_diagnostics.dart';
import 'terminal_output_pacing.dart';

class TerminalOutputPlaybackController extends ChangeNotifier {
  TerminalOutputPlaybackController({required this.contextLabel});

  final String contextLabel;
  final List<TerminalLine> _visible = <TerminalLine>[];
  final Queue<TerminalLine> _pending = Queue<TerminalLine>();
  final Set<int> _knownIds = <int>{};
  final Map<int, TerminalLine> _latestById = <int, TerminalLine>{};
  bool _processing = false;
  bool _disposed = false;
  bool _reduceMotion = false;
  Completer<void>? _idleCompleter;

  List<TerminalLine> get lines => List<TerminalLine>.unmodifiable(_visible);
  bool get busy => _processing || _pending.isNotEmpty;

  void sync(
    List<TerminalLine> source, {
    required bool reduceMotion,
  }) {
    if (_disposed) return;
    _reduceMotion = reduceMotion;
    final sourceIds = source.map((line) => line.id).toSet();
    final newestId = source.isEmpty
        ? -1
        : source.map((line) => line.id).reduce((a, b) => a > b ? a : b);
    if (source.isEmpty && (_knownIds.isNotEmpty || _visible.isNotEmpty)) {
      _pending.clear();
      _knownIds.clear();
      _latestById.clear();
      _visible.clear();
      _completeIdleIfNeeded();
      notifyListeners();
      return;
    }
    _visible.removeWhere((line) => !sourceIds.contains(line.id));
    _knownIds.removeWhere((id) => !sourceIds.contains(id));
    _latestById.removeWhere((id, _) => !sourceIds.contains(id));
    for (final line in source) {
      final renderLine = line.type == TerminalLineType.running && line.id != newestId
          ? line.copyWith(type: TerminalLineType.output)
          : line;
      _latestById[line.id] = renderLine;
      final visibleIndex = _visible.indexWhere((item) => item.id == line.id);
      if (visibleIndex >= 0) {
        final current = _visible[visibleIndex];
        final text = current.text.length >= renderLine.text.length
            ? renderLine.text
            : current.text;
        _visible[visibleIndex] = renderLine.copyWith(text: text);
      }
      if (_knownIds.add(line.id)) {
        _pending.add(renderLine);
        _idleCompleter ??= Completer<void>();
        ParkinWorkinTerminalDiagnostics.record(
          'terminal_line_enqueued',
          context: contextLabel,
          meta: <String, Object?>{
            'lineId': renderLine.id,
            'lineType': renderLine.type.name,
            'length': renderLine.text.length,
            'cadence': TerminalOutputPacing.cadenceFor(renderLine).name,
          },
        );
      }
    }
    notifyListeners();
    if (!_processing) {
      unawaited(_drain());
    }
  }

  Future<void> _drain() async {
    if (_processing || _disposed) return;
    _processing = true;
    if (!_reduceMotion &&
        _pending.isNotEmpty &&
        _pending.first.type != TerminalLineType.command) {
      await Future<void>.delayed(
        TerminalOutputPacing.initialBreath(reduceMotion: _reduceMotion),
      );
    }
    while (_pending.isNotEmpty && !_disposed) {
      final original = _pending.removeFirst();
      final latest = _latestById[original.id] ?? original;
      await _playLine(latest);
    }
    _processing = false;
    _completeIdleIfNeeded();
    if (!_disposed) notifyListeners();
  }

  Future<void> _playLine(TerminalLine line) async {
    final existingIndex = _visible.indexWhere((item) => item.id == line.id);
    if (line.type == TerminalLineType.command || _reduceMotion) {
      if (existingIndex >= 0) {
        _visible[existingIndex] = line;
      } else {
        _visible.add(line);
      }
      notifyListeners();
    } else {
      final blank = line.copyWith(text: '');
      if (existingIndex >= 0) {
        _visible[existingIndex] = blank;
      } else {
        _visible.add(blank);
      }
      notifyListeners();
      ParkinWorkinTerminalDiagnostics.record(
        'terminal_typing_start',
        context: contextLabel,
        meta: <String, Object?>{
          'lineId': line.id,
          'lineType': line.type.name,
          'length': line.text.length,
          'cadence': TerminalOutputPacing.cadenceFor(line).name,
          'firstCharMs': line.text.isEmpty
              ? 0
              : TerminalOutputPacing.characterDelay(
                  line,
                  0,
                  reduceMotion: _reduceMotion,
                ).inMilliseconds,
        },
      );
      for (var index = 0; index < line.text.length && !_disposed; index++) {
        await Future<void>.delayed(
          TerminalOutputPacing.characterDelay(
            line,
            index,
            reduceMotion: _reduceMotion,
          ),
        );
        if (_disposed) return;
        final targetIndex = _visible.indexWhere((item) => item.id == line.id);
        if (targetIndex < 0) return;
        final latest = _latestById[line.id] ?? line;
        _visible[targetIndex] = latest.copyWith(
          text: line.text.substring(0, index + 1),
        );
        notifyListeners();
      }
      ParkinWorkinTerminalDiagnostics.record(
        'terminal_typing_complete',
        context: contextLabel,
        meta: <String, Object?>{
          'lineId': line.id,
          'length': line.text.length,
        },
      );
    }
    final pause = TerminalOutputPacing.postLineDelay(
      line,
      reduceMotion: _reduceMotion,
    );
    ParkinWorkinTerminalDiagnostics.record(
      'terminal_line_pause',
      context: contextLabel,
      meta: <String, Object?>{
        'lineId': line.id,
        'milliseconds': pause.inMilliseconds,
      },
    );
    await Future<void>.delayed(pause);
  }

  Future<void> waitUntilIdle() async {
    if (!busy) return;
    _idleCompleter ??= Completer<void>();
    await _idleCompleter!.future;
  }

  void _completeIdleIfNeeded() {
    if (_processing || _pending.isNotEmpty) return;
    final completer = _idleCompleter;
    _idleCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    ParkinWorkinTerminalDiagnostics.record(
      'terminal_output_queue_idle',
      context: contextLabel,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _pending.clear();
    final completer = _idleCompleter;
    _idleCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    super.dispose();
  }
}
