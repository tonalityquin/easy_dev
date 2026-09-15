import 'package:flutter/material.dart';

import '../../../features/description/pages/description_page.dart';
import '../../../features/dev/application/debug_session_controller.dart';
import '../../../features/dev/page/dialogs/plate_billing_count_dialog.dart';
import '../../../features/dev/page/sheets/dev_quick_actions.dart';
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

  static const Set<String> _protectedCommands = <String>{
    'debug',
    'charge',
  };

  static bool requiresImportingUnlock(String command) {
    return _protectedCommands.contains(AppCommandRegistry.normalize(command));
  }

  static Future<AppCommandExecutionResult> execute(
    BuildContext context,
    String rawCommand, {
    String source = '',
    bool importingUnlocked = false,
    bool showStatusDialog = true,
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

    if (requiresImportingUnlock(definition.command) && !importingUnlocked) {
      AppCommandDiagnostics.record(
        phase: 'execute_protected_denied',
        input: definition.command,
        normalized: definition.command,
        source: source,
        command: definition.command,
        result: 'locked',
      );
      return AppCommandExecutionResult(
        state: AppCommandExecutionState.failure,
        normalizedCommand: normalized,
        definition: definition,
        outputLines: const <String>['[DENIED] command locked'],
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
        case 'setting':
          break;
        case 'charge':
          surfaceCompletion = _launchCharge(
            context,
            source: source,
          );
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
          if (showStatusDialog) {
            await AppCommandDiagnostics.showStatus(
              context,
              title: 'Terminal Status',
              description:
                  'result=success\nsource=${source.isEmpty ? '-' : source}',
            );
          }
          break;
        case 'debug':
          await DebugSessionController.enable(source: 'command_terminal');
          await DevQuickActions.mountIfNeeded();
          await _showProtectedStatus(
            context,
            command: definition.command,
            source: source,
          );
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
      if (context.mounted && requiresImportingUnlock(definition.command)) {
        await AppCommandDiagnostics.showStatus(
          context,
          title: 'Terminal Command Status',
          description:
              'command=${definition.command}\nresult=failure\nsource=${source.isEmpty ? '-' : source}',
          failure: true,
        );
      }
      return AppCommandExecutionResult(
        state: AppCommandExecutionState.failure,
        normalizedCommand: normalized,
        definition: definition,
        error: error,
      );
    }
  }

  static Future<void> _launchCharge(
    BuildContext context, {
    required String source,
  }) async {
    DebugSessionController.record(
      'charge_surface_open',
      source: 'command_terminal',
    );
    await showPlateBillingCountDialog(context);
    DebugSessionController.record(
      'charge_surface_close',
      source: 'command_terminal',
    );
    if (!context.mounted) return;
    await _showProtectedStatus(
      context,
      command: 'charge',
      source: source,
    );
  }

  static Future<void> _showProtectedStatus(
    BuildContext context, {
    required String command,
    required String source,
  }) async {
    if (!context.mounted) return;
    AppCommandDiagnostics.record(
      phase: 'protected_status_ready',
      input: command,
      normalized: command,
      source: source,
      command: command,
      result: 'success',
    );
    await AppCommandDiagnostics.showStatus(
      context,
      title: 'Terminal Command Status',
      description:
          'command=$command\nresult=success\nsource=${source.isEmpty ? '-' : source}',
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
