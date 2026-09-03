import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../features/launcher/application/mode_launcher_controller.dart';
import '../../auth/gmail_sender_auth.dart';
import '../../config/email_config.dart';
import '../../../features/selector/application/dev_auth.dart';
import '../../../features/dev/presentation/debug_caution_surface.dart';
import '../../command/application/app_command_registry.dart';
import '../../command/application/terminal_line.dart';
import '../../command/application/terminal_session_controller.dart';
import '../../init/startup_tasks.dart';
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

enum ParkinWorkinTerminalContext {
  launcher,
  workspace,
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
  bool _launcherAutoSubmitInFlight = false;
  bool _launcherAutoInputVisible = true;
  String? _queuedLauncherAutoSubmit;
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

  bool get _canBack =>
      _isLauncher && _launcherController!.canNavigateBack;

  bool get _canCancel =>
      _isLauncher && _launcherController!.canCancelAuthentication;

  bool get _canModes =>
      _isLauncher && _launcherController!.canReturnToModes;

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
      final pendingRoute = _launcherController!.consumePendingTargetRoute();
      if (pendingRoute != null) {
        await _playbackController.waitUntilIdle();
        if (!mounted || _interactionLocked) return;
        await _closeLauncherAndNavigate(pendingRoute);
        return;
      }
      final pendingAutoSubmit =
          _launcherController!.consumePendingAutoSubmitText();
      if (pendingAutoSubmit != null) {
        await _runLauncherAutoSubmit(pendingAutoSubmit);
        if (!mounted || _interactionLocked) return;
      }
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
    _promptFocusNode.requestFocus();
    _scheduleBottomLock(delay: const Duration(milliseconds: 220));
  }

  void _handleSourceChanged() {
    if (!mounted) return;
    _syncPlayback();
    setState(() {});
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
    if (!_promptFocusNode.hasFocus || _interactionLocked) return;
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
    if (_busy || _interactionLocked) return;
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
    if (!mounted || _interactionLocked || !_promptFocusNode.hasFocus) return;
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

  Future<void> _runLauncherAutoSubmit(String raw) async {
    final value = raw.trim();
    if (!_isLauncher ||
        value.isEmpty ||
        _launcherAutoSubmitInFlight ||
        _interactionLocked) {
      return;
    }
    setState(() {
      _launcherAutoSubmitInFlight = true;
    });
    try {
      await _playbackController.waitUntilIdle();
      if (!mounted || _interactionLocked) return;
      if (!_reduceMotion) {
        await Future<void>.delayed(const Duration(milliseconds: 90));
      }
      if (!mounted || _interactionLocked) return;
      setState(() {
        _launcherAutoInputVisible = false;
      });
      _setPromptText(value);
      if (_reduceMotion) {
        if (mounted) {
          setState(() {
            _launcherAutoInputVisible = true;
          });
        }
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 24));
        if (!mounted || _interactionLocked) return;
        setState(() {
          _launcherAutoInputVisible = true;
        });
      }
      ParkinWorkinTerminalDiagnostics.record(
        'terminal_selection_auto_input_visible',
        context: _contextLabel,
        meta: <String, Object?>{
          'input': value,
          'stage': _launcherController!.loginStage.name,
          'reduceMotion': _reduceMotion,
          'path': _promptPath,
        },
      );
      if (!_reduceMotion) {
        await Future<void>.delayed(const Duration(milliseconds: 170));
      }
      if (!mounted || _interactionLocked) return;
      final autoStage = _launcherController!.loginStage;
      if (autoStage != TerminalLoginStage.areaSelection &&
          autoStage != TerminalLoginStage.modeSelection) {
        ParkinWorkinTerminalDiagnostics.record(
          'terminal_selection_auto_submit_cancelled',
          context: _contextLabel,
          meta: <String, Object?>{
            'input': value,
            'stage': _launcherController!.loginStage.name,
          },
        );
        return;
      }
      ParkinWorkinTerminalDiagnostics.record(
        'terminal_selection_auto_submit',
        context: _contextLabel,
        meta: <String, Object?>{
          'input': value,
          'stage': _launcherController!.loginStage.name,
          'haptic': false,
        },
      );
      await _submitLauncherRaw(value, haptic: false);
    } finally {
      if (mounted) {
        setState(() {
          _launcherAutoSubmitInFlight = false;
          _launcherAutoInputVisible = true;
        });
      } else {
        _launcherAutoSubmitInFlight = false;
        _launcherAutoInputVisible = true;
      }
    }
    final queued = _queuedLauncherAutoSubmit;
    _queuedLauncherAutoSubmit = null;
    if (queued != null && mounted && !_interactionLocked) {
      ParkinWorkinTerminalDiagnostics.record(
        'terminal_selection_auto_submit_dequeued',
        context: _contextLabel,
        meta: <String, Object?>{
          'input': queued,
          'stage': _launcherController!.loginStage.name,
        },
      );
      await _runLauncherAutoSubmit(queued);
    }
  }

  Future<void> _submit() async {
    if (_launcherAutoSubmitInFlight) return;
    final raw = _promptController.text;
    if (_isLauncher) {
      await _submitLauncherRaw(raw);
    } else {
      await _submitWorkspaceRaw(raw);
    }
  }

  Future<void> _submitControlCommand(String command) async {
    if (_busy || _interactionLocked || _launcherAutoSubmitInFlight || !_isLauncher) return;
    await HapticFeedback.selectionClick();
    _promptController.clear();
    await _submitLauncherRaw(command, haptic: false);
  }

  Future<void> _submitHeaderCommand(String command) async {
    if (_busy || _interactionLocked || _launcherAutoSubmitInFlight) return;
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

  Future<void> _submitLauncherRaw(
    String raw, {
    bool haptic = true,
  }) async {
    final controller = _launcherController!;
    if (controller.busy || _interactionLocked) return;
    if (raw.trim().isEmpty) {
      await HapticFeedback.mediumImpact();
      controller.rejectEmptyInput();
      if (!_promptFocusNode.hasFocus) _promptFocusNode.requestFocus();
      return;
    }
    if (haptic) await HapticFeedback.selectionClick();
    final stageBefore = controller.loginStage.name;
    final dismissKeyboard = controller.shouldDismissKeyboardForInput(raw);
    ParkinWorkinTerminalDiagnostics.record(
      'terminal_prompt_submit_start',
      context: _contextLabel,
      meta: <String, Object?>{
        'stage': stageBefore,
        'dismissKeyboard': dismissKeyboard,
        'inputLength': raw.length,
        'path': _promptPath,
      },
    );
    _promptController.clear();
    if (dismissKeyboard) {
      _promptFocusNode.unfocus();
      FocusManager.instance.primaryFocus?.unfocus();
    }
    final result = await controller.submit(
      context,
      raw,
      reduceMotion: _reduceMotion,
    );
    if (!mounted) return;
    _syncPlayback();
    ParkinWorkinTerminalDiagnostics.record(
      'terminal_prompt_submit_complete',
      context: _contextLabel,
      meta: <String, Object?>{
        'stageBefore': stageBefore,
        'stageAfter': controller.loginStage.name,
        'dismissKeyboard': dismissKeyboard,
      },
    );
    if (result.promptText != null) {
      _setPromptText(
        result.promptText!,
        selectAll: result.selectPromptText,
      );
    }
    await _handleLauncherResult(result);
    if (result.autoSubmitText != null) {
      if (_launcherAutoSubmitInFlight) {
        _queuedLauncherAutoSubmit = result.autoSubmitText;
        ParkinWorkinTerminalDiagnostics.record(
          'terminal_selection_auto_submit_queued',
          context: _contextLabel,
          meta: <String, Object?>{
            'input': result.autoSubmitText!,
            'stage': controller.loginStage.name,
          },
        );
      } else {
        await _runLauncherAutoSubmit(result.autoSubmitText!);
      }
    }
  }

  Future<void> _handleLauncherResult(ModeLauncherSubmitResult result) async {
    if (result.targetRoute != null) {
      await _playbackController.waitUntilIdle();
      if (!mounted || _interactionLocked) return;
      await _closeLauncherAndNavigate(result.targetRoute!);
      return;
    }
    if (result.routeReplaced) {
      _promptFocusNode.unfocus();
      return;
    }
    if (result.surfaceCompletion != null) {
      _promptFocusNode.unfocus();
      unawaited(_restoreFocusAfterSurface(result.surfaceCompletion!));
      return;
    }
    if (result.keepFocus && !_busy && !_interactionLocked && !_promptFocusNode.hasFocus) {
      _promptFocusNode.requestFocus();
    }
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
    if (mounted && !_busy && !_interactionLocked) _promptFocusNode.requestFocus();
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
      meta: <String, Object?>{'targetRoute': route},
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
    final promptLayoutDescription = promptLayout == null
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
    ].join('\n');
    final description =
        '$baseDescription\n$interactionDescription\n$promptLayoutDescription\n${gmailStatus.developerDescription}';
    await ParkinWorkinTerminalDiagnostics.showStatus(
      context,
      terminalContext: _contextLabel,
      description: description,
    );
    if (mounted && !_busy && !_interactionLocked) _promptFocusNode.requestFocus();
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
            busy: _busy || _interactionLocked,
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
          if (_isLauncher)
            AnimatedSize(
              duration: _reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: _launcherController!.showAuthSummary
                  ? _TerminalAuthSummary(
                      key: const ValueKey<String>('auth-session'),
                      accountKind: _launcherController!.selectedAccountKindLabel,
                      modeName:
                          _launcherController!.selectedMode?.koreanName ?? '',
                      modeId: _launcherController!.selectedMode?.englishName ?? '',
                      name: _launcherController!.enteredName,
                      phone: _launcherController!.enteredPhone,
                      password: _launcherController!.maskedPassword,
                      reduceMotion: _reduceMotion,
                    )
                  : const SizedBox.shrink(),
            ),
          const Divider(height: 1, thickness: 1, color: _terminalBorder),
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
            readOnly: _launcherAutoSubmitInFlight,
            inputVisible: _launcherAutoInputVisible,
            emailEditMode: _emailEditMode,
            canBack: _canBack,
            canCancel: _canCancel,
            canModes: _canModes,
            modesLabel: _isLauncher ? _launcherController!.returnSelectionLabel : 'MODES',
            onBack: () => _submitControlCommand('back'),
            onCancel: () => _submitControlCommand('cancel'),
            onModes: () => _submitControlCommand('modes'),
            onFocusRequested: _requestPromptFocusFromRow,
            onLayoutChanged: _handlePromptLayoutChanged,
            onSubmitted: _submit,
          ),
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
          resizeToAvoidBottomInset: true,
          body: SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                12,
                12,
                12,
                MediaQuery.of(context).viewInsets.bottom > 0 ||
                        _promptFocusNode.hasFocus
                    ? 0
                    : 12,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final keyboardVisible =
                      MediaQuery.of(context).viewInsets.bottom > 0;
                  final alignBottom = keyboardVisible ||
                      _promptFocusNode.hasFocus ||
                      _interactionLocked;
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
    required this.reduceMotion,
    required this.onCloseTerminal,
    required this.onAbout,
    required this.onAppExit,
    required this.onSetting,
    required this.appExiting,
    required this.onStatus,
  });

  final bool busy;
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
          _TerminalHeaderAction(
            semanticLabel: onAppExit != null ? '시작 화면으로 돌아가기' : '터미널 닫기',
            onPressed: busy ? null : onCloseTerminal,
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
                    onPressed: busy ? null : onAppExit,
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
                    onPressed: busy ? null : onAbout,
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
            onPressed: busy ? null : onSetting,
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
                tooltip: widget.semanticLabel,
                icon: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TerminalAuthSummary extends StatelessWidget {
  const _TerminalAuthSummary({
    super.key,
    required this.accountKind,
    required this.modeName,
    required this.modeId,
    required this.name,
    required this.phone,
    required this.password,
    required this.reduceMotion,
  });

  final String accountKind;
  final String modeName;
  final String modeId;
  final String name;
  final String phone;
  final String password;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final rows = <MapEntry<String, String>>[
      if (accountKind.isNotEmpty) MapEntry<String, String>('ACCOUNT', accountKind),
      if (name.isNotEmpty) MapEntry<String, String>('NAME', name),
      if (phone.isNotEmpty) MapEntry<String, String>('PHONE', phone),
      if (password.isNotEmpty) MapEntry<String, String>('PASSWORD', password),
      if (modeName.isNotEmpty && modeId.isNotEmpty)
        MapEntry<String, String>('MODE', '$modeName / $modeId'),
    ];

    return Container(
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
              key: ValueKey<String>('${rows[index].key}-${rows[index].value}'),
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
                      width: 72,
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
                      child: Text(
                        rows[index].value,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _terminalText,
                          fontFamily: 'monospace',
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
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
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 145),
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
          const TextSpan(text: ':', style: TextStyle(color: _terminalMuted)),
          TextSpan(
            text: promptPath,
            style: const TextStyle(
              color: _terminalPath,
              fontWeight: FontWeight.w700,
            ),
          ),
          const TextSpan(text: r'$ ', style: TextStyle(color: _terminalMuted)),
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
