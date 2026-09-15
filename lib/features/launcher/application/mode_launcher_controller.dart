import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/auth/gmail_sender_auth.dart';
import '../../../app/command/application/service_settings_command_handler.dart';
import '../../../app/command/application/terminal_command_path.dart';
import '../../../app/command/application/terminal_line.dart';
import '../../../app/di/routes.dart';
import '../../../app/init/app_start_flow_prefs.dart';
import '../../../app/init/app_start_setup_flow_resolver.dart';
import '../../../app/init/app_start_user_purpose.dart';
import '../../../app/init/db_connection_status_section.dart';
import '../../../app/init/overlay_lifecycle_gate.dart';
import '../../../app/init/startup_tasks.dart';
import '../../dev/application/debug_session_controller.dart';
import '../../dev/domain/repositories/area_repo_package/area_repository.dart';
import '../../dev/page/dialogs/plate_billing_count_dialog.dart';
import '../../dev/page/sheets/dev_quick_actions.dart';
import '../../headquarter/application/fab/hub_quick_actions.dart';
import 'launcher_work_area_option.dart';
import 'launcher_work_area_resolver.dart';
import 'launcher_work_area_server_resolver.dart';
import '../../selector/application/dev_auth.dart';
import 'app_mode_definition.dart';
import 'app_mode_registry.dart';
import 'launcher_actions.dart';
import 'launcher_debug_account_override_store.dart';
import 'launcher_diagnostics.dart';
import 'launcher_startup_setup_coordinator.dart';
import 'terminal_auth_coordinator.dart';

enum TerminalLoginStage {
  command,
  accountType,
  name,
  phone,
  password,
  authenticating,
  areaSelection,
  modeSelection,
  activatingMode,
}

class ModeLauncherSubmitResult {
  const ModeLauncherSubmitResult({
    this.routeReplaced = false,
    this.surfaceCompletion,
    this.targetRoute,
    this.promptText,
    this.autoSubmitText,
    this.selectPromptText = false,
    this.keepFocus = true,
  });

  final bool routeReplaced;
  final Future<void>? surfaceCompletion;
  final String? targetRoute;
  final String? promptText;
  final String? autoSubmitText;
  final bool selectPromptText;
  final bool keepFocus;
}

class ModeLauncherController extends ChangeNotifier {
  static const String _hiddenImportingCommand = 'sudo apt importing';
  static const Set<String> _protectedCommands = <String>{
    'quick',
    'debug',
    'charge',
  };
  static const String nameDisplayLabel = 'NAME or Unique';
  static const String phoneDisplayLabel = 'TEL or Code';
  static const String passwordDisplayLabel = 'PW or Serial';
  static const String _namePrompt = '이름 혹은 유니크 명을 입력하세요.';
  static const String _nameReprompt = '이름 혹은 유니크 명을 다시 입력하세요.';
  static const String _phonePrompt = '전화번호 혹은 코드 번호를 입력하세요.';
  static const String _phoneReprompt = '전화번호 혹은 코드 번호를 다시 입력하세요.';
  static const String _passwordPrompt = '비밀번호 혹은 시리얼 넘버를 입력하세요.';
  static const String _passwordReprompt = '비밀번호 혹은 시리얼 넘버를 다시 입력하세요.';
  static const String _phoneError = '[ERROR] 전화번호 혹은 코드 번호를 다시 확인하세요.';
  static const String _passwordError = '[ERROR] 비밀번호 혹은 시리얼 넘버를 다시 확인하세요.';

  static String _authOutputLine(String label, String value) =>
      '${label.padRight(16)}$value';

  ModeLauncherController({StartupReport? startupReport})
      : _startupReport = startupReport ?? StartupTasks.lastReport {
    DevAuth.devModeEnabled.addListener(_handleDevModeChanged);
  }

  StartupReport? _startupReport;
  final List<TerminalLine> _lines = <TerminalLine>[];
  final List<String> _history = <String>[];
  int _sequence = 0;
  int _historyIndex = 0;
  int _errorSerial = 0;
  bool _busy = false;
  bool _disposed = false;
  bool _initialized = false;
  bool _authenticationBootstrapped = false;
  bool _authenticationBootstrapInFlight = false;
  bool _startupSetupResolved = false;
  bool _runtimeContextReady = false;
  bool _devAuthorized = false;
  bool _devModeEnabled = false;
  bool _importingUnlocked = false;
  AppStartUserPurpose? _startupPurpose;
  TerminalAccountKind? _defaultAccountKind;
  bool _accountKindAutoSelected = false;
  bool _debugAccountKindOverride = false;
  bool _debugOverrideSnapshotActive = false;
  TerminalSessionPersistence _sessionPersistence =
      TerminalSessionPersistence.persistent;
  String? _savedModeRaw;
  AppModeDefinition? _assignedMode;
  AppModeDefinition? _selectedMode;
  TerminalAccountKind? _selectedAccountKind;
  TerminalAuthenticatedAccount? _authenticatedAccount;
  List<LauncherWorkAreaOption> _availableWorkAreas = <LauncherWorkAreaOption>[];
  LauncherWorkAreaOption? _selectedWorkArea;
  List<AppModeDefinition> _supportedModes = <AppModeDefinition>[];
  String? _pendingTargetRoute;
  String? _pendingAutoSubmitText;
  String _runningCommand = '';
  bool? _foregroundRunning;
  TerminalLoginStage _loginStage = TerminalLoginStage.command;
  String _enteredName = '';
  String _enteredPhone = '';
  String _enteredPassword = '';
  TerminalCommandPath _commandPath = TerminalCommandPath.root;
  late final LauncherStartupSetupCoordinator _startupSetupCoordinator =
      LauncherStartupSetupCoordinator()..addListener(_handleStartupSetupChanged);

  List<TerminalLine> get lines => List<TerminalLine>.unmodifiable(_lines);
  LauncherStartupSetupCoordinator get startupSetup => _startupSetupCoordinator;
  bool get startupSetupActive =>
      !_startupSetupResolved ||
      !_startupSetupCoordinator.complete ||
      !_authenticationBootstrapped;
  bool get startupSetupBusy => _startupSetupCoordinator.busy;
  bool get startupSetupAwaitingExternalSettings =>
      _startupSetupCoordinator.awaitingExternalSettings;
  bool get startupSetupExternalSettingsRefreshInProgress =>
      _startupSetupCoordinator.externalSettingsRefreshInProgress;
  bool get runtimeContextReady => _runtimeContextReady;
  bool get busy => _busy;
  bool get initialized => _initialized;
  bool get devAuthorized => _devAuthorized;
  bool get devModeEnabled => _devModeEnabled;
  bool get importingUnlocked => _importingUnlocked;
  int get errorSerial => _errorSerial;
  String get runningCommand => _runningCommand;
  String get currentPromptPath => _commandPath.promptPath;
  bool get emailEditMode => _commandPath.isEmailEdit;
  String? get savedModeRaw => _savedModeRaw;
  AppModeDefinition? get assignedMode => _assignedMode;
  AppModeDefinition? get selectedMode => _selectedMode;
  TerminalAccountKind? get selectedAccountKind => _selectedAccountKind;
  String get selectedAccountKindLabel => _selectedAccountKind == null
      ? ''
      : TerminalAuthCoordinator.accountKindLabel(_selectedAccountKind!);
  List<AppModeDefinition> get supportedModes =>
      List<AppModeDefinition>.unmodifiable(_supportedModes);
  List<LauncherWorkAreaOption> get availableWorkAreas =>
      List<LauncherWorkAreaOption>.unmodifiable(_availableWorkAreas);
  LauncherWorkAreaOption? get selectedWorkArea => _selectedWorkArea;
  StartupReport? get startupReport => _startupReport;
  TerminalLoginStage get loginStage => _loginStage;
  String get enteredName => _enteredName;
  String get enteredPhone => _enteredPhone;
  bool get showAuthSummary => _selectedAccountKind != null ||
      _selectedMode != null ||
      _selectedWorkArea != null ||
      _enteredName.isNotEmpty ||
      _enteredPhone.isNotEmpty ||
      _enteredPassword.isNotEmpty;
  bool get obscurePrompt =>
      !startupSetupActive &&
      _commandPath.isRoot &&
      _loginStage == TerminalLoginStage.password;
  bool get commandHistoryEnabled {
    if (startupSetupActive) return false;
    if (_commandPath.isEmailEdit) return false;
    return _commandPath.isSetting || _loginStage == TerminalLoginStage.command;
  }
  bool get canNavigateBack {
    if (startupSetupActive) return false;
    if (!_commandPath.isRoot || _busy) return false;
    if (_loginStage == TerminalLoginStage.name && _accountKindAutoSelected) {
      return false;
    }
    return <TerminalLoginStage>{
      TerminalLoginStage.name,
      TerminalLoginStage.phone,
      TerminalLoginStage.password,
      TerminalLoginStage.areaSelection,
      TerminalLoginStage.modeSelection,
    }.contains(_loginStage);
  }
  bool get canCancelAuthentication => !startupSetupActive &&
      _commandPath.isRoot && !_busy &&
      _loginStage != TerminalLoginStage.command &&
      _loginStage != TerminalLoginStage.authenticating &&
      _loginStage != TerminalLoginStage.activatingMode;
  bool get canReturnToModes => !startupSetupActive &&
      _commandPath.isRoot && !_busy &&
      _authenticatedAccount != null &&
      ((_authenticatedAccount!.kind == TerminalAccountKind.user &&
              _availableWorkAreas.isNotEmpty) ||
          _supportedModes.isNotEmpty) &&
      _loginStage != TerminalLoginStage.areaSelection &&
      _loginStage != TerminalLoginStage.modeSelection &&
      _loginStage != TerminalLoginStage.activatingMode;
  String get returnSelectionLabel =>
      _authenticatedAccount?.kind == TerminalAccountKind.user ? 'AREAS' : 'MODES';
  bool shouldDismissKeyboardForInput(String raw) {
    if (_commandPath.isSetting) return false;
    if (_loginStage != TerminalLoginStage.password) return false;
    final normalized = AppModeRegistry.normalizeToken(raw.trim());
    return !_isAuthenticationControlCommand(normalized);
  }
  TextInputAction get promptInputAction => startupSetupActive
      ? TextInputAction.done
      : _commandPath.isSetting
      ? TextInputAction.done
      : switch (_loginStage) {
        TerminalLoginStage.accountType ||
        TerminalLoginStage.name ||
        TerminalLoginStage.phone =>
          TextInputAction.next,
        _ => TextInputAction.done,
        };
  TextInputType get promptKeyboardType {
    if (startupSetupActive) return TextInputType.text;
    if (_commandPath.isEmailEdit) return TextInputType.emailAddress;
    if (_commandPath.isSetting) return TextInputType.text;
    return switch (_loginStage) {
      TerminalLoginStage.phone => TextInputType.phone,
      TerminalLoginStage.password =>
        _selectedAccountKind == TerminalAccountKind.personal
            ? TextInputType.number
            : TextInputType.visiblePassword,
      _ => TextInputType.text,
    };
  }

  String? consumePendingTargetRoute() {
    final route = _pendingTargetRoute;
    _pendingTargetRoute = null;
    return route;
  }

  String? consumePendingAutoSubmitText() {
    final value = _pendingAutoSubmitText;
    _pendingAutoSubmitText = null;
    return value;
  }

  String get maskedPassword {
    if (_enteredPassword.isEmpty) return '';
    return List<String>.filled(_enteredPassword.length, '•').join();
  }

  int _nextId() => ++_sequence;

