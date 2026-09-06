import 'package:flutter/material.dart';

import '../../../app/di/routes.dart';
import '../../../app/init/app_start_debug_trace.dart';
import '../../../app/init/app_start_setup_flow_resolver.dart';
import '../../../app/init/startup_tasks.dart';
import '../../../features/launcher/application/launcher_debug_account_override_store.dart';
import '../../../features/launcher/application/launcher_diagnostics.dart';
import '../../../features/launcher/application/terminal_restore_hint.dart';

class StartGateScreen extends StatefulWidget {
  const StartGateScreen({super.key});

  @override
  State<StartGateScreen> createState() => _StartGateScreenState();
}

class _StartGateScreenState extends State<StartGateScreen> {
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    AppStartDebugTrace.log('start_gate', 'screen_init');
    _decide();
  }

  Future<void> _decide() async {
    final debugSnapshotRestored =
        await LauncherDebugAccountOverrideStore.restoreIfNeeded(
      source: 'start_gate',
    );
    if (debugSnapshotRestored) {
      AppStartDebugTrace.log(
        'start_gate',
        'debug_account_override_snapshot_restored',
      );
    }

    final setupSnapshot = await AppStartSetupFlowResolver.resolve();
    AppStartDebugTrace.log(
      'start_gate',
      'setup_state_resolved',
      meta: setupSnapshot.toDebugMeta(),
    );
    if (!mounted || _navigated) return;

    if (!setupSnapshot.complete) {
      _navigated = true;
      AppStartDebugTrace.log(
        'start_gate',
        'navigate_power_boot_for_startup_setup',
        meta: <String, Object?>{
          'route': AppRoutes.powerBoot,
          ...setupSnapshot.toDebugMeta(),
        },
      );
      LauncherDiagnostics.record(
        'startup_power_boot_required_for_setup',
        scope: 'startup',
        meta: setupSnapshot.toDebugMeta(),
      );
      Navigator.of(context).pushReplacementNamed(AppRoutes.powerBoot);
      return;
    }

    final report = await StartupTasks.runAfterPermissions();
    if (!mounted || _navigated) return;

    final restoreKind = await TerminalRestoreHint.readAccountKindId();
    if (!mounted || _navigated) return;

    _navigated = true;
    if (restoreKind != null) {
      AppStartDebugTrace.log(
        'start_gate',
        'skip_power_boot_for_restore',
        meta: <String, Object?>{
          'route': AppRoutes.modeLauncher,
          'accountKind': restoreKind,
          'startupReady': report.readyCount,
          'startupAllReady': report.allReady,
        },
      );
      LauncherDiagnostics.record(
        'startup_power_boot_skipped',
        scope: 'startup',
        meta: <String, Object?>{
          'accountKind': restoreKind,
          'firebaseReads': 0,
        },
      );
      Navigator.of(context).pushReplacementNamed(
        AppRoutes.modeLauncher,
        arguments: report,
      );
      return;
    }

    AppStartDebugTrace.log(
      'start_gate',
      'navigate_power_boot',
      meta: <String, Object?>{
        'route': AppRoutes.powerBoot,
        'startupReady': report.readyCount,
        'startupAllReady': report.allReady,
      },
    );
    LauncherDiagnostics.record(
      'startup_power_boot_required',
      scope: 'startup',
      meta: const <String, Object?>{'firebaseReads': 0},
    );
    Navigator.of(context).pushReplacementNamed(
      AppRoutes.powerBoot,
      arguments: report,
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
