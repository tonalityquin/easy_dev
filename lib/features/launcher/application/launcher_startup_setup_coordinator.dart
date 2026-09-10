import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../app/auth/google_auth_session.dart';
import '../../../app/config/auth_config.dart';
import '../../../app/config/gmail_sender_config.dart';
import '../../../app/init/app_start_debug_trace.dart';
import '../../../app/init/app_start_flow_prefs.dart';
import '../../../app/init/app_start_setup_flow_resolver.dart';
import '../../../app/init/app_start_user_purpose.dart';
import '../../../app/tutorial/policy/policy_documents.dart';
import '../../../app/tutorial/tutorial/app_start_permission_coordinator.dart';
import '../../../app/tutorial/tutorial/app_start_setup_specs.dart';

class LauncherStartupSetupCoordinator extends ChangeNotifier {
  LauncherStartupSetupCoordinator() {
    _permissionCoordinator.addListener(_handlePermissionChanged);
  }

  final AppStartPermissionCoordinator _permissionCoordinator =
      AppStartPermissionCoordinator();

  AppStartSetupSnapshot? _snapshot;
  AppStartSetupPhase _phase = AppStartSetupPhase.complete;
  AppStartUserPurpose? _purpose;
  List<int> _permissionSteps = const <int>[];
  int _permissionIndex = 0;
  bool _busy = false;
  bool _initializing = false;
  bool _awaitingExternalSettings = false;
  bool _externalSettingsRefreshInProgress = false;
  int? _externalSettingsStep;
  bool _policyReadToEnd = false;
  bool _policyAgreed = false;
  double _policyScrollProgress = 0;
  bool _googleConnected = false;
  String? _googleAccountEmail;
  String? _googleErrorText;
  int _googleSkipTapCount = 0;
  int _permissionSkipTapCount = 0;
  int? _permissionSkipTapStep;
  bool _disposed = false;

  AppStartSetupSnapshot? get snapshot => _snapshot;
  AppStartSetupPhase get phase => _phase;
  AppStartUserPurpose? get purpose => _purpose;
  bool get busy =>
      _busy ||
      _permissionCoordinator.busy ||
      _initializing ||
      _externalSettingsRefreshInProgress;
  bool get awaitingExternalSettings => _awaitingExternalSettings;
  bool get externalSettingsRefreshInProgress =>
      _externalSettingsRefreshInProgress;
  int? get externalSettingsStep => _externalSettingsStep;
  bool get complete => _phase == AppStartSetupPhase.complete;
  bool get requiresPurpose => _purpose == null;
  List<int> get permissionSteps => List<int>.unmodifiable(_permissionSteps);
  int get permissionIndex => _permissionIndex;
  int? get currentPermissionStep =>
      _permissionSteps.isEmpty ? null : _permissionSteps[_permissionIndex];
  AppStartPermissionSpec? get currentPermissionSpec {
    final step = currentPermissionStep;
    return step == null ? null : appStartPermissionSpecForStep(step);
  }

  String get currentPermissionStatus {
    final step = currentPermissionStep;
    if (step == null) return '-';
    if (_awaitingExternalSettings && _externalSettingsStep == step) {
      return _externalSettingsRefreshInProgress ? '확인 중' : '시스템 설정 대기';
    }
    return _permissionCoordinator.statusLabel(step);
  }

  String get currentPermissionActionLabel {
    final step = currentPermissionStep;
    if (step == null) return '';
    if (_awaitingExternalSettings && _externalSettingsStep == step) {
      return _externalSettingsRefreshInProgress
          ? '권한 확인 중'
          : '시스템 설정에서 허용 후 앱으로 돌아오세요';
    }
    return _permissionCoordinator.actionLabel(step);
  }

  bool get currentPermissionGranted {
    final step = currentPermissionStep;
    return step != null && _permissionCoordinator.isGranted(step);
  }

  PolicyDocumentSpec? get currentPolicySpec {
    return switch (_phase) {
      AppStartSetupPhase.terms =>
        policyDocumentOf(PolicyConsentKind.termsOfService),
      AppStartSetupPhase.privacy =>
        policyDocumentOf(PolicyConsentKind.privacyPolicy),
      AppStartSetupPhase.accountDeletion =>
        policyDocumentOf(PolicyConsentKind.accountDeletion),
      _ => null,
    };
  }

