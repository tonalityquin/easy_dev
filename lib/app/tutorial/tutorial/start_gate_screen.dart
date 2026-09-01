import 'package:flutter/material.dart';

import '../../../app/di/routes.dart';
import '../../../app/init/app_start_debug_trace.dart';
import '../../../app/init/app_start_flow_prefs.dart';
import '../../../app/init/app_start_user_purpose.dart';
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

  Future<String?> _resolvePendingPolicyRoute() async {
    final terms = await AppStartFlowPrefs.getTermsOfServiceAgreed();
    if (!terms) return AppRoutes.termsConsent;

    final privacy = await AppStartFlowPrefs.getPrivacyPolicyAgreed();
    if (!privacy) return AppRoutes.privacyPolicyConsent;

    final accountDeletion =
        await AppStartFlowPrefs.getAccountDeletionPolicyAgreed();
    if (!accountDeletion) return AppRoutes.accountDeletionPolicyConsent;

    return null;
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
    await AppStartFlowPrefs.migrateFromLegacyIfNeeded();

    final permDone = await AppStartFlowPrefs.getPermissionTutorialDone();
    final purpose = await AppStartFlowPrefs.getUserPurpose();
    final noticeDone = await AppStartFlowPrefs.getPermissionNoticeDone();
    AppStartDebugTrace.log(
      'start_gate',
      'onboarding_state_resolved',
      meta: <String, Object?>{
        'permissionDone': permDone,
        'purpose': purpose?.storageValue ?? 'none',
        'noticeDone': noticeDone,
      },
    );
    if (!mounted || _navigated) return;

    if (!permDone && purpose == null) {
      _navigated = true;
      AppStartDebugTrace.log('start_gate', 'navigate_user_purpose');
      Navigator.of(context).pushReplacementNamed(
        AppRoutes.appStartUserPurpose,
      );
      return;
    }

    if (!permDone && !noticeDone) {
      _navigated = true;
      AppStartDebugTrace.log(
        'start_gate',
        'navigate_permission_notice',
        meta: <String, Object?>{
          'purpose': purpose?.storageValue ?? 'none',
        },
      );
      Navigator.of(context).pushReplacementNamed(
        AppRoutes.appStartPermissionNotice,
      );
      return;
    }

    if (!permDone) {
      _navigated = true;
      AppStartDebugTrace.log(
        'start_gate',
        'navigate_permission_setup',
        meta: <String, Object?>{
          'purpose': purpose?.storageValue ?? 'none',
        },
      );
      Navigator.of(context).pushReplacementNamed(
        AppRoutes.appStartPermissionSetup,
      );
      return;
    }

    final skipPolicyAndPostSetup = purpose?.skipsPolicyAndPostSetup ?? false;
    if (skipPolicyAndPostSetup) {
      AppStartDebugTrace.log(
        'start_gate',
        'skip_policy_and_post_setup',
        meta: <String, Object?>{
          'purpose': purpose?.storageValue ?? 'none',
        },
      );
    } else {
      final pendingPolicyRoute = await _resolvePendingPolicyRoute();
      if (!mounted || _navigated) return;

      if (pendingPolicyRoute != null) {
        _navigated = true;
        AppStartDebugTrace.log(
          'start_gate',
          'navigate_policy',
          meta: <String, Object?>{
            'route': pendingPolicyRoute,
            'purpose': purpose?.storageValue ?? 'legacy_unknown',
          },
        );
        Navigator.of(context).pushReplacementNamed(pendingPolicyRoute);
        return;
      }

      final requiresGoogleServicesSetup =
          purpose?.requiresGoogleServicesSetup ?? false;
      if (requiresGoogleServicesSetup) {
        final googleServicesDone =
            await AppStartFlowPrefs.getGoogleServicesSetupDone();
        final googleServicesSkipped =
            await AppStartFlowPrefs.getGoogleServicesSetupSkipped();
        if (!mounted || _navigated) return;
        if (!googleServicesDone && !googleServicesSkipped) {
          _navigated = true;
          AppStartDebugTrace.log(
            'start_gate',
            'navigate_google_services_setup',
            meta: <String, Object?>{
              'purpose': purpose?.storageValue ?? 'none',
            },
          );
          Navigator.of(context).pushReplacementNamed(
            AppRoutes.appStartGoogleServicesSetup,
          );
          return;
        }
        AppStartDebugTrace.log(
          'start_gate',
          googleServicesDone
              ? 'google_services_setup_already_done'
              : 'google_services_setup_skipped',
          meta: <String, Object?>{
            'purpose': purpose?.storageValue ?? 'none',
            'done': googleServicesDone,
            'skipped': googleServicesSkipped,
          },
        );
      }
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
