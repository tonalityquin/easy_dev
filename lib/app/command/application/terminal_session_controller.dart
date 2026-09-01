import 'package:flutter/material.dart';

import 'app_command_definition.dart';
import 'app_command_diagnostics.dart';
import 'app_command_executor.dart';
import 'app_command_registry.dart';
import 'service_settings_command_handler.dart';
import 'terminal_command_path.dart';
import 'terminal_line.dart';

class TerminalSessionController extends ChangeNotifier {
  TerminalSessionController({
    required this.source,
    this.maxLines = 80,
  }) {
    _append(
      TerminalLineType.system,
      'ParkinWorkin command session ready.',
      cadence: TerminalCadence.preparing,
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
  TerminalCommandPath _commandPath = TerminalCommandPath.root;

  List<TerminalLine> get lines => List<TerminalLine>.unmodifiable(_lines);
  bool get busy => _busy;
  String get runningCommand => _runningCommand;
  int get errorSerial => _errorSerial;
  String get currentPromptPath => _commandPath.promptPath;
  bool get commandHistoryEnabled => !_commandPath.isEmailEdit;
  bool get emailEditMode => _commandPath.isEmailEdit;

  int _nextId() => ++_sequence;

  void _append(
    TerminalLineType type,
    String text, {
    TerminalCadence cadence = TerminalCadence.automatic,
    String? promptPath,
  }) {
    _lines.add(
      TerminalLine(
        id: _nextId(),
        type: type,
        text: text,
        cadence: cadence,
        promptPath: promptPath ?? _commandPath.promptPath,
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
        cadence: TerminalCadence.thinking,
        promptPath: _commandPath.promptPath,
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
    _lines[index] = _lines[index].copyWith(
      type: TerminalLineType.output,
      cadence: TerminalCadence.responding,
    );
  }

  void _rememberCommand(String command) {
    if (_commandHistory.isEmpty || _commandHistory.last != command) {
      _commandHistory.add(command);
      if (_commandHistory.length > 40) {
        _commandHistory.removeAt(0);
      }
    }
    _historyIndex = _commandHistory.length;
  }

  void _appendCommand(String command) {
    _append(
      TerminalLineType.command,
      command,
      cadence: TerminalCadence.instant,
      promptPath: _commandPath.promptPath,
    );
  }

  void rejectEmptyInput() {
    _errorSerial += 1;
    AppCommandDiagnostics.record(
      phase: 'terminal_empty',
      input: '',
      normalized: '',
      source: source,
      result: 'rejected',
      path: _commandPath.promptPath,
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

    if (!_commandPath.isEmailEdit) {
      _rememberCommand(displayCommand);
    }
    _appendCommand(displayCommand);

    if (_commandPath.isSetting) {
      return _submitSettingCommand(
        context,
        displayCommand,
        normalized,
        reduceMotion: reduceMotion,
      );
    }

    if (normalized == 'setting') {
      final from = _commandPath.promptPath;
      _commandPath = TerminalCommandPath.setting;
      AppCommandDiagnostics.record(
        phase: 'terminal_path_enter',
        input: rawCommand,
        normalized: normalized,
        source: source,
        command: 'setting',
        result: 'success',
        path: '$from -> ${_commandPath.promptPath}',
      );
      notifyListeners();
      return AppCommandExecutionResult(
        state: AppCommandExecutionState.success,
        normalizedCommand: normalized,
        definition: AppCommandRegistry.find('setting'),
      );
    }

    final definition = AppCommandRegistry.find(normalized);
    AppCommandDiagnostics.record(
      phase: 'terminal_submit',
      input: rawCommand,
      normalized: normalized,
      source: source,
      command: definition?.command ?? '',
      result: definition == null ? 'unknown' : 'matched',
      path: _commandPath.promptPath,
    );

    if (definition == null) {
      _append(
        TerminalLineType.error,
        'command not found: $normalized',
        cadence: TerminalCadence.error,
      );
      _errorSerial += 1;
      notifyListeners();
      return AppCommandExecutionResult(
        state: AppCommandExecutionState.unknown,
        normalizedCommand: normalized,
      );
    }

    return _executeDefinition(
      context,
      rawCommand,
      normalized,
      definition,
      reduceMotion: reduceMotion,
    );
  }

  Future<AppCommandExecutionResult> _submitSettingCommand(
    BuildContext context,
    String displayCommand,
    String normalized, {
    required bool reduceMotion,
  }) async {
    if (_commandPath.isEmailEdit) {
      if (normalized == 'cancel' || normalized == 'cd ..') {
        final from = _commandPath.promptPath;
        _commandPath = TerminalCommandPath.setting;
        _append(
          TerminalLineType.system,
          '[ok] email edit cancelled',
          cadence: TerminalCadence.responding,
        );
        AppCommandDiagnostics.record(
          phase: 'terminal_email_edit_cancel',
          input: displayCommand,
          normalized: normalized,
          source: source,
          command: 'email',
          result: 'success',
          path: '$from -> ${_commandPath.promptPath}',
        );
        notifyListeners();
        return AppCommandExecutionResult(
          state: AppCommandExecutionState.success,
          normalizedCommand: normalized,
        );
      }
      if (normalized == 'out' || normalized == 'exit') {
        final definition = AppCommandRegistry.find(normalized)!;
        return _executeDefinition(
          context,
          displayCommand,
          normalized,
          definition,
          reduceMotion: reduceMotion,
        );
      }
      return _submitEmailEditInput(
        context,
        displayCommand,
        normalized,
        reduceMotion: reduceMotion,
      );
    }

    if (normalized == 'setting') {
      notifyListeners();
      return AppCommandExecutionResult(
        state: AppCommandExecutionState.success,
        normalizedCommand: normalized,
      );
    }

    if (normalized == 'cd ..') {
      final from = _commandPath.promptPath;
      _commandPath = TerminalCommandPath.root;
      AppCommandDiagnostics.record(
        phase: 'terminal_path_leave',
        input: displayCommand,
        normalized: normalized,
        source: source,
        command: 'cd',
        result: 'success',
        path: '$from -> ${_commandPath.promptPath}',
      );
      notifyListeners();
      return AppCommandExecutionResult(
        state: AppCommandExecutionState.success,
        normalizedCommand: normalized,
      );
    }

    if (normalized == 'out' || normalized == 'exit') {
      final definition = AppCommandRegistry.find(normalized)!;
      return _executeDefinition(
        context,
        displayCommand,
        normalized,
        definition,
        reduceMotion: reduceMotion,
      );
    }

    _busy = true;
    _runningCommand = normalized.split(' ').first;
    final runningLineId = _appendRunning(_runningCommand);
    AppCommandDiagnostics.record(
      phase: 'terminal_setting_running',
      input: displayCommand,
      normalized: normalized,
      source: source,
      command: _runningCommand,
      result: 'visible',
      path: _commandPath.promptPath,
    );
    notifyListeners();

    await Future<void>.delayed(
      reduceMotion
          ? const Duration(milliseconds: 18)
          : const Duration(milliseconds: 105),
    );
    if (_disposed || !context.mounted) {
      _busy = false;
      _runningCommand = '';
      return AppCommandExecutionResult(
        state: AppCommandExecutionState.failure,
        normalizedCommand: normalized,
      );
    }

    final settingResult = await ServiceSettingsCommandHandler.execute(
      context,
      displayCommand,
      source: source,
    );
    _settleRunning(runningLineId);
    final previousPath = _commandPath;
    if (settingResult.nextPath != null) {
      _commandPath = settingResult.nextPath!;
      AppCommandDiagnostics.record(
        phase: 'terminal_setting_path_change',
        input: displayCommand,
        normalized: normalized,
        source: source,
        command: _runningCommand,
        result: 'success',
        path: '${previousPath.promptPath} -> ${_commandPath.promptPath}',
      );
    }
    for (final line in settingResult.lines) {
      _append(
        settingResult.succeeded
            ? TerminalLineType.output
            : TerminalLineType.error,
        line,
        cadence: settingResult.succeeded
            ? TerminalCadence.responding
            : TerminalCadence.error,
      );
    }
    if (!settingResult.succeeded) {
      _errorSerial += 1;
    }
    AppCommandDiagnostics.record(
      phase: settingResult.succeeded
          ? 'terminal_setting_complete'
          : 'terminal_setting_failure',
      input: displayCommand,
      normalized: normalized,
      source: source,
      command: _runningCommand,
      result: settingResult.succeeded ? 'success' : 'failure',
      path: _commandPath.promptPath,
    );
    _busy = false;
    _runningCommand = '';
    notifyListeners();
    return AppCommandExecutionResult(
      state: settingResult.succeeded
          ? AppCommandExecutionState.success
          : AppCommandExecutionState.failure,
      normalizedCommand: normalized,
      outputLines: settingResult.lines,
    );
  }

  Future<AppCommandExecutionResult> _submitEmailEditInput(
    BuildContext context,
    String displayCommand,
    String normalized, {
    required bool reduceMotion,
  }) async {
    _busy = true;
    _runningCommand = 'email';
    final runningLineId = _appendRunning('email');
    AppCommandDiagnostics.record(
      phase: 'terminal_email_edit_running',
      input: displayCommand,
      normalized: normalized,
      source: source,
      command: 'email',
      result: 'visible',
      path: _commandPath.promptPath,
    );
    notifyListeners();
    await Future<void>.delayed(
      reduceMotion
          ? const Duration(milliseconds: 18)
          : const Duration(milliseconds: 105),
    );
    if (_disposed || !context.mounted) {
      _busy = false;
      _runningCommand = '';
      return AppCommandExecutionResult(
        state: AppCommandExecutionState.failure,
        normalizedCommand: normalized,
      );
    }
    final result = await ServiceSettingsCommandHandler.submitEmailEdit(
      displayCommand,
      source: source,
    );
    _settleRunning(runningLineId);
    for (final line in result.lines) {
      _append(
        result.succeeded ? TerminalLineType.output : TerminalLineType.error,
        line,
        cadence: result.succeeded
            ? TerminalCadence.responding
            : TerminalCadence.error,
      );
    }
    if (result.nextPath != null) {
      final from = _commandPath.promptPath;
      _commandPath = result.nextPath!;
      AppCommandDiagnostics.record(
        phase: 'terminal_email_edit_path_change',
        input: displayCommand,
        normalized: normalized,
        source: source,
        command: 'email',
        result: 'success',
        path: '$from -> ${_commandPath.promptPath}',
      );
    }
    if (!result.succeeded) _errorSerial += 1;
    _busy = false;
    _runningCommand = '';
    notifyListeners();
    return AppCommandExecutionResult(
      state: result.succeeded
          ? AppCommandExecutionState.success
          : AppCommandExecutionState.failure,
      normalizedCommand: normalized,
      outputLines: result.lines,
    );
  }

  Future<AppCommandExecutionResult> _executeDefinition(
    BuildContext context,
    String rawCommand,
    String normalized,
    AppCommandDefinition definition, {
    required bool reduceMotion,
  }) async {
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
      path: _commandPath.promptPath,
    );
    notifyListeners();

    await Future<void>.delayed(
      reduceMotion
          ? const Duration(milliseconds: 18)
          : Duration(
              milliseconds: 105 +
                  ((definition.command).hashCode.abs() % 85),
            ),
    );
    if (_disposed || !context.mounted) {
      _busy = false;
      _runningCommand = '';
      return AppCommandExecutionResult(
        state: AppCommandExecutionState.failure,
        normalizedCommand: normalized,
        definition: definition,
      );
    }

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
      for (final line in result.outputLines) {
        _append(
          TerminalLineType.output,
          line,
          cadence: TerminalCadence.responding,
        );
      }
      _append(
        TerminalLineType.success,
        definition.successMessage,
        cadence: TerminalCadence.emphasis,
      );
      AppCommandDiagnostics.record(
        phase: 'terminal_complete',
        input: rawCommand,
        normalized: normalized,
        source: source,
        command: definition.command,
        result: 'success',
        path: _commandPath.promptPath,
      );
    } else {
      for (final line in result.outputLines) {
        _append(
          TerminalLineType.error,
          line,
          cadence: TerminalCadence.error,
        );
      }
      if (result.outputLines.isEmpty) {
        _append(
          TerminalLineType.error,
          'command failed: ${definition.command}',
          cadence: TerminalCadence.error,
        );
      }
      _errorSerial += 1;
      AppCommandDiagnostics.record(
        phase: 'terminal_failure',
        input: rawCommand,
        normalized: normalized,
        source: source,
        command: definition.command,
        result: 'failure',
        error: result.error,
        path: _commandPath.promptPath,
      );
    }

    _busy = false;
    _runningCommand = '';
    notifyListeners();
    return result;
  }

  void _appendHelpOutput() {
    _append(
      TerminalLineType.system,
      'COMMANDS',
      cadence: TerminalCadence.responding,
    );
    for (final definition in AppCommandRegistry.visibleCommands) {
      _append(
        TerminalLineType.output,
        '${definition.command.padRight(10)}${definition.title}',
        cadence: TerminalCadence.responding,
      );
    }
    _append(
      TerminalLineType.output,
      'help      Command Reference',
      cadence: TerminalCadence.responding,
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
      path: _commandPath.promptPath,
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
        path: _commandPath.promptPath,
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
