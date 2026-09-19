import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../features/launcher/application/mode_launcher_controller.dart';
import '../../../features/launcher/application/terminal_auth_coordinator.dart';
import '../../auth/gmail_sender_auth.dart';
import '../../config/email_config.dart';
import '../../../features/selector/application/dev_auth.dart';
import '../../../features/dev/presentation/debug_caution_surface.dart';
import '../../command/application/app_command_registry.dart';
import '../../command/application/terminal_line.dart';
import '../../command/application/terminal_session_controller.dart';
import '../../init/app_start_setup_flow_resolver.dart';
import '../../init/work_status_notification.dart';
import '../../init/startup_tasks.dart';
import '../../tutorial/tutorial/app_start_setup_specs.dart';
import '../application/parkinworkin_terminal_diagnostics.dart';
import '../application/terminal_output_playback_controller.dart';

const Color _terminalBackground = Color(0xFF300A24);
const Color _terminalHeader = Color(0xFF24101F);
const Color _terminalBorder = Color(0xFF5E3A55);
const Color _terminalText = Color(0xFFF2EEF1);
const Color _terminalMuted = Color(0xFFB7AAB3);
const Color _terminalPrompt = Color(0xFF8AE234);
const Color _terminalPath = Color(0xFF729FCF);
const Color _terminalSuccess = Color(0xFF8AE234);
const Color _terminalError = Color(0xFFEF6A6A);
const Color _terminalWarning = Color(0xFFFCE94F);
const Duration _miniTerminalOpenDuration = Duration(milliseconds: 660);
const Duration _miniTerminalCloseDuration = Duration(milliseconds: 410);
const Duration _miniTerminalRouteDuration = Duration(milliseconds: 170);

enum ParkinWorkinTerminalContext {
  launcher,
  workspace,
}

enum _LauncherDialogPhase {
  closed,
  preparing,
  opening,
  visible,
  closing,
}

class ParkinWorkinTerminalScreen extends StatefulWidget {
  const ParkinWorkinTerminalScreen.launcher({
    super.key,
    this.startupReport,
  })  : terminalContext = ParkinWorkinTerminalContext.launcher,
        source = 'launcher';

  const ParkinWorkinTerminalScreen.workspace({
    super.key,
    required this.source,
  })  : terminalContext = ParkinWorkinTerminalContext.workspace,
        startupReport = null;

  final ParkinWorkinTerminalContext terminalContext;
  final StartupReport? startupReport;
  final String source;

  @override
  State<ParkinWorkinTerminalScreen> createState() =>
      _ParkinWorkinTerminalScreenState();
}

