import 'package:flutter/material.dart';

import '../../../features/description/pages/description_page.dart';
import '../../../features/dev/application/debug_session_controller.dart';
import '../../../features/dev/page/dialogs/plate_billing_count_dialog.dart';
import '../../../features/dev/page/sheets/dev_quick_actions.dart';
import '../../../features/headquarter/application/fab/hub_quick_actions.dart';
import '../../init/app_exit_service.dart';
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
    this.outputLines = const <String>[],
  });

  final AppCommandExecutionState state;
  final String normalizedCommand;
  final AppCommandDefinition? definition;
  final Object? error;
  final Future<void>? surfaceCompletion;
  final List<String> outputLines;

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
      List<String> outputLines = const <String>[];
      var state = AppCommandExecutionState.success;
      Object? error;

      switch (definition.command) {
        case 'quick':
          await HeadHubActions.init();
          HeadHubActions.setEnabled(true);
          await HeadHubActions.mountIfNeeded();
          break;
        case 'setting':
          break;
        case 'charge':
          surfaceCompletion = _launchCharge(context);
          break;
        case 'about':
          surfaceCompletion = _launchAbout(context);
          break;
        case 'out':
          break;
        case 'exit':
          await AppExitService.exitApp(context);
          break;
        case 'status':
          break;
        case 'debug':
          await DebugSessionController.enable(source: 'command_terminal');
          await DevQuickActions.mountIfNeeded();
          break;
        case 'help':
          break;
      }

      AppCommandDiagnostics.record(
        phase: state == AppCommandExecutionState.success
            ? 'execute_complete'
            : 'execute_rejected',
        input: rawCommand,
        normalized: normalized,
        source: source,
        command: definition.command,
        result: state == AppCommandExecutionState.success ? 'success' : 'failure',
        error: error,
      );

      return AppCommandExecutionResult(
        state: state,
        normalizedCommand: normalized,
        definition: definition,
        error: error,
        surfaceCompletion: surfaceCompletion,
        outputLines: outputLines,
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

  static Future<void> _launchCharge(BuildContext context) async {
    DebugSessionController.record(
      'charge_surface_open',
      source: 'command_terminal',
    );
    await showPlateBillingCountDialog(context);
    DebugSessionController.record(
      'charge_surface_close',
      source: 'command_terminal',
    );
  }

  static Future<void> _launchAbout(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const DescriptionPage(),
      ),
    );
  }
}
