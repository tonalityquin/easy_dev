import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/di/routes.dart';
import '../../../app/init/app_start_debug_trace.dart';
import '../../../app/init/app_start_flow_prefs.dart';
import '../../../app/init/app_start_user_purpose.dart';
import '../../../app/init/startup_tasks.dart';

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

  String? _normalizeMode(String? raw) {
    if (raw == null) return null;
    final v = raw.trim().toLowerCase();
    if (v.isEmpty) return null;

    switch (v) {
      case 'service':
        return null;
      case 'personal':
      case 'mobile':
      case 'direct':
        return 'personal';
      case 'tablet':
        return 'tablet';
      case 'single':
      case 'simple':
        return 'single';
      case 'double':
      case 'lite':
      case 'light':
        return 'double';
      case 'triple':
      case 'normal':
        return 'triple';
      case 'minor':
        return 'minor';
      default:
        return null;
    }
  }

  Future<String?> _resolveReturnUserRoute() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = _normalizeMode(prefs.getString('mode'));
    switch (mode) {
      case 'personal':
        return AppRoutes.personalLogin;
      case 'tablet':
        return AppRoutes.tabletLogin;
      case 'single':
        return AppRoutes.singleLogin;
      case 'double':
        return AppRoutes.doubleLogin;
      case 'triple':
        return AppRoutes.tripleLogin;
      case 'minor':
        return AppRoutes.minorLogin;
      default:
        return null;
    }
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
      AppStartDebugTrace.log(
        'start_gate',
        'navigate_user_purpose',
      );
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

    final skipPolicyAndPostSetup =
        purpose?.skipsPolicyAndPostSetup ?? false;
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

    await StartupTasks.runAfterPermissions();
    if (!mounted || _navigated) return;

    final route = await _resolveReturnUserRoute();
    if (!mounted || _navigated) return;

    _navigated = true;
    final target = route ?? AppRoutes.selector;
    AppStartDebugTrace.log(
      'start_gate',
      'navigate_main_flow',
      meta: <String, Object?>{'route': target},
    );
    Navigator.of(context).pushReplacementNamed(target);
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
