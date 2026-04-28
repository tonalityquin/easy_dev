import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../app/di/routes.dart';
import '../../../app/init/app_start_flow_prefs.dart';
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
    _decide();
  }


  String? _normalizeMode(String? raw) {
    if (raw == null) return null;
    final v = raw.trim().toLowerCase();
    if (v.isEmpty) return null;

    switch (v) {
      case 'service':
        return null;
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
      case 'single':
        return AppRoutes.singleLogin;
      case 'tablet':
        return AppRoutes.tabletLogin;
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
  Future<void> _decide() async {
    await AppStartFlowPrefs.migrateFromLegacyIfNeeded();
    final permDone = await AppStartFlowPrefs.getPermissionTutorialDone();
    if (!mounted || _navigated) return;

    if (!permDone) {
      _navigated = true;
      Navigator.of(context).pushReplacementNamed(AppRoutes.appStartTutorial);
      return;
    }

    final usedBefore = await AppStartFlowPrefs.getUsedBefore();
    if (!mounted || _navigated) return;

    if (usedBefore) {
      await AppStartFlowPrefs.setSelectorScreenTutorialDone(true);
      await StartupTasks.runAfterPermissions();
      if (!mounted || _navigated) return;
      final route = await _resolveReturnUserRoute();
      if (!mounted || _navigated) return;
      _navigated = true;
      Navigator.of(context).pushReplacementNamed(route ?? AppRoutes.selector);
      return;
    }

    final selectorDone = await AppStartFlowPrefs.getSelectorScreenTutorialDone();
    if (!mounted || _navigated) return;

    if (!selectorDone) {
      _navigated = true;
      Navigator.of(context).pushReplacementNamed(AppRoutes.appStartNextTutorialFull);
      return;
    }

    await StartupTasks.runAfterPermissions();
    if (!mounted || _navigated) return;
    _navigated = true;
    Navigator.of(context).pushReplacementNamed(AppRoutes.selector);
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
