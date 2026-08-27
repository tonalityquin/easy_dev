import 'dart:async';

import 'package:flutter/material.dart';

import '../../../features/headquarter/application/actions/headquarter_common_actions.dart';
import '../../../features/headquarter/application/fab/hub_quick_actions.dart';
import '../../../features/selector/application/dev_auth.dart';
import 'app_command_definition.dart';
import 'app_command_diagnostics.dart';
import 'app_command_registry.dart';

enum AppCommandExecutionState {
  success,
  unknown,
  failure,
}

class AppCommandExecutionResult {
  const AppCommandExecutionResult({
    required this.state,
    required this.normalizedCommand,
    this.definition,
    this.error,
    this.surfaceCompletion,
  });

  final AppCommandExecutionState state;
  final String normalizedCommand;
  final AppCommandDefinition? definition;
  final Object? error;
  final Future<void>? surfaceCompletion;

  bool get succeeded => state == AppCommandExecutionState.success;
}

class AppCommandExecutor {
  AppCommandExecutor._();

  static Future<AppCommandExecutionResult> execute(
    BuildContext context,
    String rawCommand, {
    String source = '',
  }) async {
    final normalized = AppCommandRegistry.normalize(rawCommand);
    final definition = AppCommandRegistry.find(normalized);

    if (definition == null) {
      AppCommandDiagnostics.record(
        phase: 'execute_unknown',
        input: rawCommand,
        normalized: normalized,
        source: source,
        result: 'unknown',
      );
      return AppCommandExecutionResult(
        state: AppCommandExecutionState.unknown,
        normalizedCommand: normalized,
      );
    }

    AppCommandDiagnostics.record(
      phase: 'execute_start',
      input: rawCommand,
      normalized: normalized,
      source: source,
      command: definition.command,
      result: 'started',
    );

    try {
      Future<void>? surfaceCompletion;
      switch (definition.command) {
        case 'quick button':
          await HeadHubActions.init();
          HeadHubActions.setEnabled(true);
          await HeadHubActions.mountIfNeeded();
          break;
        case 'setting':
          surfaceCompletion = _launchSettings(
            context,
            rawCommand,
            normalized,
            source,
          );
          break;
        case 'debug':
          await DevAuth.setDevModeEnabled(true);
          break;
        case 'help':
          break;
      }

      AppCommandDiagnostics.record(
        phase: 'execute_complete',
        input: rawCommand,
        normalized: normalized,
        source: source,
        command: definition.command,
        result: 'success',
      );

      return AppCommandExecutionResult(
        state: AppCommandExecutionState.success,
        normalizedCommand: normalized,
        definition: definition,
        surfaceCompletion: surfaceCompletion,
      );
    } catch (error, stackTrace) {
      AppCommandDiagnostics.record(
        phase: 'execute_failure',
        input: rawCommand,
        normalized: normalized,
        source: source,
        command: definition.command,
        result: 'failure',
        error: error,
      );
      debugPrint(stackTrace.toString());
      return AppCommandExecutionResult(
        state: AppCommandExecutionState.failure,
        normalizedCommand: normalized,
        definition: definition,
        error: error,
      );
    }
  }

  static Future<void> _monitorSettingsSurface(
    Future<void> future, {
    required String rawCommand,
    required String normalized,
    required String source,
  }) async {
    try {
      await future;
      AppCommandDiagnostics.record(
        phase: 'surface_close',
        input: rawCommand,
        normalized: normalized,
        source: source,
        command: 'setting',
        result: 'closed',
      );
    } catch (error, stackTrace) {
      AppCommandDiagnostics.record(
        phase: 'surface_failure',
        input: rawCommand,
        normalized: normalized,
        source: source,
        command: 'setting',
        result: 'failure',
        error: error,
      );
      debugPrint(stackTrace.toString());
    }
  }

  static Future<void> _launchSettings(
    BuildContext context,
    String rawCommand,
    String normalized,
    String source,
  ) {
    final future = HeadquarterCommonActions.openSettings(
      context,
      source: 'command_terminal',
    );
    final monitored = _monitorSettingsSurface(
      future,
      rawCommand: rawCommand,
      normalized: normalized,
      source: source,
    );
    unawaited(monitored);
    AppCommandDiagnostics.record(
      phase: 'surface_launch',
      input: rawCommand,
      normalized: normalized,
      source: source,
      command: 'setting',
      result: 'launched',
    );
    return monitored;
  }
}
