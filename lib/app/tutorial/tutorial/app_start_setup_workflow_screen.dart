import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design_system/common_ui/common_ui_components.dart';
import '../../../design_system/common_ui/common_ui_side_dock.dart';
import '../../../design_system/common_ui/common_ui_side_dock_frame.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../../features/selector/application/dev_auth.dart';
import '../../auth/google_auth_session.dart';
import '../../config/auth_config.dart';
import '../../config/gmail_sender_config.dart';
import '../../di/routes.dart';
import '../../init/app_start_debug_trace.dart';
import '../../init/app_start_flow_prefs.dart';
import '../../init/app_start_setup_flow_resolver.dart';
import '../../init/app_start_user_purpose.dart';
import '../policy/policy_documents.dart';
import 'app_start_permission_coordinator.dart';
import 'app_start_setup_specs.dart';

class AppStartSetupWorkflowScreen extends StatefulWidget {
  const AppStartSetupWorkflowScreen({super.key});

  @override
  State<AppStartSetupWorkflowScreen> createState() =>
      _AppStartSetupWorkflowScreenState();
}

class _AppStartSetupWorkflowScreenState
    extends State<AppStartSetupWorkflowScreen> with WidgetsBindingObserver {
  final AppStartPermissionCoordinator _permissionCoordinator =
      AppStartPermissionCoordinator();
  AppStartSetupSnapshot? _snapshot;
  AppStartSetupPhase _phase = AppStartSetupPhase.purpose;
  AppStartUserPurpose? _selectedPurpose;
  List<int> _permissionSteps = const <int>[];
  int _permissionIndex = 0;
  bool _loading = true;
  bool _phaseBusy = false;
  bool _permissionPreparing = false;
  bool _developerStatusOpen = false;
  bool _completeScheduled = false;
  bool _policyReadToEnd = false;
  bool _policyAgreed = false;
  double _policyScrollProgress = 0;
  bool _googleConnected = false;
  String? _googleAccountEmail;
  String? _googleErrorText;
  int _googleSkipTapCount = 0;
  bool _googleSkipping = false;
  Timer? _permissionAdvanceTimer;
  int _contentSerial = 0;
  int _transitionDirection = 1;
  bool _purposeCommitted = false;

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  bool get _isPolicyPhase =>
      _phase == AppStartSetupPhase.terms ||
      _phase == AppStartSetupPhase.privacy ||
      _phase == AppStartSetupPhase.accountDeletion;

  AppStartUserPurpose? get _effectivePurpose =>
      _selectedPurpose ?? _snapshot?.purpose;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _permissionCoordinator.addListener(_handlePermissionCoordinatorChange);
    DevAuth.isDevModeEnabled();
    AppStartDebugTrace.log('setup_workflow', 'screen_init');
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  void _handlePermissionCoordinatorChange() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _initialize() async {
    final snapshot = await AppStartSetupFlowResolver.resolve();
    if (!mounted) return;
    setState(() {
      _snapshot = snapshot;
      _selectedPurpose = snapshot.purpose;
      _phase = snapshot.phase;
      _purposeCommitted = snapshot.noticeDone || snapshot.permissionDone;
      _loading = false;
      _contentSerial++;
    });
    AppStartDebugTrace.log(
      'setup_workflow',
      'workflow_resolved',
      meta: snapshot.toDebugMeta(),
    );
    await _preparePhase(snapshot.phase);
  }

  Future<void> _reloadAndEnterResolvedPhase() async {
    final snapshot = await AppStartSetupFlowResolver.resolve();
    if (!mounted) return;
    _snapshot = snapshot;
    _selectedPurpose ??= snapshot.purpose;
    await _enterPhase(snapshot.phase, reason: 'resolver');
  }

  Future<void> _enterPhase(
    AppStartSetupPhase phase, {
    required String reason,
    int direction = 1,
  }) async {
    _permissionAdvanceTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _phase = phase;
      _phaseBusy = false;
      _transitionDirection = direction;
      _contentSerial++;
    });
    AppStartDebugTrace.log(
      'setup_workflow',
      'phase_entered',
      meta: <String, Object?>{
        'phase': phase.name,
        'reason': reason,
        'purpose': _effectivePurpose?.storageValue ?? 'none',
      },
    );
    await _preparePhase(phase);
  }

  Future<void> _preparePhase(AppStartSetupPhase phase) async {
    switch (phase) {
      case AppStartSetupPhase.purpose:
        return;
      case AppStartSetupPhase.permissionNotice:
        return;
      case AppStartSetupPhase.permission:
        await _preparePermissionPhase();
        return;
      case AppStartSetupPhase.terms:
      case AppStartSetupPhase.privacy:
      case AppStartSetupPhase.accountDeletion:
        _resetPolicyState();
        return;
      case AppStartSetupPhase.googleServices:
        await _prepareGooglePhase();
        return;
      case AppStartSetupPhase.complete:
        _scheduleCompleteNavigation();
        return;
    }
  }

  Future<void> _preparePermissionPhase() async {
    final purpose = _effectivePurpose;
    if (purpose == null) {
      await _enterPhase(AppStartSetupPhase.purpose, reason: 'missing_purpose');
      return;
    }
    final steps = purpose.permissionStepNumbers
        .where((step) => step > 1)
        .toList(growable: false);
    if (steps.isEmpty) {
      await AppStartFlowPrefs.setPermissionTutorialDone(true);
      await _reloadAndEnterResolvedPhase();
      return;
    }
    setState(() {
      _permissionSteps = steps;
      _permissionIndex = 0;
      _permissionPreparing = true;
    });
    AppStartDebugTrace.log(
      'setup_workflow',
      'permission_profile_ready',
      meta: <String, Object?>{
        'purpose': purpose.storageValue,
        'steps': steps.join(','),
        'count': steps.length,
      },
    );
    try {
      await _permissionCoordinator.refreshSteps(steps);
    } catch (error, stackTrace) {
      AppStartDebugTrace.log(
        'setup_workflow',
        'permission_profile_refresh_failure',
        meta: <String, Object?>{
          'error': error,
          'stackTrace': stackTrace,
        },
      );
    } finally {
      if (mounted && _phase == AppStartSetupPhase.permission) {
        setState(() => _permissionPreparing = false);
      }
    }
    if (!mounted || _phase != AppStartSetupPhase.permission) return;
    final firstIncomplete = steps.indexWhere(
      (step) => !_permissionCoordinator.isGranted(step),
    );
    if (firstIncomplete < 0) {
      await _finishPermissionPhase();
      return;
    }
    setState(() => _permissionIndex = firstIncomplete);
    AppStartDebugTrace.log(
      'setup_workflow',
      'permission_step_ready',
      meta: _permissionDebugMeta(),
    );
  }

  Future<void> _prepareGooglePhase() async {
    final done = await AppStartFlowPrefs.getGoogleServicesSetupDone();
    final identity = GoogleAuthSession.instance.currentIdentity;
    if (!mounted) return;
    setState(() {
      _googleConnected = done;
      _googleAccountEmail = done ? identity?.email : null;
      _googleErrorText = null;
      _googleSkipTapCount = 0;
      _googleSkipping = false;
    });
    AppStartDebugTrace.log(
      'setup_workflow',
      'google_phase_ready',
      meta: <String, Object?>{
        'connected': done,
        'account': _googleAccountEmail ?? 'none',
      },
    );
    if (done) {
      await _advanceAfterShortSuccess('google_already_connected');
    }
  }

  void _resetPolicyState() {
    setState(() {
      _policyReadToEnd = false;
      _policyAgreed = false;
      _policyScrollProgress = 0;
    });
  }

  void _handlePolicyProgress(
    PolicyConsentKind kind,
    double progress,
    bool readToEnd,
  ) {
    if (!mounted || !_isPolicyPhase || _policyKindForPhase(_phase) != kind) {
      return;
    }
    final changed = (progress - _policyScrollProgress).abs() >= 0.01 ||
        readToEnd != _policyReadToEnd;
    if (!changed) return;
    if (readToEnd && !_policyReadToEnd) {
      AppStartDebugTrace.log(
        'setup_workflow',
        'policy_document_read_to_end',
        meta: <String, Object?>{'phase': _phase.name},
      );
    }
    setState(() {
      _policyScrollProgress = progress;
      if (readToEnd) _policyReadToEnd = true;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    if (_phase == AppStartSetupPhase.permission) {
      _refreshPermissionAfterResume();
    }
  }

  Future<void> _refreshPermissionAfterResume() async {
    if (_permissionPreparing || _permissionCoordinator.busy) return;
    if (_permissionSteps.isEmpty ||
        _permissionIndex < 0 ||
        _permissionIndex >= _permissionSteps.length) {
      return;
    }
    final step = _permissionSteps[_permissionIndex];
    AppStartDebugTrace.log(
      'setup_workflow',
      'permission_resume_refresh_start',
      meta: _permissionDebugMeta(),
    );
    await _permissionCoordinator.refreshStep(step);
    if (!mounted || _phase != AppStartSetupPhase.permission) return;
    AppStartDebugTrace.log(
      'setup_workflow',
      'permission_resume_refresh_complete',
      meta: _permissionDebugMeta(),
    );
    if (_permissionCoordinator.isGranted(step)) {
      _schedulePermissionAdvance(step);
    }
  }

  Map<String, Object?> _permissionDebugMeta() {
    if (_permissionSteps.isEmpty ||
        _permissionIndex < 0 ||
        _permissionIndex >= _permissionSteps.length) {
      return <String, Object?>{
        'permissionStep': 'none',
        'permissionIndex': '0/0',
      };
    }
    final step = _permissionSteps[_permissionIndex];
    return <String, Object?>{
      'permissionStep': step,
      'permissionKey': appStartPermissionSpecForStep(step).keyName,
      'permissionIndex': '${_permissionIndex + 1}/${_permissionSteps.length}',
      'permissionStatus': _permissionCoordinator.statusLabel(step),
      'permissionBusy': _permissionCoordinator.busy,
      'permissionPreparing': _permissionPreparing,
    };
  }

  Future<void> _selectPurpose(AppStartUserPurpose purpose) async {
    if (_phaseBusy || _phase != AppStartSetupPhase.purpose) return;
    if (_selectedPurpose != purpose) {
      await HapticFeedback.selectionClick();
      if (!mounted) return;
      setState(() => _selectedPurpose = purpose);
      AppStartDebugTrace.log(
        'setup_workflow',
        'purpose_selected',
        meta: <String, Object?>{
          'purpose': purpose.storageValue,
          'permissionCount': _actualPermissionSteps(purpose).length,
          'followUpCount': purpose.skipsPolicyAndPostSetup ? 0 : 2,
        },
      );
    }
  }

  Future<void> _continueToNotice() async {
    final purpose = _selectedPurpose;
    if (purpose == null || _phaseBusy) return;
    AppStartDebugTrace.log(
      'setup_workflow',
      'purpose_preview_confirmed',
      meta: <String, Object?>{
        'purpose': purpose.storageValue,
        'persisted': false,
      },
    );
    await _enterPhase(
      AppStartSetupPhase.permissionNotice,
      reason: 'purpose_preview_confirmed',
    );
  }

  Future<void> _returnToPurpose() async {
    if (_phaseBusy || _phase != AppStartSetupPhase.permissionNotice) return;
    final purpose = _effectivePurpose;
    setState(() {
      _phaseBusy = true;
      _purposeCommitted = false;
    });
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    AppStartDebugTrace.log(
      'setup_workflow',
      'purpose_selection_reopened',
      meta: <String, Object?>{
        'purpose': purpose?.storageValue ?? 'none',
        'from': AppStartSetupPhase.permissionNotice.name,
      },
    );
    await _enterPhase(
      AppStartSetupPhase.purpose,
      reason: 'notice_back_to_purpose',
      direction: -1,
    );
  }

  Future<void> _completeNotice() async {
    final purpose = _effectivePurpose;
    if (_phaseBusy || purpose == null) return;
    setState(() => _phaseBusy = true);
    AppStartDebugTrace.log(
      'setup_workflow',
      'permission_notice_complete_start',
      meta: <String, Object?>{
        'purpose': purpose.storageValue,
        'purposeCommitted': false,
      },
    );
    try {
      await AppStartFlowPrefs.setUserPurpose(purpose);
      await AppStartFlowPrefs.setPermissionNoticeDone(true);
      final snapshot = await AppStartSetupFlowResolver.resolve();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _selectedPurpose = purpose;
        _purposeCommitted = true;
        _phaseBusy = false;
      });
      AppStartDebugTrace.log(
        'setup_workflow',
        'purpose_committed',
        meta: <String, Object?>{
          'purpose': purpose.storageValue,
          'commitBoundary': 'permission_notice_start',
        },
      );
      AppStartDebugTrace.log(
        'setup_workflow',
        'permission_notice_complete_success',
        meta: <String, Object?>{'purpose': purpose.storageValue},
      );
      await _enterPhase(
        AppStartSetupPhase.permission,
        reason: 'notice_completed',
      );
    } catch (error, stackTrace) {
      AppStartDebugTrace.log(
        'setup_workflow',
        'permission_notice_complete_failure',
        meta: <String, Object?>{
          'purpose': purpose.storageValue,
          'error': error,
          'stackTrace': stackTrace,
        },
      );
      if (mounted) setState(() => _phaseBusy = false);
    }
  }

  Future<void> _handlePermissionPrimaryAction() async {
    if (_permissionPreparing ||
        _permissionCoordinator.busy ||
        _permissionSteps.isEmpty) {
      return;
    }
    final step = _permissionSteps[_permissionIndex];
    if (_permissionCoordinator.isGranted(step)) {
      _schedulePermissionAdvance(step);
      return;
    }
    AppStartDebugTrace.log(
      'setup_workflow',
      'permission_action_start',
      meta: _permissionDebugMeta(),
    );
    try {
      if (_permissionCoordinator.shouldOpenSettings(step)) {
        await _permissionCoordinator.openSettingsForStep(step);
        AppStartDebugTrace.log(
          'setup_workflow',
          'permission_settings_opened',
          meta: _permissionDebugMeta(),
        );
        return;
      }
      final granted = await _permissionCoordinator.requestStep(step);
      if (!mounted || _phase != AppStartSetupPhase.permission) return;
      AppStartDebugTrace.log(
        'setup_workflow',
        'permission_action_result',
        meta: <String, Object?>{
          ..._permissionDebugMeta(),
          'granted': granted,
        },
      );
      if (granted) {
        _schedulePermissionAdvance(step);
      }
    } catch (error, stackTrace) {
      AppStartDebugTrace.log(
        'setup_workflow',
        'permission_action_failure',
        meta: <String, Object?>{
          ..._permissionDebugMeta(),
          'error': error,
          'stackTrace': stackTrace,
        },
      );
    }
  }

  void _schedulePermissionAdvance(int step) {
    _permissionAdvanceTimer?.cancel();
    AppStartDebugTrace.log(
      'setup_workflow',
      'permission_step_completed',
      meta: _permissionDebugMeta(),
    );
    _permissionAdvanceTimer = Timer(
      _reduceMotion ? Duration.zero : const Duration(milliseconds: 420),
      () async {
        if (!mounted || _phase != AppStartSetupPhase.permission) return;
        if (_permissionSteps.isEmpty ||
            _permissionIndex >= _permissionSteps.length ||
            _permissionSteps[_permissionIndex] != step ||
            !_permissionCoordinator.isGranted(step)) {
          return;
        }
        if (_permissionIndex >= _permissionSteps.length - 1) {
          await _finishPermissionPhase();
          return;
        }
        setState(() {
          _permissionIndex++;
          _contentSerial++;
        });
        final nextStep = _permissionSteps[_permissionIndex];
        await _permissionCoordinator.refreshStep(nextStep);
        if (!mounted || _phase != AppStartSetupPhase.permission) return;
        AppStartDebugTrace.log(
          'setup_workflow',
          'permission_step_entered',
          meta: _permissionDebugMeta(),
        );
        if (_permissionCoordinator.isGranted(nextStep)) {
          _schedulePermissionAdvance(nextStep);
        }
      },
    );
  }

  Future<void> _finishPermissionPhase() async {
    if (_phaseBusy) return;
    setState(() => _phaseBusy = true);
    AppStartDebugTrace.log(
      'setup_workflow',
      'permission_flow_complete_start',
      meta: <String, Object?>{
        'purpose': _effectivePurpose?.storageValue ?? 'none',
      },
    );
    try {
      await AppStartFlowPrefs.setPermissionTutorialDone(true);
      if (!mounted) return;
      setState(() => _phaseBusy = false);
      AppStartDebugTrace.log(
        'setup_workflow',
        'permission_flow_complete_success',
      );
      await _reloadAndEnterResolvedPhase();
    } catch (error, stackTrace) {
      AppStartDebugTrace.log(
        'setup_workflow',
        'permission_flow_complete_failure',
        meta: <String, Object?>{
          'error': error,
          'stackTrace': stackTrace,
        },
      );
      if (mounted) setState(() => _phaseBusy = false);
    }
  }

  PolicyConsentKind _policyKindForPhase(AppStartSetupPhase phase) {
    return switch (phase) {
      AppStartSetupPhase.terms => PolicyConsentKind.termsOfService,
      AppStartSetupPhase.privacy => PolicyConsentKind.privacyPolicy,
      AppStartSetupPhase.accountDeletion => PolicyConsentKind.accountDeletion,
      _ => throw StateError('not_policy_phase:${phase.name}'),
    };
  }

  Future<void> _savePolicyAgreement() async {
    if (!_isPolicyPhase || !_policyReadToEnd || !_policyAgreed || _phaseBusy) {
      return;
    }
    final kind = _policyKindForPhase(_phase);
    setState(() => _phaseBusy = true);
    AppStartDebugTrace.log(
      'setup_workflow',
      'policy_agreement_save_start',
      meta: <String, Object?>{'kind': kind.name},
    );
    try {
      switch (kind) {
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
      if (!mounted) return;
      setState(() => _phaseBusy = false);
      AppStartDebugTrace.log(
        'setup_workflow',
        'policy_agreement_save_success',
        meta: <String, Object?>{'kind': kind.name},
      );
      await _reloadAndEnterResolvedPhase();
    } catch (error, stackTrace) {
      AppStartDebugTrace.log(
        'setup_workflow',
        'policy_agreement_save_failure',
        meta: <String, Object?>{
          'kind': kind.name,
          'error': error,
          'stackTrace': stackTrace,
        },
      );
      if (mounted) setState(() => _phaseBusy = false);
    }
  }

  Future<void> _connectGoogleServices() async {
    if (_phaseBusy || _googleConnected || _googleSkipping) return;
    setState(() {
      _phaseBusy = true;
      _googleErrorText = null;
    });
    AppStartDebugTrace.log(
      'setup_workflow',
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
      if (!mounted || _googleSkipping) return;
      await AppStartFlowPrefs.setGoogleServicesSetupDone(true);
      if (!mounted) return;
      setState(() {
        _googleConnected = true;
        _googleAccountEmail = identity.email;
        _googleErrorText = null;
        _phaseBusy = false;
      });
      AppStartDebugTrace.log(
        'setup_workflow',
        'google_oauth_success',
        meta: <String, Object?>{
          'email': identity.email,
          'gmailSenderInitialized': gmailSenderInitialized,
          'scopeCount': AppScopes.values.length,
        },
      );
      await _advanceAfterShortSuccess('google_connected');
    } catch (error, stackTrace) {
      if (!mounted || _googleSkipping) return;
      setState(() {
        _googleErrorText = 'Google 서비스 연결을 완료하지 못했습니다.';
        _phaseBusy = false;
      });
      AppStartDebugTrace.log(
        'setup_workflow',
        'google_oauth_failure',
        meta: <String, Object?>{
          'error': error,
          'stackTrace': stackTrace,
        },
      );
    }
  }

  Future<void> _handleGoogleTitleTap() async {
    if (_phaseBusy || _googleConnected || _googleSkipping) return;
    final next = (_googleSkipTapCount + 1).clamp(0, 5).toInt();
    setState(() => _googleSkipTapCount = next);
    AppStartDebugTrace.log(
      'setup_workflow',
      'google_skip_tap',
      meta: <String, Object?>{'count': next, 'required': 5},
    );
    if (next < 5) {
      await HapticFeedback.selectionClick();
      return;
    }
    setState(() {
      _googleSkipping = true;
      _phaseBusy = true;
      _googleErrorText = null;
    });
    await HapticFeedback.mediumImpact();
    await AppStartFlowPrefs.setGoogleServicesSetupSkipped(true);
    AppStartDebugTrace.log(
      'setup_workflow',
      'google_setup_skipped',
      meta: <String, Object?>{
        'purpose': _effectivePurpose?.storageValue ?? 'none',
      },
    );
    if (!mounted) return;
    setState(() => _phaseBusy = false);
    await AppStartDebugTrace.showDeveloperStatus(
      context,
      title: '초기 설정 개발자 상태',
      description: 'Google 서비스 연결 스킵 상태의 debugPrint 코드를 복사할 수 있습니다.',
      scope: 'setup_workflow',
    );
    if (!mounted) return;
    await _reloadAndEnterResolvedPhase();
  }

  Future<void> _advanceAfterShortSuccess(String reason) async {
    AppStartDebugTrace.log(
      'setup_workflow',
      'phase_success_hold',
      meta: <String, Object?>{'reason': reason, 'phase': _phase.name},
    );
    await Future<void>.delayed(
      _reduceMotion ? Duration.zero : const Duration(milliseconds: 460),
    );
    if (!mounted) return;
    await _reloadAndEnterResolvedPhase();
  }

  void _scheduleCompleteNavigation() {
    if (_completeScheduled) return;
    _completeScheduled = true;
    AppStartDebugTrace.log(
      'setup_workflow',
      'workflow_complete',
      meta: <String, Object?>{
        'purpose': _effectivePurpose?.storageValue ?? 'legacy_unknown',
      },
    );
    Future<void>.delayed(
      _reduceMotion ? Duration.zero : const Duration(milliseconds: 720),
      () {
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.startGate,
          (route) => false,
        );
      },
    );
  }

  Future<void> _showDeveloperStatus() async {
    if (_developerStatusOpen) return;
    setState(() => _developerStatusOpen = true);
    final media = MediaQuery.maybeOf(context);
    final viewportHeight = media?.size.height ?? 0;
    final textScale = media?.textScaler.scale(1.0) ?? 1.0;
    final meta = <String, Object?>{
      'workflowProfile': 'serial_single_route_list_surface_optional_left_sidedock',
      'phase': _phase.name,
      'purpose': _effectivePurpose?.storageValue ?? 'none',
      'selectedPurpose': _selectedPurpose?.storageValue ?? 'none',
      'persistedPurpose': _snapshot?.purpose?.storageValue ?? 'none',
      'purposeSelectionMode': 'editable_until_permission_notice_start',
      'viewportHeight': viewportHeight.toStringAsFixed(1),
      'textScale': textScale.toStringAsFixed(2),
      'bodyScrollMode': _isPolicyPhase ? 'policy_document' : 'adaptive',
      'sideDock': 'optional_left_preview',
      'phaseBusy': _phaseBusy,
      'purposeCommitted': _purposeCommitted,
      'noticeBackSupported': true,
      'transitionDirection': _transitionDirection > 0 ? 'forward' : 'backward',
      'reduceMotion': _reduceMotion,
      'policyReadToEnd': _policyReadToEnd,
      'policyProgress': _policyScrollProgress.toStringAsFixed(3),
      'policyAgreed': _policyAgreed,
      'googleConnected': _googleConnected,
      'googleAccount': _googleAccountEmail ?? 'none',
      'googleSkipTapCount': _googleSkipTapCount,
      ..._permissionDebugMeta(),
    };
    AppStartDebugTrace.log(
      'setup_workflow',
      'developer_status_request',
      meta: meta,
    );
    await AppStartDebugTrace.showDeveloperStatus(
      context,
      title: '초기 설정 개발자 상태',
      description: '직렬 초기 설정 워크플로우의 debugPrint 코드를 복사할 수 있습니다.',
      scope: 'setup_workflow',
    );
    if (!mounted) return;
    setState(() => _developerStatusOpen = false);
  }

  List<int> _actualPermissionSteps(AppStartUserPurpose purpose) {
    return purpose.permissionStepNumbers
        .where((step) => step > 1)
        .toList(growable: false);
  }

  int _followUpCount(AppStartUserPurpose purpose) {
    return purpose.skipsPolicyAndPostSetup ? 0 : 2;
  }

  IconData _purposeIcon(AppStartUserPurpose purpose) {
    return switch (purpose) {
      AppStartUserPurpose.branchEmployee => Icons.apartment_rounded,
      AppStartUserPurpose.headOfficeEmployee => Icons.business_center_rounded,
      AppStartUserPurpose.tabletInstallation => Icons.tablet_android_rounded,
      AppStartUserPurpose.commuteRecorder => Icons.schedule_rounded,
      AppStartUserPurpose.personal => Icons.person_rounded,
    };
  }

  Future<void> _showPurposePreview() async {
    final purpose = _selectedPurpose;
    if (purpose == null) return;
    final permissionSpecs = _actualPermissionSteps(purpose)
        .map(appStartPermissionSpecForStep)
        .toList(growable: false);
    AppStartDebugTrace.log(
      'setup_workflow',
      'purpose_preview_open',
      meta: <String, Object?>{
        'purpose': purpose.storageValue,
        'permissionCount': permissionSpecs.length,
        'followUpCount': _followUpCount(purpose),
      },
    );
    await showCommonLeftSideDock<void>(
      context: context,
      barrierLabel: '${purpose.label} 설정 미리보기',
      builder: (dockContext) {
        return CommonSideDockFrame(
          title: purpose.label,
          subtitle: purpose.description,
          icon: _purposeIcon(purpose),
          onClose: () => Navigator.of(dockContext).pop(),
          child: _PurposePreviewDockBody(
            permissionSpecs: permissionSpecs,
            includeFollowUp: !purpose.skipsPolicyAndPostSetup,
          ),
        );
      },
    );
    AppStartDebugTrace.log(
      'setup_workflow',
      'purpose_preview_close',
      meta: <String, Object?>{'purpose': purpose.storageValue},
    );
  }

  String _phaseContentKey() {
    if (_phase == AppStartSetupPhase.permission && _permissionSteps.isNotEmpty) {
      return '${_phase.name}_${_permissionSteps[_permissionIndex]}_$_contentSerial';
    }
    return '${_phase.name}_$_contentSerial';
  }

  Widget _buildPurposePhase(BuildContext context) {
    final selected = _selectedPurpose;
    return _AdaptiveWorkflowBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _PhaseHeader(
            icon: Icons.tune_rounded,
            title: '사용 환경을 선택해 주세요',
            description: '선택한 환경에 필요한 설정만 순서대로 진행합니다.',
          ),
          const SizedBox(height: 20),
          _WorkflowListSurface(
            children: [
              for (var i = 0; i < AppStartUserPurpose.values.length; i++) ...[
                _PurposeSelectionRow(
                  purpose: AppStartUserPurpose.values[i],
                  icon: _purposeIcon(AppStartUserPurpose.values[i]),
                  selected: selected == AppStartUserPurpose.values[i],
                  permissionCount:
                      _actualPermissionSteps(AppStartUserPurpose.values[i])
                          .length,
                  onTap: () => _selectPurpose(AppStartUserPurpose.values[i]),
                ),
                if (i < AppStartUserPurpose.values.length - 1)
                  const _WorkflowDivider(),
              ],
            ],
          ),
          if (selected != null) ...[
            const SizedBox(height: 14),
            Text(
              '${selected.label} · 필수 설정 ${_actualPermissionSteps(selected).length}개 · 후속 설정 ${_followUpCount(selected)}개',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: CommonUiTheme.of(context).textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNoticePhase(BuildContext context) {
    return const _AdaptiveWorkflowBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PhaseHeader(
            icon: Icons.verified_user_outlined,
            title: '설정을 시작합니다',
            description: '필요한 권한을 하나씩 완료하면 다음 작업이 자동으로 이어집니다.',
          ),
          SizedBox(height: 20),
          _WorkflowListSurface(
            children: [
              _WorkflowInfoRow(
                icon: Icons.settings_suggest_outlined,
                title: '권한 설정 유지',
                description: '앱에서 안내한 설정과 다르게 기기의 권한을 임의로 변경할 경우 서비스 이용에 문제가 발생할 수 있습니다.',
              ),
              _WorkflowDivider(),
              _WorkflowInfoRow(
                icon: Icons.report_gmailerrorred_rounded,
                title: '이용 장애',
                description: '이로 인한 이용 장애에 대해서는 책임지지 않습니다.',
              ),
              _WorkflowDivider(),
              _WorkflowInfoRow(
                icon: Icons.restart_alt_rounded,
                title: '초기 설정 재진행',
                description: '문제가 발생한 경우 앱 캐시 및 데이터를 삭제한 뒤 재설치하여 초기 설정을 다시 진행해 주세요.',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionPhase(BuildContext context) {
    if (_permissionSteps.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final step = _permissionSteps[_permissionIndex];
    final spec = appStartPermissionSpecForStep(step);
    final status = _permissionCoordinator.statusLabel(step);
    final granted = _permissionCoordinator.isGranted(step);
    final tokens = CommonUiTheme.of(context);
    return _AdaptiveWorkflowBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WorkflowProgress(
            label: '권한 설정',
            index: _permissionIndex + 1,
            total: _permissionSteps.length,
          ),
          const SizedBox(height: 18),
          _PhaseHeader(
            icon: spec.icon,
            title: spec.title,
            description: spec.description,
            success: granted,
          ),
          const SizedBox(height: 20),
          _WorkflowListSurface(
            children: [
              _WorkflowValueRow(
                label: '현재 상태',
                value: status,
                valueColor: granted
                    ? tokens.success
                    : status == '영구 거부됨'
                        ? tokens.danger
                        : tokens.warning,
              ),
              const _WorkflowDivider(),
              _WorkflowValueRow(
                label: '진행 순서',
                value: '${_permissionIndex + 1} / ${_permissionSteps.length}',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPolicyPhase(BuildContext context) {
    final kind = _policyKindForPhase(_phase);
    final spec = policyDocumentOf(kind);
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WorkflowProgress(
            label: '정책 확인',
            index: spec.step,
            total: spec.totalSteps,
          ),
          const SizedBox(height: 14),
          Text(
            spec.title,
            style: textTheme.headlineSmall?.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            spec.subtitle,
            style: textTheme.bodyMedium?.copyWith(
              color: tokens.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: _PolicyDocumentView(
              spec: spec,
              onProgress: _handlePolicyProgress,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGooglePhase(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return _AdaptiveWorkflowBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleGoogleTitleTap,
            child: _PhaseHeader(
              icon: Icons.security_rounded,
              title: 'Google 서비스 연결',
              description: '업무에 필요한 Google 서비스를 한 번의 승인 과정으로 연결합니다.',
              success: _googleConnected,
            ),
          ),
          const SizedBox(height: 20),
          _WorkflowListSurface(
            children: [
              for (var i = 0; i < appStartGoogleServiceSpecs.length; i++) ...[
                _WorkflowInfoRow(
                  icon: appStartGoogleServiceSpecs[i].icon,
                  title: appStartGoogleServiceSpecs[i].title,
                  description: appStartGoogleServiceSpecs[i].description,
                  trailing: _googleConnected ? '연결됨' : '',
                  trailingColor: _googleConnected ? tokens.success : null,
                ),
                if (i < appStartGoogleServiceSpecs.length - 1)
                  const _WorkflowDivider(),
              ],
            ],
          ),
          if (_googleAccountEmail != null) ...[
            const SizedBox(height: 12),
            _WorkflowListSurface(
              children: [
                _WorkflowValueRow(
                  label: '연결 계정',
                  value: _googleAccountEmail!,
                  valueColor: tokens.success,
                ),
              ],
            ),
          ],
          if (_googleErrorText != null) ...[
            const SizedBox(height: 12),
            Text(
              _googleErrorText!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: tokens.danger,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompletePhase(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: _reduceMotion ? Duration.zero : CommonUiMotion.component,
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: tokens.successContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_rounded,
                size: 38,
                color: tokens.onSuccessContainer,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '초기 설정이 완료되었습니다',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhaseBody(BuildContext context) {
    return switch (_phase) {
      AppStartSetupPhase.purpose => _buildPurposePhase(context),
      AppStartSetupPhase.permissionNotice => _buildNoticePhase(context),
      AppStartSetupPhase.permission => _buildPermissionPhase(context),
      AppStartSetupPhase.terms => _buildPolicyPhase(context),
      AppStartSetupPhase.privacy => _buildPolicyPhase(context),
      AppStartSetupPhase.accountDeletion => _buildPolicyPhase(context),
      AppStartSetupPhase.googleServices => _buildGooglePhase(context),
      AppStartSetupPhase.complete => _buildCompletePhase(context),
    };
  }

  Widget _buildPurposeFooter(BuildContext context) {
    final selected = _selectedPurpose;
    return _WorkflowFooter(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 440;
          final preview = CommonButton(
            label: '설정 미리보기',
            icon: Icons.view_list_rounded,
            variant: CommonButtonVariant.tertiary,
            onPressed: selected == null || _phaseBusy ? null : _showPurposePreview,
            expand: true,
          );
          final start = CommonButton(
            label: selected == null ? '이 환경으로 시작' : '${selected.label}으로 시작',
            icon: Icons.arrow_forward_rounded,
            onPressed: selected == null || _phaseBusy ? null : _continueToNotice,
            loading: _phaseBusy,
            expand: true,
            haptic: CommonHaptic.selection,
          );
          if (stacked) {
            return Column(
              children: [
                start,
                const SizedBox(height: 6),
                preview,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: preview),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: start),
            ],
          );
        },
      ),
    );
  }

  Widget _buildNoticeFooter(BuildContext context) {
    return _WorkflowFooter(
      child: CommonButton(
        label: '설정 시작',
        icon: Icons.arrow_forward_rounded,
        onPressed: _phaseBusy ? null : _completeNotice,
        loading: _phaseBusy,
        expand: true,
        haptic: CommonHaptic.selection,
      ),
    );
  }

  Widget _buildPermissionFooter(BuildContext context) {
    if (_permissionSteps.isEmpty) return const SizedBox.shrink();
    final step = _permissionSteps[_permissionIndex];
    final granted = _permissionCoordinator.isGranted(step);
    return _WorkflowFooter(
      child: CommonButton(
        label: _permissionPreparing
            ? '상태 확인 중'
            : (_phaseBusy || _permissionCoordinator.busy)
                ? '처리 중'
                : _permissionCoordinator.actionLabel(step),
        icon: granted
            ? Icons.check_rounded
            : _permissionCoordinator.shouldOpenSettings(step) || step == 6
                ? Icons.settings_rounded
                : Icons.verified_user_rounded,
        variant: granted
            ? CommonButtonVariant.success
            : CommonButtonVariant.primary,
        onPressed: _permissionPreparing ||
                _phaseBusy ||
                _permissionCoordinator.busy ||
                granted
            ? null
            : _handlePermissionPrimaryAction,
        loading: _permissionPreparing ||
            _phaseBusy ||
            _permissionCoordinator.busy,
        preserveVariantWhenDisabled: granted,
        expand: true,
        haptic: CommonHaptic.selection,
      ),
    );
  }

  Widget _buildPolicyFooter(BuildContext context) {
    final spec = policyDocumentOf(_policyKindForPhase(_phase));
    final tokens = CommonUiTheme.of(context);
    return _WorkflowFooter(
      child: Column(
        children: [
          _WorkflowListSurface(
            children: [
              CheckboxListTile(
                value: _policyAgreed,
                onChanged: _policyReadToEnd && !_phaseBusy
                    ? (value) {
                        final agreed = value ?? false;
                        setState(() => _policyAgreed = agreed);
                        AppStartDebugTrace.log(
                          'setup_workflow',
                          'policy_agreement_toggle',
                          meta: <String, Object?>{
                            'phase': _phase.name,
                            'agreed': agreed,
                          },
                        );
                      }
                    : null,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                dense: true,
                title: Text(
                  spec.agreeLabel,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: _policyReadToEnd
                            ? tokens.textPrimary
                            : tokens.textDisabled,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          CommonButton(
            label: '동의하고 계속',
            icon: Icons.arrow_forward_rounded,
            onPressed: _policyAgreed && !_phaseBusy ? _savePolicyAgreement : null,
            loading: _phaseBusy,
            expand: true,
            haptic: CommonHaptic.selection,
          ),
        ],
      ),
    );
  }

  Widget _buildGoogleFooter(BuildContext context) {
    return _WorkflowFooter(
      child: CommonButton(
        label: _googleConnected
            ? '연결 완료'
            : _googleErrorText == null
                ? 'Google 계정 연결'
                : '다시 연결',
        icon: _googleConnected ? Icons.check_rounded : Icons.login_rounded,
        variant: _googleConnected
            ? CommonButtonVariant.success
            : CommonButtonVariant.primary,
        onPressed: _phaseBusy || _googleConnected || _googleSkipping
            ? null
            : _connectGoogleServices,
        loading: _phaseBusy,
        preserveVariantWhenDisabled: _googleConnected,
        expand: true,
        haptic: CommonHaptic.selection,
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return switch (_phase) {
      AppStartSetupPhase.purpose => _buildPurposeFooter(context),
      AppStartSetupPhase.permissionNotice => _buildNoticeFooter(context),
      AppStartSetupPhase.permission => _buildPermissionFooter(context),
      AppStartSetupPhase.terms => _buildPolicyFooter(context),
      AppStartSetupPhase.privacy => _buildPolicyFooter(context),
      AppStartSetupPhase.accountDeletion => _buildPolicyFooter(context),
      AppStartSetupPhase.googleServices => _buildGoogleFooter(context),
      AppStartSetupPhase.complete => const SizedBox.shrink(),
    };
  }

  @override
  void dispose() {
    _permissionAdvanceTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _permissionCoordinator.removeListener(_handlePermissionCoordinatorChange);
    _permissionCoordinator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CommonUiScope(
      child: Builder(
        builder: (context) {
          final tokens = CommonUiTheme.of(context);
          final brightness = tokens.isDark ? Brightness.light : Brightness.dark;
          final contentKey = _phaseContentKey();
          return PopScope(
            canPop: false,
            onPopInvoked: (didPop) {
              if (didPop || _phase != AppStartSetupPhase.permissionNotice) {
                return;
              }
              _returnToPurpose();
            },
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: tokens.surface,
                statusBarIconBrightness: brightness,
                statusBarBrightness:
                    tokens.isDark ? Brightness.dark : Brightness.light,
                systemNavigationBarColor: tokens.canvas,
                systemNavigationBarIconBrightness: brightness,
                systemNavigationBarDividerColor: tokens.borderSubtle,
              ),
              child: Scaffold(
                backgroundColor: tokens.canvas,
                appBar: AppBar(
                  title: const Text('초기 설정'),
                  centerTitle: true,
                  automaticallyImplyLeading: false,
                  leading: _phase == AppStartSetupPhase.permissionNotice
                      ? IconButton(
                          onPressed: _phaseBusy ? null : _returnToPurpose,
                          icon: const Icon(Icons.arrow_back_rounded),
                        )
                      : null,
                  actions: [
                    ValueListenableBuilder<bool>(
                      valueListenable: DevAuth.devModeEnabled,
                      builder: (context, enabled, child) {
                        if (!enabled) return const SizedBox.shrink();
                        return IconButton(
                          onPressed: _developerStatusOpen
                              ? null
                              : _showDeveloperStatus,
                          icon: const Icon(Icons.terminal_rounded),
                        );
                      },
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
                body: SafeArea(
                  child: _loading
                      ? Center(
                          child: CircularProgressIndicator(color: tokens.accent),
                        )
                      : Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 820),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: _ForwardPhaseSwitcher(
                                    currentKey: contentKey,
                                    reduceMotion: _reduceMotion,
                                    direction: _transitionDirection,
                                    child: KeyedSubtree(
                                      key: ValueKey<String>(contentKey),
                                      child: _buildPhaseBody(context),
                                    ),
                                  ),
                                ),
                                AnimatedSwitcher(
                                  duration: _reduceMotion
                                      ? Duration.zero
                                      : CommonUiMotion.component,
                                  child: KeyedSubtree(
                                    key: ValueKey<String>('footer_${_phase.name}'),
                                    child: _buildFooter(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ForwardPhaseSwitcher extends StatelessWidget {
  const _ForwardPhaseSwitcher({
    required this.currentKey,
    required this.reduceMotion,
    required this.direction,
    required this.child,
  });

  final String currentKey;
  final bool reduceMotion;
  final int direction;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
      reverseDuration: reduceMotion ? Duration.zero : CommonUiMotion.component,
      switchInCurve: CommonUiMotion.enter,
      switchOutCurve: CommonUiMotion.exit,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          fit: StackFit.expand,
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (child, animation) {
        final incoming = child.key == ValueKey<String>(currentKey);
        final forward = direction >= 0;
        final incomingOffset = forward ? .035 : -.035;
        final outgoingOffset = forward ? -.035 : .035;
        final offsetTween = Tween<Offset>(
          begin: Offset(incoming ? incomingOffset : outgoingOffset, 0),
          end: Offset.zero,
        );
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: offsetTween.animate(animation),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _AdaptiveWorkflowBody extends StatefulWidget {
  const _AdaptiveWorkflowBody({required this.child});

  final Widget child;

  @override
  State<_AdaptiveWorkflowBody> createState() => _AdaptiveWorkflowBodyState();
}

class _AdaptiveWorkflowBodyState extends State<_AdaptiveWorkflowBody> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final textScale = media?.textScaler.scale(1.0) ?? 1.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : media?.size.height ?? 720;
        final scroll = height < 560 || textScale >= 1.35;
        final content = Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: widget.child,
            ),
          ),
        );
        if (!scroll) return content;
        return Scrollbar(
          controller: _controller,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _controller,
            physics: const ClampingScrollPhysics(),
            child: content,
          ),
        );
      },
    );
  }
}

class _PhaseHeader extends StatelessWidget {
  const _PhaseHeader({
    required this.icon,
    required this.title,
    required this.description,
    this.success = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool success;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Column(
      children: [
        AnimatedContainer(
          duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: success ? tokens.successContainer : tokens.accentContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(
            success ? Icons.check_rounded : icon,
            color: success ? tokens.onSuccessContainer : tokens.onAccentContainer,
            size: 27,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: textTheme.headlineSmall?.copyWith(
            color: tokens.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          description,
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(
            color: tokens.textSecondary,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _WorkflowProgress extends StatelessWidget {
  const _WorkflowProgress({
    required this.label,
    required this.index,
    required this.total,
  });

  final String label;
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final progress = total <= 0 ? 0.0 : index / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: tokens.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            Text(
              '$index / $total',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: tokens.accent,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TweenAnimationBuilder<double>(
          duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
          curve: CommonUiMotion.standard,
          tween: Tween<double>(begin: 0, end: progress),
          builder: (context, value, child) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 4,
                backgroundColor: tokens.surfaceOverlay,
                color: tokens.accent,
              ),
            );
          },
        ),
      ],
    );
  }
}

class _WorkflowListSurface extends StatelessWidget {
  const _WorkflowListSurface({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tokens.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

class _WorkflowDivider extends StatelessWidget {
  const _WorkflowDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: CommonUiTheme.of(context).borderSubtle,
    );
  }
}

class _PurposeSelectionRow extends StatefulWidget {
  const _PurposeSelectionRow({
    required this.purpose,
    required this.icon,
    required this.selected,
    required this.permissionCount,
    required this.onTap,
  });

  final AppStartUserPurpose purpose;
  final IconData icon;
  final bool selected;
  final int permissionCount;
  final VoidCallback onTap;

  @override
  State<_PurposeSelectionRow> createState() => _PurposeSelectionRowState();
}

class _PurposeSelectionRowState extends State<_PurposeSelectionRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Semantics(
      button: true,
      selected: widget.selected,
      label:
          '${widget.purpose.label}, ${widget.purpose.description}, 필수 설정 ${widget.permissionCount}개',
      child: AnimatedScale(
        scale: _pressed ? .985 : 1,
        duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
        curve: CommonUiMotion.enter,
        child: Stack(
          children: [
            AnimatedContainer(
              duration:
                  reduceMotion ? Duration.zero : CommonUiMotion.selection,
              curve: CommonUiMotion.standard,
              color: widget.selected
                  ? tokens.surfaceSelected
                  : tokens.transparent,
              child: Material(
                color: tokens.transparent,
                child: InkWell(
                  onTap: widget.onTap,
                  onHighlightChanged: (value) {
                    if (_pressed == value) return;
                    setState(() => _pressed = value);
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
                    child: Row(
                      children: [
                        AnimatedContainer(
                          duration: reduceMotion
                              ? Duration.zero
                              : CommonUiMotion.selection,
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: widget.selected
                                ? tokens.accentContainer
                                : tokens.surfaceOverlay,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            widget.icon,
                            size: 21,
                            color: widget.selected
                                ? tokens.onAccentContainer
                                : tokens.iconSecondary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.purpose.label,
                                style: textTheme.titleSmall?.copyWith(
                                  color: tokens.textPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.purpose.description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.bodySmall?.copyWith(
                                  color: tokens.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${widget.permissionCount}개',
                          style: textTheme.labelMedium?.copyWith(
                            color: widget.selected
                                ? tokens.accent
                                : tokens.textSecondary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 10),
                        AnimatedSwitcher(
                          duration: reduceMotion
                              ? Duration.zero
                              : CommonUiMotion.selection,
                          transitionBuilder: (child, animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: ScaleTransition(
                                scale: Tween<double>(begin: .84, end: 1)
                                    .animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: Icon(
                            widget.selected
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            key: ValueKey<bool>(widget.selected),
                            color: widget.selected
                                ? tokens.accent
                                : tokens.iconSecondary,
                            size: 22,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              bottom: 8,
              right: 0,
              child: AnimatedContainer(
                duration:
                    reduceMotion ? Duration.zero : CommonUiMotion.selection,
                curve: CommonUiMotion.standard,
                width: widget.selected ? 3 : 0,
                decoration: BoxDecoration(
                  color: tokens.accent,
                  borderRadius: BorderRadius.circular(CommonUiShapes.pill),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkflowInfoRow extends StatelessWidget {
  const _WorkflowInfoRow({
    required this.icon,
    required this.title,
    required this.description,
    this.trailing = '',
    this.trailingColor,
  });

  final IconData icon;
  final String title;
  final String description;
  final String trailing;
  final Color? trailingColor;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tokens.surfaceOverlay,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 19, color: tokens.accent),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: textTheme.titleSmall?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: textTheme.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (trailing.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              trailing,
              style: textTheme.labelMedium?.copyWith(
                color: trailingColor ?? tokens.textSecondary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WorkflowValueRow extends StatelessWidget {
  const _WorkflowValueRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: textTheme.bodyMedium?.copyWith(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: textTheme.bodyMedium?.copyWith(
                color: valueColor ?? tokens.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkflowFooter extends StatelessWidget {
  const _WorkflowFooter({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(top: BorderSide(color: tokens.borderSubtle)),
      ),
      child: child,
    );
  }
}

class _PolicyDocumentView extends StatefulWidget {
  const _PolicyDocumentView({
    required this.spec,
    required this.onProgress,
  });

  final PolicyDocumentSpec spec;
  final void Function(
    PolicyConsentKind kind,
    double progress,
    bool readToEnd,
  ) onProgress;

  @override
  State<_PolicyDocumentView> createState() => _PolicyDocumentViewState();
}

class _PolicyDocumentViewState extends State<_PolicyDocumentView> {
  final ScrollController _controller = ScrollController();
  double _progress = 0;
  bool _readToEnd = false;

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _markReadIfNeeded());
  }

  void _handleScroll() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final progress = position.maxScrollExtent <= 0
        ? 1.0
        : (position.pixels / position.maxScrollExtent)
            .clamp(0.0, 1.0)
            .toDouble();
    final readToEnd = position.maxScrollExtent <= 0 ||
        position.pixels >= position.maxScrollExtent - 24;
    if ((progress - _progress).abs() < 0.01 && readToEnd == _readToEnd) {
      return;
    }
    setState(() {
      _progress = progress;
      if (readToEnd) _readToEnd = true;
    });
    widget.onProgress(widget.spec.kind, _progress, _readToEnd);
  }

  void _markReadIfNeeded() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    if (position.maxScrollExtent > 0) return;
    setState(() {
      _progress = 1;
      _readToEnd = true;
    });
    widget.onProgress(widget.spec.kind, 1, true);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleScroll);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final duration = _reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 180);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 8, 2, 10),
          child: Row(
            children: [
              AnimatedSwitcher(
                duration: duration,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: Icon(
                  _readToEnd
                      ? Icons.check_circle_rounded
                      : Icons.article_outlined,
                  key: ValueKey<bool>(_readToEnd),
                  size: 19,
                  color: _readToEnd ? tokens.success : tokens.accent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '문서 확인',
                  style: textTheme.titleSmall?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: duration,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.08, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: Text(
                  _readToEnd ? '확인 완료' : '${(_progress * 100).round()}%',
                  key: ValueKey<String>(_readToEnd ? 'complete' : 'progress'),
                  style: textTheme.labelMedium?.copyWith(
                    color: _readToEnd ? tokens.success : tokens.accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: _progress),
          duration: duration,
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return SizedBox(
              height: 3,
              child: LinearProgressIndicator(
                value: value,
                backgroundColor: tokens.surfaceOverlay,
                color: _readToEnd ? tokens.success : tokens.accent,
              ),
            );
          },
        ),
        Divider(
          height: 1,
          thickness: 1,
          color: tokens.borderSubtle,
        ),
        Expanded(
          child: Scrollbar(
            controller: _controller,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _controller,
              padding: const EdgeInsets.fromLTRB(2, 18, 12, 22),
              child: Text(
                widget.spec.body.trim(),
                style: textTheme.bodyMedium?.copyWith(
                  color: tokens.textPrimary,
                  height: 1.62,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PurposePreviewDockBody extends StatefulWidget {
  const _PurposePreviewDockBody({
    required this.permissionSpecs,
    required this.includeFollowUp,
  });

  final List<AppStartPermissionSpec> permissionSpecs;
  final bool includeFollowUp;

  @override
  State<_PurposePreviewDockBody> createState() =>
      _PurposePreviewDockBodyState();
}

class _PurposePreviewDockBodyState extends State<_PurposePreviewDockBody> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final textScale = media?.textScaler.scale(1.0) ?? 1.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : media?.size.height ?? 720;
        final scroll = height < 500 || textScale >= 1.35;
        final child = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CommonSideDockSection(
              title: '필수 설정',
              subtitle: '${widget.permissionSpecs.length}개',
              order: 1,
              child: _WorkflowListSurface(
                children: [
                  for (var i = 0; i < widget.permissionSpecs.length; i++) ...[
                    _PreviewRow(
                      icon: widget.permissionSpecs[i].icon,
                      title: widget.permissionSpecs[i].title,
                      trailing: '${i + 1}/${widget.permissionSpecs.length}',
                    ),
                    if (i < widget.permissionSpecs.length - 1)
                      const _WorkflowDivider(),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            CommonSideDockSection(
              title: '후속 설정',
              subtitle: widget.includeFollowUp ? '2개' : '생략',
              order: 2,
              child: _WorkflowListSurface(
                children: widget.includeFollowUp
                    ? const [
                        _PreviewRow(
                          icon: Icons.policy_outlined,
                          title: '정책 동의',
                          trailing: '3단계',
                        ),
                        _WorkflowDivider(),
                        _PreviewRow(
                          icon: Icons.security_rounded,
                          title: 'Google 서비스 연결',
                          trailing: '3개',
                        ),
                      ]
                    : const [
                        _PreviewRow(
                          icon: Icons.check_circle_outline_rounded,
                          title: '추가 후속 설정 없음',
                          trailing: '생략',
                        ),
                      ],
              ),
            ),
          ],
        );
        if (!scroll) return child;
        return Scrollbar(
          controller: _controller,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _controller,
            physics: const ClampingScrollPhysics(),
            child: child,
          ),
        );
      },
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.icon,
    required this.title,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: tokens.surfaceOverlay,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 17, color: tokens.accent),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            trailing,
            style: textTheme.labelMedium?.copyWith(
              color: tokens.accent,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