  void _handleStartupSetupChanged() {
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> runStartupSetupPrimaryAction(
    BuildContext context, {
    required bool reduceMotion,
  }) async {
    if (_disposed ||
        !startupSetupActive ||
        _startupSetupCoordinator.busy ||
        _startupSetupCoordinator.awaitingExternalSettings) {
      return;
    }
    final before = _startupSetupCoordinator.debugMeta();
    final beforePhase = _startupSetupCoordinator.phase;
    final beforePermissionStep =
        _startupSetupCoordinator.currentPermissionStep;
    final permissionSpec = _startupSetupCoordinator.currentPermissionSpec;
    final policySpec = _startupSetupCoordinator.currentPolicySpec;
    final label = switch (beforePhase) {
      AppStartSetupPhase.permission => permissionSpec?.title ?? 'Permission',
      AppStartSetupPhase.terms ||
      AppStartSetupPhase.privacy ||
      AppStartSetupPhase.accountDeletion => policySpec?.title ?? 'Policy',
      AppStartSetupPhase.googleServices => 'Google services',
      _ => beforePhase.name,
    };
    _runningCommand = 'SETUP';
    _append(TerminalLineType.running, 'Processing startup setup: $label');
    LauncherDiagnostics.record(
      'startup_setup_action_start',
      meta: before,
    );
    notifyListeners();
    try {
      await _startupSetupCoordinator.runPrimaryAction(
        reduceMotion: reduceMotion,
      );
      if (_disposed || !context.mounted) return;
      final afterPhase = _startupSetupCoordinator.phase;
      final phaseChanged = beforePhase != afterPhase;
      final permissionCompleted = beforePhase == AppStartSetupPhase.permission &&
          (phaseChanged ||
              beforePermissionStep !=
                  _startupSetupCoordinator.currentPermissionStep ||
              _startupSetupCoordinator.currentPermissionGranted);
      if (phaseChanged || permissionCompleted) {
        _append(TerminalLineType.success, '[ OK ] $label');
      } else {
        _append(
          TerminalLineType.system,
          'Pending: ${_startupSetupCoordinator.primaryActionLabel}',
        );
      }
      LauncherDiagnostics.record(
        'startup_setup_action_complete',
        meta: _startupSetupCoordinator.debugMeta(),
      );
      if (_startupSetupCoordinator.complete) {
        await _bootstrapAuthenticationAfterStartupSetup(
          context,
          reduceMotion: reduceMotion,
        );
      } else if (phaseChanged) {
        _append(
          TerminalLineType.system,
          'Next startup task: ${_startupSetupCoordinator.phase.name}',
        );
      }
    } finally {
      _runningCommand = '';
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> refreshStartupSetupAfterResume(
    BuildContext context, {
    required bool reduceMotion,
  }) async {
    if (_disposed || !startupSetupActive) return;
    if (_startupSetupCoordinator.busy &&
        !_startupSetupCoordinator.awaitingExternalSettings) {
      return;
    }
    final beforePhase = _startupSetupCoordinator.phase;
    final beforeStep = _startupSetupCoordinator.currentPermissionStep;
    final beforeAwaiting =
        _startupSetupCoordinator.awaitingExternalSettings;
    await _startupSetupCoordinator.refreshAfterResume(
      reduceMotion: reduceMotion,
    );
    if (_disposed || !context.mounted) return;
    LauncherDiagnostics.record(
      'startup_setup_resume_refresh',
      meta: _startupSetupCoordinator.debugMeta(),
    );
    final permissionAdvanced = beforeStep != null &&
        (beforePhase != _startupSetupCoordinator.phase ||
            beforeStep != _startupSetupCoordinator.currentPermissionStep);
    if (permissionAdvanced) {
      _append(
        TerminalLineType.success,
        '[ OK ] Permission step completed after system settings',
      );
    } else if (beforeAwaiting &&
        !_startupSetupCoordinator.awaitingExternalSettings &&
        beforeStep == _startupSetupCoordinator.currentPermissionStep &&
        !_startupSetupCoordinator.currentPermissionGranted) {
      _append(
        TerminalLineType.system,
        'Permission is still not granted. System settings can be opened again.',
      );
    }
    if (_startupSetupCoordinator.complete) {
      await _bootstrapAuthenticationAfterStartupSetup(
        context,
        reduceMotion: reduceMotion,
      );
    }
  }

  void updateStartupPolicyProgress(double progress, bool readToEnd) {
    _startupSetupCoordinator.updatePolicyProgress(progress, readToEnd);
  }

  void setStartupPolicyAgreed(bool value) {
    _startupSetupCoordinator.setPolicyAgreed(value);
  }

  Future<bool> registerStartupPermissionTitleTap(
    BuildContext context, {
    required bool reduceMotion,
  }) async {
    if (_disposed || !startupSetupActive) return false;
    final spec = _startupSetupCoordinator.currentPermissionSpec;
    final step = _startupSetupCoordinator.currentPermissionStep;
    if (spec == null || step == null) return false;
    final actualGranted = _startupSetupCoordinator.currentPermissionGranted;
    final skipped =
        await _startupSetupCoordinator.registerPermissionTitleTap();
    if (!skipped || _disposed || !context.mounted) return skipped;
    _append(TerminalLineType.system, '[ SKIP ] ${spec.title}');
    LauncherDiagnostics.record(
      'startup_permission_step_skipped',
      scope: 'launcher_startup_setup',
      meta: <String, Object?>{
        'skippedStep': step,
        'skippedPermission': spec.keyName,
        'actualGranted': actualGranted,
        'skipByFiveTap': true,
        ..._startupSetupCoordinator.debugMeta(),
      },
    );
    await LauncherDiagnostics.showStatus(
      context,
      title: 'Launcher Startup Status',
      description: developerStatusDescription(),
      scope: 'launcher_startup_setup',
    );
    if (_disposed || !context.mounted) return true;
    if (_startupSetupCoordinator.complete) {
      await _bootstrapAuthenticationAfterStartupSetup(
        context,
        reduceMotion: reduceMotion,
      );
    }
    return true;
  }

  Future<bool> registerStartupGoogleTitleTap(
    BuildContext context, {
    required bool reduceMotion,
  }) async {
    if (_disposed || !startupSetupActive) return false;
    final skipped = await _startupSetupCoordinator.registerGoogleTitleTap();
    if (!skipped || _disposed || !context.mounted) return skipped;
    _append(TerminalLineType.system, '[ SKIP ] Google services setup');
    LauncherDiagnostics.record(
      'startup_google_setup_skipped',
      meta: _startupSetupCoordinator.debugMeta(),
    );
    await LauncherDiagnostics.showStatus(
      context,
      title: 'Launcher Startup Status',
      description: developerStatusDescription(),
      scope: 'launcher_startup_setup',
    );
    if (_disposed || !context.mounted) return true;
    if (_startupSetupCoordinator.complete) {
      await _bootstrapAuthenticationAfterStartupSetup(
        context,
        reduceMotion: reduceMotion,
      );
    }
    return true;
  }

  Future<void> _bootstrapAuthenticationAfterStartupSetup(
    BuildContext context, {
    required bool reduceMotion,
  }) async {
    if (_authenticationBootstrapped ||
        _authenticationBootstrapInFlight ||
        _disposed ||
        !context.mounted) {
      return;
    }
    _authenticationBootstrapInFlight = true;
    notifyListeners();
    try {
      _append(TerminalLineType.success, '[ OK ] Startup setup complete');
      LauncherDiagnostics.record(
        'startup_setup_complete',
        meta: _startupSetupCoordinator.debugMeta(),
      );
      final report = await StartupTasks.runAfterPermissions();
      _startupReport = report;
      await _refreshLiveStatus();
      if (_disposed || !context.mounted) return;
      _append(
        report.allReady ? TerminalLineType.success : TerminalLineType.system,
        '${report.allReady ? '[ OK ]' : '[WARN]'} Startup services ${report.readyCount}/4',
      );
      LauncherDiagnostics.record(
        'authentication_bootstrap_after_startup_setup',
        meta: <String, Object?>{
          'startupReady': report.readyCount,
          'startupAllReady': report.allReady,
          ..._startupSetupCoordinator.debugMeta(),
        },
      );
      await _bootstrapAuthentication(
        context,
        reduceMotion: reduceMotion,
      );
      if (_disposed) return;
      _authenticationBootstrapped = true;
      _authenticationBootstrapInFlight = false;
      notifyListeners();
    } finally {
      if (!_authenticationBootstrapped) {
        _authenticationBootstrapInFlight = false;
        if (!_disposed) notifyListeners();
      }
    }
  }

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
    if (_lines.length > 120) {
      _lines.removeRange(0, _lines.length - 120);
    }
    notifyListeners();
  }

  Future<void> _appendPaced(
    TerminalLineType type,
    String text,
    bool reduceMotion,
  ) async {
    if (_disposed) return;
    _append(
      type,
      text,
      cadence: reduceMotion
          ? TerminalCadence.instant
          : TerminalCadence.automatic,
    );
  }

  bool get _unknownSavedMode {
    final raw = AppModeRegistry.normalizeToken(_savedModeRaw);
    return raw.isNotEmpty && raw != 'service' && _assignedMode == null;
  }

  bool isModeAllowed(AppModeDefinition mode) {
    if (_unknownSavedMode) return true;
    return _assignedMode == null || _assignedMode!.id == mode.id;
  }

  Future<void> initialize(BuildContext context, {required bool reduceMotion}) async {
    if (_initialized || _disposed) return;
    _initialized = true;
    LauncherDiagnostics.record('terminal_initialize_start');
    LauncherDiagnostics.record(
      'auth_presentation_config',
      scope: 'auth_presentation',
      meta: <String, Object?>{
        'nameLabel': nameDisplayLabel,
        'phoneLabel': phoneDisplayLabel,
        'passwordLabel': passwordDisplayLabel,
        'namePrompt': _namePrompt,
        'phonePrompt': _phonePrompt,
        'passwordPrompt': _passwordPrompt,
        'historyColumnWidth': 16,
        'summaryLabelWidth': 120,
        'summaryResizeMs': reduceMotion ? 0 : 190,
        'valueSwitchMs': reduceMotion ? 0 : 160,
      },
    );

    final debugSnapshotRestored =
        await LauncherDebugAccountOverrideStore.restoreIfNeeded(
      source: 'mode_launcher_initialize',
    );
    _debugOverrideSnapshotActive = false;
    _sessionPersistence = TerminalSessionPersistence.persistent;
    if (debugSnapshotRestored) {
      LauncherDiagnostics.record(
        'debug_account_override_startup_rollback_complete',
        meta: const <String, Object?>{
          'sessionPersistence': 'persistent',
        },
      );
    }

    final prefs = await DevAuth.restorePrefs();
    final devMode = await DevAuth.isDevModeEnabled();
    if (_disposed) return;
    _savedModeRaw = prefs.savedMode;
    _assignedMode = AppModeRegistry.findLegacy(_savedModeRaw);
    _devModeEnabled = devMode;
    _devAuthorized = devMode;
    await _refreshLiveStatus();
    LauncherDiagnostics.record(
      'terminal_preferences_loaded',
      meta: <String, Object?>{
        'savedMode': _savedModeRaw ?? '',
        'assignedMode': _assignedMode?.id ?? '',
        'unknownSavedMode': _unknownSavedMode,
        'devAuthorized': _devAuthorized,
        'devModeEnabled': _devModeEnabled,
        'foregroundRunning': _foregroundRunning,
      },
    );

    await _appendPaced(
      TerminalLineType.system,
      'ParkinWorkin System',
      reduceMotion
    );
    await _appendStartupStatus(reduceMotion);
    if (_disposed) return;

    final db = DbConnectionSnapshot.read();
    await _appendPaced(
      db.storageDbOn ? TerminalLineType.success : TerminalLineType.system,
      '${db.storageDbOn ? '[ OK ]' : '[WARN]'} Storage DB',
      reduceMotion
    );
    await _appendPaced(
      db.liveDbOn ? TerminalLineType.success : TerminalLineType.system,
      '${db.liveDbOn ? '[ OK ]' : '[WARN]'} Live DB',
      reduceMotion
    );

    if (_assignedMode != null) {
      await _appendPaced(
        TerminalLineType.system,
        'Assigned mode: ${_assignedMode!.koreanName}',
        reduceMotion
    );
    } else if (_unknownSavedMode) {
      await _appendPaced(
        TerminalLineType.system,
        'Saved mode is not registered: ${_savedModeRaw!.trim()}',
        reduceMotion
    );
    }

    _startupPurpose ??= await AppStartFlowPrefs.getUserPurpose();
    if (_startupPurpose == null) {
      _append(
        TerminalLineType.error,
        '[BLOCKED] Startup purpose is not selected',
      );
      _pendingTargetRoute = AppRoutes.powerBoot;
      LauncherDiagnostics.record(
        'startup_setup_missing_purpose',
        meta: const <String, Object?>{'targetRoute': AppRoutes.powerBoot},
      );
      LauncherDiagnostics.record('terminal_initialize_complete');
      return;
    }

    await _startupSetupCoordinator.initialize();
    if (_disposed) return;
    _startupSetupResolved = true;
    notifyListeners();
    if (_startupSetupCoordinator.complete) {
      await _bootstrapAuthenticationAfterStartupSetup(
        context,
        reduceMotion: reduceMotion,
      );
    } else {
      _append(
        TerminalLineType.system,
        'Startup setup: ${_startupSetupCoordinator.phase.name}',
      );
      _append(
        TerminalLineType.output,
        'Profile: ${_startupPurpose!.label}',
      );
      LauncherDiagnostics.record(
        'startup_setup_waiting_for_action',
        meta: _startupSetupCoordinator.debugMeta(),
      );
    }
    LauncherDiagnostics.record('terminal_initialize_complete');
  }

  Future<void> _refreshLiveStatus() async {
    try {
      _foregroundRunning = await FlutterForegroundTask.isRunningService;
    } catch (error) {
      _foregroundRunning = null;
      LauncherDiagnostics.record(
        'foreground_status_failed',
        meta: <String, Object?>{'error': error},
      );
    }
  }

  void _handleDevModeChanged() {
    if (_disposed) return;
    _devModeEnabled = DevAuth.devModeEnabled.value;
    _devAuthorized = _devModeEnabled;
    LauncherDiagnostics.record(
      'developer_mode_changed',
      meta: <String, Object?>{
        'devModeEnabled': _devModeEnabled,
        'devAuthorized': _devAuthorized,
      },
    );
    notifyListeners();
  }

  Future<void> _appendStartupStatus(bool reduceMotion) async {
    final report = _startupReport;
    if (report == null) {
      await _appendPaced(
        TerminalLineType.system,
        '[WARN] Startup report unavailable',
        reduceMotion,
      );
      return;
    }
    await _appendPaced(
      report.notificationsReady
          ? TerminalLineType.success
          : TerminalLineType.system,
      '${report.notificationsReady ? '[ OK ]' : '[WARN]'} Notifications',
      reduceMotion,
    );
    await _appendPaced(
      report.reminderReady ? TerminalLineType.success : TerminalLineType.system,
      '${report.reminderReady ? '[ OK ]' : '[WARN]'} Reminder service',
      reduceMotion,
    );
    await _appendPaced(
      report.chillStoreReady
          ? TerminalLineType.success
          : TerminalLineType.system,
      '${report.chillStoreReady ? '[ OK ]' : '[WARN]'} Productivity store',
      reduceMotion,
    );
    await _appendPaced(
      (_foregroundRunning ?? report.foregroundServiceReady)
          ? TerminalLineType.success
          : TerminalLineType.system,
      '${(_foregroundRunning ?? report.foregroundServiceReady) ? '[ OK ]' : '[WARN]'} Foreground service',
      reduceMotion,
    );
  }

  void _appendModeList() {
    final account = _authenticatedAccount;
    if (account == null) {
      _append(TerminalLineType.system, '업무 지역과 지원 모드는 로그인 성공 후 표시됩니다.');
      return;
    }
    if (account.kind == TerminalAccountKind.user && _availableWorkAreas.isNotEmpty) {
      _appendWorkAreaList();
      return;
    }
    _appendSupportedModeList();
  }

  void _appendAccountTypeList() {
    _append(TerminalLineType.system, 'ACCOUNT TYPES');
    _append(TerminalLineType.system, '────────────────────────────────────────');
    _append(TerminalLineType.output, '1  일반 계정      user');
    _append(TerminalLineType.output, '2  개인형 계정    personal');
    _append(TerminalLineType.output, '3  태블릿형 계정  tablet');
    _append(TerminalLineType.system, '────────────────────────────────────────');
  }

  void _appendSupportedModeList() {
    _append(TerminalLineType.system, 'SUPPORTED MODES');
    _append(TerminalLineType.system, '────────────────────────────────────────');
    for (var index = 0; index < _supportedModes.length; index++) {
      final mode = _supportedModes[index];
      _append(
        TerminalLineType.output,
        '${index + 1}  ${mode.koreanName}',
      );
    }
    _append(TerminalLineType.system, '────────────────────────────────────────');
    LauncherDiagnostics.record(
      'auth_supported_mode_list_rendered',
      meta: <String, Object?>{
        'display': 'name_only',
        'modeCount': _supportedModes.length,
        'modeNames': _supportedModes.map((mode) => mode.koreanName).join(','),
        'paced': false,
      },
    );
  }

  void _appendWorkAreaList() {
    _append(TerminalLineType.system, 'WORK AREAS');
    _append(TerminalLineType.system, '────────────────────────────────────────');
    for (var index = 0; index < _availableWorkAreas.length; index++) {
      final area = _availableWorkAreas[index];
      _append(
        TerminalLineType.output,
        '${index + 1}  ${area.areaName}',
      );
    }
    _append(TerminalLineType.system, '────────────────────────────────────────');
    LauncherDiagnostics.record(
      'auth_work_area_list_rendered',
      meta: <String, Object?>{
        'display': 'name_only',
        'areaCount': _availableWorkAreas.length,
        'areaNames': _availableWorkAreas.map((area) => area.areaName).join(','),
        'paced': false,
      },
    );
  }

  Future<void> _appendWorkAreaListPaced(bool reduceMotion) async {
    await _appendPaced(
      TerminalLineType.system,
      'WORK AREAS',
      reduceMotion,
    );
    await _appendPaced(
      TerminalLineType.system,
      '────────────────────────────────────────',
      reduceMotion,
    );
    for (var index = 0; index < _availableWorkAreas.length; index++) {
      final area = _availableWorkAreas[index];
      await _appendPaced(
        TerminalLineType.output,
        '${index + 1}  ${area.areaName}',
        reduceMotion,
      );
    }
    _append(TerminalLineType.system, '────────────────────────────────────────');
    LauncherDiagnostics.record(
      'auth_work_area_list_rendered',
      meta: <String, Object?>{
        'display': 'name_only',
        'areaCount': _availableWorkAreas.length,
        'areaNames': _availableWorkAreas.map((area) => area.areaName).join(','),
        'paced': true,
        'reduceMotion': reduceMotion,
      },
    );
  }

  Future<void> _appendCommandList(bool reduceMotion) async {
    await _appendPaced(
      TerminalLineType.system,
      'COMMANDS',
      reduceMotion
    );
    await _appendPaced(
      TerminalLineType.system,
      '────────────────────────────────────────',
      reduceMotion
    );
    final commands = <String>[
      'modes       업무 지역/모드 목록',
      'account     로그인 전 계정 유형 변경',
      'back        이전 입력 단계',
      'cancel      로그인 입력 취소',
      'status      시스템 상태',
      'setting     설정 경로',
      'quick       빠른 실행',
      'update      업데이트',
      'support     앱 이용 문의',
      'signup      개인형 회원가입',
      'clear       화면 정리',
      'out         터미널 종료',
      'exit        앱 종료',
      'debug       DEBUG 세션 활성화',
      'charge      청구 집계',
      if (_devAuthorized) 'practice    Practice Space',
      if (_devAuthorized) 'dev         Developer',
    ];
    for (final command in commands) {
      await _appendPaced(
        TerminalLineType.output,
        command,
        reduceMotion
    );
    }
    _append(TerminalLineType.system, '────────────────────────────────────────');
  }

  Future<void> _appendSupportedModeListPaced(bool reduceMotion) async {
    await _appendPaced(
      TerminalLineType.system,
      'SUPPORTED MODES',
      reduceMotion
    );
    await _appendPaced(
      TerminalLineType.system,
      '────────────────────────────────────────',
      reduceMotion
    );
    for (var index = 0; index < _supportedModes.length; index++) {
      final mode = _supportedModes[index];
      await _appendPaced(
        TerminalLineType.output,
        '${index + 1}  ${mode.koreanName}',
        reduceMotion
    );
    }
    _append(TerminalLineType.system, '────────────────────────────────────────');
    LauncherDiagnostics.record(
      'auth_supported_mode_list_rendered',
      meta: <String, Object?>{
        'display': 'name_only',
        'modeCount': _supportedModes.length,
        'modeNames': _supportedModes.map((mode) => mode.koreanName).join(','),
        'paced': true,
        'reduceMotion': reduceMotion,
      },
    );
  }


  void _appendStatus() {
    final db = DbConnectionSnapshot.read();
    final report = _startupReport;
    _append(TerminalLineType.system, 'SYSTEM STATUS');
    _append(TerminalLineType.system, '────────────────────────────────────────');
    _append(
      db.storageDbOn ? TerminalLineType.success : TerminalLineType.system,
      'Storage DB          ${db.storageDbOn ? 'ONLINE' : 'OFFLINE'}',
    );
    _append(
      db.liveDbOn ? TerminalLineType.success : TerminalLineType.system,
      'Live DB             ${db.liveDbOn ? 'ONLINE' : 'OFFLINE'}',
    );
    _append(
      report?.notificationsReady == true
          ? TerminalLineType.success
          : TerminalLineType.system,
      'Notifications       ${report?.notificationsReady == true ? 'READY' : 'WARN'}',
    );
    _append(
      (_foregroundRunning ?? report?.foregroundServiceReady) == true
          ? TerminalLineType.success
          : TerminalLineType.system,
      'Foreground service  ${(_foregroundRunning ?? report?.foregroundServiceReady) == true ? 'ACTIVE' : 'WARN'}',
    );
    _append(
      TerminalLineType.output,
      'Developer mode      ${_devModeEnabled ? 'ON' : 'OFF'}',
    );
    _append(
      TerminalLineType.output,
      'Assigned mode       ${_assignedMode?.koreanName ?? '-'}',
    );
    _append(
      TerminalLineType.output,
      'Account kind        ${_selectedAccountKind == null ? '-' : TerminalAuthCoordinator.accountKindId(_selectedAccountKind!)}',
    );
    _append(
      TerminalLineType.output,
      'Startup purpose     ${_startupPurpose?.storageValue ?? '-'}',
    );
    _append(
      TerminalLineType.output,
      'Default account     ${_defaultAccountKind == null ? '-' : TerminalAuthCoordinator.accountKindId(_defaultAccountKind!)}',
    );
    _append(
      TerminalLineType.output,
      'Auto account        ${_accountKindAutoSelected ? 'ON' : 'OFF'}',
    );
    _append(
      TerminalLineType.output,
      'Debug override      ${_debugAccountKindOverride ? 'ON' : 'OFF'}',
    );
    _append(
      TerminalLineType.output,
      'Session scope       ${TerminalAuthCoordinator.sessionPersistenceId(_sessionPersistence)}',
    );
    _append(
      TerminalLineType.output,
      'Debug snapshot      ${_debugOverrideSnapshotActive ? 'ACTIVE' : 'OFF'}',
    );
    _append(
      TerminalLineType.output,
      'Work areas          ${_availableWorkAreas.isEmpty ? '-' : _availableWorkAreas.map((area) => area.areaName).join(',')}',
    );
    _append(
      TerminalLineType.output,
      'Selected area       ${_selectedWorkArea?.areaName ?? '-'}',
    );
    _append(
      TerminalLineType.output,
      'Supported modes     ${_supportedModes.isEmpty ? '-' : _supportedModes.map((mode) => mode.id).join(',')}',
    );
    _append(
      TerminalLineType.output,
      'Startup setup       ${_startupSetupCoordinator.phase.name}',
    );
    _append(
      TerminalLineType.output,
      'Setup busy          ${_startupSetupCoordinator.busy ? 'YES' : 'NO'}',
    );
    _append(
      TerminalLineType.output,
      'External settings   ${_startupSetupCoordinator.awaitingExternalSettings ? 'WAITING' : 'IDLE'}',
    );
    _append(
      TerminalLineType.output,
      'Runtime context      ${_runtimeContextReady ? 'READY' : 'NOT READY'}',
    );
    _append(
      TerminalLineType.output,
      'Overlay lifecycle    ${OverlayLifecycleGate.stateLabel}',
    );
    _append(
      TerminalLineType.output,
      'Overlay gate reason  ${OverlayLifecycleGate.reason}',
    );
    _append(
      TerminalLineType.output,
      'Auth stage          ${_loginStage.name}',
    );
    _append(
      TerminalLineType.output,
      'Terminal path       ${_commandPath.promptPath}',
    );
    _append(TerminalLineType.system, '────────────────────────────────────────');
  }

  String developerStatusDescription() {
    final db = DbConnectionSnapshot.read();
    final report = _startupReport;
    return <String>[
      'Storage DB: ${db.storageDbOn ? 'ONLINE' : 'OFFLINE'}',
      'Live DB: ${db.liveDbOn ? 'ONLINE' : 'OFFLINE'}',
      'Notifications: ${report?.notificationsReady == true ? 'READY' : 'WARN'}',
      'Reminder: ${report?.reminderReady == true ? 'READY' : 'WARN'}',
      'Productivity store: ${report?.chillStoreReady == true ? 'READY' : 'WARN'}',
      'Foreground service: ${(_foregroundRunning ?? report?.foregroundServiceReady) == true ? 'ACTIVE' : 'WARN'}',
      'Saved mode: ${_savedModeRaw ?? '-'}',
      'Assigned mode: ${_assignedMode?.id ?? '-'}',
      'Selected area: ${_selectedWorkArea?.areaName ?? '-'}',
      'Available work areas: ${_availableWorkAreas.isEmpty ? '-' : _availableWorkAreas.map((area) => area.areaName).join(',')}',
      'Selected mode: ${_selectedMode?.id ?? '-'}',
      'Work area display: name_only',
      'Mode display: name_only',
      'Name display: $nameDisplayLabel',
      'Phone display: $phoneDisplayLabel',
      'Password display: $passwordDisplayLabel',
      'Name prompt: $_namePrompt',
      'Phone prompt: $_phonePrompt',
      'Password prompt: $_passwordPrompt',
      'Account kind: ${_selectedAccountKind == null ? '-' : TerminalAuthCoordinator.accountKindId(_selectedAccountKind!)}',
      'Startup purpose: ${_startupPurpose?.storageValue ?? '-'}',
      'Default account kind: ${_defaultAccountKind == null ? '-' : TerminalAuthCoordinator.accountKindId(_defaultAccountKind!)}',
      'Account auto selected: $_accountKindAutoSelected',
      'Debug account override: $_debugAccountKindOverride',
      'Session persistence: ${TerminalAuthCoordinator.sessionPersistenceId(_sessionPersistence)}',
      'Debug override snapshot: $_debugOverrideSnapshotActive',
      'Supported modes: ${_supportedModes.map((mode) => mode.id).join(',')}',
      'Startup setup phase: ${_startupSetupCoordinator.phase.name}',
      'Startup setup resolved: $_startupSetupResolved',
      'Startup setup busy: ${_startupSetupCoordinator.busy}',
      'External settings waiting: ${_startupSetupCoordinator.awaitingExternalSettings}',
      'External settings refresh: ${_startupSetupCoordinator.externalSettingsRefreshInProgress}',
      'External settings step: ${_startupSetupCoordinator.externalSettingsStep ?? '-'}',
      'Startup setup permission: ${_startupSetupCoordinator.currentPermissionSpec?.keyName ?? '-'}',
      'Permission skip taps: ${_startupSetupCoordinator.permissionSkipTapCount}',
      'Permission skip step: ${_startupSetupCoordinator.permissionSkipTapStep ?? '-'}',
      'Startup setup policy: ${_startupSetupCoordinator.currentPolicySpec?.kind.name ?? '-'}',
      'Startup setup policy progress: ${_startupSetupCoordinator.policyScrollProgress.toStringAsFixed(3)}',
      'Startup setup Google connected: ${_startupSetupCoordinator.googleConnected}',
      'Runtime context ready: $_runtimeContextReady',
      'Overlay lifecycle: ${OverlayLifecycleGate.stateLabel}',
      'Overlay gate reason: ${OverlayLifecycleGate.reason}',
      'Overlay gate generation: ${OverlayLifecycleGate.generation}',
      'Auth stage: ${_loginStage.name}',
      'Terminal path: ${_commandPath.promptPath}',
      'Email edit mode: ${_commandPath.isEmailEdit}',
      'Name length: ${_enteredName.length}',
      'Phone: ${_maskPhone(_enteredPhone)}',
      'Password length: ${_enteredPassword.length}',
      'Developer authorized: $_devAuthorized',
      'Developer mode: $_devModeEnabled',
      'Protected commands unlocked: $_importingUnlocked',
    ].join('\n');
  }

  void rejectEmptyInput() {
    _errorSerial += 1;
    LauncherDiagnostics.record(
      'terminal_empty_input',
      meta: <String, Object?>{'stage': _loginStage.name},
    );
    notifyListeners();
  }

  String? previousCommand() {
    if (!commandHistoryEnabled || _history.isEmpty) return null;
    if (_historyIndex > 0) _historyIndex -= 1;
    return _history[_historyIndex];
  }

  String? nextCommand() {
    if (!commandHistoryEnabled || _history.isEmpty) return null;
    if (_historyIndex < _history.length - 1) {
      _historyIndex += 1;
      return _history[_historyIndex];
    }
    _historyIndex = _history.length;
    return '';
  }

  Future<ModeLauncherSubmitResult> submit(
    BuildContext context,
    String raw, {
    required bool reduceMotion,
  }) async {
    if (_busy || _disposed || startupSetupActive) {
      return const ModeLauncherSubmitResult();
    }
    final input = raw.trim();
    if (input.isEmpty) {
      rejectEmptyInput();
      return const ModeLauncherSubmitResult();
    }

    final normalized = AppModeRegistry.normalizeToken(input);
    if (!_commandPath.isEmailEdit && normalized == _hiddenImportingCommand) {
      _append(
        TerminalLineType.command,
        input,
        promptPath: _commandPath.promptPath,
      );
      return _unlockImporting(
        context,
        reduceMotion: reduceMotion,
      );
    }
    if (_commandPath.isSetting) {
      if (!_commandPath.isEmailEdit) {
        if (_history.isEmpty || _history.last != input) {
          _history.add(input);
          if (_history.length > 50) _history.removeAt(0);
        }
        _historyIndex = _history.length;
      }
      _append(
        TerminalLineType.command,
        input,
        promptPath: _commandPath.promptPath,
      );
      return _submitSettingPathCommand(
        context,
        input,
        normalized,
        reduceMotion: reduceMotion,
      );
    }
    if (_loginStage != TerminalLoginStage.command) {
      if (_isAccountTypeEscapeCommand(normalized)) {
        _append(
          TerminalLineType.command,
          input,
          promptPath: _commandPath.promptPath,
        );
        return _submitDebugAccountTypeEscape(
          normalized,
          reduceMotion: reduceMotion,
        );
      }
      if (_isNavigationCommand(normalized)) {
        return _submitNavigationCommand(normalized);
      }
      final commandWindow = _loginStage == TerminalLoginStage.accountType ||
          _loginStage == TerminalLoginStage.areaSelection ||
          _loginStage == TerminalLoginStage.modeSelection;
      final authenticationGlobal = _isAuthenticationGlobalCommand(normalized);
      if (authenticationGlobal ||
          (commandWindow && _isGlobalCommand(normalized))) {
        if (_history.isEmpty || _history.last != input) {
          _history.add(input);
          if (_history.length > 50) _history.removeAt(0);
        }
        _historyIndex = _history.length;
        _append(
          TerminalLineType.command,
          input,
          promptPath: _commandPath.promptPath,
        );
        return _submitGlobalCommand(
          context,
          input,
          normalized,
          reduceMotion: reduceMotion,
        );
      }
      return _submitAuthenticationInput(
        context,
        input,
        reduceMotion: reduceMotion,
      );
    }

    if (_history.isEmpty || _history.last != input) {
      _history.add(input);
      if (_history.length > 50) _history.removeAt(0);
    }
    _historyIndex = _history.length;
    _append(
      TerminalLineType.command,
      input,
      promptPath: _commandPath.promptPath,
    );

    final mode = AppModeRegistry.find(input);
    LauncherDiagnostics.record(
      'terminal_submit',
      meta: <String, Object?>{
        'input': input,
        'normalized': normalized,
        'mode': mode?.id ?? '',
      },
    );

    if (mode != null) {
      _append(TerminalLineType.error, '[ERROR] 로그인 후 지원 모드를 선택할 수 있습니다.');
      _errorSerial += 1;
      notifyListeners();
      return const ModeLauncherSubmitResult();
    }

    return _submitGlobalCommand(
      context,
      input,
      normalized,
      reduceMotion: reduceMotion,
    );
  }

  bool _isNavigationCommand(String normalized) {
    return const <String>{
      'back',
      '뒤로',
      '이전',
      'cancel',
      '취소',
      'modes',
      'mode',
      '모드',
    }.contains(normalized);
  }

  bool _isAccountTypeEscapeCommand(String normalized) {
    return normalized == 'cd ..' || normalized == 'cd..';
  }

  bool _isAuthenticationGlobalCommand(String normalized) {
    if (normalized == 'debug') return true;
    if (!_devModeEnabled) return false;
    return normalized == 'status' || normalized == '상태';
  }

  bool _isAuthenticationControlCommand(String normalized) {
    return _isNavigationCommand(normalized) ||
        _isAccountTypeEscapeCommand(normalized) ||
        _isAuthenticationGlobalCommand(normalized);
  }

  ModeLauncherSubmitResult _submitNavigationCommand(String normalized) {
    switch (normalized) {
      case 'back':
      case '뒤로':
      case '이전':
        return _goBackAuthentication();
      case 'cancel':
      case '취소':
        return _cancelAuthentication();
      case 'modes':
      case 'mode':
      case '모드':
        return _returnToModeSelection();
      default:
        return const ModeLauncherSubmitResult();
    }
  }

  Future<ModeLauncherSubmitResult> _submitDebugAccountTypeEscape(
    String normalized, {
    required bool reduceMotion,
  }) async {
    if (!_devModeEnabled) {
      _append(TerminalLineType.error, '[DENIED] DEBUG mode required');
      _errorSerial += 1;
      LauncherDiagnostics.record(
        'auth_account_kind_debug_override_denied',
        meta: <String, Object?>{
          'command': normalized,
          'stage': _loginStage.name,
          'startupPurpose': _startupPurpose?.storageValue ?? '',
        },
      );
      notifyListeners();
      return const ModeLauncherSubmitResult();
    }
    if (_authenticatedAccount != null ||
        !<TerminalLoginStage>{
          TerminalLoginStage.name,
          TerminalLoginStage.phone,
          TerminalLoginStage.password,
        }.contains(_loginStage)) {
      _append(TerminalLineType.error, '[DENIED] Account override unavailable');
      _errorSerial += 1;
      LauncherDiagnostics.record(
        'auth_account_kind_debug_override_denied',
        meta: <String, Object?>{
          'command': normalized,
          'stage': _loginStage.name,
          'reason': 'stage_or_session',
        },
      );
      notifyListeners();
      return const ModeLauncherSubmitResult();
    }
    final previousKind = _selectedAccountKind;
    final previousStage = _loginStage;
    _busy = true;
    _runningCommand = 'cd ..';
    _append(TerminalLineType.running, 'Opening account types');
    notifyListeners();
    await _commandDelay(reduceMotion);
    if (_disposed) {
      _busy = false;
      _runningCommand = '';
      return const ModeLauncherSubmitResult();
    }
    final snapshotStarted = await LauncherDebugAccountOverrideStore.begin();
    await LauncherDebugAccountOverrideStore.clearAccountKindBinding();
    _debugOverrideSnapshotActive = true;
    _sessionPersistence = TerminalSessionPersistence.ephemeral;
    _runningCommand = 'DEBUG SCOPE';
    _append(TerminalLineType.running, 'Isolating debug session');
    notifyListeners();
    await _commandDelay(reduceMotion);
    if (_disposed) {
      _busy = false;
      _runningCommand = '';
      return const ModeLauncherSubmitResult();
    }
    _selectedAccountKind = null;
    _authenticatedAccount = null;
    _availableWorkAreas = <LauncherWorkAreaOption>[];
    _selectedWorkArea = null;
    _supportedModes = <AppModeDefinition>[];
    _selectedMode = null;
    _enteredName = '';
    _enteredPhone = '';
    _enteredPassword = '';
    _accountKindAutoSelected = false;
    _debugAccountKindOverride = true;
    _loginStage = TerminalLoginStage.accountType;
    _busy = false;
    _runningCommand = '';
    _append(TerminalLineType.success, '[ OK ] DEBUG account override');
    _appendAccountTypeList();
    _append(TerminalLineType.system, '계정 유형을 입력하세요.');
    LauncherDiagnostics.record(
      'auth_account_kind_debug_override_opened',
      meta: <String, Object?>{
        'command': normalized,
        'fromStage': previousStage.name,
        'fromAccountKind': previousKind == null
            ? ''
            : TerminalAuthCoordinator.accountKindId(previousKind),
        'startupPurpose': _startupPurpose?.storageValue ?? '',
        'defaultAccountKind': _defaultAccountKind == null
            ? ''
            : TerminalAuthCoordinator.accountKindId(_defaultAccountKind!),
        'debugMode': _devModeEnabled,
        'snapshotStarted': snapshotStarted,
        'sessionPersistence': TerminalAuthCoordinator.sessionPersistenceId(
          _sessionPersistence,
        ),
      },
    );
    DebugSessionController.record(
      'auth_account_kind_debug_override_opened',
      source: 'mode_terminal',
      meta: <String, Object?>{
        'fromStage': previousStage.name,
        'fromAccountKind': previousKind == null
            ? ''
            : TerminalAuthCoordinator.accountKindId(previousKind),
        'startupPurpose': _startupPurpose?.storageValue ?? '',
        'snapshotStarted': snapshotStarted,
        'sessionPersistence': TerminalAuthCoordinator.sessionPersistenceId(
          _sessionPersistence,
        ),
      },
    );
    notifyListeners();
    return const ModeLauncherSubmitResult(promptText: '');
  }

  ModeLauncherSubmitResult _goBackAuthentication() {
    if (_busy) return const ModeLauncherSubmitResult();
    switch (_loginStage) {
      case TerminalLoginStage.name:
        if (_accountKindAutoSelected) {
          LauncherDiagnostics.record(
            'auth_navigation_back_blocked',
            meta: <String, Object?>{
              'stage': 'name',
              'reason': 'startupPurposeAutoSelection',
              'startupPurpose': _startupPurpose?.storageValue ?? '',
              'accountKind': _selectedAccountKind == null
                  ? ''
                  : TerminalAuthCoordinator.accountKindId(
                      _selectedAccountKind!,
                    ),
            },
          );
          return const ModeLauncherSubmitResult();
        }
        _loginStage = TerminalLoginStage.accountType;
        _appendAccountTypeList();
        _append(TerminalLineType.system, '계정 유형을 다시 선택하세요.');
        LauncherDiagnostics.record(
          'auth_navigation_back',
          meta: <String, Object?>{'from': 'name', 'to': 'accountType'},
        );
        notifyListeners();
        return const ModeLauncherSubmitResult();
      case TerminalLoginStage.phone:
        _enteredPassword = '';
        _authenticatedAccount = null;
        _availableWorkAreas = <LauncherWorkAreaOption>[];
        _selectedWorkArea = null;
        _supportedModes = <AppModeDefinition>[];
        _selectedMode = null;
        _loginStage = TerminalLoginStage.name;
        _append(TerminalLineType.system, _nameReprompt);
        LauncherDiagnostics.record(
          'auth_navigation_back',
          meta: <String, Object?>{'from': 'phone', 'to': 'name'},
        );
        notifyListeners();
        return ModeLauncherSubmitResult(
          promptText: _enteredName,
          selectPromptText: true,
        );
      case TerminalLoginStage.password:
        _enteredPassword = '';
        _authenticatedAccount = null;
        _availableWorkAreas = <LauncherWorkAreaOption>[];
        _selectedWorkArea = null;
        _supportedModes = <AppModeDefinition>[];
        _selectedMode = null;
        _loginStage = TerminalLoginStage.phone;
        _append(TerminalLineType.system, _phoneReprompt);
        LauncherDiagnostics.record(
          'auth_navigation_back',
          meta: <String, Object?>{'from': 'password', 'to': 'phone'},
        );
        notifyListeners();
        return ModeLauncherSubmitResult(
          promptText: _enteredPhone,
          selectPromptText: true,
        );
      case TerminalLoginStage.areaSelection:
        final account = _authenticatedAccount;
        if (account?.activated == true) {
          _appendWorkAreaList();
          _append(
            TerminalLineType.system,
            '복원된 로그인 세션은 유지됩니다. 업무 지역을 선택하세요.',
          );
          LauncherDiagnostics.record(
            'auth_navigation_back_blocked',
            meta: const <String, Object?>{
              'stage': 'areaSelection',
              'reason': 'restoredSession',
            },
          );
          return const ModeLauncherSubmitResult();
        }
        _authenticatedAccount = null;
        _availableWorkAreas = <LauncherWorkAreaOption>[];
        _selectedWorkArea = null;
        _supportedModes = <AppModeDefinition>[];
        _selectedMode = null;
        _enteredPassword = '';
        _loginStage = TerminalLoginStage.password;
        _append(TerminalLineType.system, _passwordReprompt);
        LauncherDiagnostics.record(
          'auth_navigation_back',
          meta: <String, Object?>{'from': 'areaSelection', 'to': 'password'},
        );
        notifyListeners();
        return const ModeLauncherSubmitResult();
      case TerminalLoginStage.modeSelection:
        final account = _authenticatedAccount;
        if (account?.kind == TerminalAccountKind.user &&
            _selectedWorkArea != null &&
            _availableWorkAreas.isNotEmpty) {
          _selectedMode = null;
          _supportedModes = account!.supportedModes;
          _selectedWorkArea = null;
          _loginStage = TerminalLoginStage.areaSelection;
          _appendWorkAreaList();
          _append(TerminalLineType.system, '업무 지역을 다시 선택하세요.');
          LauncherDiagnostics.record(
            'auth_navigation_back',
            meta: <String, Object?>{'from': 'modeSelection', 'to': 'areaSelection'},
          );
          notifyListeners();
          return const ModeLauncherSubmitResult();
        }
        if (account?.activated == true) {
          _append(
            TerminalLineType.system,
            '복원된 로그인 세션은 유지됩니다. 지원 모드 중 하나를 선택하세요.',
          );
          LauncherDiagnostics.record(
            'auth_navigation_back_blocked',
            meta: const <String, Object?>{
              'stage': 'modeSelection',
              'reason': 'restoredSession',
            },
          );
          return const ModeLauncherSubmitResult();
        }
        _authenticatedAccount = null;
        _availableWorkAreas = <LauncherWorkAreaOption>[];
        _selectedWorkArea = null;
        _supportedModes = <AppModeDefinition>[];
        _selectedMode = null;
        _enteredPassword = '';
        _loginStage = TerminalLoginStage.password;
        _append(TerminalLineType.system, _passwordReprompt);
        LauncherDiagnostics.record(
          'auth_navigation_back',
          meta: <String, Object?>{'from': 'modeSelection', 'to': 'password'},
        );
        notifyListeners();
        return const ModeLauncherSubmitResult();
      case TerminalLoginStage.accountType:
      case TerminalLoginStage.command:
      case TerminalLoginStage.authenticating:
      case TerminalLoginStage.activatingMode:
        return const ModeLauncherSubmitResult();
    }
  }

  ModeLauncherSubmitResult _cancelAuthentication() {
    if (_busy) return const ModeLauncherSubmitResult();
    final restoredSession = _authenticatedAccount?.activated == true;
    if (restoredSession) {
      _selectedMode = null;
      _selectedWorkArea = null;
      if (_authenticatedAccount?.kind == TerminalAccountKind.user &&
          _availableWorkAreas.isNotEmpty) {
        _supportedModes = _authenticatedAccount!.supportedModes;
        _loginStage = TerminalLoginStage.areaSelection;
        _appendWorkAreaList();
        _append(
          TerminalLineType.system,
          '복원된 로그인 세션은 유지됩니다. 업무 지역을 입력하세요.',
        );
      } else {
        _loginStage = TerminalLoginStage.modeSelection;
        _appendSupportedModeList();
        _append(
          TerminalLineType.system,
          '복원된 로그인 세션은 유지됩니다. 사용할 모드를 입력하세요.',
        );
      }
      LauncherDiagnostics.record(
        'auth_navigation_cancel',
        meta: const <String, Object?>{
          'sessionPreserved': true,
          'firebaseReads': 0,
          'firebaseWrites': 0,
        },
      );
      notifyListeners();
      return const ModeLauncherSubmitResult();
    }
    if (_accountKindAutoSelected && _selectedAccountKind != null) {
      _authenticatedAccount = null;
      _availableWorkAreas = <LauncherWorkAreaOption>[];
      _selectedWorkArea = null;
      _supportedModes = <AppModeDefinition>[];
      _selectedMode = null;
      _enteredName = '';
      _enteredPhone = '';
      _enteredPassword = '';
      _loginStage = TerminalLoginStage.name;
      _append(TerminalLineType.success, '[ OK ] 로그인 입력을 초기화했습니다.');
      _append(TerminalLineType.system, _namePrompt);
      LauncherDiagnostics.record(
        'auth_navigation_cancel',
        meta: <String, Object?>{
          'sessionPreserved': false,
          'autoAccountKindPreserved': true,
          'startupPurpose': _startupPurpose?.storageValue ?? '',
          'accountKind': TerminalAuthCoordinator.accountKindId(
            _selectedAccountKind!,
          ),
          'firebaseReads': 0,
          'firebaseWrites': 0,
        },
      );
      notifyListeners();
      return const ModeLauncherSubmitResult(promptText: '');
    }
    _selectedAccountKind = null;
    _authenticatedAccount = null;
    _availableWorkAreas = <LauncherWorkAreaOption>[];
    _selectedWorkArea = null;
    _supportedModes = <AppModeDefinition>[];
    _selectedMode = null;
    _enteredName = '';
    _enteredPhone = '';
    _enteredPassword = '';
    _debugAccountKindOverride = _debugOverrideSnapshotActive;
    _sessionPersistence = _debugOverrideSnapshotActive
        ? TerminalSessionPersistence.ephemeral
        : TerminalSessionPersistence.persistent;
    _loginStage = TerminalLoginStage.accountType;
    _append(TerminalLineType.success, '[ OK ] 로그인 입력을 취소했습니다.');
    _appendAccountTypeList();
    _append(TerminalLineType.system, '계정 유형을 입력하세요.');
    LauncherDiagnostics.record(
      'auth_navigation_cancel',
      meta: const <String, Object?>{
        'sessionPreserved': false,
        'autoAccountKindPreserved': false,
        'firebaseReads': 0,
        'firebaseWrites': 0,
      },
    );
    notifyListeners();
    return const ModeLauncherSubmitResult();
  }

  ModeLauncherSubmitResult _returnToModeSelection() {
    final account = _authenticatedAccount;
    if (account == null) {
      _append(
        TerminalLineType.system,
        '로그인 후 업무 지역과 지원 모드를 선택할 수 있습니다.',
      );
      return const ModeLauncherSubmitResult();
    }
    _selectedMode = null;
    if (account.kind == TerminalAccountKind.user && _availableWorkAreas.isNotEmpty) {
      _selectedWorkArea = null;
      _supportedModes = account.supportedModes;
      _loginStage = TerminalLoginStage.areaSelection;
      _appendWorkAreaList();
      _append(TerminalLineType.system, '업무 지역을 입력하세요.');
      LauncherDiagnostics.record(
        'auth_navigation_work_areas',
        meta: <String, Object?>{
          'areaCount': _availableWorkAreas.length,
          'firebaseReads': 0,
          'firebaseWrites': 0,
          'dataSource': 'sqlite',
        },
      );
    } else if (_supportedModes.isNotEmpty) {
      _loginStage = TerminalLoginStage.modeSelection;
      _appendSupportedModeList();
      _append(TerminalLineType.system, '사용할 모드를 입력하세요.');
      LauncherDiagnostics.record(
        'auth_navigation_modes',
        meta: <String, Object?>{
          'supportedModes': _supportedModes.map((mode) => mode.id).join(','),
          'firebaseReads': 0,
          'firebaseWrites': 0,
        },
      );
    }
    notifyListeners();
    return const ModeLauncherSubmitResult();
  }

  bool _requiresImportingUnlock(String normalized) {
    return _protectedCommands.contains(normalized);
  }

  Future<ModeLauncherSubmitResult> _unlockImporting(
    BuildContext context, {
    required bool reduceMotion,
  }) async {
    if (_importingUnlocked) {
      _append(TerminalLineType.success, '[ OK ] protected commands enabled');
      notifyListeners();
      return const ModeLauncherSubmitResult();
    }
    _busy = true;
    _runningCommand = 'AUTH';
    _append(TerminalLineType.running, 'authorizing');
    LauncherDiagnostics.record(
      'terminal_importing_unlock_start',
      scope: 'mode_terminal',
      meta: <String, Object?>{
        'path': _commandPath.promptPath,
        'command': '<hidden>',
      },
    );
    notifyListeners();
    await _commandDelay(reduceMotion);
    if (_disposed || !context.mounted) {
      _busy = false;
      _runningCommand = '';
      return const ModeLauncherSubmitResult();
    }
    _importingUnlocked = true;
    _busy = false;
    _runningCommand = '';
    _append(TerminalLineType.success, '[ OK ] protected commands enabled');
    LauncherDiagnostics.record(
      'terminal_importing_unlock_complete',
      scope: 'mode_terminal',
      meta: <String, Object?>{
        'path': _commandPath.promptPath,
        'command': '<hidden>',
      },
    );
    notifyListeners();
    await LauncherDiagnostics.showStatus(
      context,
      title: 'Terminal Session Status',
      description: 'protectedCommands=enabled\nscope=session',
      scope: 'mode_terminal',
    );
    return const ModeLauncherSubmitResult();
  }

  ModeLauncherSubmitResult _rejectProtectedCommand(String normalized) {
    _append(TerminalLineType.error, '[DENIED] command locked');
    _errorSerial += 1;
    LauncherDiagnostics.record(
      'terminal_protected_command_denied',
      scope: 'mode_terminal',
      meta: <String, Object?>{
        'command': normalized,
        'path': _commandPath.promptPath,
      },
    );
    notifyListeners();
    return const ModeLauncherSubmitResult();
  }

  Future<ModeLauncherSubmitResult> executeUtilityCommand(
    BuildContext context,
    String command, {
    required bool reduceMotion,
  }) async {
    if (_busy || _disposed) return const ModeLauncherSubmitResult();
    final input = command.trim();
    final normalized = AppModeRegistry.normalizeToken(input);
    if (!const <String>{
      'out',
      'exit',
      'setting',
    }.contains(normalized)) {
      return const ModeLauncherSubmitResult();
    }
    LauncherDiagnostics.record(
      'terminal_header_command',
      scope: 'mode_terminal',
      meta: <String, Object?>{'command': normalized},
    );
    return _submitGlobalCommand(
      context,
      input,
      normalized,
      reduceMotion: reduceMotion,
    );
  }

  bool _isGlobalCommand(String normalized) {
    return const <String>{
      'modes', 'mode', '모드', 'help', 'status', '상태',
      'setting', 'quick', 'update', '업데이트',
      'signup', '회원가입', 'support', '문의', 'clear', 'cls', '지우기',
      'out', 'exit', '종료', 'debug', 'charge', 'practice', '연습', 'dev', '개발',
    }.contains(normalized);
  }

  Future<ModeLauncherSubmitResult> _submitGlobalCommand(
    BuildContext context,
    String input,
    String normalized, {
    required bool reduceMotion,
  }) async {
    if (_requiresImportingUnlock(normalized) && !_importingUnlocked) {
      return _rejectProtectedCommand(normalized);
    }
    switch (normalized) {
      case 'setting':
        final from = _commandPath.promptPath;
        _commandPath = TerminalCommandPath.setting;
        LauncherDiagnostics.record(
          'terminal_path_enter',
          scope: 'mode_terminal',
          meta: <String, Object?>{
            'from': from,
            'to': _commandPath.promptPath,
          },
        );
        notifyListeners();
        return const ModeLauncherSubmitResult();
      case 'quick':
        _busy = true;
        _runningCommand = 'quick';
        _append(TerminalLineType.running, 'quick');
        await _commandDelay(reduceMotion);
        await HeadHubActions.init();
        HeadHubActions.setEnabled(true);
        await HeadHubActions.mountIfNeeded();
        _busy = false;
        _runningCommand = '';
        _append(TerminalLineType.success, '[ OK ] quick');
        LauncherDiagnostics.record(
          'terminal_quick',
          scope: 'mode_terminal',
          meta: <String, Object?>{
            'path': _commandPath.promptPath,
            'importingUnlocked': _importingUnlocked,
          },
        );
        notifyListeners();
        await LauncherDiagnostics.showStatus(
          context,
          title: 'Terminal Command Status',
          description: 'command=quick\nresult=success\nprotectedCommands=enabled',
          scope: 'mode_terminal',
        );
        return const ModeLauncherSubmitResult();
      case 'modes':
      case 'mode':
      case '모드':
        _appendModeList();
        return const ModeLauncherSubmitResult();
      case 'help':
        await _appendCommandList(reduceMotion);
        return const ModeLauncherSubmitResult();
      case 'status':
      case '상태':
        await _refreshLiveStatus();
        final gmailStatus = await GmailSenderAuth.status();
        _appendStatus();
        _append(
          TerminalLineType.output,
          'Gmail configured    ${gmailStatus.configuredEmail.isEmpty ? '-' : gmailStatus.configuredEmail}',
        );
        _append(
          TerminalLineType.output,
          'Gmail authenticated ${gmailStatus.authenticatedEmail.isEmpty ? '-' : gmailStatus.authenticatedEmail}',
        );
        _append(
          gmailStatus.matches ? TerminalLineType.success : TerminalLineType.system,
          'Gmail sender state  ${gmailStatus.state}',
        );
        if (_devModeEnabled && context.mounted) {
          final completion = LauncherDiagnostics.showStatus(
            context,
            title: 'Launcher Status',
            description: '${developerStatusDescription()}\n${gmailStatus.developerDescription}',
            scope: 'mode_terminal',
          );
          return ModeLauncherSubmitResult(surfaceCompletion: completion);
        }
        return const ModeLauncherSubmitResult();
      case 'update':
      case '업데이트':
        return _launchSurface(
          context,
          'update',
          () => LauncherActions.openUpdate(context),
          reduceMotion: reduceMotion,
        );
      case 'signup':
      case '회원가입':
        return _launchSurface(
          context,
          'signup',
          () => LauncherActions.openPersonalSignup(context),
          reduceMotion: reduceMotion,
        );
      case 'support':
      case '문의':
        _busy = true;
        _runningCommand = 'support';
        _append(TerminalLineType.running, 'Opening support');
        await _commandDelay(reduceMotion);
        final opened = await LauncherActions.openSupport();
        _busy = false;
        _runningCommand = '';
        _append(
          opened ? TerminalLineType.success : TerminalLineType.error,
          opened ? '[ OK ] Support opened' : '[ERROR] Support open failed',
        );
        if (!opened) _errorSerial += 1;
        notifyListeners();
        return const ModeLauncherSubmitResult();
      case 'clear':
      case 'cls':
      case '지우기':
        _lines.clear();
        notifyListeners();
        LauncherDiagnostics.record('terminal_clear');
        return const ModeLauncherSubmitResult();
      case 'out':
        _append(TerminalLineType.system, 'Closing ParkinWorkin Terminal');
        LauncherDiagnostics.record('terminal_out');
        return const ModeLauncherSubmitResult(targetRoute: AppRoutes.powerBoot);
      case 'exit':
      case '종료':
        if (_busy) return const ModeLauncherSubmitResult();
        _busy = true;
        _runningCommand = 'exit';
        _append(TerminalLineType.system, 'Powering off ParkinWorkin');
        LauncherDiagnostics.record(
          'terminal_exit_lock_start',
          scope: 'mode_terminal',
          meta: <String, Object?>{
            'busy': _busy,
            'runningCommand': _runningCommand,
          },
        );
        notifyListeners();
        try {
          if (!reduceMotion) {
            await Future<void>.delayed(const Duration(milliseconds: 160));
          }
          if (_disposed || !context.mounted) {
            return const ModeLauncherSubmitResult(routeReplaced: true);
          }
          LauncherDiagnostics.record(
            'terminal_exit_requested',
            scope: 'mode_terminal',
          );
          await LauncherActions.exitApp(context);
          if (!_disposed) {
            LauncherDiagnostics.record(
              'terminal_exit_action_returned',
              scope: 'mode_terminal',
            );
          }
          return const ModeLauncherSubmitResult(routeReplaced: true);
        } finally {
          if (!_disposed) {
            _busy = false;
            _runningCommand = '';
            LauncherDiagnostics.record(
              'terminal_exit_lock_release',
              scope: 'mode_terminal',
              meta: <String, Object?>{
                'busy': _busy,
                'runningCommand': _runningCommand,
              },
            );
            notifyListeners();
          }
        }
      case 'debug':
        final stageBeforeDebug = _loginStage;
        _busy = true;
        _runningCommand = 'debug';
        _append(TerminalLineType.running, 'Activating DEBUG session');
        await _commandDelay(reduceMotion);
        await DebugSessionController.enable(source: 'mode_terminal');
        await DevQuickActions.mountIfNeeded();
        _busy = false;
        _runningCommand = '';
        _append(TerminalLineType.success, '[ OK ] DEBUG session active');
        LauncherDiagnostics.record(
          'terminal_debug_enabled',
          scope: 'mode_terminal',
          meta: <String, Object?>{
            'authStage': stageBeforeDebug.name,
            'startupPurpose': _startupPurpose?.storageValue ?? '',
            'accountKind': _selectedAccountKind == null
                ? ''
                : TerminalAuthCoordinator.accountKindId(
                    _selectedAccountKind!,
                  ),
            'autoSelected': _accountKindAutoSelected,
            'importingUnlocked': _importingUnlocked,
          },
        );
        notifyListeners();
        await LauncherDiagnostics.showStatus(
          context,
          title: 'Terminal Command Status',
          description: 'command=debug\nresult=success\nprotectedCommands=enabled',
          scope: 'mode_terminal',
        );
        return const ModeLauncherSubmitResult();
      case 'charge':
        return _launchSurface(
          context,
          'charge',
          () async {
            await showPlateBillingCountDialog(context);
            if (!context.mounted) return;
            LauncherDiagnostics.record(
              'terminal_charge_complete',
              scope: 'mode_terminal',
              meta: <String, Object?>{
                'importingUnlocked': _importingUnlocked,
              },
            );
            await LauncherDiagnostics.showStatus(
              context,
              title: 'Terminal Command Status',
              description: 'command=charge\nresult=success\nprotectedCommands=enabled',
              scope: 'mode_terminal',
            );
          },
          reduceMotion: reduceMotion,
        );
      case 'practice':
      case '연습':
        if (!_devAuthorized) return _rejectDeveloperCommand(normalized);
        return _launchSurface(
          context,
          'practice',
          () => LauncherActions.openPractice(context),
          reduceMotion: reduceMotion,
        );
      case 'dev':
      case '개발':
        if (!_devAuthorized) return _rejectDeveloperCommand(normalized);
        _busy = true;
        _runningCommand = 'dev';
        _append(TerminalLineType.running, 'Opening developer');
        await _commandDelay(reduceMotion);
        if (!context.mounted) {
          _busy = false;
          _runningCommand = '';
          return const ModeLauncherSubmitResult();
        }
        _busy = false;
        _runningCommand = '';
        notifyListeners();
        unawaited(LauncherActions.openDev(context));
        return const ModeLauncherSubmitResult(routeReplaced: true);
      default:
        _append(TerminalLineType.error, '[ERROR] 알 수 없는 명령입니다: $input');
        _errorSerial += 1;
        LauncherDiagnostics.record(
          'terminal_unknown_command',
          meta: <String, Object?>{
            'input': input,
            'path': _commandPath.promptPath,
          },
        );
        notifyListeners();
        return const ModeLauncherSubmitResult();
    }
  }

  Future<ModeLauncherSubmitResult> _submitSettingPathCommand(
    BuildContext context,
    String input,
    String normalized, {
    required bool reduceMotion,
  }) async {
    if (_commandPath.isEmailEdit) {
      if (normalized == 'cancel' || normalized == 'cd ..') {
        final from = _commandPath.promptPath;
        _commandPath = TerminalCommandPath.setting;
        _append(TerminalLineType.system, '[ok] email edit cancelled');
        LauncherDiagnostics.record(
          'terminal_email_edit_cancel',
          scope: 'mode_terminal',
          meta: <String, Object?>{
            'from': from,
            'to': _commandPath.promptPath,
          },
        );
        notifyListeners();
        return const ModeLauncherSubmitResult();
      }
      if (normalized == 'out' || normalized == 'exit') {
        return _submitGlobalCommand(
          context,
          input,
          normalized,
          reduceMotion: reduceMotion,
        );
      }
      return _runEmailEdit(
        context,
        input,
        reduceMotion: reduceMotion,
      );
    }
    if (normalized == 'setting') {
      return const ModeLauncherSubmitResult();
    }
    if (normalized == 'cd ..') {
      final from = _commandPath.promptPath;
      _commandPath = TerminalCommandPath.root;
      LauncherDiagnostics.record(
        'terminal_path_leave',
        scope: 'mode_terminal',
        meta: <String, Object?>{
          'from': from,
          'to': _commandPath.promptPath,
        },
      );
      notifyListeners();
      return const ModeLauncherSubmitResult();
    }
    if (normalized == 'out' || normalized == 'exit') {
      return _submitGlobalCommand(
        context,
        input,
        normalized,
        reduceMotion: reduceMotion,
      );
    }
    return _runServiceSettingCommand(
      context,
      input,
      reduceMotion: reduceMotion,
    );
  }

  Future<ModeLauncherSubmitResult> _runServiceSettingCommand(
    BuildContext context,
    String input, {
    required bool reduceMotion,
  }) async {
    _busy = true;
    _runningCommand = input.split(' ').first;
    _append(TerminalLineType.running, _runningCommand);
    await _commandDelay(reduceMotion);
    if (!context.mounted) {
      _busy = false;
      _runningCommand = '';
      notifyListeners();
      return const ModeLauncherSubmitResult();
    }
    final result = await ServiceSettingsCommandHandler.execute(
      context,
      input,
      source: 'mode_terminal',
    );
    final previousPath = _commandPath;
    if (result.nextPath != null) {
      _commandPath = result.nextPath!;
      LauncherDiagnostics.record(
        'terminal_setting_path_change',
        scope: 'mode_terminal',
        meta: <String, Object?>{
          'from': previousPath.promptPath,
          'to': _commandPath.promptPath,
        },
      );
    }
    _busy = false;
    _runningCommand = '';
    for (final line in result.lines) {
      _append(
        result.succeeded ? TerminalLineType.output : TerminalLineType.error,
        line,
      );
    }
    if (!result.succeeded) {
      _errorSerial += 1;
    }
    LauncherDiagnostics.record(
      result.succeeded ? 'setting_command_complete' : 'setting_command_rejected',
      scope: 'mode_terminal',
      meta: <String, Object?>{'input': input},
    );
    notifyListeners();
    return const ModeLauncherSubmitResult();
  }

  Future<ModeLauncherSubmitResult> _runEmailEdit(
    BuildContext context,
    String input, {
    required bool reduceMotion,
  }) async {
    _busy = true;
    _runningCommand = 'email';
    _append(TerminalLineType.running, 'email');
    await _commandDelay(reduceMotion);
    if (!context.mounted) {
      _busy = false;
      _runningCommand = '';
      notifyListeners();
      return const ModeLauncherSubmitResult();
    }
    final result = await ServiceSettingsCommandHandler.submitEmailEdit(
      context,
      input,
      source: 'mode_terminal',
    );
    for (final line in result.lines) {
      _append(
        result.succeeded ? TerminalLineType.output : TerminalLineType.error,
        line,
      );
    }
    if (result.nextPath != null) {
      final from = _commandPath.promptPath;
      _commandPath = result.nextPath!;
      LauncherDiagnostics.record(
        'terminal_email_edit_path_change',
        scope: 'mode_terminal',
        meta: <String, Object?>{
          'from': from,
          'to': _commandPath.promptPath,
        },
      );
    }
    if (!result.succeeded) _errorSerial += 1;
    _busy = false;
    _runningCommand = '';
    notifyListeners();
    await ServiceSettingsCommandHandler.showEmailEditDeveloperStatus(
      context,
      succeeded: result.succeeded,
    );
    return const ModeLauncherSubmitResult();
  }

  Future<void> _bootstrapAuthentication(
    BuildContext context, {
    required bool reduceMotion,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    _startupPurpose ??= await AppStartFlowPrefs.getUserPurpose();
    _defaultAccountKind =
        TerminalAuthCoordinator.accountKindForPurpose(_startupPurpose);
    LauncherDiagnostics.record(
      'auth_startup_purpose_resolved',
      meta: <String, Object?>{
        'startupPurpose': _startupPurpose?.storageValue ?? '',
        'defaultAccountKind': _defaultAccountKind == null
            ? ''
            : TerminalAuthCoordinator.accountKindId(_defaultAccountKind!),
        'defaultAccountNumber': _defaultAccountKind == null
            ? 0
            : TerminalAuthCoordinator.accountKindNumber(_defaultAccountKind!),
      },
    );
    final kind = await TerminalAuthCoordinator.readLocalRestoreKind(
      savedMode: _savedModeRaw,
    );

    if (kind != null && context.mounted) {
      _busy = true;
      _runningCommand = 'SESSION';
      _append(TerminalLineType.running, 'Checking previous session');
      final restored = await TerminalAuthCoordinator.tryRestoreAccount(
        context,
        kind: kind,
        savedMode: _savedModeRaw,
      );
      _busy = false;
      _runningCommand = '';
      if (_disposed || !context.mounted) return;

      final account = restored.account;
      if (restored.success && account != null) {
        _accountKindAutoSelected = false;
        _debugAccountKindOverride = false;
        _debugOverrideSnapshotActive = false;
        _sessionPersistence = TerminalSessionPersistence.persistent;
        _selectedAccountKind = account.kind;
        _authenticatedAccount = account;
        _supportedModes = account.supportedModes;
        _availableWorkAreas = <LauncherWorkAreaOption>[];
        _selectedWorkArea = null;
        LauncherWorkAreaResolution? restoreWorkAreaResolution;
        if (account.kind == TerminalAccountKind.user && account.user != null) {
          restoreWorkAreaResolution = await _resolveLauncherWorkAreas(
            context,
            account: account,
            reduceMotion: reduceMotion,
          );
          _availableWorkAreas = restoreWorkAreaResolution.areas;
        }
        _enteredName = account.displayName;
        _append(TerminalLineType.success, '[ OK ] ${restored.message}');
        LauncherDiagnostics.record(
          'auth_account_restored',
          meta: <String, Object?>{
            'accountKind': TerminalAuthCoordinator.accountKindId(account.kind),
            'supportedModes': _supportedModes.map((mode) => mode.id).join(','),
            'startupPurpose': _startupPurpose?.storageValue ?? '',
            'restorePriority': 'session_before_startup_purpose',
          },
        );

        final savedMode = AppModeRegistry.findLegacy(_savedModeRaw);
        final savedModeAllowed = savedMode != null &&
            _supportedModes.any((mode) => mode.id == savedMode.id);

        if (account.kind == TerminalAccountKind.user) {
          _selectedMode = savedModeAllowed ? savedMode : null;
          _loginStage = TerminalLoginStage.areaSelection;
          if (_availableWorkAreas.isEmpty) {
            _append(
              TerminalLineType.error,
              '[ERROR] 사용할 수 있는 업무 지역이 없습니다.',
            );
            LauncherDiagnostics.record(
              'auth_restore_work_area_selection_blocked',
              meta: <String, Object?>{
                'reason': 'work_area_resolution_empty',
                'dataSource': restoreWorkAreaResolution?.dataSource ?? 'none',
                'firebaseAreaDocumentReads':
                    restoreWorkAreaResolution?.firebaseAreaDocumentReads ?? 0,
                'firebaseWrites': 0,
              },
            );
            _errorSerial += 1;
            notifyListeners();
            return;
          }
          await _appendWorkAreaListPaced(reduceMotion);
          final firstArea = _availableWorkAreas.first;
          LauncherDiagnostics.record(
            'auth_restore_work_area_selection_ready',
            meta: <String, Object?>{
              'areaCount': _availableWorkAreas.length,
              'firstArea': firstArea.areaName,
              'firstIsHeadquarter': firstArea.isHeadquarter,
              'savedMode': savedModeAllowed ? savedMode.id : '',
              'firebaseAreaDocumentReads':
                  restoreWorkAreaResolution?.firebaseAreaDocumentReads ?? 0,
              'firebaseWrites': 0,
              'dataSource': restoreWorkAreaResolution?.dataSource ?? 'none',
            },
          );
          final autoSelectReason = _workAreaAutoSelectReason();
          if (autoSelectReason != null) {
            _append(
              TerminalLineType.system,
              _workAreaAutoSelectMessage(autoSelectReason),
            );
            _pendingAutoSubmitText = '1';
            LauncherDiagnostics.record(
              'auth_restore_work_area_auto_input_queued',
              meta: <String, Object?>{
                'reason': autoSelectReason,
                'areaCount': _availableWorkAreas.length,
                'area': firstArea.areaName,
                'isHeadquarter': firstArea.isHeadquarter,
                'selectionNumber': 1,
                'supportedModes': firstArea.supportedModes
                    .map((mode) => mode.id)
                    .join(','),
                'firebaseAreaDocumentReads':
                    restoreWorkAreaResolution?.firebaseAreaDocumentReads ?? 0,
                'firebaseWrites': 0,
              },
            );
          } else {
            _append(TerminalLineType.system, '업무 지역을 입력하세요.');
          }
          notifyListeners();
          return;
        }

        if (savedModeAllowed) {
          _selectedMode = savedMode;
          _loginStage = TerminalLoginStage.activatingMode;
          _busy = true;
          _runningCommand = 'MODE';
          _append(
            TerminalLineType.success,
            '[ OK ] ${savedMode.koreanName}',
          );
          await _appendPaced(
            TerminalLineType.running,
            'Restoring runtime session',
            reduceMotion,
          );
          LauncherDiagnostics.record(
            'auth_saved_mode_resume_start',
            meta: <String, Object?>{
              'mode': savedMode.id,
              'targetRoute': savedMode.postLoginRoute,
            },
          );
          final activated = await TerminalAuthCoordinator.activateMode(
            context,
            account: account,
            mode: savedMode,
            persistence: TerminalSessionPersistence.persistent,
          );
          _busy = false;
          _runningCommand = '';
          if (_disposed || !context.mounted) return;
          if (!activated.success) {
            await prefs.remove('mode');
            _savedModeRaw = null;
            _assignedMode = null;
            _selectedMode = null;
            _append(
              TerminalLineType.error,
              '[FAILED] ${activated.message}',
            );
            _loginStage = TerminalLoginStage.modeSelection;
            await _appendSupportedModeListPaced(reduceMotion);
            _append(TerminalLineType.system, '사용할 모드를 입력하세요.');
            LauncherDiagnostics.record(
              'auth_saved_mode_resume_failed',
              meta: <String, Object?>{
                'mode': savedMode.id,
                'message': activated.message,
              },
            );
            notifyListeners();
            return;
          }
          _authenticatedAccount = account.copyWith(activated: true);
          _runtimeContextReady = true;
          _savedModeRaw = AppModeRegistry.persistedValue(savedMode.id);
          _assignedMode = savedMode;
          _append(TerminalLineType.success, '[ OK ] ${activated.message}');
          _pendingTargetRoute = savedMode.postLoginRoute;
          LauncherDiagnostics.record(
            'auth_runtime_context_ready',
            meta: <String, Object?>{
              'source': 'saved_mode_restore',
              'mode': savedMode.id,
              'targetRoute': savedMode.postLoginRoute,
            },
          );
          LauncherDiagnostics.record(
            'auth_saved_mode_resume_success',
            meta: <String, Object?>{
              'mode': savedMode.id,
              'targetRoute': savedMode.postLoginRoute,
            },
          );
          notifyListeners();
          return;
        }

        if ((_savedModeRaw ?? '').trim().isNotEmpty) {
          await prefs.remove('mode');
          _savedModeRaw = null;
          _assignedMode = null;
        }
        _loginStage = TerminalLoginStage.modeSelection;
        await _appendSupportedModeListPaced(reduceMotion);
        _append(TerminalLineType.system, '사용할 모드를 입력하세요.');
        notifyListeners();
        return;
      }

      if ((_savedModeRaw ?? '').trim().isNotEmpty) {
        await prefs.remove('mode');
        _savedModeRaw = null;
        _assignedMode = null;
      }
      _selectedAccountKind = null;
      _authenticatedAccount = null;
      _availableWorkAreas = <LauncherWorkAreaOption>[];
      _selectedWorkArea = null;
      _supportedModes = <AppModeDefinition>[];
      _selectedMode = null;
      _enteredName = '';
      _enteredPhone = '';
      _enteredPassword = '';
      _append(
        TerminalLineType.system,
        'Last account type: ${TerminalAuthCoordinator.accountKindLabel(kind)}',
      );
      LauncherDiagnostics.record(
        'auth_account_restore_fallback',
        meta: <String, Object?>{
          'lastAccountKind': TerminalAuthCoordinator.accountKindId(kind),
          'startupPurpose': _startupPurpose?.storageValue ?? '',
          'defaultAccountKind': _defaultAccountKind == null
              ? ''
              : TerminalAuthCoordinator.accountKindId(_defaultAccountKind!),
        },
      );
      if (await _selectStartupPurposeAccountKind(reduceMotion: reduceMotion)) {
        return;
      }
      await _showAccountTypeSelectionPaced(reduceMotion);
      return;
    }

    if (await _selectStartupPurposeAccountKind(reduceMotion: reduceMotion)) {
      return;
    }
    await _showAccountTypeSelectionPaced(reduceMotion);
  }

  Future<bool> _selectStartupPurposeAccountKind({
    required bool reduceMotion,
  }) async {
    final kind = _defaultAccountKind;
    if (kind == null) return false;
    await _selectAccountKind(
      kind,
      source: 'app_start_user_purpose',
      reduceMotion: reduceMotion,
      autoSelected: true,
      persistence: TerminalSessionPersistence.persistent,
    );
    return true;
  }

  Future<void> _showAccountTypeSelectionPaced(bool reduceMotion) async {
    _accountKindAutoSelected = false;
    _debugAccountKindOverride = false;
    _debugOverrideSnapshotActive = false;
    _sessionPersistence = TerminalSessionPersistence.persistent;
    _loginStage = TerminalLoginStage.accountType;
    await _appendPaced(
      TerminalLineType.system,
      'ACCOUNT TYPES',
      reduceMotion,
    );
    await _appendPaced(
      TerminalLineType.system,
      '────────────────────────────────────────',
      reduceMotion,
    );
    await _appendPaced(
      TerminalLineType.output,
      '1  일반 계정      user',
      reduceMotion,
    );
    await _appendPaced(
      TerminalLineType.output,
      '2  개인형 계정    personal',
      reduceMotion,
    );
    await _appendPaced(
      TerminalLineType.output,
      '3  태블릿형 계정  tablet',
      reduceMotion,
    );
    _append(TerminalLineType.system, '────────────────────────────────────────');
    _append(TerminalLineType.system, '계정 유형을 입력하세요.');
    LauncherDiagnostics.record(
      'auth_account_kind_manual_selection_opened',
      meta: <String, Object?>{
        'startupPurpose': _startupPurpose?.storageValue ?? '',
        'defaultAccountKind': _defaultAccountKind == null
            ? ''
            : TerminalAuthCoordinator.accountKindId(_defaultAccountKind!),
      },
    );
    notifyListeners();
  }

  Future<ModeLauncherSubmitResult> _selectAccountKind(
    TerminalAccountKind kind, {
    required String source,
    required bool reduceMotion,
    required bool autoSelected,
    required TerminalSessionPersistence persistence,
  }) async {
    final kindChanged = _selectedAccountKind != kind;
    _selectedAccountKind = kind;
    if (kindChanged) {
      _enteredName = '';
      _enteredPhone = '';
      _enteredPassword = '';
      _authenticatedAccount = null;
      _availableWorkAreas = <LauncherWorkAreaOption>[];
      _selectedWorkArea = null;
      _supportedModes = <AppModeDefinition>[];
      _selectedMode = null;
    }
    _accountKindAutoSelected = autoSelected;
    _sessionPersistence = persistence;
    if (autoSelected) {
      _debugAccountKindOverride = false;
      _debugOverrideSnapshotActive = false;
      _busy = true;
      _runningCommand = 'ACCOUNT';
      _append(TerminalLineType.running, 'Applying account profile');
      notifyListeners();
      await _commandDelay(reduceMotion);
      if (_disposed) {
        _busy = false;
        _runningCommand = '';
        return const ModeLauncherSubmitResult();
      }
    }
    if (persistence == TerminalSessionPersistence.persistent) {
      await TerminalAuthCoordinator.persistAccountKind(kind);
    } else {
      await LauncherDebugAccountOverrideStore.clearAccountKindBinding();
    }
    if (autoSelected) {
      _busy = false;
      _runningCommand = '';
      _append(
        TerminalLineType.success,
        '[ OK ] ACCOUNT ${TerminalAuthCoordinator.accountKindLabel(kind)}',
      );
    } else {
      _append(
        TerminalLineType.output,
        'ACCOUNT  ${TerminalAuthCoordinator.accountKindLabel(kind)}',
      );
    }
    LauncherDiagnostics.record(
      autoSelected
          ? 'auth_account_kind_auto_selected'
          : 'auth_account_kind_selected',
      meta: <String, Object?>{
        'accountKind': TerminalAuthCoordinator.accountKindId(kind),
        'accountNumber': TerminalAuthCoordinator.accountKindNumber(kind),
        'source': source,
        'startupPurpose': _startupPurpose?.storageValue ?? '',
        'defaultAccountKind': _defaultAccountKind == null
            ? ''
            : TerminalAuthCoordinator.accountKindId(_defaultAccountKind!),
        'autoSelected': autoSelected,
        'debugOverride': _debugAccountKindOverride,
        'sessionPersistence': TerminalAuthCoordinator.sessionPersistenceId(
          _sessionPersistence,
        ),
        'debugSnapshotActive': _debugOverrideSnapshotActive,
      },
    );
    DebugSessionController.record(
      autoSelected
          ? 'auth_account_kind_auto_selected'
          : 'auth_account_kind_selected',
      source: 'mode_terminal',
      meta: <String, Object?>{
        'accountKind': TerminalAuthCoordinator.accountKindId(kind),
        'accountNumber': TerminalAuthCoordinator.accountKindNumber(kind),
        'selectionSource': source,
        'startupPurpose': _startupPurpose?.storageValue ?? '',
        'debugOverride': _debugAccountKindOverride,
        'sessionPersistence': TerminalAuthCoordinator.sessionPersistenceId(
          _sessionPersistence,
        ),
        'debugSnapshotActive': _debugOverrideSnapshotActive,
      },
    );
    _loginStage = TerminalLoginStage.name;
    _append(TerminalLineType.system, _namePrompt);
    notifyListeners();
    return ModeLauncherSubmitResult(
      promptText: _enteredName.isEmpty ? null : _enteredName,
      selectPromptText: _enteredName.isNotEmpty,
    );
  }


  Future<LauncherWorkAreaResolution> _resolveLauncherWorkAreas(
    BuildContext context, {
    required TerminalAuthenticatedAccount account,
    required bool reduceMotion,
  }) async {
    final user = account.user;
    if (user == null) {
      return const LauncherWorkAreaResolution(
        hasSnapshot: false,
        division: '',
        areas: <LauncherWorkAreaOption>[],
        dataSource: 'user_missing',
      );
    }
    final local = await LauncherWorkAreaResolver.resolve(
      user: user,
      accountModes: account.supportedModes,
    );
    if (local.hasSnapshot || local.areas.isNotEmpty) return local;
    await _appendPaced(
      TerminalLineType.running,
      'Local work area snapshot unavailable',
      reduceMotion,
    );
    final authorizedAreaCount = user.areas
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .length;
    await _appendPaced(
      TerminalLineType.running,
      authorizedAreaCount == 1
          ? 'Checking authorized work area'
          : 'Restoring primary work area',
      reduceMotion,
    );
    final resolved = await LauncherWorkAreaServerResolver.resolve(
      user: user,
      accountModes: account.supportedModes,
      areaRepository: context.read<AreaRepository>(),
    );
    LauncherDiagnostics.record(
      'auth_work_area_snapshot_miss_fallback_complete',
      meta: <String, Object?>{
        'authorizedAreaCount': authorizedAreaCount,
        'availableAreaCount': resolved.areas.length,
        'dataSource': resolved.dataSource,
        'firebaseAreaDocumentReads': resolved.firebaseAreaDocumentReads,
        'serverFallbackUsed': resolved.serverFallbackUsed,
      },
    );
    return resolved;
  }

  Future<LauncherWorkAreaOption?> _verifyBootstrapWorkArea(
    BuildContext context, {
    required TerminalAuthenticatedAccount account,
    required LauncherWorkAreaOption area,
    required bool reduceMotion,
  }) async {
    if (!area.requiresServerAreaResolution) return area;
    final user = account.user;
    if (user == null) return null;
    _busy = true;
    _runningCommand = 'AREA';
    _append(
      TerminalLineType.running,
      'Verifying ${area.areaName}',
    );
    LauncherDiagnostics.record(
      'auth_work_area_first_array_verification_start',
      meta: <String, Object?>{
        'division': area.division,
        'area': area.areaName,
        'arrayIndex': 0,
        'firebaseAreaDocumentReadAttempt': 1,
      },
    );
    notifyListeners();
    await _commandDelay(reduceMotion);
    final verified = await LauncherWorkAreaServerResolver.verifyArea(
      division: area.division,
      areaName: area.areaName,
      accountModes: account.supportedModes,
      areaRepository: context.read<AreaRepository>(),
      source: 'multi_area_first_array_selection',
    );
    _busy = false;
    _runningCommand = '';
    if (verified == null) {
      LauncherDiagnostics.record(
        'auth_work_area_first_array_verification_failed',
        meta: <String, Object?>{
          'division': area.division,
          'area': area.areaName,
          'arrayIndex': 0,
          'firebaseAreaDocumentReads': 1,
        },
      );
      notifyListeners();
      return null;
    }
    final index = _availableWorkAreas.indexWhere(
      (item) => item.areaName == area.areaName,
    );
    if (index >= 0) {
      final updated = List<LauncherWorkAreaOption>.of(_availableWorkAreas);
      updated[index] = verified;
      _availableWorkAreas = updated;
    }
    LauncherDiagnostics.record(
      'auth_work_area_first_array_verification_success',
      meta: <String, Object?>{
        'division': verified.division,
        'area': verified.areaName,
        'arrayIndex': 0,
        'isHeadquarter': verified.isHeadquarter,
        'supportedModes': verified.supportedModes
            .map((mode) => mode.id)
            .join(','),
        'firebaseAreaDocumentReads': 1,
        'verifiedRecordReusedForActivation': true,
      },
    );
    notifyListeners();
    return verified;
  }

  String? _workAreaAutoSelectReason() {
    if (_availableWorkAreas.isEmpty) return null;
    if (_availableWorkAreas.length == 1) return 'single_area';
    if (_availableWorkAreas.first.isHeadquarter) {
      return 'headquarter_priority';
    }
    return null;
  }

  String _workAreaAutoSelectMessage(String reason) {
    if (reason == 'single_area') {
      return '업무 지역이 1개이므로 1번을 자동 선택합니다.';
    }
    return '본사 1번을 자동 선택합니다.';
  }

  LauncherWorkAreaOption? _findWorkArea(String input) {
    final numeric = int.tryParse(input.trim());
    if (numeric != null &&
        numeric >= 1 &&
        numeric <= _availableWorkAreas.length) {
      return _availableWorkAreas[numeric - 1];
    }
    final normalized = input.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    for (final area in _availableWorkAreas) {
      if (area.areaName.toLowerCase() == normalized ||
          (area.isHeadquarter &&
              const <String>{'본사', 'headquarter', 'hq'}.contains(normalized))) {
        return area;
      }
    }
    return null;
  }

  AppModeDefinition? _findSupportedMode(String input) {
    final numeric = int.tryParse(input.trim());
    if (numeric != null && numeric >= 1 && numeric <= _supportedModes.length) {
      return _supportedModes[numeric - 1];
    }
    final mode = AppModeRegistry.find(input);
    if (mode == null) return null;
    for (final supported in _supportedModes) {
      if (supported.id == mode.id) return supported;
    }
    return null;
  }

  void _resetAccountSelection() {
    _selectedAccountKind = null;
    _authenticatedAccount = null;
    _availableWorkAreas = <LauncherWorkAreaOption>[];
    _selectedWorkArea = null;
    _supportedModes = <AppModeDefinition>[];
    _selectedMode = null;
    _enteredName = '';
    _enteredPhone = '';
    _enteredPassword = '';
    _accountKindAutoSelected = false;
    if (!_debugAccountKindOverride) {
      _sessionPersistence = TerminalSessionPersistence.persistent;
      _debugOverrideSnapshotActive = false;
    }
    _loginStage = TerminalLoginStage.accountType;
    _appendAccountTypeList();
    _append(TerminalLineType.system, '계정 유형을 입력하세요.');
    LauncherDiagnostics.record(
      'auth_account_kind_reset',
      meta: <String, Object?>{
        'debugOverride': _debugAccountKindOverride,
        'startupPurpose': _startupPurpose?.storageValue ?? '',
        'sessionPersistence': TerminalAuthCoordinator.sessionPersistenceId(
          _sessionPersistence,
        ),
        'debugSnapshotActive': _debugOverrideSnapshotActive,
      },
    );
    notifyListeners();
  }

  Future<ModeLauncherSubmitResult> _activateSelectedHeadquarter(
    BuildContext context, {
    required TerminalAuthenticatedAccount account,
    required bool reduceMotion,
  }) async {
    final workArea = _selectedWorkArea;
    if (workArea == null || !workArea.isHeadquarter) {
      _append(TerminalLineType.error, '[ERROR] 본사 업무 지역을 확인할 수 없습니다.');
      _errorSerial += 1;
      notifyListeners();
      return const ModeLauncherSubmitResult();
    }
    _loginStage = TerminalLoginStage.activatingMode;
    _busy = true;
    _runningCommand = 'HEADQUARTER';
    _append(
      TerminalLineType.running,
      'Preparing ${workArea.areaName}',
    );
    LauncherDiagnostics.record(
      'auth_headquarter_selected',
      meta: <String, Object?>{
        'area': workArea.areaName,
        'isHeadquarter': true,
        'modeIndependent': true,
        'postLoginRoute': AppRoutes.headquarterCommute,
        'sessionPersistence': TerminalAuthCoordinator.sessionPersistenceId(
          _sessionPersistence,
        ),
      },
    );
    notifyListeners();
    await _commandDelay(reduceMotion);
    if (_disposed || !context.mounted) {
      _busy = false;
      _runningCommand = '';
      return const ModeLauncherSubmitResult();
    }
    final activated = await TerminalAuthCoordinator.activateHeadquarterContext(
      context,
      account: account,
      targetArea: workArea.areaName,
      persistence: _sessionPersistence,
      verifiedAreaRecord: workArea.verifiedAreaRecord,
    );
    if (_disposed || !context.mounted) {
      _busy = false;
      _runningCommand = '';
      return const ModeLauncherSubmitResult();
    }
    if (!activated.success) {
      _append(TerminalLineType.error, '[ERROR] ${activated.message}');
      _busy = false;
      _runningCommand = '';
      _loginStage = TerminalLoginStage.areaSelection;
      _errorSerial += 1;
      notifyListeners();
      return const ModeLauncherSubmitResult();
    }
    _authenticatedAccount = account.copyWith(activated: true);
    _runtimeContextReady = true;
    _assignedMode = null;
    _selectedMode = null;
    _append(TerminalLineType.success, '[ OK ] ${activated.message}');
    _busy = false;
    _runningCommand = '';
    LauncherDiagnostics.record(
      'auth_runtime_context_ready',
      meta: <String, Object?>{
        'source': 'headquarter_activation',
        'area': workArea.areaName,
        'targetRoute': AppRoutes.headquarterCommute,
      },
    );
    LauncherDiagnostics.record(
      'auth_headquarter_activation_success',
      meta: <String, Object?>{
        'area': workArea.areaName,
        'modeIndependent': true,
        'persistMode': false,
        'publishMode': false,
        'targetRoute': AppRoutes.headquarterCommute,
        'firebaseAreaSelectionQueries': workArea.hasVerifiedAreaRecord ? 0 : 1,
        'firebaseWorkAreaListQueries': 0,
        'verifiedAreaRecordReused': workArea.hasVerifiedAreaRecord,
        'workAreaListSource': workArea.dataSource,
      },
    );
    notifyListeners();
    return const ModeLauncherSubmitResult(
      targetRoute: AppRoutes.headquarterCommute,
    );
  }

  Future<ModeLauncherSubmitResult> _activateSelectedMode(
    BuildContext context, {
    required TerminalAuthenticatedAccount account,
    required AppModeDefinition mode,
    required bool reduceMotion,
  }) async {
    final workArea = _selectedWorkArea;
    _loginStage = TerminalLoginStage.activatingMode;
    _busy = true;
    _runningCommand = 'MODE';
    _append(
      TerminalLineType.running,
      'Preparing ${mode.koreanName}',
    );
    LauncherDiagnostics.record(
      'auth_mode_selected',
      meta: <String, Object?>{
        'area': workArea?.areaName ?? '',
        'isHeadquarter': false,
        'mode': mode.id,
        'postLoginRoute': mode.postLoginRoute,
        'sessionPersistence': TerminalAuthCoordinator.sessionPersistenceId(
          _sessionPersistence,
        ),
      },
    );
    notifyListeners();
    await _commandDelay(reduceMotion);
    if (_disposed || !context.mounted) {
      _busy = false;
      _runningCommand = '';
      return const ModeLauncherSubmitResult();
    }
    final activated = await TerminalAuthCoordinator.activateMode(
      context,
      account: account,
      mode: mode,
      targetArea: workArea?.areaName ?? '',
      persistence: _sessionPersistence,
      verifiedAreaRecord: workArea?.verifiedAreaRecord,
    );
    if (_disposed || !context.mounted) {
      _busy = false;
      _runningCommand = '';
      return const ModeLauncherSubmitResult();
    }
    if (!activated.success) {
      _append(TerminalLineType.error, '[ERROR] ${activated.message}');
      _busy = false;
      _runningCommand = '';
      _loginStage = TerminalLoginStage.modeSelection;
      _errorSerial += 1;
      notifyListeners();
      return const ModeLauncherSubmitResult();
    }
    _authenticatedAccount = account.copyWith(activated: true);
    _runtimeContextReady = true;
    _savedModeRaw = AppModeRegistry.persistedValue(mode.id);
    _assignedMode = mode;
    _selectedMode = mode;
    _append(TerminalLineType.success, '[ OK ] ${activated.message}');
    _busy = false;
    _runningCommand = '';
    LauncherDiagnostics.record(
      'auth_runtime_context_ready',
      meta: <String, Object?>{
        'source': 'mode_activation',
        'area': workArea?.areaName ?? '',
        'mode': mode.id,
        'targetRoute': mode.postLoginRoute,
      },
    );
    LauncherDiagnostics.record(
      'auth_mode_activation_routed',
      meta: <String, Object?>{
        'area': workArea?.areaName ?? '',
        'mode': mode.id,
        'targetRoute': mode.postLoginRoute,
        'firebaseAreaSelectionQueries': workArea?.hasVerifiedAreaRecord == true ? 0 : 1,
        'firebaseWorkAreaListQueries': 0,
        'verifiedAreaRecordReused': workArea?.hasVerifiedAreaRecord == true,
        'workAreaListSource': workArea?.dataSource ?? 'none',
      },
    );
    notifyListeners();
    return ModeLauncherSubmitResult(targetRoute: mode.postLoginRoute);
  }

  Future<ModeLauncherSubmitResult> _submitAuthenticationInput(
    BuildContext context,
    String input, {
    required bool reduceMotion,
  }) async {
    final normalized = AppModeRegistry.normalizeToken(input);
    if ((normalized == 'account' ||
            normalized == '계정' ||
            normalized == '계정유형') &&
        _authenticatedAccount == null) {
      if (_accountKindAutoSelected) {
        _append(TerminalLineType.error, '[DENIED] Account type is automatic');
        _errorSerial += 1;
        LauncherDiagnostics.record(
          'auth_account_kind_manual_open_denied',
          meta: <String, Object?>{
            'startupPurpose': _startupPurpose?.storageValue ?? '',
            'accountKind': _selectedAccountKind == null
                ? ''
                : TerminalAuthCoordinator.accountKindId(
                    _selectedAccountKind!,
                  ),
            'debugMode': _devModeEnabled,
          },
        );
        notifyListeners();
        return const ModeLauncherSubmitResult();
      }
      _resetAccountSelection();
      return const ModeLauncherSubmitResult();
    }

    switch (_loginStage) {
      case TerminalLoginStage.accountType:
        final kind = TerminalAuthCoordinator.parseAccountKind(input);
        if (kind == null) {
          _append(TerminalLineType.error, '[ERROR] 계정 유형을 다시 확인하세요.');
          _errorSerial += 1;
          notifyListeners();
          return const ModeLauncherSubmitResult();
        }
        return _selectAccountKind(
          kind,
          source: _debugOverrideSnapshotActive
              ? 'debug_manual_override'
              : 'manual',
          reduceMotion: reduceMotion,
          autoSelected: false,
          persistence: _debugOverrideSnapshotActive
              ? TerminalSessionPersistence.ephemeral
              : TerminalSessionPersistence.persistent,
        );
      case TerminalLoginStage.name:
        final changed = _enteredName != input;
        _enteredName = input;
        if (changed) {
          _enteredPassword = '';
          _authenticatedAccount = null;
          _availableWorkAreas = <LauncherWorkAreaOption>[];
          _selectedWorkArea = null;
          _supportedModes = <AppModeDefinition>[];
          _selectedMode = null;
        }
        _append(
          TerminalLineType.output,
          _authOutputLine(nameDisplayLabel, _enteredName),
        );
        LauncherDiagnostics.record(
          'auth_name_completed',
          meta: <String, Object?>{
            'accountKind': _selectedAccountKind == null
                ? ''
                : TerminalAuthCoordinator.accountKindId(_selectedAccountKind!),
            'nameLength': _enteredName.length,
            'displayLabel': nameDisplayLabel,
            'nextPrompt': _phonePrompt,
          },
        );
        _loginStage = TerminalLoginStage.phone;
        _append(TerminalLineType.system, _phonePrompt);
        notifyListeners();
        return ModeLauncherSubmitResult(
          promptText: _enteredPhone.isEmpty ? null : _enteredPhone,
          selectPromptText: _enteredPhone.isNotEmpty,
        );
      case TerminalLoginStage.phone:
        final kind = _selectedAccountKind;
        if (kind == null) {
          _resetAccountSelection();
          return const ModeLauncherSubmitResult();
        }
        final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
        final phonePattern = kind == TerminalAccountKind.personal
            ? RegExp(r'^\d{9,11}$')
            : RegExp(r'^\d{10,11}$');
        if (!phonePattern.hasMatch(digits)) {
          _append(TerminalLineType.error, _phoneError);
          _errorSerial += 1;
          LauncherDiagnostics.record(
            'auth_phone_rejected',
            meta: <String, Object?>{
              'accountKind': TerminalAuthCoordinator.accountKindId(kind),
              'length': digits.length,
              'displayLabel': phoneDisplayLabel,
              'errorText': _phoneError,
            },
          );
          notifyListeners();
          return const ModeLauncherSubmitResult();
        }
        final changed = _enteredPhone != digits;
        _enteredPhone = digits;
        if (changed) {
          _enteredPassword = '';
          _authenticatedAccount = null;
          _availableWorkAreas = <LauncherWorkAreaOption>[];
          _selectedWorkArea = null;
          _supportedModes = <AppModeDefinition>[];
          _selectedMode = null;
        }
        _append(
          TerminalLineType.output,
          _authOutputLine(phoneDisplayLabel, _enteredPhone),
        );
        LauncherDiagnostics.record(
          'auth_phone_completed',
          meta: <String, Object?>{
            'accountKind': TerminalAuthCoordinator.accountKindId(kind),
            'phoneMasked': _maskPhone(_enteredPhone),
            'displayLabel': phoneDisplayLabel,
            'nextPrompt': _passwordPrompt,
          },
        );
        _loginStage = TerminalLoginStage.password;
        _append(TerminalLineType.system, _passwordPrompt);
        notifyListeners();
        return const ModeLauncherSubmitResult();
      case TerminalLoginStage.password:
        final kind = _selectedAccountKind;
        if (kind == null) {
          _resetAccountSelection();
          return const ModeLauncherSubmitResult();
        }
        final validPassword = kind == TerminalAccountKind.personal
            ? RegExp(r'^\d{5}$').hasMatch(input)
            : input.length >= 5;
        if (!validPassword) {
          _append(TerminalLineType.error, _passwordError);
          _errorSerial += 1;
          LauncherDiagnostics.record(
            'auth_password_rejected',
            meta: <String, Object?>{
              'accountKind': TerminalAuthCoordinator.accountKindId(kind),
              'passwordLength': input.length,
              'displayLabel': passwordDisplayLabel,
              'errorText': _passwordError,
            },
          );
          notifyListeners();
          return const ModeLauncherSubmitResult();
        }
        _enteredPassword = input;
        _append(
          TerminalLineType.output,
          _authOutputLine(passwordDisplayLabel, maskedPassword),
        );
        LauncherDiagnostics.record(
          'auth_password_completed',
          meta: <String, Object?>{
            'accountKind': TerminalAuthCoordinator.accountKindId(kind),
            'passwordLength': _enteredPassword.length,
            'displayLabel': passwordDisplayLabel,
          },
        );
        _loginStage = TerminalLoginStage.authenticating;
        _busy = true;
        _runningCommand = 'AUTH';
        _append(TerminalLineType.running, 'Authenticating');
        notifyListeners();
        await _commandDelay(reduceMotion);
        if (_disposed || !context.mounted) {
          _busy = false;
          _runningCommand = '';
          return const ModeLauncherSubmitResult();
        }

        final result = await TerminalAuthCoordinator.authenticateAccount(
          context,
          kind: kind,
          name: _enteredName,
          phone: _enteredPhone,
          password: _enteredPassword,
          persistence: _sessionPersistence,
        );
        if (_disposed || !context.mounted) {
          _busy = false;
          _runningCommand = '';
          return const ModeLauncherSubmitResult();
        }

        final account = result.account;
        if (result.success && account != null) {
          _authenticatedAccount = account;
          _availableWorkAreas = <LauncherWorkAreaOption>[];
          _selectedWorkArea = null;
          _supportedModes = account.supportedModes;
          _enteredName = account.displayName;
          _append(TerminalLineType.success, '[ OK ] ${result.message}');

          if (account.kind == TerminalAccountKind.user && account.user != null) {
            _runningCommand = 'AREAS';
            _append(TerminalLineType.running, 'Loading work areas from local snapshot');
            notifyListeners();
            final resolution = await _resolveLauncherWorkAreas(
              context,
              account: account,
              reduceMotion: reduceMotion,
            );
            if (_disposed || !context.mounted) {
              _busy = false;
              _runningCommand = '';
              return const ModeLauncherSubmitResult();
            }
            _availableWorkAreas = resolution.areas;
            _busy = false;
            _runningCommand = '';
            _loginStage = TerminalLoginStage.areaSelection;
            if (_availableWorkAreas.isEmpty) {
              _append(
                TerminalLineType.error,
                '[ERROR] 업무 지역 정보를 불러오지 못했습니다.',
              );
              LauncherDiagnostics.record(
                'auth_work_area_selection_blocked',
                meta: <String, Object?>{
                  'reason': 'work_area_resolution_empty',
                  'division': resolution.division,
                  'dataSource': resolution.dataSource,
                  'firebaseAreaDocumentReads':
                      resolution.firebaseAreaDocumentReads,
                  'firebaseWrites': 0,
                },
              );
              _errorSerial += 1;
              notifyListeners();
              return const ModeLauncherSubmitResult();
            }
            await _appendWorkAreaListPaced(reduceMotion);
            final firstArea = _availableWorkAreas.first;
            LauncherDiagnostics.record(
              'auth_work_area_selection_ready',
              meta: <String, Object?>{
                'areaCount': _availableWorkAreas.length,
                'firstArea': firstArea.areaName,
                'firstIsHeadquarter': firstArea.isHeadquarter,
                'snapshotAvailable': resolution.hasSnapshot,
                'requiresServerHeadquarterVerification':
                    firstArea.requiresServerHeadquarterVerification,
                'requiresServerAreaResolution':
                    firstArea.requiresServerAreaResolution,
                'firebaseAreaDocumentReads':
                    resolution.firebaseAreaDocumentReads,
                'firebaseWrites': 0,
                'dataSource': resolution.dataSource,
              },
            );
            final autoSelectReason = _workAreaAutoSelectReason();
            if (autoSelectReason != null) {
              _append(
                TerminalLineType.system,
                _workAreaAutoSelectMessage(autoSelectReason),
              );
              LauncherDiagnostics.record(
                'auth_work_area_auto_input_queued',
                meta: <String, Object?>{
                  'reason': autoSelectReason,
                  'areaCount': _availableWorkAreas.length,
                  'area': firstArea.areaName,
                  'isHeadquarter': firstArea.isHeadquarter,
                  'selectionNumber': 1,
                  'supportedModes': firstArea.supportedModes
                      .map((mode) => mode.id)
                      .join(','),
                  'firebaseAreaDocumentReads':
                      resolution.firebaseAreaDocumentReads,
                  'firebaseWrites': 0,
                },
              );
              notifyListeners();
              return const ModeLauncherSubmitResult(autoSubmitText: '1');
            }
            _append(TerminalLineType.system, '업무 지역을 입력하세요.');
            notifyListeners();
            return const ModeLauncherSubmitResult();
          }

          _busy = false;
          _runningCommand = '';
          _loginStage = TerminalLoginStage.modeSelection;
          await _appendSupportedModeListPaced(reduceMotion);
          if (_supportedModes.isEmpty) {
            _append(
              TerminalLineType.error,
              '[ERROR] 활성화된 모드가 없습니다.',
            );
            _errorSerial += 1;
            notifyListeners();
            return const ModeLauncherSubmitResult();
          }
          final automaticMode = _supportedModes.first;
          _append(
            TerminalLineType.system,
            '기본 모드 1번을 자동 선택합니다.',
          );
          LauncherDiagnostics.record(
            'auth_mode_auto_input_queued',
            meta: <String, Object?>{
              'accountKind': TerminalAuthCoordinator.accountKindId(kind),
              'supportedModeCount': _supportedModes.length,
              'selectionNumber': 1,
              'mode': automaticMode.id,
              'reason': _supportedModes.length == 1
                  ? 'single_supported_mode'
                  : 'first_supported_mode',
              'sessionPersistence': TerminalAuthCoordinator.sessionPersistenceId(
                _sessionPersistence,
              ),
            },
          );
          notifyListeners();
          return const ModeLauncherSubmitResult(autoSubmitText: '1');
        }

        _append(TerminalLineType.error, '[ERROR] ${result.message}');
        _busy = false;
        _runningCommand = '';
        _enteredPassword = '';
        _loginStage = TerminalLoginStage.password;
        _errorSerial += 1;
        notifyListeners();
        return const ModeLauncherSubmitResult(promptText: '');
      case TerminalLoginStage.areaSelection:
        final account = _authenticatedAccount;
        if (account == null || account.kind != TerminalAccountKind.user) {
          _resetAccountSelection();
          return const ModeLauncherSubmitResult();
        }
        var area = _findWorkArea(input);
        if (area == null) {
          _append(TerminalLineType.error, '[DENIED] 지원하지 않는 업무 지역입니다.');
          _appendWorkAreaList();
          _errorSerial += 1;
          notifyListeners();
          return const ModeLauncherSubmitResult();
        }
        final requiredServerResolution = area.requiresServerAreaResolution;
        if (requiredServerResolution) {
          final verifiedArea = await _verifyBootstrapWorkArea(
            context,
            account: account,
            area: area,
            reduceMotion: reduceMotion,
          );
          if (_disposed || !context.mounted) {
            _busy = false;
            _runningCommand = '';
            return const ModeLauncherSubmitResult();
          }
          if (verifiedArea == null) {
            _append(
              TerminalLineType.error,
              '[ERROR] 선택한 업무 지역 정보를 확인하지 못했습니다.',
            );
            _errorSerial += 1;
            notifyListeners();
            return const ModeLauncherSubmitResult();
          }
          area = verifiedArea;
        }
        _selectedWorkArea = area;
        _supportedModes = area.supportedModes;
        LauncherDiagnostics.record(
          'auth_work_area_selected',
          meta: <String, Object?>{
            'area': area.areaName,
            'isHeadquarter': area.isHeadquarter,
            'supportedModes': area.supportedModes.map((mode) => mode.id).join(','),
            'requiresServerHeadquarterVerification':
                area.requiresServerHeadquarterVerification,
            'requiredServerAreaResolution': requiredServerResolution,
            'verifiedAreaRecord': area.hasVerifiedAreaRecord,
            'firebaseAreaDocumentReads': requiredServerResolution ? 1 : 0,
            'firebaseWrites': 0,
            'dataSource': area.dataSource,
          },
        );
        if (area.isHeadquarter) {
          return _activateSelectedHeadquarter(
            context,
            account: account,
            reduceMotion: reduceMotion,
          );
        }
        if (_supportedModes.isEmpty) {
          _append(
            TerminalLineType.error,
            '[DENIED] 이 지역에서 사용할 수 있는 업무 모드가 없습니다.',
          );
          _selectedWorkArea = null;
          _supportedModes = account.supportedModes;
          _errorSerial += 1;
          notifyListeners();
          return const ModeLauncherSubmitResult();
        }
        _loginStage = TerminalLoginStage.modeSelection;
        await _appendSupportedModeListPaced(reduceMotion);
        if (_supportedModes.length == 1) {
          _append(
            TerminalLineType.system,
            '${area.areaName}의 지원 모드 1번을 자동 선택합니다.',
          );
          LauncherDiagnostics.record(
            'auth_area_single_mode_auto_input_queued',
            meta: <String, Object?>{
              'area': area.areaName,
              'mode': _supportedModes.first.id,
              'selectionNumber': 1,
              'firebaseReads': 0,
              'firebaseWrites': 0,
            },
          );
          notifyListeners();
          return const ModeLauncherSubmitResult(autoSubmitText: '1');
        }
        _append(
          TerminalLineType.system,
          '${area.areaName}에서 사용할 모드를 입력하세요.',
        );
        notifyListeners();
        return const ModeLauncherSubmitResult();
      case TerminalLoginStage.modeSelection:
        final account = _authenticatedAccount;
        if (account == null) {
          _resetAccountSelection();
          return const ModeLauncherSubmitResult();
        }
        final mode = _findSupportedMode(input);
        if (mode == null) {
          _append(TerminalLineType.error, '[DENIED] 지원하지 않는 모드입니다.');
          _appendSupportedModeList();
          _errorSerial += 1;
          notifyListeners();
          return const ModeLauncherSubmitResult();
        }
        _selectedMode = mode;
        return _activateSelectedMode(
          context,
          account: account,
          mode: mode,
          reduceMotion: reduceMotion,
        );
      case TerminalLoginStage.command:
      case TerminalLoginStage.authenticating:
      case TerminalLoginStage.activatingMode:
        return const ModeLauncherSubmitResult();
    }
  }

  ModeLauncherSubmitResult _rejectDeveloperCommand(String input) {
    _append(TerminalLineType.error, '[DENIED] Developer authorization required');
    _errorSerial += 1;
    LauncherDiagnostics.record(
      'developer_command_denied',
      meta: <String, Object?>{'input': input},
    );
    notifyListeners();
    return const ModeLauncherSubmitResult();
  }

  Future<ModeLauncherSubmitResult> _launchSurface(
    BuildContext context,
    String command,
    Future<void> Function() launch, {
    required bool reduceMotion,
  }) async {
    _busy = true;
    _runningCommand = command;
    _append(TerminalLineType.running, 'Opening $command');
    await _commandDelay(reduceMotion);
    if (_disposed || !context.mounted) {
      _busy = false;
      _runningCommand = '';
      return const ModeLauncherSubmitResult();
    }
    _append(TerminalLineType.success, '[ OK ] $command');
    _busy = false;
    _runningCommand = '';
    notifyListeners();
    final completion = launch();
    return ModeLauncherSubmitResult(surfaceCompletion: completion);
  }

  Future<void> _commandDelay(bool reduceMotion) {
    if (reduceMotion) {
      return Future<void>.delayed(const Duration(milliseconds: 18));
    }
    final seed = _runningCommand.hashCode.abs() + _loginStage.index * 17;
    return Future<void>.delayed(
      Duration(milliseconds: 105 + seed % 86),
    );
  }

  String _maskPhone(String value) {
    if (value.isEmpty) return '-';
    if (value.length < 7) return List<String>.filled(value.length, '*').join();
    return '${value.substring(0, 3)}****${value.substring(value.length - 4)}';
  }

  @override
  void dispose() {
    _importingUnlocked = false;
    _disposed = true;
    _enteredPassword = '';
    DevAuth.devModeEnabled.removeListener(_handleDevModeChanged);
    _startupSetupCoordinator.removeListener(_handleStartupSetupChanged);
    _startupSetupCoordinator.dispose();
    super.dispose();
  }
}