  bool get policyReadToEnd => _policyReadToEnd;
  bool get policyAgreed => _policyAgreed;
  double get policyScrollProgress => _policyScrollProgress;
  bool get googleConnected => _googleConnected;
  String? get googleAccountEmail => _googleAccountEmail;
  String? get googleErrorText => _googleErrorText;
  int get googleSkipTapCount => _googleSkipTapCount;
  int get permissionSkipTapCount => _permissionSkipTapCount;
  int? get permissionSkipTapStep => _permissionSkipTapStep;

  bool get primaryActionEnabled {
    if (busy || _awaitingExternalSettings) return false;
    return switch (_phase) {
      AppStartSetupPhase.permission => currentPermissionStep != null,
      AppStartSetupPhase.terms ||
      AppStartSetupPhase.privacy ||
      AppStartSetupPhase.accountDeletion =>
        _policyReadToEnd && _policyAgreed,
      AppStartSetupPhase.googleServices => !_googleConnected,
      _ => false,
    };
  }

  String get primaryActionLabel {
    return switch (_phase) {
      AppStartSetupPhase.permission => currentPermissionActionLabel,
      AppStartSetupPhase.terms ||
      AppStartSetupPhase.privacy ||
      AppStartSetupPhase.accountDeletion =>
        currentPolicySpec?.actionLabel ?? '계속',
      AppStartSetupPhase.googleServices =>
        _googleConnected ? '연결 완료' : 'Google 계정 연결',
      _ => '',
    };
  }

