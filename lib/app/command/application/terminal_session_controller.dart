import 'package:flutter/material.dart';

import 'app_command_diagnostics.dart';
import 'app_command_executor.dart';
import 'app_command_registry.dart';
import 'terminal_line.dart';

class TerminalSessionController extends ChangeNotifier {
  TerminalSessionController({
    required this.source,
    this.maxLines = 80,
  }) {
    _lines.add(
      TerminalLine(
        id: _nextId(),
        type: TerminalLineType.system,
        text: 'Pelican command session ready.',
      ),
    );
    _lines.add(
      TerminalLine(
        id: _nextId(),
        type: TerminalLineType.system,
        text: "type 'help' to list available commands.",
      ),
    );
  }

  final String source;
  final int maxLines;
  final List<TerminalLine> _lines = <TerminalLine>[];
  final List<String> _commandHistory = <String>[];
  int _sequence = 0;
  int _historyIndex = 0;
  int _errorSerial = 0;
  bool _busy = false;
  bool _disposed = false;
  String _runningCommand = '';

  List<TerminalLine> get lines => List<TerminalLine>.unmodifiable(_lines);
  bool get busy => _busy;
  String get runningCommand => _runningCommand;
  int get errorSerial => _errorSerial;

  int _nextId() => ++_sequence;

  void _append(TerminalLineType type, String text) {
    _lines.add(
      TerminalLine(
        id: _nextId(),
        type: type,
        text: text,
      ),
    );
    if (_lines.length > maxLines) {
      _lines.removeRange(0, _lines.length - maxLines);
    }
  }

  int _appendRunning(String text) {
    final id = _nextId();
    _lines.add(
      TerminalLine(
        id: id,
        type: TerminalLineType.running,
        text: text,
      ),
    );
    if (_lines.length > maxLines) {
      _lines.removeRange(0, _lines.length - maxLines);
    }
    return id;
  }

  void _settleRunning(int id) {
    final index = _lines.indexWhere((line) => line.id == id);
    if (index < 0) return;
    _lines[index] = _lines[index].copyWith(type: TerminalLineType.output);
  }

  void rejectEmptyInput() {
    _errorSerial += 1;
    AppCommandDiagnostics.record(
      phase: 'terminal_empty',
      input: '',
      normalized: '',
      source: source,
      result: 'rejected',
    );
    notifyListeners();
  }

  Future<AppCommandExecutionResult?> submit(
    BuildContext context,
    String rawCommand, {
    required bool reduceMotion,
  }) async {
    if (_busy || _disposed) return null;
    final displayCommand = rawCommand.trim();
    final normalized = AppCommandRegistry.normalize(rawCommand);
    if (displayCommand.isEmpty) {
      rejectEmptyInput();
      return null;
    }

    if (_commandHistory.isEmpty || _commandHistory.last != displayCommand) {
      _commandHistory.add(displayCommand);
      if (_commandHistory.length > 40) {
        _commandHistory.removeAt(0);
      }
    }
    _historyIndex = _commandHistory.length;
    _append(TerminalLineType.command, displayCommand);

    final definition = AppCommandRegistry.find(normalized);
    AppCommandDiagnostics.record(
      phase: 'terminal_submit',
      input: rawCommand,
      normalized: normalized,
      source: source,
      command: definition?.command ?? '',
      result: definition == null ? 'unknown' : 'matched',
    );

    if (definition == null) {
      _append(TerminalLineType.error, 'command not found: $normalized');
      _append(
        TerminalLineType.system,
        "type 'help' to list available commands.",
      );
      _errorSerial += 1;
      notifyListeners();
      return AppCommandExecutionResult(
        state: AppCommandExecutionState.unknown,
        normalizedCommand: normalized,
      );
    }

    _busy = true;
    _runningCommand = definition.command;
    final runningLineId = _appendRunning(definition.runningMessage);
    AppCommandDiagnostics.record(
      phase: 'terminal_running',
      input: rawCommand,
      normalized: normalized,
      source: source,
      command: definition.command,
      result: 'visible',
    );
    notifyListeners();

    await Future<void>.delayed(
      reduceMotion
          ? const Duration(milliseconds: 80)
          : const Duration(milliseconds: 220),
    );
    if (_disposed || !context.mounted) return null;

    final result = await AppCommandExecutor.execute(
      context,
      rawCommand,
      source: source,
    );
    if (_disposed) return result;

    _settleRunning(runningLineId);
    if (result.succeeded) {
      if (definition.command == 'help') {
        _appendHelpOutput();
      }
      _append(TerminalLineType.success, definition.successMessage);
      AppCommandDiagnostics.record(
        phase: 'terminal_complete',
        input: rawCommand,
        normalized: normalized,
        source: source,
        command: definition.command,
        result: 'success',
      );
    } else {
      _append(
        TerminalLineType.error,
        'command failed: ${definition.command}',
      );
      _errorSerial += 1;
      AppCommandDiagnostics.record(
        phase: 'terminal_failure',
        input: rawCommand,
        normalized: normalized,
        source: source,
        command: definition.command,
        result: 'failure',
        error: result.error,
      );
    }

    _busy = false;
    _runningCommand = '';
    notifyListeners();
    return result;
  }

  void _appendHelpOutput() {
    _append(TerminalLineType.system, 'Available commands');
    _append(TerminalLineType.system, '────────────────────────────');
    for (final category in AppCommandRegistry.categories) {
      _append(TerminalLineType.system, '[$category]');
      for (final definition in AppCommandRegistry.byCategory(category)) {
        _append(
          TerminalLineType.output,
          '${definition.command.padRight(14)}${definition.title}',
        );
      }
    }
    _append(
      TerminalLineType.system,
      '${AppCommandRegistry.commands.length} commands available.',
    );
  }

  String? previousCommand() {
    if (_commandHistory.isEmpty) return null;
    if (_historyIndex > 0) {
      _historyIndex -= 1;
    }
    final value = _commandHistory[_historyIndex];
    AppCommandDiagnostics.record(
      phase: 'history_recall',
      input: value,
      normalized: AppCommandRegistry.normalize(value),
      source: source,
      result: 'previous',
    );
    return value;
  }

  String? nextCommand() {
    if (_commandHistory.isEmpty) return null;
    if (_historyIndex < _commandHistory.length - 1) {
      _historyIndex += 1;
      final value = _commandHistory[_historyIndex];
      AppCommandDiagnostics.record(
        phase: 'history_recall',
        input: value,
        normalized: AppCommandRegistry.normalize(value),
        source: source,
        result: 'next',
      );
      return value;
    }
    _historyIndex = _commandHistory.length;
    return '';
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