class _ParkinWorkinTerminalScreenState extends State<ParkinWorkinTerminalScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  ModeLauncherController? _launcherController;
  TerminalSessionController? _workspaceController;
  late final TerminalOutputPlaybackController _playbackController;
  late final AnimationController _openController;
  final TextEditingController _promptController = TextEditingController();
  late final FocusNode _promptFocusNode;
  final ScrollController _scrollController = ScrollController();
  bool _initialized = false;
  bool _nearBottom = true;
  bool _closing = false;
  bool _appExiting = false;
  bool _reduceMotion = false;
  bool _launcherPresentationReady = false;
  bool _launcherNavigationFinalizing = false;
  _LauncherDialogPhase _launcherDialogPhase = _LauncherDialogPhase.closed;
  ModeLauncherSubmitResult? _deferredLauncherResult;
  String _lastLauncherActivitySignature = '';
  Timer? _bottomLockTimer;
  Future<void>? _openFuture;
  _TerminalPromptLayoutSnapshot? _promptLayoutSnapshot;

  bool get _isLauncher =>
      widget.terminalContext == ParkinWorkinTerminalContext.launcher;

  bool get _exitInProgress =>
      _appExiting || (_isLauncher && _launcherController?.runningCommand == 'exit');

  bool get _interactionLocked => _closing || _exitInProgress;

  String get _contextLabel => _isLauncher ? 'launcher' : widget.source;

  List<TerminalLine> get _sourceLines => _isLauncher
      ? _launcherController!.lines
      : _workspaceController!.lines;

  bool get _busy => _isLauncher
      ? _launcherController!.busy
      : _workspaceController!.busy;

  String get _runningCommand => _isLauncher
      ? _launcherController!.runningCommand
      : _workspaceController!.runningCommand;

  String get _promptPath => _isLauncher
      ? _launcherController!.currentPromptPath
      : _workspaceController!.currentPromptPath;

  bool get _commandHistoryEnabled => _isLauncher
      ? _launcherController!.commandHistoryEnabled
      : _workspaceController!.commandHistoryEnabled;

  bool get _emailEditMode => _isLauncher
      ? _launcherController!.emailEditMode
      : _workspaceController!.emailEditMode;

  bool get _importingUnlocked => _isLauncher
      ? _launcherController!.importingUnlocked
      : _workspaceController!.importingUnlocked;

  TextInputType get _keyboardType => _isLauncher
      ? _launcherController!.promptKeyboardType
      : _emailEditMode
          ? TextInputType.emailAddress
          : TextInputType.text;

  TextInputAction get _inputAction => _isLauncher
      ? _launcherController!.promptInputAction
      : TextInputAction.done;

  bool get _obscureText =>
      _isLauncher && _launcherController!.obscurePrompt;

  bool get _startupSetupActive =>
      _isLauncher && _launcherController!.startupSetupPanelActive;

  bool get _launcherBootstrapLocked =>
      _isLauncher && !_launcherController!.authenticationBootstrapped;

  bool get _startupSetupBusy =>
      _isLauncher && _launcherController!.startupSetupBusy;

  bool get _startupSetupAwaitingExternalSettings =>
      _isLauncher &&
      _launcherController!.startupSetupAwaitingExternalSettings;

  @override
  void initState() {
    super.initState();
    if (_isLauncher) {
      _launcherController = ModeLauncherController(
        startupReport: widget.startupReport,
      );
      _launcherController!.addListener(_handleSourceChanged);
    } else {
      _workspaceController = TerminalSessionController(source: widget.source);
      _workspaceController!.addListener(_handleSourceChanged);
    }
    _playbackController = TerminalOutputPlaybackController(
      contextLabel: _contextLabel,
    )..addListener(_handlePlaybackChanged);
    _openController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 920),
      reverseDuration: const Duration(milliseconds: 460),
    );
    _promptFocusNode = FocusNode(onKeyEvent: _handlePromptKeyEvent);
    _promptFocusNode.addListener(_handlePromptFocusChanged);
    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance.addObserver(this);
    ParkinWorkinTerminalDiagnostics.record(
      'terminal_screen_init',
      context: _contextLabel,
      meta: <String, Object?>{
        'mode': widget.terminalContext.name,
      },
    );
    unawaited(DevAuth.isDevModeEnabled());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.of(context).disableAnimations;
    _syncPlayback();
    if (_initialized) return;
    _initialized = true;
    if (_reduceMotion) {
      _openController.value = 1;
      _openFuture = Future<void>.value();
    } else {
      _openFuture = _openController.forward(from: 0);
    }
    unawaited(_initializeTerminal());
  }

  Future<void> _initializeTerminal() async {
    if (_isLauncher) {
      if (!_reduceMotion) {
        await Future<void>.delayed(const Duration(milliseconds: 520));
      }
      if (!mounted) return;
      await _launcherController!.initialize(
        context,
        reduceMotion: _reduceMotion,
      );
      if (!mounted) return;
      _syncPlayback();
      await (_openFuture ?? Future<void>.value());
      if (!mounted || _interactionLocked) return;
      final handledPending = await _consumeLauncherPendingFlow();
      if (handledPending || !mounted || _interactionLocked) return;
    } else {
      await (_openFuture ?? Future<void>.value());
      ParkinWorkinTerminalDiagnostics.record(
        'terminal_open_complete',
        context: _contextLabel,
      );
    }
    await Future<void>.delayed(
      _reduceMotion
          ? Duration.zero
          : Duration(milliseconds: 75 + (_contextLabel.hashCode.abs() % 55)),
    );
    if (!mounted || _interactionLocked) return;
    if (_isLauncher) {
      await _syncLauncherInteractionSurface();
    } else if (!_startupSetupActive) {
      _promptFocusNode.requestFocus();
    }
    _scheduleBottomLock(delay: const Duration(milliseconds: 220));
  }

  Future<bool> _consumeLauncherPendingFlow() async {
    if (!_isLauncher || !mounted || _interactionLocked) return false;
    final pendingRoute = _launcherController!.consumePendingTargetRoute();
    if (pendingRoute == null) return false;
    await _finalizeLauncherAndNavigate(
      pendingRoute,
      source: 'pending_target_route',
    );
    return true;
  }

  Future<void> _runStartupSetupPrimaryAction() async {
    if (!_isLauncher ||
        _interactionLocked ||
        _startupSetupBusy ||
        _startupSetupAwaitingExternalSettings) {
      return;
    }
    _promptFocusNode.unfocus();
    await HapticFeedback.selectionClick();
    await _launcherController!.runStartupSetupPrimaryAction(
      context,
      reduceMotion: _reduceMotion,
    );
    if (!mounted || _interactionLocked) return;
    _syncPlayback();
    final handledPending = await _consumeLauncherPendingFlow();
    if (handledPending || !mounted || _interactionLocked) return;
    if (!_startupSetupActive) {
      await _syncLauncherInteractionSurface();
    }
    _scheduleBottomLock(delay: const Duration(milliseconds: 140));
  }

  Future<void> _handleStartupPermissionTitleTap() async {
    if (!_isLauncher || _interactionLocked || _startupSetupBusy) return;
    await HapticFeedback.selectionClick();
    final skipped =
        await _launcherController!.registerStartupPermissionTitleTap(
      context,
      reduceMotion: _reduceMotion,
    );
    if (!mounted || !skipped) return;
    _syncPlayback();
    final handledPending = await _consumeLauncherPendingFlow();
    if (handledPending || !mounted || _interactionLocked) return;
    if (!_startupSetupActive) {
      await _syncLauncherInteractionSurface();
    }
  }

  Future<void> _handleStartupGoogleTitleTap() async {
    if (!_isLauncher || _interactionLocked || _startupSetupBusy) return;
    await HapticFeedback.selectionClick();
    final skipped = await _launcherController!.registerStartupGoogleTitleTap(
      context,
      reduceMotion: _reduceMotion,
    );
    if (!mounted || !skipped) return;
    _syncPlayback();
    final handledPending = await _consumeLauncherPendingFlow();
    if (handledPending || !mounted || _interactionLocked) return;
    if (!_startupSetupActive) {
      await _syncLauncherInteractionSurface();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed ||
        !_isLauncher ||
        !_initialized ||
        !_startupSetupActive) {
      return;
    }
    unawaited(_refreshStartupSetupAfterResume());
  }

  Future<void> _refreshStartupSetupAfterResume() async {
    if (!_isLauncher || _interactionLocked) return;
    if (_startupSetupBusy && !_startupSetupAwaitingExternalSettings) return;
    await _launcherController!.refreshStartupSetupAfterResume(
      context,
      reduceMotion: _reduceMotion,
    );
    if (!mounted || _interactionLocked) return;
    _syncPlayback();
    final handledPending = await _consumeLauncherPendingFlow();
    if (handledPending || !mounted || _interactionLocked) return;
    if (!_startupSetupActive) {
      await _syncLauncherInteractionSurface();
    }
  }

  void _handleSourceChanged() {
    if (!mounted) return;
    _syncPlayback();
    setState(() {});
    if (_isLauncher) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_syncLauncherInteractionSurface());
      });
    }
  }

  void _handleLauncherActivitySignatureChanged(String signature) {
    if (!_isLauncher || signature == _lastLauncherActivitySignature) return;
    _lastLauncherActivitySignature = signature;
    ParkinWorkinTerminalDiagnostics.record(
      'launcher_activity_changed',
      context: _contextLabel,
      meta: <String, Object?>{
        'signature': signature,
        'stage': _launcherController!.loginStage.name,
        'runningCommand': _launcherController!.runningCommand,
        'busy': _launcherController!.busy,
        'dialogPhase': _launcherDialogPhase.name,
        'runtimeContextReady': _launcherController!.runtimeContextReady,
        'playbackBusy': _playbackController.busy,
        'presentationReady': _launcherPresentationReady,
      },
    );
  }

  void _setLauncherDialogPhase(
    _LauncherDialogPhase phase, {
    required String source,
  }) {
    if (_launcherDialogPhase == phase) return;
    final previous = _launcherDialogPhase;
    _launcherDialogPhase = phase;
    if (mounted) setState(() {});
    ParkinWorkinTerminalDiagnostics.record(
      'launcher_dialog_phase_changed',
      context: _contextLabel,
      meta: <String, Object?>{
        'from': previous.name,
        'to': phase.name,
        'source': source,
        'stage': _launcherController?.loginStage.name ?? '',
        'runningCommand': _launcherController?.runningCommand ?? '',
      },
    );
  }

  void _handleLauncherDialogOpened() {
    if (_launcherDialogPhase != _LauncherDialogPhase.opening &&
        _launcherDialogPhase != _LauncherDialogPhase.preparing) {
      return;
    }
    _setLauncherDialogPhase(
      _LauncherDialogPhase.visible,
      source: 'mini_terminal_open_complete',
    );
  }

  void _handleLauncherDialogClosing() {
    if (_launcherDialogPhase == _LauncherDialogPhase.closed ||
        _launcherDialogPhase == _LauncherDialogPhase.closing) {
      return;
    }
    _setLauncherDialogPhase(
      _LauncherDialogPhase.closing,
      source: 'mini_terminal_close_start',
    );
  }

  void _syncPlayback() {
    _playbackController.sync(
      _sourceLines,
      reduceMotion: _reduceMotion,
    );
  }

  void _handlePlaybackChanged() {
    if (!mounted) return;
    setState(() {});
    _scheduleAutoScroll();
  }

  void _handlePromptFocusChanged() {
    if (_isLauncher || !_promptFocusNode.hasFocus || _interactionLocked) return;
    ParkinWorkinTerminalDiagnostics.record(
      'terminal_prompt_focus',
      context: _contextLabel,
      meta: <String, Object?>{
        'path': _promptPath,
      },
    );
    _scheduleBottomLock(delay: const Duration(milliseconds: 220));
  }

  void _requestPromptFocusFromRow() {
    if (_isLauncher || _busy || _interactionLocked) return;
    ParkinWorkinTerminalDiagnostics.record(
      'terminal_prompt_focus_requested',
      context: _contextLabel,
      meta: <String, Object?>{
        'path': _promptPath,
        'source': 'prompt_row_tap',
        'alreadyFocused': _promptFocusNode.hasFocus,
      },
    );
    if (!_promptFocusNode.hasFocus) {
      _promptFocusNode.requestFocus();
    }
    _scheduleBottomLock(delay: const Duration(milliseconds: 160));
  }

  void _handlePromptLayoutChanged(_TerminalPromptLayoutSnapshot snapshot) {
    _promptLayoutSnapshot = snapshot;
    ParkinWorkinTerminalDiagnostics.record(
      'terminal_prompt_layout_changed',
      context: _contextLabel,
      meta: <String, Object?>{
        'path': snapshot.promptPath,
        'density': snapshot.density.name,
        'availableWidth': snapshot.availableWidth.toStringAsFixed(1),
        'promptMaxWidth': snapshot.promptMaxWidth.toStringAsFixed(1),
        'minimumInputWidth': snapshot.minimumInputWidth.toStringAsFixed(1),
        'emailSuffix': snapshot.emailSuffixVisible,
        'actionLabel': snapshot.actionLabelVisible,
        'busyLabel': snapshot.busyLabelVisible,
      },
    );
  }

  @override
  void didChangeMetrics() {
    if (_isLauncher ||
        !mounted ||
        _interactionLocked ||
        !_promptFocusNode.hasFocus) {
      return;
    }
    _scheduleBottomLock(delay: const Duration(milliseconds: 110));
  }

  void _scheduleBottomLock({
    Duration delay = const Duration(milliseconds: 220),
  }) {
    _bottomLockTimer?.cancel();
    _bottomLockTimer = Timer(delay, () {
      if (!mounted || _interactionLocked || !_scrollController.hasClients) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _interactionLocked || !_scrollController.hasClients) return;
        final position = _scrollController.position;
        _scrollController.jumpTo(position.maxScrollExtent);
      });
    });
  }

  void _scheduleAutoScroll() {
    if (!_nearBottom || _interactionLocked) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _interactionLocked || !_nearBottom || !_scrollController.hasClients) {
        return;
      }
      final target = _scrollController.position.maxScrollExtent;
      if (_reduceMotion) {
        _scrollController.jumpTo(target);
      } else {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 145),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    _nearBottom = position.maxScrollExtent - position.pixels < 96;
  }

  KeyEventResult _handlePromptKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_interactionLocked) return KeyEventResult.handled;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (!_busy) {
        if (_isLauncher) {
          unawaited(_submitHeaderCommand('out'));
        } else {
          unawaited(_executeWorkspaceCommand('out'));
        }
      }
      return KeyEventResult.handled;
    }
    if (_busy || !_commandHistoryEnabled) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      final value = _isLauncher
          ? _launcherController!.previousCommand()
          : _workspaceController!.previousCommand();
      if (value != null) _setPromptText(value);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      final value = _isLauncher
          ? _launcherController!.nextCommand()
          : _workspaceController!.nextCommand();
      if (value != null) _setPromptText(value);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _setPromptText(
    String value, {
    bool selectAll = false,
  }) {
    _promptController.value = TextEditingValue(
      text: value,
      selection: selectAll
          ? TextSelection(baseOffset: 0, extentOffset: value.length)
          : TextSelection.collapsed(offset: value.length),
    );
  }



  Future<void> _submit() async {
    if (_isLauncher) return;
    await _submitWorkspaceRaw(_promptController.text);
  }

  Future<void> _submitHeaderCommand(String command) async {
    if (_busy ||
        _interactionLocked ||
        (_isLauncher && (_startupSetupActive || _launcherBootstrapLocked))) {
      return;
    }
    if (command == 'setting' && _promptPath == '~/setting') {
      if (!_promptFocusNode.hasFocus) _promptFocusNode.requestFocus();
      return;
    }
    if (command == 'setting' && _emailEditMode && !_isLauncher) {
      await HapticFeedback.selectionClick();
      await _executeWorkspaceCommand('cd ..', preservePrompt: true);
      return;
    }
    final appExit = _isLauncher && command == 'exit';
    if (appExit) {
      _bottomLockTimer?.cancel();
      _promptFocusNode.unfocus();
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => _appExiting = true);
      ParkinWorkinTerminalDiagnostics.record(
        'terminal_app_exit_lock_start',
        context: _contextLabel,
        meta: <String, Object?>{
          'busy': _busy,
          'appExiting': _appExiting,
        },
      );
    }
    try {
      await HapticFeedback.selectionClick();
      ParkinWorkinTerminalDiagnostics.record(
        'terminal_header_command',
        context: _contextLabel,
        meta: <String, Object?>{'command': command},
      );
      if (_isLauncher) {
        final result = await _launcherController!.executeUtilityCommand(
          context,
          command,
          reduceMotion: _reduceMotion,
        );
        if (!mounted) return;
        await _handleLauncherResult(result);
        return;
      }
      await _executeWorkspaceCommand(command, preservePrompt: true);
    } finally {
      if (appExit && mounted) {
        setState(() => _appExiting = false);
        ParkinWorkinTerminalDiagnostics.record(
          'terminal_app_exit_lock_release',
          context: _contextLabel,
          meta: <String, Object?>{
            'busy': _busy,
            'appExiting': _appExiting,
          },
        );
      }
    }
  }



  Future<void> _handleLauncherResult(ModeLauncherSubmitResult result) async {
    if (result.targetRoute != null) {
      await _finalizeLauncherAndNavigate(
        result.targetRoute!,
        source: 'launcher_submit_result',
      );
      return;
    }
    if (result.routeReplaced) {
      return;
    }
    if (result.surfaceCompletion != null) {
      final completion = result.surfaceCompletion!;
      unawaited(() async {
        await completion;
        if (!mounted || _interactionLocked) return;
        await _syncLauncherInteractionSurface();
      }());
    }
  }

  Future<void> _finalizeLauncherAndNavigate(
    String route, {
    required String source,
  }) async {
    if (!_isLauncher ||
        !mounted ||
        _interactionLocked ||
        _launcherNavigationFinalizing) {
      return;
    }
    _launcherNavigationFinalizing = true;
    ParkinWorkinTerminalDiagnostics.record(
      'launcher_presentation_finalize_start',
      context: _contextLabel,
      meta: <String, Object?>{
        'source': source,
        'targetRoute': route,
        'runtimeContextReady': _launcherController!.runtimeContextReady,
        'playbackBusy': _playbackController.busy,
        'presentationReady': _launcherPresentationReady,
      },
    );
    try {
      await _playbackController.waitUntilIdle();
      if (!mounted || _interactionLocked) return;
      if (!_launcherPresentationReady) {
        setState(() {
          _launcherPresentationReady = true;
        });
      }
      ParkinWorkinTerminalDiagnostics.record(
        'launcher_presentation_ready',
        context: _contextLabel,
        meta: <String, Object?>{
          'source': source,
          'targetRoute': route,
          'runtimeContextReady': _launcherController!.runtimeContextReady,
          'playbackBusy': _playbackController.busy,
          'presentationReady': _launcherPresentationReady,
        },
      );
      await WidgetsBinding.instance.endOfFrame;
      if (!_reduceMotion) {
        await Future<void>.delayed(const Duration(milliseconds: 240));
      }
      if (!mounted || _interactionLocked) return;
      await _closeLauncherAndNavigate(route);
    } finally {
      _launcherNavigationFinalizing = false;
    }
  }

  Future<void> _syncLauncherInteractionSurface() async {
    if (!_isLauncher ||
        !mounted ||
        _interactionLocked ||
        _startupSetupActive ||
        _launcherBootstrapLocked ||
        _launcherDialogPhase != _LauncherDialogPhase.closed ||
        _launcherController!.busy) {
      return;
    }
    final stage = _launcherController!.loginStage;
    final canOpen = switch (stage) {
      TerminalLoginStage.accountTypeSelection => true,
      TerminalLoginStage.credentials => true,
      TerminalLoginStage.areaSelection =>
        _launcherController!.availableWorkAreas.isNotEmpty,
      TerminalLoginStage.modeSelection =>
        _launcherController!.supportedModes.isNotEmpty,
      _ => false,
    };
    if (!canOpen) return;
    _deferredLauncherResult = null;
    _setLauncherDialogPhase(
      _LauncherDialogPhase.preparing,
      source: 'interaction_surface_prepare',
    );
    ParkinWorkinTerminalDiagnostics.record(
      'launcher_dialog_prepare',
      context: _contextLabel,
      meta: <String, Object?>{'stage': stage.name},
    );
    try {
      await _playbackController.waitUntilIdle();
      if (!mounted || _interactionLocked || _launcherController!.busy) return;
      final currentStage = _launcherController!.loginStage;
      switch (currentStage) {
        case TerminalLoginStage.accountTypeSelection:
          await _showLauncherAccountTypeDialog();
          break;
        case TerminalLoginStage.credentials:
          await _showLauncherAccountDialog();
          break;
        case TerminalLoginStage.areaSelection:
          if (_launcherController!.availableWorkAreas.isNotEmpty) {
            await _showLauncherWorkAreaDialog();
          }
          break;
        case TerminalLoginStage.modeSelection:
          if (_launcherController!.supportedModes.isNotEmpty) {
            await _showLauncherModeDialog();
          }
          break;
        case TerminalLoginStage.command:
        case TerminalLoginStage.authenticating:
        case TerminalLoginStage.activatingMode:
          break;
      }
    } finally {
      if (mounted) {
        _setLauncherDialogPhase(
          _LauncherDialogPhase.closed,
          source: 'interaction_surface_complete',
        );
      }
    }
    if (!mounted || _interactionLocked) return;
    final deferred = _deferredLauncherResult;
    _deferredLauncherResult = null;
    if (deferred != null) {
      await _handleLauncherResult(deferred);
      if (!mounted || _interactionLocked) return;
    }
    await _syncLauncherInteractionSurface();
  }

  Future<void> _showLauncherDialog({
    required WidgetBuilder builder,
  }) async {
    _setLauncherDialogPhase(
      _LauncherDialogPhase.opening,
      source: 'dialog_route_start',
    );
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'launcher interaction',
      barrierColor: const Color(0xB8000000),
      transitionDuration:
          _reduceMotion ? Duration.zero : _miniTerminalRouteDuration,
      pageBuilder: (dialogContext, _, __) {
        final viewInsets = MediaQuery.viewInsetsOf(dialogContext);
        return Material(
          type: MaterialType.transparency,
          child: SafeArea(
            child: AnimatedPadding(
              duration: _reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.fromLTRB(
                12,
                12,
                12,
                12 + viewInsets.bottom,
              ),
              child: Center(
                child: SingleChildScrollView(
                  child: builder(dialogContext),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: child,
        );
      },
    );
  }

  Future<void> _showLauncherAccountTypeDialog() async {
    ParkinWorkinTerminalDiagnostics.record(
      'launcher_account_type_dialog_open',
      context: _contextLabel,
    );
    await _showLauncherDialog(
      builder: (dialogContext) => _LauncherSelectionDialog(
        title: 'ACCOUNT TYPE',
        description: '계정 유형을 선택하세요.',
        options: const <String>['일반 계정', '개인형 계정', '태블릿형 계정'],
        confirmLabel: '확인',
        reduceMotion: _reduceMotion,
        onStatus: _showDeveloperStatus,
        onOpened: _handleLauncherDialogOpened,
        onClosing: _handleLauncherDialogClosing,
        onConfirm: (index) async {
          const kinds = <TerminalAccountKind>[
            TerminalAccountKind.user,
            TerminalAccountKind.personal,
            TerminalAccountKind.tablet,
          ];
          final before = _launcherController!.errorSerial;
          final result = await _launcherController!.selectAccountKind(
            kinds[index],
            reduceMotion: _reduceMotion,
          );
          if (!mounted) return '처리를 완료하지 못했습니다.';
          _syncPlayback();
          if (_launcherController!.loginStage ==
              TerminalLoginStage.credentials) {
            _deferredLauncherResult = result;
            ParkinWorkinTerminalDiagnostics.record(
              'launcher_account_type_dialog_complete',
              context: _contextLabel,
              meta: <String, Object?>{
                'selection': TerminalAuthCoordinator.accountKindId(
                  kinds[index],
                ),
              },
            );
            return null;
          }
          if (_launcherController!.errorSerial > before) {
            return _latestLauncherError('계정 유형을 다시 확인하세요.');
          }
          return '계정 유형을 적용하지 못했습니다.';
        },
      ),
    );
  }

  Future<void> _showLauncherAccountDialog() async {
    ParkinWorkinTerminalDiagnostics.record(
      'launcher_account_dialog_open',
      context: _contextLabel,
      meta: <String, Object?>{
        'accountKind': _launcherController!.selectedAccountKindLabel,
      },
    );
    await _showLauncherDialog(
      builder: (dialogContext) => _LauncherAccountDialog(
        accountKind: _launcherController!.selectedAccountKindLabel,
        initialName: _launcherController!.enteredName,
        initialPhone: _launcherController!.enteredPhone,
        reduceMotion: _reduceMotion,
        onStatus: _showDeveloperStatus,
        onOpened: _handleLauncherDialogOpened,
        onClosing: _handleLauncherDialogClosing,
        onAuthenticate: _authenticateLauncherAccount,
      ),
    );
  }

  Future<LauncherCredentialSubmitResult> _authenticateLauncherAccount(
    String name,
    String phone,
    String password,
  ) async {
    ParkinWorkinTerminalDiagnostics.record(
      'launcher_account_dialog_submit',
      context: _contextLabel,
      meta: <String, Object?>{
        'nameLength': name.trim().length,
        'phoneLength': phone.replaceAll(RegExp(r'[^0-9]'), '').length,
        'passwordLength': password.length,
      },
    );
    final result = await _launcherController!.authenticateCredentials(
      context,
      name: name,
      phone: phone,
      password: password,
      reduceMotion: _reduceMotion,
    );
    if (!mounted) return result;
    _syncPlayback();
    if (result.accepted) {
      _deferredLauncherResult = result.flowResult;
      ParkinWorkinTerminalDiagnostics.record(
        'launcher_account_dialog_complete',
        context: _contextLabel,
        meta: <String, Object?>{
          'stage': _launcherController!.loginStage.name,
          'nameLength': name.trim().length,
          'phoneLength': phone.replaceAll(RegExp(r'[^0-9]'), '').length,
          'hasTargetRoute': result.flowResult.targetRoute != null,
        },
      );
    } else {
      ParkinWorkinTerminalDiagnostics.record(
        'launcher_account_dialog_rejected',
        context: _contextLabel,
        meta: <String, Object?>{
          'stage': _launcherController!.loginStage.name,
          'nameError': result.nameError != null,
          'phoneError': result.phoneError != null,
          'passwordError': result.passwordError != null,
          'authenticationError': result.authenticationError != null,
        },
      );
    }
    return result;
  }

  Future<void> _showLauncherWorkAreaDialog() async {
    final areas = _launcherController!.availableWorkAreas;
    final labels = areas.map((area) => area.areaName).toList(growable: false);
    ParkinWorkinTerminalDiagnostics.record(
      'launcher_work_area_dialog_open',
      context: _contextLabel,
      meta: <String, Object?>{'optionCount': labels.length},
    );
    await _showLauncherDialog(
      builder: (dialogContext) => _LauncherSelectionDialog(
        title: 'WORK AREA',
        description: '근무 지역을 선택하세요.',
        options: labels,
        confirmLabel: '확인',
        reduceMotion: _reduceMotion,
        onStatus: _showDeveloperStatus,
        onOpened: _handleLauncherDialogOpened,
        onClosing: _handleLauncherDialogClosing,
        onConfirm: (index) async {
          final before = _launcherController!.errorSerial;
          final area = areas[index];
          final result = await _launcherController!.selectWorkArea(
            context,
            area: area,
            reduceMotion: _reduceMotion,
          );
          if (!mounted) return '업무 지역을 적용하지 못했습니다.';
          _syncPlayback();
          final stage = _launcherController!.loginStage;
          if (_launcherController!.errorSerial > before &&
              stage == TerminalLoginStage.areaSelection) {
            return _latestLauncherError('업무 지역을 다시 확인하세요.');
          }
          if (stage == TerminalLoginStage.areaSelection &&
              result.targetRoute == null) {
            return _latestLauncherError('업무 지역을 적용하지 못했습니다.');
          }
          _deferredLauncherResult = result;
          ParkinWorkinTerminalDiagnostics.record(
            'launcher_work_area_dialog_complete',
            context: _contextLabel,
            meta: <String, Object?>{
              'area': area.areaName,
              'nextStage': stage.name,
              'hasTargetRoute': result.targetRoute != null,
            },
          );
          return null;
        },
      ),
    );
  }

  Future<void> _showLauncherModeDialog() async {
    final modes = _launcherController!.supportedModes;
    final labels = modes.map((mode) => mode.koreanName).toList(growable: false);
    ParkinWorkinTerminalDiagnostics.record(
      'launcher_mode_dialog_open',
      context: _contextLabel,
      meta: <String, Object?>{'optionCount': labels.length},
    );
    await _showLauncherDialog(
      builder: (dialogContext) => _LauncherSelectionDialog(
        title: 'WORK MODE',
        description: '사용할 모드를 선택하세요.',
        options: labels,
        confirmLabel: '확인',
        reduceMotion: _reduceMotion,
        onStatus: _showDeveloperStatus,
        onOpened: _handleLauncherDialogOpened,
        onClosing: _handleLauncherDialogClosing,
        onConfirm: (index) async {
          final before = _launcherController!.errorSerial;
          final mode = modes[index];
          final result = await _launcherController!.selectMode(
            context,
            mode: mode,
            reduceMotion: _reduceMotion,
          );
          if (!mounted) return '업무 모드를 적용하지 못했습니다.';
          _syncPlayback();
          final stage = _launcherController!.loginStage;
          if (_launcherController!.errorSerial > before &&
              stage == TerminalLoginStage.modeSelection) {
            return _latestLauncherError('업무 모드를 다시 확인하세요.');
          }
          if (stage == TerminalLoginStage.modeSelection &&
              result.targetRoute == null) {
            return _latestLauncherError('업무 모드를 적용하지 못했습니다.');
          }
          _deferredLauncherResult = result;
          ParkinWorkinTerminalDiagnostics.record(
            'launcher_mode_dialog_complete',
            context: _contextLabel,
            meta: <String, Object?>{
              'mode': mode.id,
              'hasTargetRoute': result.targetRoute != null,
            },
          );
          return null;
        },
      ),
    );
  }

  String _latestLauncherError(String fallback) {
    for (final line in _launcherController!.lines.reversed) {
      if (line.type == TerminalLineType.error) {
        return line.text
            .replaceFirst('[ERROR] ', '')
            .replaceFirst('[DENIED] ', '')
            .trim();
      }
    }
    return fallback;
  }

  Future<void> _submitWorkspaceRaw(String raw) async {
    if (_busy || _interactionLocked) return;
    if (raw.trim().isEmpty) {
      await HapticFeedback.mediumImpact();
      _workspaceController!.rejectEmptyInput();
      _promptFocusNode.requestFocus();
      return;
    }
    await HapticFeedback.selectionClick();
    _promptController.clear();
    await _executeWorkspaceCommand(raw);
  }

  Future<void> _executeWorkspaceCommand(
    String raw, {
    bool preservePrompt = false,
  }) async {
    if (_busy || _interactionLocked) return;
    final normalized = AppCommandRegistry.normalize(raw);
    final result = await _workspaceController!.submit(
      context,
      raw,
      reduceMotion: _reduceMotion,
    );
    if (!mounted || result == null) return;
    _syncPlayback();
    if (result.succeeded) {
      await HapticFeedback.lightImpact();
    } else {
      await HapticFeedback.mediumImpact();
    }
    if (result.definition?.command == 'out' && result.succeeded) {
      if (!mounted || _interactionLocked) return;
      await _closeWorkspaceTerminal();
      return;
    }
    if (normalized == 'status' && result.succeeded) {
      await _showDeveloperStatus();
      return;
    }
    if (result.definition?.launchesSurface == true) {
      _promptFocusNode.unfocus();
      final completion = result.surfaceCompletion;
      if (completion != null) unawaited(_restoreFocusAfterSurface(completion));
      return;
    }
    if (preservePrompt && _promptController.text.isNotEmpty) {
      return;
    }
    if (!_busy && !_interactionLocked && !_promptFocusNode.hasFocus) {
      _promptFocusNode.requestFocus();
    }
  }

  Future<void> _restoreFocusAfterSurface(Future<void> completion) async {
    await completion;
    if (!mounted || _busy || _interactionLocked) return;
    await Future<void>.delayed(
      _reduceMotion
          ? Duration.zero
          : Duration(milliseconds: 75 + (_contextLabel.hashCode.abs() % 45)),
    );
    if (mounted &&
        !_isLauncher &&
        !_busy &&
        !_interactionLocked &&
        !_startupSetupActive) {
      _promptFocusNode.requestFocus();
    }
  }

  Future<void> _closeLauncherAndNavigate(String route) async {
    if (_closing) return;
    setState(() => _closing = true);
    _bottomLockTimer?.cancel();
    _promptFocusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    ParkinWorkinTerminalDiagnostics.record(
      'terminal_close_start',
      context: _contextLabel,
      meta: <String, Object?>{'targetRoute': route},
    );
    if (_reduceMotion) {
      _openController.value = 0;
    } else {
      await _openController.reverse(from: 1);
    }
    if (!mounted) return;
    ParkinWorkinTerminalDiagnostics.record(
      'terminal_close_complete',
      context: _contextLabel,
      meta: <String, Object?>{
        'targetRoute': route,
        'runtimeContextReady':
            _isLauncher ? _launcherController!.runtimeContextReady : false,
        'workStatusNotification':
            WorkStatusNotificationController.status.value.title,
        'workStatusNotificationService':
            WorkStatusNotificationController.status.value.serviceRunning,
      },
    );
    Navigator.of(context).pushReplacementNamed(route);
  }

  Future<void> _closeWorkspaceTerminal() async {
    if (_closing) return;
    setState(() => _closing = true);
    _bottomLockTimer?.cancel();
    _promptFocusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    ParkinWorkinTerminalDiagnostics.record(
      'terminal_close_start',
      context: _contextLabel,
    );
    if (_reduceMotion) {
      _openController.value = 0;
    } else {
      await _openController.reverse(from: 1);
    }
    if (!mounted) return;
    ParkinWorkinTerminalDiagnostics.record(
      'terminal_close_complete',
      context: _contextLabel,
    );
    Navigator.of(context).pop();
  }

  Future<void> _showDeveloperStatus() async {
    if (_interactionLocked) return;
    _promptFocusNode.unfocus();
    final gmailStatus = await GmailSenderAuth.status();
    if (!mounted) return;
    final baseDescription = _isLauncher
        ? _launcherController!.developerStatusDescription()
        : <String>[
            'Context: workspace',
            'Source: ${widget.source}',
            'Busy: ${_workspaceController!.busy}',
            'Running: ${_workspaceController!.runningCommand.isEmpty ? '-' : _workspaceController!.runningCommand}',
            'Path: ${_workspaceController!.currentPromptPath}',
            'Email edit mode: ${_workspaceController!.emailEditMode}',
            'Source lines: ${_workspaceController!.lines.length}',
            'Visible lines: ${_playbackController.lines.length}',
            'Output queue: ${_playbackController.busy ? 'ACTIVE' : 'IDLE'}',
          ].join('\n');
    final promptLayout = _promptLayoutSnapshot;
    final surfaceDescription = _isLauncher
        ? <String>[
            'Launcher input surface: dialog',
            'Account dialog policy: credentials_only',
            'Session restore account dialog: bypass',
            'Launcher dialog phase: ${_launcherDialogPhase.name}',
            'Launcher dialog visible: ${_launcherDialogPhase == _LauncherDialogPhase.visible}',
            'Mini terminal open: ${_miniTerminalOpenDuration.inMilliseconds}ms',
            'Mini terminal close: ${_miniTerminalCloseDuration.inMilliseconds}ms',
            'Dialog route transition: ${_miniTerminalRouteDuration.inMilliseconds}ms',
            'Selection transport: structured',
            'Activity signature: ${_lastLauncherActivitySignature.isEmpty ? '-' : _lastLauncherActivitySignature}',
          ].join('\n')
        : promptLayout == null
            ? 'Prompt layout: -'
            : <String>[
                'Prompt layout: ${promptLayout.density.name}',
                'Prompt width: ${promptLayout.availableWidth.toStringAsFixed(1)}',
                'Prompt prefix max: ${promptLayout.promptMaxWidth.toStringAsFixed(1)}',
                'Prompt input reserve: ${promptLayout.minimumInputWidth.toStringAsFixed(1)}',
              ].join('\n');
    final interactionDescription = <String>[
      'App exiting: $_exitInProgress',
      'Interaction locked: $_interactionLocked',
      if (_isLauncher)
        'Runtime context ready: ${_launcherController!.runtimeContextReady}',
      if (_isLauncher)
        'Terminal playback: ${_playbackController.busy ? 'ACTIVE' : 'IDLE'}',
      if (_isLauncher)
        'Presentation ready: $_launcherPresentationReady',
      if (_isLauncher)
        'Navigation finalizing: $_launcherNavigationFinalizing',
      if (_isLauncher)
        'Login stage: ${_launcherController!.loginStage.name}',
      if (_isLauncher)
        'Running command: ${_launcherController!.runningCommand.isEmpty ? '-' : _launcherController!.runningCommand}',
      if (_isLauncher)
        'Account kind: ${_launcherController!.selectedAccountKindLabel.isEmpty ? '-' : _launcherController!.selectedAccountKindLabel}',
      if (_isLauncher)
        'Work area: ${_launcherController!.selectedWorkArea?.areaName ?? '-'}',
      if (_isLauncher)
        'Mode: ${_launcherController!.selectedMode?.koreanName ?? '-'}',
    ].join('\n');
    final description =
        '$baseDescription\n$interactionDescription\n$surfaceDescription\n${gmailStatus.developerDescription}';
    await ParkinWorkinTerminalDiagnostics.showStatus(
      context,
      terminalContext: _contextLabel,
      description: description,
    );
    if (mounted &&
        !_isLauncher &&
        !_busy &&
        !_interactionLocked) {
      _promptFocusNode.requestFocus();
    }
  }

  Widget _buildTerminal(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    final media = MediaQuery.of(context);
    final keyboardVisible = media.viewInsets.bottom > 0;
    final availableWidth = constraints.maxWidth;
    final availableHeight = constraints.maxHeight;
    final compact = availableWidth < 640;
    final width = compact
        ? availableWidth
        : math.min(availableWidth * .88, 980.0).toDouble();
    final fullSafeHeight = math.max(
      0.0,
      media.size.height - media.viewPadding.vertical - 24,
    ).toDouble();
    final restingHeight = compact ? fullSafeHeight * .80 : fullSafeHeight * .74;
    final height = math.min(restingHeight, availableHeight).toDouble();

    return AnimatedBuilder(
      animation: _openController,
      builder: (context, child) {
        final value = _reduceMotion ? 1.0 : _openController.value;
        final horizontal = Curves.easeOutCubic.transform(
          (value / .38).clamp(0.0, 1.0).toDouble(),
        );
        final vertical = Curves.easeOutCubic.transform(
          ((value - .22) / .50).clamp(0.0, 1.0).toDouble(),
        );
        final contentOpacity = Curves.easeOutCubic.transform(
          ((value - .58) / .42).clamp(0.0, 1.0).toDouble(),
        );
        final beamOpacity = value < .58
            ? (1 - ((value - .28) / .30).clamp(0.0, 1.0)).toDouble()
            : 0.0;

        return Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: beamOpacity,
              child: Container(
                width: width * horizontal,
                height: 2,
                color: _terminalPrompt,
              ),
            ),
            Transform.scale(
              scaleX: math.max(.015, horizontal).toDouble(),
              scaleY: math.max(.006, vertical).toDouble(),
              alignment: Alignment.center,
              child: AnimatedContainer(
                duration: _reduceMotion || keyboardVisible || _interactionLocked
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: width,
                height: height,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _terminalBackground,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _terminalBorder),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x99000000),
                        blurRadius: 32,
                        offset: Offset(0, 18),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: Opacity(
                      opacity: contentOpacity,
                      child: AnimatedScale(
                        scale: _exitInProgress ? .992 : 1,
                        duration: _reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        child: AnimatedOpacity(
                          opacity: _exitInProgress ? .82 : 1,
                          duration: _reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          child: child,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: Column(
        children: [
          _TerminalHeader(
            busy: _busy || _startupSetupBusy || _interactionLocked,
            navigationLocked: _startupSetupActive || _launcherBootstrapLocked,
            importingUnlocked: _importingUnlocked,
            reduceMotion: _reduceMotion,
            onCloseTerminal: () => _submitHeaderCommand('out'),
            onAbout: _isLauncher ? null : () => _submitHeaderCommand('about'),
            onAppExit: _isLauncher ? () => _submitHeaderCommand('exit') : null,
            onSetting: () => _submitHeaderCommand('setting'),
            appExiting: _exitInProgress,
            onStatus: _showDeveloperStatus,
          ),
          const Divider(height: 1, thickness: 1, color: _terminalBorder),
          Expanded(
            child: _TerminalHistory(
              lines: _playbackController.lines,
              scrollController: _scrollController,
              reduceMotion: _reduceMotion,
            ),
          ),
          if (_startupSetupActive) ...[
            const Divider(height: 1, thickness: 1, color: _terminalBorder),
            _TerminalStartupSetupPanel(
              controller: _launcherController!,
              reduceMotion: _reduceMotion,
              onPrimaryAction: _runStartupSetupPrimaryAction,
              onPermissionTitleTap: _handleStartupPermissionTitleTap,
              onGoogleTitleTap: _handleStartupGoogleTitleTap,
            ),
          ] else ...[
            if (_isLauncher)
              AnimatedSize(
                duration: _reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: _launcherController!.showAuthSummary
                    ? _TerminalAuthSummary(
                        key: const ValueKey<String>('auth-session'),
                        accountKind:
                            _launcherController!.selectedAccountKindLabel,
                        modeName:
                            _launcherController!.selectedMode?.koreanName ?? '',
                        areaName:
                            _launcherController!.selectedWorkArea?.areaName ?? '',
                        name: _launcherController!.enteredName,
                        reduceMotion: _reduceMotion,
                      )
                    : const SizedBox.shrink(),
              ),
            const Divider(height: 1, thickness: 1, color: _terminalBorder),
            if (_isLauncher)
              _LauncherActivityPanel(
                controller: _launcherController!,
                dialogPhase: _launcherDialogPhase,
                presentationReady: _launcherPresentationReady,
                closing: _closing,
                exiting: _exitInProgress,
                reduceMotion: _reduceMotion,
                onSignatureChanged: _handleLauncherActivitySignatureChanged,
              )
            else
              _TerminalPrompt(
                controller: _promptController,
                promptPath: _promptPath,
                focusNode: _promptFocusNode,
                busy: _busy || _interactionLocked,
                runningCommand: _exitInProgress
                    ? 'EXITING'
                    : _closing
                        ? 'CLOSING'
                        : _runningCommand,
                reduceMotion: _reduceMotion,
                keyboardType: _keyboardType,
                inputAction: _inputAction,
                obscureText: _obscureText,
                readOnly: false,
                inputVisible: true,
                emailEditMode: _emailEditMode,
                canBack: false,
                canCancel: false,
                canModes: false,
                modesLabel: 'MODES',
                onBack: () {},
                onCancel: () {},
                onModes: () {},
                onFocusRequested: _requestPromptFocusFromRow,
                onLayoutChanged: _handlePromptLayoutChanged,
                onSubmitted: _submit,
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Color(0xFF130810),
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: Color(0xFF130810),
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Scaffold(
          backgroundColor: const Color(0xFF130810),
          resizeToAvoidBottomInset: !_isLauncher,
          body: SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                12,
                12,
                12,
                !_isLauncher &&
                        (MediaQuery.of(context).viewInsets.bottom > 0 ||
                            _promptFocusNode.hasFocus)
                    ? 0
                    : 12,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final keyboardVisible =
                      MediaQuery.of(context).viewInsets.bottom > 0;
                  final alignBottom = !_isLauncher &&
                      (keyboardVisible ||
                          _promptFocusNode.hasFocus ||
                          _interactionLocked);
                  return Align(
                    alignment:
                        alignBottom ? Alignment.bottomCenter : Alignment.center,
                    child: _buildTerminal(context, constraints),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bottomLockTimer?.cancel();
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _promptFocusNode.removeListener(_handlePromptFocusChanged);
    _promptFocusNode.dispose();
    _promptController.dispose();
    _openController.dispose();
    _playbackController.removeListener(_handlePlaybackChanged);
    _playbackController.dispose();
    if (_launcherController != null) {
      _launcherController!.removeListener(_handleSourceChanged);
      _launcherController!.dispose();
    }
    if (_workspaceController != null) {
      _workspaceController!.removeListener(_handleSourceChanged);
      _workspaceController!.dispose();
    }
    super.dispose();
  }
}

class _TerminalHeader extends StatelessWidget {
  const _TerminalHeader({
    required this.busy,
    required this.navigationLocked,
    required this.importingUnlocked,
    required this.reduceMotion,
    required this.onCloseTerminal,
    required this.onAbout,
    required this.onAppExit,
    required this.onSetting,
    required this.appExiting,
    required this.onStatus,
  });

  final bool busy;
  final bool navigationLocked;
  final bool importingUnlocked;
  final bool reduceMotion;
  final VoidCallback onCloseTerminal;
  final VoidCallback? onAbout;
  final VoidCallback? onAppExit;
  final VoidCallback onSetting;
  final bool appExiting;
  final VoidCallback onStatus;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: _terminalHeader,
      child: Row(
        children: [
          const Text(
            '>_',
            style: TextStyle(
              color: _terminalPrompt,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 9),
          const Expanded(
            child: Text(
              'PARKINWORKIN TERMINAL',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _terminalText,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: .7,
              ),
            ),
          ),
          Semantics(
            label: importingUnlocked ? '보호 명령 활성' : '보호 명령 잠금',
            child: AnimatedSwitcher(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 240),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: .72, end: 1).animate(animation),
                    child: child,
                  ),
                );
              },
              child: Icon(
                importingUnlocked
                    ? Icons.lock_open_rounded
                    : Icons.lock_outline_rounded,
                key: ValueKey<bool>(importingUnlocked),
                size: 15,
                color: importingUnlocked ? _terminalSuccess : _terminalMuted,
              ),
            ),
          ),
          const SizedBox(width: 7),
          _TerminalHeaderAction(
            semanticLabel: onAppExit != null ? '시작 화면으로 돌아가기' : '터미널 닫기',
            onPressed: busy || navigationLocked ? null : onCloseTerminal,
            reduceMotion: reduceMotion,
            child: const Text(
              'X',
              style: TextStyle(
                color: _terminalMuted,
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 2),
          AnimatedSwitcher(
            duration:
                reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: .82, end: 1).animate(animation),
                  child: child,
                ),
              );
            },
            child: onAppExit != null
                ? _TerminalHeaderAction(
                    key: const ValueKey<String>('app_exit'),
                    semanticLabel: '앱 종료',
                    onPressed: busy || navigationLocked ? null : onAppExit,
                    reduceMotion: reduceMotion,
                    processing: appExiting,
                    child: AnimatedSwitcher(
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 150),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: appExiting
                          ? const SizedBox(
                              key: ValueKey<String>('exit_processing'),
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.8,
                                color: _terminalError,
                              ),
                            )
                          : const Icon(
                              Icons.power_settings_new_rounded,
                              key: ValueKey<String>('exit_idle'),
                              size: 17,
                              color: _terminalError,
                            ),
                    ),
                  )
                : _TerminalHeaderAction(
                    key: const ValueKey<String>('about'),
                    semanticLabel: '앱 소개',
                    onPressed: busy || navigationLocked ? null : onAbout,
                    reduceMotion: reduceMotion,
                    child: const Text(
                      '?',
                      style: TextStyle(
                        color: _terminalMuted,
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 2),
          _TerminalHeaderAction(
            semanticLabel: '설정',
            onPressed: busy || navigationLocked ? null : onSetting,
            reduceMotion: reduceMotion,
            child: const Icon(
              Icons.settings_outlined,
              size: 16,
              color: _terminalMuted,
            ),
          ),
          const SizedBox(width: 4),
          ValueListenableBuilder<bool>(
            valueListenable: DevAuth.devModeEnabled,
            builder: (context, enabled, _) {
              return AnimatedSwitcher(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 160),
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(.08, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: Row(
                  key: ValueKey<String>(enabled ? 'debug' : 'standard'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (enabled)
                      const DebugCautionSurface(
                        child: Padding(
                          padding: EdgeInsets.all(2),
                          child: DebugCautionLabel(
                            padding: EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 4,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 5,
                                  height: 5,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: debugCautionYellow,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                                SizedBox(width: 5),
                                Text(
                                  'DEBUG',
                                  style: TextStyle(
                                    color: debugCautionYellow,
                                    fontFamily: 'monospace',
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: .4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _terminalMuted.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: _terminalMuted),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 5,
                              height: 5,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: _terminalMuted,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            SizedBox(width: 5),
                            Text(
                              'STANDARD',
                              style: TextStyle(
                                color: _terminalMuted,
                                fontFamily: 'monospace',
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: .4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (enabled) ...[
                      const SizedBox(width: 6),
                      TextButton(
                        onPressed: busy ? null : onStatus,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 30),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'STATUS',
                          style: TextStyle(
                            color: _terminalMuted,
                            fontFamily: 'monospace',
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TerminalHeaderAction extends StatefulWidget {
  const _TerminalHeaderAction({
    super.key,
    required this.semanticLabel,
    required this.onPressed,
    required this.reduceMotion,
    required this.child,
    this.processing = false,
  });

  final String semanticLabel;
  final VoidCallback? onPressed;
  final bool reduceMotion;
  final Widget child;
  final bool processing;

  @override
  State<_TerminalHeaderAction> createState() => _TerminalHeaderActionState();
}

class _TerminalHeaderActionState extends State<_TerminalHeaderAction> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: AnimatedOpacity(
        opacity: enabled ? 1 : widget.processing ? .88 : .34,
        duration: widget.reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: AnimatedScale(
          scale: _pressed ? .84 : 1,
          duration: widget.reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          child: Listener(
            onPointerDown: enabled
                ? (_) {
                    if (!_pressed) setState(() => _pressed = true);
                  }
                : null,
            onPointerUp: (_) {
              if (_pressed) setState(() => _pressed = false);
            },
            onPointerCancel: (_) {
              if (_pressed) setState(() => _pressed = false);
            },
            child: SizedBox(
              width: 30,
              height: 30,
              child: IconButton(
                onPressed: widget.onPressed,
                padding: EdgeInsets.zero,
                splashRadius: 16,
                icon: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TerminalStartupSetupPanel extends StatelessWidget {
  const _TerminalStartupSetupPanel({
    required this.controller,
    required this.reduceMotion,
    required this.onPrimaryAction,
    required this.onPermissionTitleTap,
    required this.onGoogleTitleTap,
  });

  final ModeLauncherController controller;
  final bool reduceMotion;
  final Future<void> Function() onPrimaryAction;
  final Future<void> Function() onPermissionTitleTap;
  final Future<void> Function() onGoogleTitleTap;

  @override
  Widget build(BuildContext context) {
    final setup = controller.startupSetup;
    final key = ValueKey<String>(
      '${setup.phase.name}-${setup.currentPermissionStep ?? 0}-${setup.currentPolicySpec?.kind.name ?? 'none'}',
    );
    final child = switch (setup.phase) {
      AppStartSetupPhase.permission => _TerminalPermissionSetupView(
          key: key,
          controller: controller,
          reduceMotion: reduceMotion,
          onPrimaryAction: onPrimaryAction,
          onTitleTap: onPermissionTitleTap,
        ),
      AppStartSetupPhase.terms ||
      AppStartSetupPhase.privacy ||
      AppStartSetupPhase.accountDeletion =>
        _TerminalPolicySetupView(
          key: key,
          controller: controller,
          reduceMotion: reduceMotion,
          onPrimaryAction: onPrimaryAction,
        ),
      AppStartSetupPhase.googleServices => _TerminalGoogleSetupView(
          key: key,
          controller: controller,
          reduceMotion: reduceMotion,
          onPrimaryAction: onPrimaryAction,
          onTitleTap: onGoogleTitleTap,
        ),
      _ => const SizedBox.shrink(),
    };
    return AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 190),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        if (reduceMotion) return child;
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, .035),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _TerminalPermissionSetupView extends StatelessWidget {
  const _TerminalPermissionSetupView({
    super.key,
    required this.controller,
    required this.reduceMotion,
    required this.onPrimaryAction,
    required this.onTitleTap,
  });

  final ModeLauncherController controller;
  final bool reduceMotion;
  final Future<void> Function() onPrimaryAction;
  final Future<void> Function() onTitleTap;

  @override
  Widget build(BuildContext context) {
    final setup = controller.startupSetup;
    final spec = setup.currentPermissionSpec;
    if (spec == null) return const SizedBox.shrink();
    final statusColor = setup.currentPermissionGranted
        ? _terminalSuccess
        : setup.busy || setup.awaitingExternalSettings
            ? _terminalWarning
            : _terminalText;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'SETUP / PERMISSIONS',
                  style: _terminalSectionLabelStyle,
                ),
              ),
              Text(
                '${setup.permissionIndex + 1} / ${setup.permissionSteps.length}',
                style: _terminalSectionMetaStyle,
              ),
            ],
          ),
          const SizedBox(height: 9),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTitleTap,
            child: TweenAnimationBuilder<double>(
              key: ValueKey<String>(
                'permission-title-${spec.step}-${setup.permissionSkipTapCount}',
              ),
              tween: Tween<double>(begin: .985, end: 1),
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 130),
              curve: Curves.easeOutCubic,
              builder: (context, scale, child) {
                return Transform.scale(
                  scale: scale,
                  alignment: Alignment.centerLeft,
                  child: child,
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  spec.title,
                  style: _terminalSectionTitleStyle,
                ),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            spec.description,
            style: _terminalSectionBodyStyle,
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, thickness: 1, color: _terminalBorder),
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(
                width: 88,
                child: Text('STATUS', style: _terminalSectionLabelStyle),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 170),
                  child: Text(
                    setup.currentPermissionStatus.toUpperCase(),
                    key: ValueKey<String>(setup.currentPermissionStatus),
                    style: _terminalSectionBodyStyle.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _TerminalSetupActionButton(
            label: setup.primaryActionLabel,
            enabled: setup.primaryActionEnabled,
            busy: setup.busy,
            reduceMotion: reduceMotion,
            onPressed: onPrimaryAction,
          ),
        ],
      ),
    );
  }
}

class _TerminalPolicySetupView extends StatefulWidget {
  const _TerminalPolicySetupView({
    super.key,
    required this.controller,
    required this.reduceMotion,
    required this.onPrimaryAction,
  });

  final ModeLauncherController controller;
  final bool reduceMotion;
  final Future<void> Function() onPrimaryAction;

  @override
  State<_TerminalPolicySetupView> createState() =>
      _TerminalPolicySetupViewState();
}

class _TerminalPolicySetupViewState extends State<_TerminalPolicySetupView> {
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportProgress());
  }

  void _handleScroll() {
    _reportProgress();
  }

  void _reportProgress() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    final max = position.maxScrollExtent;
    final progress = max <= 0 ? 1.0 : (position.pixels / max).clamp(0.0, 1.0);
    final readToEnd = max <= 0 || position.pixels >= max - 8;
    widget.controller.updateStartupPolicyProgress(
      progress.toDouble(),
      readToEnd,
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_handleScroll);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final setup = widget.controller.startupSetup;
    final spec = setup.currentPolicySpec;
    if (spec == null) return const SizedBox.shrink();
    final bodyHeight = (MediaQuery.sizeOf(context).height * .24)
        .clamp(112.0, 250.0)
        .toDouble();
    final progressText = setup.policyReadToEnd
        ? 'READ COMPLETE'
        : '${(setup.policyScrollProgress * 100).round()}%';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('SETUP / POLICY', style: _terminalSectionLabelStyle),
              ),
              Text(
                '${spec.step} / ${spec.totalSteps}',
                style: _terminalSectionMetaStyle,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(spec.title, style: _terminalSectionTitleStyle),
          const SizedBox(height: 4),
          Text(spec.subtitle, style: _terminalSectionBodyStyle),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('READ', style: _terminalSectionLabelStyle),
              const SizedBox(width: 10),
              Expanded(
                child: TweenAnimationBuilder<double>(
                  duration: widget.reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  tween: Tween<double>(
                    begin: 0,
                    end: setup.policyScrollProgress,
                  ),
                  builder: (context, value, child) {
                    return LinearProgressIndicator(
                      minHeight: 2,
                      value: value,
                      backgroundColor: _terminalBorder,
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(_terminalPrompt),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              AnimatedSwitcher(
                duration: widget.reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 160),
                child: Text(
                  progressText,
                  key: ValueKey<String>(progressText),
                  style: _terminalSectionMetaStyle.copyWith(
                    color: setup.policyReadToEnd
                        ? _terminalSuccess
                        : _terminalMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          const Divider(height: 1, thickness: 1, color: _terminalBorder),
          SizedBox(
            height: bodyHeight,
            child: Scrollbar(
              controller: _controller,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _controller,
                padding: const EdgeInsets.fromLTRB(0, 10, 10, 10),
                child: Text(
                  spec.body,
                  style: _terminalSectionBodyStyle.copyWith(height: 1.55),
                ),
              ),
            ),
          ),
          const Divider(height: 1, thickness: 1, color: _terminalBorder),
          const SizedBox(height: 7),
          _TerminalPolicyAgreementRow(
            label: spec.agreeLabel,
            enabled: setup.policyReadToEnd && !setup.busy,
            checked: setup.policyAgreed,
            reduceMotion: widget.reduceMotion,
            onChanged: widget.controller.setStartupPolicyAgreed,
          ),
          const SizedBox(height: 9),
          _TerminalSetupActionButton(
            label: setup.primaryActionLabel,
            enabled: setup.primaryActionEnabled,
            busy: setup.busy,
            reduceMotion: widget.reduceMotion,
            onPressed: widget.onPrimaryAction,
          ),
        ],
      ),
    );
  }
}

class _TerminalGoogleSetupView extends StatelessWidget {
  const _TerminalGoogleSetupView({
    super.key,
    required this.controller,
    required this.reduceMotion,
    required this.onPrimaryAction,
    required this.onTitleTap,
  });

  final ModeLauncherController controller;
  final bool reduceMotion;
  final Future<void> Function() onPrimaryAction;
  final Future<void> Function() onTitleTap;

  @override
  Widget build(BuildContext context) {
    final setup = controller.startupSetup;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('SETUP / SERVICES', style: _terminalSectionLabelStyle),
          const SizedBox(height: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTitleTap,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 2),
              child: Text(
                'Google 서비스 연결',
                style: _terminalSectionTitleStyle,
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '업무에 필요한 Google 서비스를 한 번의 승인 과정으로 연결합니다.',
            style: _terminalSectionBodyStyle,
          ),
          const SizedBox(height: 9),
          const Divider(height: 1, thickness: 1, color: _terminalBorder),
          for (var index = 0;
              index < appStartGoogleServiceSpecs.length;
              index++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 118,
                    child: Text(
                      appStartGoogleServiceSpecs[index].title,
                      style: _terminalSectionBodyStyle.copyWith(
                        color: _terminalText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      appStartGoogleServiceSpecs[index].detail,
                      style: _terminalSectionMetaStyle,
                    ),
                  ),
                ],
              ),
            ),
            if (index < appStartGoogleServiceSpecs.length - 1)
              const Divider(height: 1, thickness: 1, color: _terminalBorder),
          ],
          const Divider(height: 1, thickness: 1, color: _terminalBorder),
          const SizedBox(height: 7),
          Row(
            children: [
              const SizedBox(
                width: 88,
                child: Text('STATUS', style: _terminalSectionLabelStyle),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration:
                      reduceMotion ? Duration.zero : const Duration(milliseconds: 170),
                  child: Text(
                    setup.googleConnected ? 'CONNECTED' : 'NOT CONNECTED',
                    key: ValueKey<bool>(setup.googleConnected),
                    style: _terminalSectionBodyStyle.copyWith(
                      color: setup.googleConnected
                          ? _terminalSuccess
                          : _terminalText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (setup.googleAccountEmail != null) ...[
            const SizedBox(height: 4),
            Text(
              setup.googleAccountEmail!,
              style: _terminalSectionMetaStyle,
            ),
          ],
          if (setup.googleErrorText != null) ...[
            const SizedBox(height: 5),
            Text(
              setup.googleErrorText!,
              style: _terminalSectionBodyStyle.copyWith(color: _terminalError),
            ),
          ],
          const SizedBox(height: 9),
          _TerminalSetupActionButton(
            label: setup.primaryActionLabel,
            enabled: setup.primaryActionEnabled,
            busy: setup.busy,
            reduceMotion: reduceMotion,
            onPressed: onPrimaryAction,
          ),
        ],
      ),
    );
  }
}

class _TerminalPolicyAgreementRow extends StatelessWidget {
  const _TerminalPolicyAgreementRow({
    required this.label,
    required this.enabled,
    required this.checked,
    required this.reduceMotion,
    required this.onChanged,
  });

  final String label;
  final bool enabled;
  final bool checked;
  final bool reduceMotion;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      checked: checked,
      enabled: enabled,
      label: label,
      child: InkWell(
        onTap: enabled ? () => onChanged(!checked) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              AnimatedContainer(
                width: 18,
                height: 18,
                duration:
                    reduceMotion ? Duration.zero : const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: checked ? _terminalPrompt : Colors.transparent,
                  border: Border.all(
                    color: enabled ? _terminalPrompt : _terminalBorder,
                  ),
                ),
                child: AnimatedSwitcher(
                  duration:
                      reduceMotion ? Duration.zero : const Duration(milliseconds: 140),
                  child: checked
                      ? const Icon(
                          Icons.check_rounded,
                          key: ValueKey<String>('checked'),
                          size: 14,
                          color: _terminalBackground,
                        )
                      : const SizedBox.shrink(
                          key: ValueKey<String>('unchecked'),
                        ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  style: _terminalSectionBodyStyle.copyWith(
                    color: enabled ? _terminalText : _terminalMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TerminalSetupActionButton extends StatefulWidget {
  const _TerminalSetupActionButton({
    required this.label,
    required this.enabled,
    required this.busy,
    required this.reduceMotion,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final bool busy;
  final bool reduceMotion;
  final Future<void> Function() onPressed;

  @override
  State<_TerminalSetupActionButton> createState() =>
      _TerminalSetupActionButtonState();
}

class _TerminalSetupActionButtonState extends State<_TerminalSetupActionButton> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && (_pressed || _hovered);
    final borderColor = widget.enabled ? _terminalPrompt : _terminalBorder;
    final foreground = widget.enabled ? _terminalPrompt : _terminalMuted;
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.label,
      child: MouseRegion(
        onEnter: (_) {
          if (widget.enabled) setState(() => _hovered = true);
        },
        onExit: (_) {
          if (_hovered) setState(() => _hovered = false);
        },
        child: AnimatedScale(
          scale: _pressed ? .985 : 1,
          duration:
              widget.reduceMotion ? Duration.zero : const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            width: double.infinity,
            duration:
                widget.reduceMotion ? Duration.zero : const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: active ? const Color(0x2236FF74) : Colors.transparent,
              border: Border.all(color: borderColor),
            ),
            child: InkWell(
              onTap: widget.enabled && !widget.busy ? widget.onPressed : null,
              onHighlightChanged: (value) {
                if (_pressed == value) return;
                setState(() => _pressed = value);
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 42),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedSwitcher(
                        duration: widget.reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 150),
                        child: widget.busy
                            ? const SizedBox(
                                key: ValueKey<String>('busy'),
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: _terminalWarning,
                                ),
                              )
                            : const Icon(
                                Icons.chevron_right_rounded,
                                key: ValueKey<String>('ready'),
                                size: 17,
                                color: _terminalPrompt,
                              ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: AnimatedSwitcher(
                          duration: widget.reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 170),
                          transitionBuilder: (child, animation) {
                            final slide = Tween<Offset>(
                              begin: const Offset(.04, 0),
                              end: Offset.zero,
                            ).animate(
                              CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutCubic,
                              ),
                            );
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: slide,
                                child: child,
                              ),
                            );
                          },
                          child: Text(
                            widget.label.toUpperCase(),
                            key: ValueKey<String>(widget.label),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: foreground,
                              fontFamily: 'monospace',
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const TextStyle _terminalSectionLabelStyle = TextStyle(
  color: _terminalWarning,
  fontFamily: 'monospace',
  fontSize: 9.5,
  fontWeight: FontWeight.w800,
  letterSpacing: .2,
);

const TextStyle _terminalSectionMetaStyle = TextStyle(
  color: _terminalMuted,
  fontFamily: 'monospace',
  fontSize: 10.5,
  height: 1.35,
  fontWeight: FontWeight.w600,
);

const TextStyle _terminalSectionTitleStyle = TextStyle(
  color: _terminalText,
  fontFamily: 'monospace',
  fontSize: 14.5,
  height: 1.35,
  fontWeight: FontWeight.w800,
);

const TextStyle _terminalSectionBodyStyle = TextStyle(
  color: _terminalMuted,
  fontFamily: 'monospace',
  fontSize: 11.2,
  height: 1.42,
  fontWeight: FontWeight.w500,
);

class _TerminalAuthSummary extends StatelessWidget {
  const _TerminalAuthSummary({
    super.key,
    required this.accountKind,
    required this.modeName,
    required this.areaName,
    required this.name,
    required this.reduceMotion,
  });

  final String accountKind;
  final String modeName;
  final String areaName;
  final String name;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final rows = <MapEntry<String, String>>[
      if (accountKind.isNotEmpty)
        MapEntry<String, String>('ACCOUNT', accountKind),
      if (name.isNotEmpty)
        MapEntry<String, String>('USER', name),
      if (areaName.isNotEmpty)
        MapEntry<String, String>('AREA', areaName),
      if (modeName.isNotEmpty)
        MapEntry<String, String>('MODE', modeName),
    ];

    return AnimatedSize(
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 190),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Container(
        width: double.infinity,
        color: const Color(0xFF2A0C22),
        padding: const EdgeInsets.fromLTRB(16, 9, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'AUTH SESSION',
              style: TextStyle(
                color: _terminalWarning,
                fontFamily: 'monospace',
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 5),
            for (var index = 0; index < rows.length; index++)
              TweenAnimationBuilder<double>(
                key: ValueKey<String>(rows[index].key),
                duration: reduceMotion
                    ? Duration.zero
                    : Duration(milliseconds: 130 + index * 35),
                curve: Curves.easeOutCubic,
                tween: Tween<double>(begin: 0, end: 1),
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, (1 - value) * 4),
                      child: child,
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 120,
                        child: Text(
                          rows[index].key,
                          style: const TextStyle(
                            color: _terminalMuted,
                            fontFamily: 'monospace',
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 160),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) {
                            final slide = Tween<Offset>(
                              begin: const Offset(.025, 0),
                              end: Offset.zero,
                            ).animate(animation);
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: slide,
                                child: child,
                              ),
                            );
                          },
                          child: Text(
                            rows[index].value,
                            key: ValueKey<String>(
                              '${rows[index].key}:${rows[index].value}',
                            ),
                            style: const TextStyle(
                              color: _terminalText,
                              fontFamily: 'monospace',
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}


class _TerminalHistory extends StatelessWidget {
  const _TerminalHistory({
    required this.lines,
    required this.scrollController,
    required this.reduceMotion,
  });

  final List<TerminalLine> lines;
  final ScrollController scrollController;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: scrollController,
      thumbVisibility: false,
      child: ListView.builder(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        itemCount: lines.length,
        itemBuilder: (context, index) {
          final line = lines[index];
          return _TerminalOutputLine(
            key: ValueKey<int>(line.id),
            line: line,
            reduceMotion: reduceMotion,
          );
        },
      ),
    );
  }
}

class _TerminalOutputLine extends StatelessWidget {
  const _TerminalOutputLine({
    super.key,
    required this.line,
    required this.reduceMotion,
  });

  final TerminalLine line;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final color = switch (line.type) {
      TerminalLineType.command => _terminalText,
      TerminalLineType.running => _terminalMuted,
      TerminalLineType.output => _terminalText,
      TerminalLineType.success => _terminalSuccess,
      TerminalLineType.error => _terminalError,
      TerminalLineType.system => _terminalMuted,
    };
    final child = line.type == TerminalLineType.command
        ? _PromptCommandLine(
            command: line.text,
            promptPath: line.promptPath,
          )
        : line.type == TerminalLineType.running
            ? _RunningTerminalText(
                text: line.text,
                reduceMotion: reduceMotion,
              )
            : Text(
                line.text,
                style: TextStyle(
                  color: color,
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  height: 1.42,
                  fontWeight: line.type == TerminalLineType.success ||
                          line.type == TerminalLineType.error
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
              );

    return TweenAnimationBuilder<double>(
      duration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 145),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 4),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: child,
      ),
    );
  }
}

class _RunningTerminalText extends StatefulWidget {
  const _RunningTerminalText({
    required this.text,
    required this.reduceMotion,
  });

  final String text;
  final bool reduceMotion;

  @override
  State<_RunningTerminalText> createState() => _RunningTerminalTextState();
}

class _RunningTerminalTextState extends State<_RunningTerminalText> {
  Timer? _timer;
  int _dots = 1;

  @override
  void initState() {
    super.initState();
    _configureTimer();
  }

  @override
  void didUpdateWidget(covariant _RunningTerminalText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reduceMotion != widget.reduceMotion) {
      _configureTimer();
    }
  }

  void _configureTimer() {
    _timer?.cancel();
    if (widget.reduceMotion) return;
    _timer = Timer.periodic(const Duration(milliseconds: 410), (_) {
      if (!mounted) return;
      setState(() => _dots = _dots == 3 ? 1 : _dots + 1);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.text.replaceFirst(RegExp(r'\.+$'), '');
    final suffix = widget.text.isEmpty
        ? ''
        : widget.reduceMotion
            ? '...'
            : List<String>.filled(_dots, '.').join();
    return Text(
      '$base$suffix',
      style: const TextStyle(
        color: _terminalMuted,
        fontFamily: 'monospace',
        fontSize: 12.5,
        height: 1.42,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _PromptCommandLine extends StatelessWidget {
  const _PromptCommandLine({
    required this.command,
    required this.promptPath,
  });

  final String command;
  final String promptPath;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12.5,
          height: 1.42,
        ),
        children: [
          const TextSpan(
            text: 'parkinworkin@terminal',
            style: TextStyle(
              color: _terminalPrompt,
              fontWeight: FontWeight.w700,
            ),
          ),
          const TextSpan(
            text: ':',
            style: TextStyle(color: _terminalMuted),
          ),
          TextSpan(
            text: promptPath,
            style: const TextStyle(
              color: _terminalPath,
              fontWeight: FontWeight.w700,
            ),
          ),
          const TextSpan(
            text: r'$ ',
            style: TextStyle(color: _terminalMuted),
          ),
          TextSpan(
            text: command,
            style: const TextStyle(
              color: _terminalText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

enum _TerminalPromptDensity {
  full,
  compact,
  pathOnly,
}

class _TerminalPromptLayoutSnapshot {
  const _TerminalPromptLayoutSnapshot({
    required this.promptPath,
    required this.density,
    required this.availableWidth,
    required this.promptMaxWidth,
    required this.minimumInputWidth,
    required this.emailSuffixVisible,
    required this.actionLabelVisible,
    required this.busyLabelVisible,
  });

  final String promptPath;
  final _TerminalPromptDensity density;
  final double availableWidth;
  final double promptMaxWidth;
  final double minimumInputWidth;
  final bool emailSuffixVisible;
  final bool actionLabelVisible;
  final bool busyLabelVisible;

  String get signature => <Object>[
        promptPath,
        density.name,
        availableWidth.round(),
        promptMaxWidth.round(),
        minimumInputWidth.round(),
        emailSuffixVisible,
        actionLabelVisible,
        busyLabelVisible,
      ].join('|');
}

class _TerminalPrompt extends StatefulWidget {
  const _TerminalPrompt({
    required this.controller,
    required this.promptPath,
    required this.focusNode,
    required this.busy,
    required this.runningCommand,
    required this.reduceMotion,
    required this.keyboardType,
    required this.inputAction,
    required this.obscureText,
    required this.readOnly,
    required this.inputVisible,
    required this.emailEditMode,
    required this.canBack,
    required this.canCancel,
    required this.canModes,
    required this.modesLabel,
    required this.onBack,
    required this.onCancel,
    required this.onModes,
    required this.onFocusRequested,
    required this.onLayoutChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final String promptPath;
  final FocusNode focusNode;
  final bool busy;
  final String runningCommand;
  final bool reduceMotion;
  final TextInputType keyboardType;
  final TextInputAction inputAction;
  final bool obscureText;
  final bool readOnly;
  final bool inputVisible;
  final bool emailEditMode;
  final bool canBack;
  final bool canCancel;
  final bool canModes;
  final String modesLabel;
  final VoidCallback onBack;
  final VoidCallback onCancel;
  final VoidCallback onModes;
  final VoidCallback onFocusRequested;
  final ValueChanged<_TerminalPromptLayoutSnapshot> onLayoutChanged;
  final VoidCallback onSubmitted;

  @override
  State<_TerminalPrompt> createState() => _TerminalPromptState();
}

class _TerminalPromptState extends State<_TerminalPrompt> {
  String? _lastLayoutSignature;

  void _reportLayout(_TerminalPromptLayoutSnapshot snapshot) {
    final signature = snapshot.signature;
    if (_lastLayoutSignature == signature) return;
    _lastLayoutSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onLayoutChanged(snapshot);
    });
  }

  @override
  Widget build(BuildContext context) {
    final showActions = widget.canBack || widget.canCancel || widget.canModes;
    return AnimatedContainer(
      duration: widget.reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 180),
      constraints: BoxConstraints(minHeight: showActions ? 72 : 50),
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      color: widget.busy ? const Color(0xFF2A0C22) : _terminalHeader,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.maxWidth;
              final showActionLabel = !widget.busy && availableWidth >= 500;
              final emailSuffixReserve = widget.emailEditMode ? 82.0 : 0.0;
              final busyLabelReserve = widget.busy ? 92.0 : 0.0;
              final actionLabelReserve = showActionLabel ? 38.0 : 0.0;
              final trailingReserve = emailSuffixReserve +
                  busyLabelReserve +
                  actionLabelReserve;
              final promptAndInputWidth = math.max(
                0.0,
                availableWidth - trailingReserve,
              ).toDouble();
              final preferredInputWidth = math.max(
                112.0,
                promptAndInputWidth * .48,
              ).toDouble();
              final minimumInputWidth = math.max(
                0.0,
                math.min(
                  210.0,
                  math.min(
                    preferredInputWidth,
                    math.max(
                      0.0,
                      promptAndInputWidth - 18.0,
                    ),
                  ),
                ),
              ).toDouble();
              final promptMaxWidth = math.max(
                0.0,
                promptAndInputWidth - minimumInputWidth,
              ).toDouble();
              final density = promptMaxWidth >= 250
                  ? _TerminalPromptDensity.full
                  : promptMaxWidth >= 150
                      ? _TerminalPromptDensity.compact
                      : _TerminalPromptDensity.pathOnly;
              final snapshot = _TerminalPromptLayoutSnapshot(
                promptPath: widget.promptPath,
                density: density,
                availableWidth: availableWidth,
                promptMaxWidth: promptMaxWidth,
                minimumInputWidth: minimumInputWidth,
                emailSuffixVisible: widget.emailEditMode,
                actionLabelVisible: showActionLabel,
                busyLabelVisible: widget.busy,
              );
              _reportLayout(snapshot);
              final hostLabel = switch (density) {
                _TerminalPromptDensity.full => 'parkinworkin@terminal',
                _TerminalPromptDensity.compact => 'pw@terminal',
                _TerminalPromptDensity.pathOnly => '',
              };
              final hostVisible = hostLabel.isNotEmpty;
              final pathMaxWidth = switch (density) {
                _TerminalPromptDensity.full => math.max(
                    0.0,
                    promptMaxWidth - 166.0,
                  ).toDouble(),
                _TerminalPromptDensity.compact => math.max(
                    0.0,
                    promptMaxWidth - 94.0,
                  ).toDouble(),
                _TerminalPromptDensity.pathOnly => math.max(
                    0.0,
                    promptMaxWidth - 16.0,
                  ).toDouble(),
              };
              return GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: widget.busy ? null : widget.onFocusRequested,
                child: Row(
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: promptMaxWidth),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ClipRect(
                            child: AnimatedSwitcher(
                              duration: widget.reduceMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 155),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (child, animation) {
                                final offset = Tween<Offset>(
                                  begin: const Offset(-0.08, 0),
                                  end: Offset.zero,
                                ).animate(
                                  CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeOutCubic,
                                  ),
                                );
                                return FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: offset,
                                    child: child,
                                  ),
                                );
                              },
                              child: hostVisible
                                  ? Text(
                                      hostLabel,
                                      key: ValueKey<String>(
                                        'terminal-host-$hostLabel',
                                      ),
                                      maxLines: 1,
                                      softWrap: false,
                                      style: const TextStyle(
                                        color: _terminalPrompt,
                                        fontFamily: 'monospace',
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    )
                                  : const SizedBox.shrink(
                                      key: ValueKey<String>(
                                        'terminal-host-hidden',
                                      ),
                                    ),
                            ),
                          ),
                          AnimatedSwitcher(
                            duration: widget.reduceMotion
                                ? Duration.zero
                                : const Duration(milliseconds: 130),
                            child: hostVisible
                                ? const Text(
                                    ':',
                                    key: ValueKey<String>('terminal-colon'),
                                    style: TextStyle(
                                      color: _terminalMuted,
                                      fontFamily: 'monospace',
                                      fontSize: 12.5,
                                    ),
                                  )
                                : const SizedBox.shrink(
                                    key: ValueKey<String>(
                                      'terminal-colon-hidden',
                                    ),
                                  ),
                          ),
                          Flexible(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: pathMaxWidth,
                              ),
                              child: ClipRect(
                                child: AnimatedSwitcher(
                                  duration: widget.reduceMotion
                                      ? Duration.zero
                                      : const Duration(milliseconds: 165),
                                  transitionBuilder: (child, animation) {
                                    final offset = Tween<Offset>(
                                      begin: const Offset(0.08, 0),
                                      end: Offset.zero,
                                    ).animate(
                                      CurvedAnimation(
                                        parent: animation,
                                        curve: Curves.easeOutCubic,
                                      ),
                                    );
                                    return FadeTransition(
                                      opacity: animation,
                                      child: SlideTransition(
                                        position: offset,
                                        child: child,
                                      ),
                                    );
                                  },
                                  child: Text(
                                    widget.promptPath,
                                    key: ValueKey<String>(widget.promptPath),
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: _terminalPath,
                                      fontFamily: 'monospace',
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const Text(
                            r'$ ',
                            style: TextStyle(
                              color: _terminalMuted,
                              fontFamily: 'monospace',
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: AnimatedSlide(
                        duration: widget.reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 145),
                        curve: Curves.easeOutCubic,
                        offset: widget.inputVisible
                            ? Offset.zero
                            : const Offset(-0.025, 0),
                        child: AnimatedOpacity(
                          duration: widget.reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 145),
                          curve: Curves.easeOutCubic,
                          opacity: widget.inputVisible ? 1 : 0,
                          child: TextField(
                            controller: widget.controller,
                            focusNode: widget.focusNode,
                            enabled: !widget.busy,
                            readOnly: widget.readOnly,
                            keyboardType: widget.keyboardType,
                            obscureText: widget.obscureText,
                            textInputAction: widget.inputAction,
                            autocorrect: false,
                            enableSuggestions: false,
                            textCapitalization: TextCapitalization.none,
                            inputFormatters: widget.emailEditMode
                                ? <TextInputFormatter>[
                                    TextInputFormatter.withFunction(
                                      (oldValue, newValue) {
                                        return RegExp(r'^[A-Za-z0-9.]*$')
                                                .hasMatch(newValue.text)
                                            ? newValue
                                            : oldValue;
                                      },
                                    ),
                                  ]
                                : null,
                            cursorColor: _terminalPrompt,
                            cursorWidth: 2,
                            style: const TextStyle(
                              color: _terminalText,
                              fontFamily: 'monospace',
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onEditingComplete: () {},
                            onSubmitted: (_) => widget.onSubmitted(),
                          ),
                        ),
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: widget.reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 145),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0.06, 0),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                            ),
                          ),
                          child: ScaleTransition(
                            scale: Tween<double>(begin: 0.96, end: 1).animate(
                              CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutCubic,
                              ),
                            ),
                            child: SizeTransition(
                              sizeFactor: animation,
                              axis: Axis.horizontal,
                              child: child,
                            ),
                          ),
                        ),
                      ),
                      child: widget.emailEditMode
                          ? const SizedBox(
                              key: ValueKey<String>('gmail-suffix'),
                              width: 82,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  EmailConfig.gmailSuffix,
                                  maxLines: 1,
                                  softWrap: false,
                                  style: TextStyle(
                                    color: _terminalMuted,
                                    fontFamily: 'monospace',
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            )
                          : const SizedBox.shrink(
                              key: ValueKey<String>('gmail-suffix-hidden'),
                            ),
                    ),
                    AnimatedSwitcher(
                      duration: widget.reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 140),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SizeTransition(
                          sizeFactor: animation,
                          axis: Axis.horizontal,
                          child: child,
                        ),
                      ),
                      child: widget.busy
                          ? SizedBox(
                              key: const ValueKey<String>('running'),
                              width: 92,
                              child: Text(
                                widget.runningCommand.isEmpty
                                    ? 'RUNNING'
                                    : widget.runningCommand.toUpperCase(),
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                                style: const TextStyle(
                                  color: _terminalWarning,
                                  fontFamily: 'monospace',
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            )
                          : showActionLabel
                              ? SizedBox(
                                  key: ValueKey<String>(
                                    widget.inputAction == TextInputAction.next
                                        ? 'next'
                                        : 'enter',
                                  ),
                                  width: 38,
                                  child: Text(
                                    widget.inputAction == TextInputAction.next
                                        ? 'NEXT'
                                        : 'ENTER',
                                    maxLines: 1,
                                    softWrap: false,
                                    textAlign: TextAlign.end,
                                    style: const TextStyle(
                                      color: _terminalMuted,
                                      fontFamily: 'monospace',
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(
                                  key: ValueKey<String>('action-label-hidden'),
                                ),
                    ),
                  ],
                ),
              );
            },
          ),
          AnimatedSwitcher(
            duration: widget.reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 150),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: showActions
                ? Padding(
                    key: ValueKey<String>(
                      'actions-${widget.canBack}-${widget.canCancel}-${widget.canModes}',
                    ),
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (widget.canModes)
                          _TerminalPromptAction(
                            label: widget.modesLabel,
                            onPressed: widget.busy ? null : widget.onModes,
                          ),
                        if (widget.canBack)
                          _TerminalPromptAction(
                            label: 'BACK',
                            onPressed: widget.busy ? null : widget.onBack,
                          ),
                        if (widget.canCancel)
                          _TerminalPromptAction(
                            label: 'CANCEL',
                            onPressed: widget.busy ? null : widget.onCancel,
                          ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(
                    key: ValueKey<String>('actions-none'),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TerminalPromptAction extends StatelessWidget {
  const _TerminalPromptAction({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          opacity: onPressed == null ? .35 : 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(
              label,
              style: const TextStyle(
                color: _terminalMuted,
                fontFamily: 'monospace',
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _LauncherActivityTone {
  waiting,
  running,
  success,
  warning,
}

class _LauncherActivitySnapshot {
  const _LauncherActivitySnapshot({
    required this.title,
    required this.message,
    required this.stateLabel,
    required this.tone,
  });

  final String title;
  final String message;
  final String stateLabel;
  final _LauncherActivityTone tone;

  bool get animated =>
      tone == _LauncherActivityTone.waiting ||
      tone == _LauncherActivityTone.running;

  String get signature => '$title|$message|$stateLabel|${tone.name}';

  static _LauncherActivitySnapshot resolve({
    required ModeLauncherController controller,
    required _LauncherDialogPhase dialogPhase,
    required bool presentationReady,
    required bool closing,
    required bool exiting,
  }) {
    final dialogVisible = dialogPhase == _LauncherDialogPhase.visible;
    final dialogOpening = dialogPhase == _LauncherDialogPhase.preparing ||
        dialogPhase == _LauncherDialogPhase.opening;
    if (exiting) {
      return const _LauncherActivitySnapshot(
        title: 'SYSTEM POWER',
        message: '애플리케이션 종료 절차를 진행하고 있습니다.',
        stateLabel: 'EXITING',
        tone: _LauncherActivityTone.running,
      );
    }
    if (closing) {
      return const _LauncherActivitySnapshot(
        title: 'TERMINAL SESSION',
        message: '런처 세션을 종료하고 다음 화면을 준비하고 있습니다.',
        stateLabel: 'CLOSING',
        tone: _LauncherActivityTone.running,
      );
    }
    if (dialogPhase == _LauncherDialogPhase.closing) {
      return const _LauncherActivitySnapshot(
        title: 'TERMINAL INTERACTION',
        message: '작업 창을 닫고 다음 시스템 상태로 전환하고 있습니다.',
        stateLabel: 'CLOSING',
        tone: _LauncherActivityTone.running,
      );
    }
    if (controller.busy) {
      return switch (controller.runningCommand.toUpperCase()) {
        'STARTUP' => const _LauncherActivitySnapshot(
            title: 'SYSTEM SERVICES',
            message: '실행에 필요한 시스템 서비스를 준비하고 있습니다.',
            stateLabel: 'INITIALIZING',
            tone: _LauncherActivityTone.running,
          ),
        'SESSION_CHECK' => const _LauncherActivitySnapshot(
            title: 'ACCOUNT SESSION',
            message: '저장된 로그인 정보를 확인하고 있습니다.',
            stateLabel: 'CHECKING',
            tone: _LauncherActivityTone.running,
          ),
        'SESSION_RESTORE' => const _LauncherActivitySnapshot(
            title: 'ACCOUNT SESSION',
            message: '기존 로그인 세션을 복원하고 있습니다.',
            stateLabel: 'RESTORING',
            tone: _LauncherActivityTone.running,
          ),
        'SESSION' => const _LauncherActivitySnapshot(
            title: 'ACCOUNT SESSION',
            message: '기존 로그인 세션을 확인하고 있습니다.',
            stateLabel: 'RESTORING',
            tone: _LauncherActivityTone.running,
          ),
        'ACCOUNT' => const _LauncherActivitySnapshot(
            title: 'ACCOUNT PROFILE',
            message: '사용 목적에 맞는 계정 프로필을 구성하고 있습니다.',
            stateLabel: 'PREPARING',
            tone: _LauncherActivityTone.running,
          ),
        'AUTH' => const _LauncherActivitySnapshot(
            title: 'ACCOUNT AUTHENTICATION',
            message: '계정 정보를 확인하고 있습니다.',
            stateLabel: 'VERIFYING',
            tone: _LauncherActivityTone.running,
          ),
        'AREAS' => const _LauncherActivitySnapshot(
            title: 'WORK AREA',
            message: '사용 가능한 업무 지역 정보를 불러오고 있습니다.',
            stateLabel: 'LOADING',
            tone: _LauncherActivityTone.running,
          ),
        'AREA' => const _LauncherActivitySnapshot(
            title: 'WORK AREA',
            message: '선택한 업무 지역을 검증하고 있습니다.',
            stateLabel: 'VERIFYING',
            tone: _LauncherActivityTone.running,
          ),
        'MODE' => const _LauncherActivitySnapshot(
            title: 'WORK MODE',
            message: '선택한 업무 모드를 활성화하고 있습니다.',
            stateLabel: 'CONFIGURING',
            tone: _LauncherActivityTone.running,
          ),
        'HEADQUARTER' => const _LauncherActivitySnapshot(
            title: 'HEADQUARTER',
            message: '본사 실행 환경을 구성하고 있습니다.',
            stateLabel: 'CONFIGURING',
            tone: _LauncherActivityTone.running,
          ),
        _ => _LauncherActivitySnapshot(
            title: controller.runningCommand.isEmpty
                ? 'SYSTEM TASK'
                : controller.runningCommand.toUpperCase(),
            message: '시스템 작업을 처리하고 있습니다.',
            stateLabel: 'RUNNING',
            tone: _LauncherActivityTone.running,
          ),
      };
    }
    if (controller.runtimeContextReady) {
      if (!presentationReady) {
        return const _LauncherActivitySnapshot(
          title: 'SYSTEM FINALIZATION',
          message: '마지막 시스템 출력을 정리하고 있습니다.',
          stateLabel: 'FINALIZING',
          tone: _LauncherActivityTone.running,
        );
      }
      return const _LauncherActivitySnapshot(
        title: 'SYSTEM READY',
        message: '실행 환경 구성이 완료되었습니다.',
        stateLabel: 'READY',
        tone: _LauncherActivityTone.success,
      );
    }
    return switch (controller.loginStage) {
      TerminalLoginStage.accountTypeSelection => _LauncherActivitySnapshot(
          title: 'ACCOUNT TYPE',
          message: dialogVisible
              ? '계정 유형 선택을 기다리고 있습니다.'
              : '계정 유형 선택 화면을 준비하고 있습니다.',
          stateLabel: dialogVisible
              ? 'WAITING'
              : dialogOpening
                  ? 'OPENING'
                  : 'PREPARING',
          tone: dialogVisible
              ? _LauncherActivityTone.waiting
              : _LauncherActivityTone.running,
        ),
      TerminalLoginStage.credentials => _LauncherActivitySnapshot(
          title: 'ACCOUNT AUTHENTICATION',
          message: dialogVisible
              ? '계정 정보 입력을 기다리고 있습니다.'
              : '계정 인증 화면을 준비하고 있습니다.',
          stateLabel: dialogVisible
              ? 'WAITING'
              : dialogOpening
                  ? 'OPENING'
                  : 'PREPARING',
          tone: dialogVisible
              ? _LauncherActivityTone.waiting
              : _LauncherActivityTone.running,
        ),
      TerminalLoginStage.authenticating => const _LauncherActivitySnapshot(
          title: 'ACCOUNT AUTHENTICATION',
          message: '계정 정보를 확인하고 있습니다.',
          stateLabel: 'VERIFYING',
          tone: _LauncherActivityTone.running,
        ),
      TerminalLoginStage.areaSelection => _LauncherActivitySnapshot(
          title: 'WORK AREA',
          message: dialogVisible
              ? '업무 지역 선택을 기다리고 있습니다.'
              : '업무 지역 선택 화면을 준비하고 있습니다.',
          stateLabel: dialogVisible
              ? 'WAITING'
              : dialogOpening
                  ? 'OPENING'
                  : 'PREPARING',
          tone: dialogVisible
              ? _LauncherActivityTone.waiting
              : _LauncherActivityTone.running,
        ),
      TerminalLoginStage.modeSelection => _LauncherActivitySnapshot(
          title: 'WORK MODE',
          message: dialogVisible
              ? '업무 모드 선택을 기다리고 있습니다.'
              : '업무 모드 선택 화면을 준비하고 있습니다.',
          stateLabel: dialogVisible
              ? 'WAITING'
              : dialogOpening
                  ? 'OPENING'
                  : 'PREPARING',
          tone: dialogVisible
              ? _LauncherActivityTone.waiting
              : _LauncherActivityTone.running,
        ),
      TerminalLoginStage.activatingMode => const _LauncherActivitySnapshot(
          title: 'WORK MODE',
          message: '실행 모드를 적용하고 있습니다.',
          stateLabel: 'CONFIGURING',
          tone: _LauncherActivityTone.running,
        ),
      TerminalLoginStage.command => const _LauncherActivitySnapshot(
          title: 'TERMINAL READY',
          message: '런처 세션이 준비되었습니다.',
          stateLabel: 'IDLE',
          tone: _LauncherActivityTone.success,
        ),
    };
  }
}

class _LauncherActivityPanel extends StatefulWidget {
  const _LauncherActivityPanel({
    required this.controller,
    required this.dialogPhase,
    required this.presentationReady,
    required this.closing,
    required this.exiting,
    required this.reduceMotion,
    required this.onSignatureChanged,
  });

  final ModeLauncherController controller;
  final _LauncherDialogPhase dialogPhase;
  final bool presentationReady;
  final bool closing;
  final bool exiting;
  final bool reduceMotion;
  final ValueChanged<String> onSignatureChanged;

  @override
  State<_LauncherActivityPanel> createState() => _LauncherActivityPanelState();
}

class _LauncherActivityPanelState extends State<_LauncherActivityPanel>
    with TickerProviderStateMixin {
  late final AnimationController _scanController;
  late final AnimationController _pulseController;
  String _lastSignature = '';

  @override
  void initState() {
    super.initState();
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1350),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _syncAnimationState();
  }

  @override
  void didUpdateWidget(covariant _LauncherActivityPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reduceMotion != widget.reduceMotion ||
        oldWidget.controller.busy != widget.controller.busy ||
        oldWidget.dialogPhase != widget.dialogPhase) {
      _syncAnimationState();
    }
  }

  void _syncAnimationState() {
    if (widget.reduceMotion) {
      _scanController.stop();
      _scanController.value = .62;
      _pulseController.stop();
      _pulseController.value = .45;
      return;
    }
    if (!_scanController.isAnimating) {
      _scanController.repeat();
    }
    if (!_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    }
  }

  Color _toneColor(_LauncherActivityTone tone) {
    return switch (tone) {
      _LauncherActivityTone.waiting => _terminalWarning,
      _LauncherActivityTone.running => _terminalPrompt,
      _LauncherActivityTone.success => _terminalSuccess,
      _LauncherActivityTone.warning => _terminalError,
    };
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _LauncherActivitySnapshot.resolve(
      controller: widget.controller,
      dialogPhase: widget.dialogPhase,
      presentationReady: widget.presentationReady,
      closing: widget.closing,
      exiting: widget.exiting,
    );
    if (snapshot.signature != _lastSignature) {
      _lastSignature = snapshot.signature;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onSignatureChanged(snapshot.signature);
      });
    }
    final toneColor = _toneColor(snapshot.tone);
    return Semantics(
      liveRegion: true,
      label: '${snapshot.title}, ${snapshot.message}, ${snapshot.stateLabel}',
      child: Container(
        constraints: const BoxConstraints(minHeight: 76),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 9),
        color: _terminalHeader.withOpacity(.52),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    final pulse = snapshot.animated
                        ? .92 + (_pulseController.value * .12)
                        : 1.0;
                    return Transform.scale(
                      scale: pulse,
                      child: Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: toneColor.withOpacity(.08),
                          border: Border.all(
                            color: toneColor.withOpacity(.78),
                          ),
                        ),
                        child: AnimatedSwitcher(
                          duration: widget.reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                          child: snapshot.tone == _LauncherActivityTone.success
                              ? Icon(
                                  Icons.check_rounded,
                                  key: const ValueKey<String>('ready'),
                                  size: 16,
                                  color: toneColor,
                                )
                              : Container(
                                  key: ValueKey<String>(snapshot.stateLabel),
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: toneColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: widget.reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 210),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(.025, 0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: Column(
                      key: ValueKey<String>(snapshot.signature),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          snapshot.title,
                          style: TextStyle(
                            color: toneColor,
                            fontFamily: 'monospace',
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .55,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          snapshot.message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _terminalMuted,
                            fontFamily: 'monospace',
                            fontSize: 10.5,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                AnimatedContainer(
                  duration: widget.reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: toneColor.withOpacity(.08),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: toneColor.withOpacity(.48)),
                  ),
                  child: Text(
                    snapshot.stateLabel,
                    style: TextStyle(
                      color: toneColor,
                      fontFamily: 'monospace',
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .45,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: SizedBox(
                height: 3,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _terminalBorder.withOpacity(.5),
                  ),
                  child: snapshot.tone == _LauncherActivityTone.success
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: 1,
                            child: ColoredBox(color: toneColor),
                          ),
                        )
                      : AnimatedBuilder(
                          animation: _scanController,
                          builder: (context, child) {
                            final x = (_scanController.value * 2.4) - 1.2;
                            return Align(
                              alignment: Alignment(x, 0),
                              child: FractionallySizedBox(
                                widthFactor: .28,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: <Color>[
                                        toneColor.withOpacity(0),
                                        toneColor,
                                        toneColor.withOpacity(0),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scanController.dispose();
    _pulseController.dispose();
    super.dispose();
  }
}

class _MiniTerminalFrame extends StatefulWidget {
  const _MiniTerminalFrame({
    super.key,
    required this.title,
    required this.reduceMotion,
    required this.onStatus,
    required this.onOpenCompleted,
    required this.child,
  });

  final String title;
  final bool reduceMotion;
  final VoidCallback onStatus;
  final VoidCallback onOpenCompleted;
  final Widget child;

  @override
  State<_MiniTerminalFrame> createState() => _MiniTerminalFrameState();
}

class _MiniTerminalFrameState extends State<_MiniTerminalFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _openReported = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.reduceMotion ? Duration.zero : _miniTerminalOpenDuration,
      reverseDuration:
          widget.reduceMotion ? Duration.zero : _miniTerminalCloseDuration,
    );
    _controller.addStatusListener(_handleStatus);
    ParkinWorkinTerminalDiagnostics.record(
      'mini_terminal_open_started',
      context: 'launcher',
      meta: <String, Object?>{
        'title': widget.title,
        'durationMs': widget.reduceMotion
            ? 0
            : _miniTerminalOpenDuration.inMilliseconds,
        'reduceMotion': widget.reduceMotion,
      },
    );
    if (widget.reduceMotion) {
      _controller.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) => _reportOpen());
    } else {
      _controller.forward();
    }
  }

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _reportOpen();
    }
  }

  void _reportOpen() {
    if (_openReported || !mounted) return;
    setState(() => _openReported = true);
    ParkinWorkinTerminalDiagnostics.record(
      'mini_terminal_open_completed',
      context: 'launcher',
      meta: <String, Object?>{
        'title': widget.title,
        'durationMs': widget.reduceMotion
            ? 0
            : _miniTerminalOpenDuration.inMilliseconds,
      },
    );
    widget.onOpenCompleted();
  }

  Future<void> close() async {
    if (_closing || !mounted) return;
    setState(() => _closing = true);
    ParkinWorkinTerminalDiagnostics.record(
      'mini_terminal_close_started',
      context: 'launcher',
      meta: <String, Object?>{
        'title': widget.title,
        'durationMs': widget.reduceMotion
            ? 0
            : _miniTerminalCloseDuration.inMilliseconds,
        'controllerValue': _controller.value.toStringAsFixed(3),
        'reduceMotion': widget.reduceMotion,
      },
    );
    if (widget.reduceMotion) {
      _controller.value = 0;
    } else if (_controller.status != AnimationStatus.dismissed) {
      await _controller.reverse();
    }
    if (!mounted) return;
    ParkinWorkinTerminalDiagnostics.record(
      'mini_terminal_close_completed',
      context: 'launcher',
      meta: <String, Object?>{
        'title': widget.title,
        'durationMs': widget.reduceMotion
            ? 0
            : _miniTerminalCloseDuration.inMilliseconds,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxWidth = math.max(
      0.0,
      math.min(MediaQuery.sizeOf(context).width - 24, 520.0),
    ).toDouble();
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final value = widget.reduceMotion ? 1.0 : _controller.value;
        final horizontal = Curves.easeOutCubic.transform(
          (value / .38).clamp(0.0, 1.0).toDouble(),
        );
        final vertical = Curves.easeOutCubic.transform(
          ((value - .22) / .50).clamp(0.0, 1.0).toDouble(),
        );
        final headerOpacity = Curves.easeOutCubic.transform(
          ((value - .50) / .26).clamp(0.0, 1.0).toDouble(),
        );
        final contentOpacity = Curves.easeOutCubic.transform(
          ((value - .58) / .42).clamp(0.0, 1.0).toDouble(),
        );
        final contentOffset = 8.0 * (1 - contentOpacity);
        final beamOpacity = value < .58
            ? (1 - ((value - .28) / .30).clamp(0.0, 1.0)).toDouble()
            : 0.0;
        final interactive = !_closing && _openReported;
        return Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: beamOpacity,
              child: Container(
                width: maxWidth * horizontal,
                height: 2,
                color: _terminalPrompt,
              ),
            ),
            IgnorePointer(
              ignoring: !interactive,
              child: Transform.scale(
                scaleX: math.max(.015, horizontal).toDouble(),
                scaleY: math.max(.006, vertical).toDouble(),
                alignment: Alignment.center,
                child: Container(
                  width: maxWidth,
                  decoration: BoxDecoration(
                    color: _terminalBackground,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _terminalBorder),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x99000000),
                        blurRadius: 30,
                        offset: Offset(0, 16),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Opacity(
                          opacity: headerOpacity,
                          child: Container(
                            height: 40,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            color: _terminalHeader,
                            child: Row(
                              children: [
                                const Text(
                                  '>_',
                                  style: TextStyle(
                                    color: _terminalPrompt,
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    widget.title,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: _terminalText,
                                      fontFamily: 'monospace',
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: .55,
                                    ),
                                  ),
                                ),
                                ValueListenableBuilder<bool>(
                                  valueListenable: DevAuth.devModeEnabled,
                                  builder: (context, enabled, _) {
                                    if (!enabled) {
                                      return const SizedBox.shrink();
                                    }
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: TextButton(
                                        onPressed: widget.onStatus,
                                        style: TextButton.styleFrom(
                                          minimumSize: const Size(0, 28),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                          ),
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: const Text(
                                          'STATUS',
                                          style: TextStyle(
                                            color: _terminalMuted,
                                            fontFamily: 'monospace',
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(
                                  width: 7,
                                  height: 7,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: _terminalPrompt,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Opacity(
                          opacity: headerOpacity,
                          child: const Divider(
                            height: 1,
                            thickness: 1,
                            color: _terminalBorder,
                          ),
                        ),
                        Transform.translate(
                          offset: Offset(0, contentOffset),
                          child: Opacity(
                            opacity: contentOpacity,
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 16, 16, 14),
                              child: widget.child,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_handleStatus);
    _controller.dispose();
    super.dispose();
  }
}

class _LauncherAccountDialog extends StatefulWidget {
  const _LauncherAccountDialog({
    required this.accountKind,
    required this.initialName,
    required this.initialPhone,
    required this.reduceMotion,
    required this.onStatus,
    required this.onOpened,
    required this.onClosing,
    required this.onAuthenticate,
  });

  final String accountKind;
  final String initialName;
  final String initialPhone;
  final bool reduceMotion;
  final VoidCallback onStatus;
  final VoidCallback onOpened;
  final VoidCallback onClosing;
  final Future<LauncherCredentialSubmitResult> Function(
    String name,
    String phone,
    String password,
  ) onAuthenticate;

  @override
  State<_LauncherAccountDialog> createState() => _LauncherAccountDialogState();
}

class _LauncherAccountDialogState extends State<_LauncherAccountDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _passwordController;
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _phoneFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final GlobalKey<_MiniTerminalFrameState> _frameKey =
      GlobalKey<_MiniTerminalFrameState>();
  bool _busy = false;
  String? _nameError;
  String? _phoneError;
  String? _passwordError;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _phoneController = TextEditingController(text: widget.initialPhone);
    _passwordController = TextEditingController();
  }

  void _handleOpened() {
    widget.onOpened();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _busy) return;
      if (_nameController.text.isEmpty) {
        _nameFocus.requestFocus();
      } else if (_phoneController.text.isEmpty) {
        _phoneFocus.requestFocus();
      } else {
        _passwordFocus.requestFocus();
      }
    });
  }

  Future<void> _authenticate() async {
    if (_busy) return;
    final name = _nameController.text.trim();
    final phone = _phoneController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final password = _passwordController.text;
    setState(() {
      _nameError = name.isEmpty ? '입력해 주세요.' : null;
      _phoneError = phone.isEmpty ? '입력해 주세요.' : null;
      _passwordError = password.isEmpty ? '입력해 주세요.' : null;
      _submitError = null;
    });
    if (_nameError != null || _phoneError != null || _passwordError != null) {
      await HapticFeedback.mediumImpact();
      if (_nameError != null) {
        _nameFocus.requestFocus();
      } else if (_phoneError != null) {
        _phoneFocus.requestFocus();
      } else {
        _passwordFocus.requestFocus();
      }
      return;
    }
    setState(() => _busy = true);
    await HapticFeedback.selectionClick();
    final result = await widget.onAuthenticate(name, phone, password);
    if (!mounted) return;
    if (result.accepted) {
      await HapticFeedback.lightImpact();
      FocusManager.instance.primaryFocus?.unfocus();
      widget.onClosing();
      await WidgetsBinding.instance.endOfFrame;
      await _frameKey.currentState?.close();
      if (!mounted) return;
      Navigator.of(context).pop();
      return;
    }
    await HapticFeedback.mediumImpact();
    setState(() {
      _busy = false;
      _nameError = result.nameError;
      _phoneError = result.phoneError;
      _passwordError = result.passwordError;
      _submitError = result.authenticationError;
    });
    if (_nameError != null) {
      _nameFocus.requestFocus();
    } else if (_phoneError != null) {
      _phoneFocus.requestFocus();
    } else if (_passwordError != null) {
      _passwordFocus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: _MiniTerminalFrame(
        key: _frameKey,
        title: 'ACCOUNT AUTHENTICATION',
        reduceMotion: widget.reduceMotion,
        onStatus: widget.onStatus,
        onOpenCompleted: _handleOpened,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.accountKind.isNotEmpty) ...[
              Row(
                children: [
                  const Text(
                    'PROFILE',
                    style: TextStyle(
                      color: _terminalMuted,
                      fontFamily: 'monospace',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.accountKind,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: _terminalPrompt,
                        fontFamily: 'monospace',
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            _TerminalDialogField(
              label: ModeLauncherController.nameDisplayLabel,
              controller: _nameController,
              focusNode: _nameFocus,
              enabled: !_busy,
              errorText: _nameError,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _phoneFocus.requestFocus(),
            ),
            const SizedBox(height: 12),
            _TerminalDialogField(
              label: ModeLauncherController.phoneDisplayLabel,
              controller: _phoneController,
              focusNode: _phoneFocus,
              enabled: !_busy,
              errorText: _phoneError,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              onSubmitted: (_) => _passwordFocus.requestFocus(),
            ),
            const SizedBox(height: 12),
            _TerminalDialogField(
              label: ModeLauncherController.passwordDisplayLabel,
              controller: _passwordController,
              focusNode: _passwordFocus,
              enabled: !_busy,
              errorText: _passwordError,
              obscureText: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _authenticate(),
            ),
            AnimatedSwitcher(
              duration: widget.reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 160),
              child: _submitError == null
                  ? const SizedBox.shrink()
                  : Padding(
                      key: ValueKey<String>(_submitError!),
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _submitError!,
                        style: const TextStyle(
                          color: _terminalError,
                          fontFamily: 'monospace',
                          fontSize: 10.5,
                          height: 1.3,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: _TerminalDialogActionButton(
                label: '인증',
                busy: _busy,
                enabled: !_busy,
                reduceMotion: widget.reduceMotion,
                onPressed: _authenticate,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }
}

class _LauncherSelectionDialog extends StatefulWidget {
  const _LauncherSelectionDialog({
    required this.title,
    required this.description,
    required this.options,
    required this.confirmLabel,
    required this.reduceMotion,
    required this.onStatus,
    required this.onOpened,
    required this.onClosing,
    required this.onConfirm,
  });

  final String title;
  final String description;
  final List<String> options;
  final String confirmLabel;
  final bool reduceMotion;
  final VoidCallback onStatus;
  final VoidCallback onOpened;
  final VoidCallback onClosing;
  final Future<String?> Function(int index) onConfirm;

  @override
  State<_LauncherSelectionDialog> createState() =>
      _LauncherSelectionDialogState();
}

class _LauncherSelectionDialogState extends State<_LauncherSelectionDialog> {
  final GlobalKey<_MiniTerminalFrameState> _frameKey =
      GlobalKey<_MiniTerminalFrameState>();
  int? _selectedIndex;
  bool _busy = false;
  String? _error;

  Future<void> _confirm() async {
    final selected = _selectedIndex;
    if (_busy || selected == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    await HapticFeedback.selectionClick();
    final error = await widget.onConfirm(selected);
    if (!mounted) return;
    if (error == null) {
      await HapticFeedback.lightImpact();
      FocusManager.instance.primaryFocus?.unfocus();
      widget.onClosing();
      await WidgetsBinding.instance.endOfFrame;
      await _frameKey.currentState?.close();
      if (!mounted) return;
      Navigator.of(context).pop();
      return;
    }
    await HapticFeedback.mediumImpact();
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: _MiniTerminalFrame(
        key: _frameKey,
        title: widget.title,
        reduceMotion: widget.reduceMotion,
        onStatus: widget.onStatus,
        onOpenCompleted: widget.onOpened,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.description,
              style: const TextStyle(
                color: _terminalText,
                fontFamily: 'monospace',
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < widget.options.length; index++) ...[
              _TerminalSelectionRow(
                index: index,
                label: widget.options[index],
                selected: _selectedIndex == index,
                enabled: !_busy,
                reduceMotion: widget.reduceMotion,
                onPressed: () {
                  setState(() {
                    _selectedIndex = index;
                    _error = null;
                  });
                  HapticFeedback.selectionClick();
                },
              ),
              if (index != widget.options.length - 1)
                const SizedBox(height: 7),
            ],
            AnimatedSwitcher(
              duration: widget.reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 160),
              child: _error == null
                  ? const SizedBox.shrink()
                  : Padding(
                      key: ValueKey<String>(_error!),
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: _terminalError,
                          fontFamily: 'monospace',
                          fontSize: 10.5,
                          height: 1.3,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: _TerminalDialogActionButton(
                label: widget.confirmLabel,
                busy: _busy,
                enabled: !_busy && _selectedIndex != null,
                reduceMotion: widget.reduceMotion,
                onPressed: _confirm,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TerminalDialogField extends StatelessWidget {
  const _TerminalDialogField({
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.errorText,
    required this.textInputAction,
    required this.onSubmitted,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.inputFormatters,
  });

  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final String? errorText;
  final TextInputType keyboardType;
  final bool obscureText;
  final TextInputAction textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: focusNode,
      builder: (context, child) {
        final active = focusNode.hasFocus;
        final borderColor = errorText != null
            ? _terminalError
            : active
                ? _terminalPrompt
                : _terminalBorder;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: active ? _terminalPrompt : _terminalMuted,
                fontFamily: 'monospace',
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: .35,
              ),
            ),
            const SizedBox(height: 6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              constraints: const BoxConstraints(minHeight: 42),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: _terminalHeader.withOpacity(.58),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: borderColor),
              ),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                enabled: enabled,
                keyboardType: keyboardType,
                obscureText: obscureText,
                textInputAction: textInputAction,
                inputFormatters: inputFormatters,
                autocorrect: false,
                enableSuggestions: false,
                cursorColor: _terminalPrompt,
                cursorWidth: 2,
                style: const TextStyle(
                  color: _terminalText,
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 11),
                ),
                onSubmitted: onSubmitted,
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 140),
              child: errorText == null
                  ? const SizedBox.shrink()
                  : Padding(
                      key: ValueKey<String>(errorText!),
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        errorText!,
                        style: const TextStyle(
                          color: _terminalError,
                          fontFamily: 'monospace',
                          fontSize: 9.5,
                        ),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _TerminalSelectionRow extends StatelessWidget {
  const _TerminalSelectionRow({
    required this.index,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.reduceMotion,
    required this.onPressed,
  });

  final int index;
  final String label;
  final bool selected;
  final bool enabled;
  final bool reduceMotion;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(5),
          child: AnimatedContainer(
            duration:
                reduceMotion ? Duration.zero : const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: selected
                  ? _terminalPrompt.withOpacity(.08)
                  : _terminalHeader.withOpacity(.42),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: selected ? _terminalPrompt : _terminalBorder,
              ),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 150),
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? _terminalPrompt : _terminalMuted,
                    ),
                  ),
                  child: AnimatedScale(
                    scale: selected ? 1 : 0,
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 150),
                    curve: Curves.easeOutBack,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: _terminalPrompt,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${index + 1}'.padLeft(2, '0'),
                  style: const TextStyle(
                    color: _terminalPath,
                    fontFamily: 'monospace',
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected ? _terminalText : _terminalMuted,
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TerminalDialogActionButton extends StatelessWidget {
  const _TerminalDialogActionButton({
    required this.label,
    required this.busy,
    required this.enabled,
    required this.reduceMotion,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final bool enabled;
  final bool reduceMotion;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 140),
      opacity: enabled || busy ? 1 : .42,
      child: SizedBox(
        height: 40,
        child: OutlinedButton(
          onPressed: enabled ? onPressed : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: _terminalPrompt,
            side: BorderSide(
              color: enabled ? _terminalPrompt : _terminalBorder,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          child: AnimatedSwitcher(
            duration:
                reduceMotion ? Duration.zero : const Duration(milliseconds: 150),
            child: busy
                ? const SizedBox(
                    key: ValueKey<String>('busy'),
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: _terminalPrompt,
                    ),
                  )
                : Text(
                    label,
                    key: ValueKey<String>(label),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .4,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