  void _handlePermissionChanged() {
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> initialize() async {
    if (_initializing || _disposed) return;
    _initializing = true;
    notifyListeners();
    AppStartDebugTrace.log('launcher_startup_setup', 'initialize_start');
    try {
      await _resolveAndPrepare();
      AppStartDebugTrace.log(
        'launcher_startup_setup',
        'initialize_complete',
        meta: debugMeta(),
      );
    } finally {
      _initializing = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _resolveAndPrepare() async {
    while (!_disposed) {
      final resolved = await AppStartSetupFlowResolver.resolve();
      _snapshot = resolved;
      _purpose = resolved.purpose;
      if (_purpose == null) {
        _phase = AppStartSetupPhase.purpose;
        notifyListeners();
        AppStartDebugTrace.log(
          'launcher_startup_setup',
          'purpose_missing',
          meta: resolved.toDebugMeta(),
        );
        return;
      }

      if (resolved.phase == AppStartSetupPhase.permissionNotice) {
        await AppStartFlowPrefs.setPermissionNoticeDone(true);
        AppStartDebugTrace.log(
          'launcher_startup_setup',
          'legacy_permission_notice_checkpoint_completed',
          meta: <String, Object?>{'purpose': _purpose!.storageValue},
        );
        continue;
      }

      _phase = resolved.phase;
      notifyListeners();
      AppStartDebugTrace.log(
        'launcher_startup_setup',
        'phase_resolved',
        meta: resolved.toDebugMeta(),
      );

      switch (_phase) {
        case AppStartSetupPhase.permission:
          final prepared = await _preparePermissionPhase();
          if (prepared) return;
          continue;
        case AppStartSetupPhase.terms:
        case AppStartSetupPhase.privacy:
        case AppStartSetupPhase.accountDeletion:
          _resetPolicyState();
          return;
        case AppStartSetupPhase.googleServices:
          await _prepareGooglePhase();
          return;
        case AppStartSetupPhase.complete:
          return;
        case AppStartSetupPhase.purpose:
        case AppStartSetupPhase.permissionNotice:
          return;
      }
    }
  }

  Future<bool> _preparePermissionPhase() async {
    final purpose = _purpose;
    if (purpose == null) return true;
    final steps = purpose.permissionStepNumbers
        .where((step) => step > 1)
        .toList(growable: false);
    _permissionSteps = steps;
    _permissionIndex = 0;
    _permissionSkipTapCount = 0;
    _permissionSkipTapStep = null;
    notifyListeners();
    AppStartDebugTrace.log(
      'launcher_startup_setup',
      'permission_profile_ready',
      meta: <String, Object?>{
        'purpose': purpose.storageValue,
        'steps': steps.join(','),
        'count': steps.length,
      },
    );
    if (steps.isEmpty) {
      await AppStartFlowPrefs.setPermissionTutorialDone(true);
      return false;
    }
    await _permissionCoordinator.refreshSteps(steps);
    final firstIncomplete = steps.indexWhere(
      (step) => !_permissionCoordinator.isGranted(step),
    );
    if (firstIncomplete < 0) {
      await AppStartFlowPrefs.setPermissionTutorialDone(true);
      AppStartDebugTrace.log(
        'launcher_startup_setup',
        'permission_profile_already_complete',
        meta: <String, Object?>{'purpose': purpose.storageValue},
      );
      return false;
    }
    _permissionIndex = firstIncomplete;
    notifyListeners();
    AppStartDebugTrace.log(
      'launcher_startup_setup',
      'permission_step_ready',
      meta: debugMeta(),
    );
    return true;
  }

  Future<void> _prepareGooglePhase() async {
    final done = await AppStartFlowPrefs.getGoogleServicesSetupDone();
    final identity = GoogleAuthSession.instance.currentIdentity;
    _googleConnected = done;
    _googleAccountEmail = done ? identity?.email : null;
    _googleErrorText = null;
    _googleSkipTapCount = 0;
    notifyListeners();
    AppStartDebugTrace.log(
      'launcher_startup_setup',
      'google_phase_ready',
      meta: <String, Object?>{
        'connected': done,
        'account': _googleAccountEmail ?? 'none',
      },
    );
  }

  void _resetPolicyState() {
    _policyReadToEnd = false;
    _policyAgreed = false;
    _policyScrollProgress = 0;
    notifyListeners();
  }

  void updatePolicyProgress(double progress, bool readToEnd) {
    if (currentPolicySpec == null || _disposed) return;
    final normalized = progress.clamp(0.0, 1.0).toDouble();
    final changed = (normalized - _policyScrollProgress).abs() >= 0.01 ||
        readToEnd != _policyReadToEnd;
    if (!changed) return;
    final reachedEnd = readToEnd && !_policyReadToEnd;
    _policyScrollProgress = normalized;
    _policyReadToEnd = readToEnd;
    if (!readToEnd) _policyAgreed = false;
    notifyListeners();
    if (reachedEnd) {
      AppStartDebugTrace.log(
        'launcher_startup_setup',
        'policy_document_read_to_end',
        meta: <String, Object?>{
          'kind': currentPolicySpec?.kind.name ?? 'unknown',
        },
      );
    }
  }

  void setPolicyAgreed(bool value) {
    if (!_policyReadToEnd || currentPolicySpec == null || _disposed) return;
    if (_policyAgreed == value) return;
    _policyAgreed = value;
    notifyListeners();
    AppStartDebugTrace.log(
      'launcher_startup_setup',
      'policy_agreement_toggled',
      meta: <String, Object?>{
        'kind': currentPolicySpec?.kind.name ?? 'unknown',
        'agreed': value,
      },
    );
  }

  Future<void> runPrimaryAction({required bool reduceMotion}) async {
    if (!primaryActionEnabled || _disposed) return;
    _busy = true;
    notifyListeners();
    final phaseAtStart = _phase;
    AppStartDebugTrace.log(
      'launcher_startup_setup',
      'primary_action_start',
      meta: debugMeta(),
    );
    try {
      switch (phaseAtStart) {
        case AppStartSetupPhase.permission:
          await _runPermissionAction(reduceMotion: reduceMotion);
          break;
        case AppStartSetupPhase.terms:
        case AppStartSetupPhase.privacy:
        case AppStartSetupPhase.accountDeletion:
          await _savePolicyAgreement();
          break;
        case AppStartSetupPhase.googleServices:
          await _connectGoogleServices();
          break;
        case AppStartSetupPhase.purpose:
        case AppStartSetupPhase.permissionNotice:
        case AppStartSetupPhase.complete:
          break;
      }
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
      AppStartDebugTrace.log(
        'launcher_startup_setup',
        'primary_action_complete',
        meta: debugMeta(),
      );
    }
  }

  Future<void> _runPermissionAction({required bool reduceMotion}) async {
    final step = currentPermissionStep;
    if (step == null) return;
    if (!_permissionCoordinator.isGranted(step)) {
      if (_permissionCoordinator.shouldOpenSettings(step) || step == 6) {
        _launchExternalSettings(step);
        return;
      }
      await _permissionCoordinator.requestStep(step);
      await _permissionCoordinator.refreshStep(step);
    }
    if (!_permissionCoordinator.isGranted(step)) {
      AppStartDebugTrace.log(
        'launcher_startup_setup',
        'permission_step_blocked',
        meta: debugMeta(),
      );
      return;
    }
    AppStartDebugTrace.log(
      'launcher_startup_setup',
      'permission_step_completed',
      meta: debugMeta(),
    );
    await Future<void>.delayed(
      reduceMotion ? Duration.zero : const Duration(milliseconds: 420),
    );
    await _advancePermissionStep();
  }

  void _launchExternalSettings(int step) {
    if (_disposed || _awaitingExternalSettings) return;
    _awaitingExternalSettings = true;
    _externalSettingsStep = step;
    _externalSettingsRefreshInProgress = false;
    notifyListeners();
    AppStartDebugTrace.log(
      'launcher_startup_setup',
      'permission_system_settings_launch',
      meta: debugMeta(),
    );
    unawaited(_openExternalSettings(step));
    AppStartDebugTrace.log(
      'launcher_startup_setup',
      'permission_system_settings_waiting',
      meta: debugMeta(),
    );
  }

  Future<void> _openExternalSettings(int step) async {
    try {
      await _permissionCoordinator.openSettingsForStep(step);
    } catch (error, stackTrace) {
      if (_disposed ||
          !_awaitingExternalSettings ||
          _externalSettingsStep != step) {
        return;
      }
      _awaitingExternalSettings = false;
      _externalSettingsStep = null;
      _externalSettingsRefreshInProgress = false;
      notifyListeners();
      AppStartDebugTrace.log(
        'launcher_startup_setup',
        'permission_system_settings_launch_failed',
        meta: <String, Object?>{
          ...debugMeta(),
          'error': error,
          'stackTrace': stackTrace,
        },
      );
    }
  }

  Future<void> _advancePermissionStep() async {
    if (_permissionSteps.isEmpty) return;
    for (var index = _permissionIndex + 1;
        index < _permissionSteps.length;
        index++) {
      final step = _permissionSteps[index];
      await _permissionCoordinator.refreshStep(step);
      if (!_permissionCoordinator.isGranted(step)) {
        _permissionIndex = index;
        _permissionSkipTapCount = 0;
        _permissionSkipTapStep = null;
        notifyListeners();
        AppStartDebugTrace.log(
          'launcher_startup_setup',
          'permission_step_entered',
          meta: debugMeta(),
        );
        return;
      }
    }
    _permissionSkipTapCount = 0;
    _permissionSkipTapStep = null;
    await AppStartFlowPrefs.setPermissionTutorialDone(true);
    AppStartDebugTrace.log(
      'launcher_startup_setup',
      'permission_flow_complete',
      meta: <String, Object?>{
        'purpose': _purpose?.storageValue ?? 'none',
      },
    );
    await _resolveAndPrepare();
  }

  Future<void> refreshAfterResume({required bool reduceMotion}) async {
    if (_disposed || _phase != AppStartSetupPhase.permission) return;
    if (busy && !_awaitingExternalSettings) return;
    final step = currentPermissionStep;
    if (step == null) return;

    if (_awaitingExternalSettings) {
      final expectedStep = _externalSettingsStep;
      if (expectedStep != null && expectedStep != step) {
        _awaitingExternalSettings = false;
        _externalSettingsStep = null;
        _externalSettingsRefreshInProgress = false;
        notifyListeners();
        AppStartDebugTrace.log(
          'launcher_startup_setup',
          'permission_system_settings_step_changed',
          meta: debugMeta(),
        );
        return;
      }
      if (_externalSettingsRefreshInProgress) return;
      _externalSettingsRefreshInProgress = true;
      notifyListeners();
      AppStartDebugTrace.log(
        'launcher_startup_setup',
        'permission_system_settings_resumed',
        meta: debugMeta(),
      );
      var refreshFailed = false;
      try {
        await _refreshExternalSettingsPermission(step);
      } catch (error, stackTrace) {
        refreshFailed = true;
        AppStartDebugTrace.log(
          'launcher_startup_setup',
          'permission_system_settings_refresh_failed',
          meta: <String, Object?>{
            ...debugMeta(),
            'error': error,
            'stackTrace': stackTrace,
          },
        );
      } finally {
        _awaitingExternalSettings = false;
        _externalSettingsStep = null;
        _externalSettingsRefreshInProgress = false;
        if (!_disposed) notifyListeners();
      }
      if (refreshFailed) return;
      final granted = _permissionCoordinator.isGranted(step);
      AppStartDebugTrace.log(
        'launcher_startup_setup',
        granted
            ? 'permission_system_settings_granted'
            : 'permission_system_settings_not_granted',
        meta: debugMeta(),
      );
      if (!granted) return;
      await Future<void>.delayed(
        reduceMotion ? Duration.zero : const Duration(milliseconds: 280),
      );
      await _advancePermissionStep();
      return;
    }

    await _permissionCoordinator.refreshStep(step);
    AppStartDebugTrace.log(
      'launcher_startup_setup',
      'permission_resume_refresh',
      meta: debugMeta(),
    );
    if (_permissionCoordinator.isGranted(step)) {
      await Future<void>.delayed(
        reduceMotion ? Duration.zero : const Duration(milliseconds: 280),
      );
      await _advancePermissionStep();
    }
  }

  Future<void> _refreshExternalSettingsPermission(int step) async {
    const retryDelays = <Duration>[
      Duration.zero,
      Duration(milliseconds: 120),
      Duration(milliseconds: 240),
    ];
    for (var index = 0; index < retryDelays.length; index++) {
      final delay = retryDelays[index];
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      AppStartDebugTrace.log(
        'launcher_startup_setup',
        'permission_system_settings_refresh_start',
        meta: <String, Object?>{
          ...debugMeta(),
          'attempt': index + 1,
          'attemptCount': retryDelays.length,
        },
      );
      await _permissionCoordinator.refreshStep(step);
      final granted = _permissionCoordinator.isGranted(step);
      AppStartDebugTrace.log(
        'launcher_startup_setup',
        'permission_system_settings_refresh_complete',
        meta: <String, Object?>{
          ...debugMeta(),
          'attempt': index + 1,
          'attemptCount': retryDelays.length,
          'granted': granted,
        },
      );
      if (granted) return;
    }
  }

  Future<void> _savePolicyAgreement() async {
    final spec = currentPolicySpec;
    if (spec == null || !_policyReadToEnd || !_policyAgreed) return;
    switch (spec.kind) {
      case PolicyConsentKind.termsOfService:
        await AppStartFlowPrefs.setTermsOfServiceAgreed(true);
        break;
      case PolicyConsentKind.privacyPolicy:
        await AppStartFlowPrefs.setPrivacyPolicyAgreed(true);
        break;
      case PolicyConsentKind.accountDeletion:
        await AppStartFlowPrefs.setAccountDeletionPolicyAgreed(true);
        break;
    }
    AppStartDebugTrace.log(
      'launcher_startup_setup',
      'policy_agreement_saved',
      meta: <String, Object?>{'kind': spec.kind.name},
    );
    await _resolveAndPrepare();
  }

  Future<void> _connectGoogleServices() async {
    _googleErrorText = null;
    notifyListeners();
    AppStartDebugTrace.log(
      'launcher_startup_setup',
      'google_oauth_start',
      meta: <String, Object?>{
        'scopeCount': AppScopes.values.length,
        'scopes': AppScopes.values.join(','),
      },
    );
    try {
      await GoogleAuthSession.instance.init(
        serverClientId: AuthConfig.webClientId,
      );
      final identity = await GoogleAuthSession.instance.authenticateAccount(
        bridgeFirebase: false,
      );
      final gmailSenderInitialized =
          await GmailSenderConfig.initializeFromEmailIfUnset(identity.email);
      await AppStartFlowPrefs.setGoogleServicesSetupDone(true);
      _googleConnected = true;
      _googleAccountEmail = identity.email;
      _googleErrorText = null;
      notifyListeners();
      AppStartDebugTrace.log(
        'launcher_startup_setup',
        'google_oauth_success',
        meta: <String, Object?>{
          'email': identity.email,
          'gmailSenderInitialized': gmailSenderInitialized,
          'scopeCount': AppScopes.values.length,
        },
      );
      await _resolveAndPrepare();
    } catch (error, stackTrace) {
      _googleErrorText = 'Google 서비스 연결을 완료하지 못했습니다.';
      notifyListeners();
      AppStartDebugTrace.log(
        'launcher_startup_setup',
        'google_oauth_failure',
        meta: <String, Object?>{
          'error': error,
          'stackTrace': stackTrace,
        },
      );
    }
  }

  Future<bool> registerPermissionTitleTap() async {
    if (_phase != AppStartSetupPhase.permission || busy || _disposed) {
      return false;
    }
    final step = currentPermissionStep;
    final spec = currentPermissionSpec;
    if (step == null || spec == null) return false;

    if (_permissionSkipTapStep != step) {
      _permissionSkipTapStep = step;
      _permissionSkipTapCount = 0;
    }

    _permissionSkipTapCount =
        (_permissionSkipTapCount + 1).clamp(0, 5).toInt();
    notifyListeners();
    AppStartDebugTrace.log(
      'launcher_startup_setup',
      'permission_skip_tap',
      meta: <String, Object?>{
        'step': step,
        'permissionKey': spec.keyName,
        'count': _permissionSkipTapCount,
        'required': 5,
        'actualGranted': _permissionCoordinator.isGranted(step),
        'awaitingExternalSettings': _awaitingExternalSettings,
      },
    );
    if (_permissionSkipTapCount < 5) return false;

    final actualGranted = _permissionCoordinator.isGranted(step);
    _busy = true;
    _awaitingExternalSettings = false;
    _externalSettingsStep = null;
    _externalSettingsRefreshInProgress = false;
    _permissionSkipTapCount = 0;
    _permissionSkipTapStep = null;
    notifyListeners();

    try {
      AppStartDebugTrace.log(
        'launcher_startup_setup',
        'permission_step_skipped_by_title_tap',
        meta: <String, Object?>{
          'step': step,
          'permissionKey': spec.keyName,
          'actualGranted': actualGranted,
          'skipByFiveTap': true,
        },
      );
      await _advancePermissionStep();
      return true;
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<bool> registerGoogleTitleTap() async {
    if (_phase != AppStartSetupPhase.googleServices || busy || _disposed) {
      return false;
    }
    _googleSkipTapCount = (_googleSkipTapCount + 1).clamp(0, 5).toInt();
    notifyListeners();
    AppStartDebugTrace.log(
      'launcher_startup_setup',
      'google_skip_tap',
      meta: <String, Object?>{
        'count': _googleSkipTapCount,
        'required': 5,
      },
    );
    if (_googleSkipTapCount < 5) return false;
    _busy = true;
    notifyListeners();
    try {
      await AppStartFlowPrefs.setGoogleServicesSetupSkipped(true);
      AppStartDebugTrace.log(
        'launcher_startup_setup',
        'google_setup_skipped',
        meta: <String, Object?>{
          'purpose': _purpose?.storageValue ?? 'none',
        },
      );
      await _resolveAndPrepare();
      return true;
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Map<String, Object?> debugMeta() {
    final permissionSpec = currentPermissionSpec;
    final policySpec = currentPolicySpec;
    return <String, Object?>{
      'phase': _phase.name,
      'purpose': _purpose?.storageValue ?? 'none',
      'busy': busy,
      'awaitingExternalSettings': _awaitingExternalSettings,
      'externalSettingsRefreshInProgress': _externalSettingsRefreshInProgress,
      'externalSettingsStep': _externalSettingsStep ?? 0,
      'externalSettingsPermission':
          _externalSettingsStep == null
              ? 'none'
              : appStartPermissionSpecForStep(_externalSettingsStep!).keyName,
      'permissionStep': currentPermissionStep ?? 0,
      'permissionKey': permissionSpec?.keyName ?? 'none',
      'permissionIndex': _permissionSteps.isEmpty ? 0 : _permissionIndex + 1,
      'permissionCount': _permissionSteps.length,
      'permissionStatus': currentPermissionStatus,
      'permissionSkipTapCount': _permissionSkipTapCount,
      'permissionSkipTapStep': _permissionSkipTapStep ?? 0,
      'policyKind': policySpec?.kind.name ?? 'none',
      'policyProgress': _policyScrollProgress.toStringAsFixed(3),
      'policyReadToEnd': _policyReadToEnd,
      'policyAgreed': _policyAgreed,
      'googleConnected': _googleConnected,
      'googleAccount': _googleAccountEmail ?? 'none',
      'googleSkipTapCount': _googleSkipTapCount,
    };
  }

  @override
  void dispose() {
    _disposed = true;
    _permissionCoordinator.removeListener(_handlePermissionChanged);
    _permissionCoordinator.dispose();
    super.dispose();
  }
}
