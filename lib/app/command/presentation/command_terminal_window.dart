import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../features/selector/application/dev_auth.dart';
import '../application/app_command_diagnostics.dart';
import '../application/terminal_line.dart';
import '../application/terminal_session_controller.dart';

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

Future<void> showCommandTerminal(
  BuildContext context, {
  String source = 'command_launcher',
}) async {
  if (!context.mounted) return;
  final reduceMotion =
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  final navigator = Navigator.of(context, rootNavigator: true);
  AppCommandDiagnostics.record(
    phase: 'terminal_open',
    input: '',
    normalized: '',
    source: source,
    result: 'started',
  );
  await navigator.push<void>(
    _CommandTerminalRoute(
      source: source,
      reduceMotion: reduceMotion,
    ),
  );
  AppCommandDiagnostics.record(
    phase: 'terminal_close_complete',
    input: '',
    normalized: '',
    source: source,
    result: 'closed',
  );
}

class _CommandTerminalRoute extends PopupRoute<void> {
  _CommandTerminalRoute({
    required this.source,
    required this.reduceMotion,
  });

  final String source;
  final bool reduceMotion;

  @override
  Color? get barrierColor => const Color(0xA6000000);

  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => 'Pelican Terminal';

  @override
  Duration get transitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 230);

  @override
  Duration get reverseTransitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 170);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return _CommandTerminalRoutePage(source: source);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (reduceMotion) return child;
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, .025),
          end: Offset.zero,
        ).animate(curved),
        child: ScaleTransition(
          scale: Tween<double>(begin: .965, end: 1).animate(curved),
          child: child,
        ),
      ),
    );
  }
}

class _CommandTerminalRoutePage extends StatefulWidget {
  const _CommandTerminalRoutePage({required this.source});

  final String source;

  @override
  State<_CommandTerminalRoutePage> createState() =>
      _CommandTerminalRoutePageState();
}

class _CommandTerminalRoutePageState
    extends State<_CommandTerminalRoutePage> {
  late final TerminalSessionController _session;
  final TextEditingController _promptController = TextEditingController();
  late final FocusNode _promptFocusNode;
  final ScrollController _scrollController = ScrollController();
  bool _focusScheduled = false;
  bool _nearBottom = true;
  int _lastLineCount = 0;

  @override
  void initState() {
    super.initState();
    _session = TerminalSessionController(source: widget.source);
    unawaited(DevAuth.isDevModeEnabled());
    _promptFocusNode = FocusNode(onKeyEvent: _handlePromptKeyEvent);
    _scrollController.addListener(_handleScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_focusScheduled) return;
    _focusScheduled = true;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      AppCommandDiagnostics.record(
        phase: 'terminal_open_complete',
        input: '',
        normalized: '',
        source: widget.source,
        result: 'visible',
      );
      await Future<void>.delayed(
        reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 170),
      );
      if (mounted) {
        _promptFocusNode.requestFocus();
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
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (!_session.busy) {
        _close();
      }
      return KeyEventResult.handled;
    }
    if (_session.busy) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      final value = _session.previousCommand();
      if (value != null) {
        _setPromptText(value);
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      final value = _session.nextCommand();
      if (value != null) {
        _setPromptText(value);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _setPromptText(String value) {
    _promptController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  Future<void> _submit() async {
    if (_session.busy) return;
    final raw = _promptController.text;
    if (raw.trim().isEmpty) {
      HapticFeedback.mediumImpact();
      _session.rejectEmptyInput();
      _promptFocusNode.requestFocus();
      return;
    }

    HapticFeedback.selectionClick();
    _promptController.clear();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final future = _session.submit(
      context,
      raw,
      reduceMotion: reduceMotion,
    );
    final result = await future;
    if (!mounted) return;
    if (result?.succeeded == true) {
      HapticFeedback.lightImpact();
    } else if (result != null) {
      HapticFeedback.mediumImpact();
    }
    if (result?.definition?.launchesSurface != true) {
      _promptFocusNode.requestFocus();
    } else {
      _promptFocusNode.unfocus();
      final surfaceCompletion = result?.surfaceCompletion;
      if (surfaceCompletion != null) {
        unawaited(_restoreFocusAfterSurface(surfaceCompletion));
      }
    }
  }

  Future<void> _restoreFocusAfterSurface(Future<void> completion) async {
    await completion;
    if (!mounted || _session.busy) return;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (mounted) {
      _promptFocusNode.requestFocus();
    }
  }

  Future<void> _showStatus() async {
    AppCommandDiagnostics.record(
      phase: 'status_open',
      input: '',
      normalized: '',
      source: widget.source,
      result: 'requested',
    );
    await AppCommandDiagnostics.showStatus(
      context,
      title: 'Command Status',
      description: 'Terminal session 및 Command 실행 로그입니다.',
    );
  }

  void _close() {
    if (_session.busy) return;
    AppCommandDiagnostics.record(
      phase: 'terminal_close',
      input: '',
      normalized: '',
      source: widget.source,
      result: 'requested',
    );
    _promptFocusNode.unfocus();
    Navigator.of(context, rootNavigator: true).pop();
  }

  void _scheduleAutoScroll(int lineCount, bool reduceMotion) {
    if (lineCount == _lastLineCount) return;
    _lastLineCount = lineCount;
    final shouldScroll = _nearBottom;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !shouldScroll || !_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (reduceMotion) {
        _scrollController.jumpTo(target);
      } else {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _promptFocusNode.dispose();
    _promptController.dispose();
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final reduceMotion = media.disableAnimations;
    final size = media.size;
    final keyboardInset = media.viewInsets.bottom;
    final availableHeight = math.max(
      280.0,
      size.height - keyboardInset - media.padding.vertical - 28,
    ).toDouble();
    final compact = size.width < 600;
    final width = compact
        ? size.width * .94
        : math.min(size.width * .76, 820.0).toDouble();
    final desiredHeight = compact ? size.height * .74 : size.height * .66;
    final height = math.min(desiredHeight, availableHeight).toDouble();

    return AnimatedBuilder(
      animation: _session,
      builder: (context, _) {
        _scheduleAutoScroll(_session.lines.length, reduceMotion);
        return PopScope(
          canPop: !_session.busy,
          child: Material(
            color: Colors.transparent,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _session.busy ? null : _close,
                  ),
                ),
                SafeArea(
                  child: Center(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {},
                      onLongPress: _showStatus,
                      child: SizedBox(
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
                            child: Column(
                              children: [
                                _TerminalHeader(
                                  busy: _session.busy,
                                  onClose: _close,
                                  onStatus: _showStatus,
                                  reduceMotion: reduceMotion,
                                ),
                                const Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: _terminalBorder,
                                ),
                                Expanded(
                                  child: _TerminalHistory(
                                    lines: _session.lines,
                                    scrollController: _scrollController,
                                    reduceMotion: reduceMotion,
                                  ),
                                ),
                                const Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: _terminalBorder,
                                ),
                                _TerminalPrompt(
                                  controller: _promptController,
                                  focusNode: _promptFocusNode,
                                  busy: _session.busy,
                                  runningCommand: _session.runningCommand,
                                  errorSerial: _session.errorSerial,
                                  reduceMotion: reduceMotion,
                                  onSubmitted: _submit,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TerminalHeader extends StatelessWidget {
  const _TerminalHeader({
    required this.busy,
    required this.onClose,
    required this.onStatus,
    required this.reduceMotion,
  });

  final bool busy;
  final VoidCallback onClose;
  final VoidCallback onStatus;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
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
          const Text(
            'PELICAN TERMINAL',
            style: TextStyle(
              color: _terminalText,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: .7,
            ),
          ),
          const Spacer(),
          ValueListenableBuilder<bool>(
            valueListenable: DevAuth.devModeEnabled,
            builder: (context, enabled, _) {
              return AnimatedSwitcher(
                duration:
                    reduceMotion ? Duration.zero : const Duration(milliseconds: 160),
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
                child: enabled
                    ? Row(
                        key: const ValueKey<String>('developer'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0x332ECC71),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: _terminalSuccess,
                              ),
                            ),
                            child: const Text(
                              'DEV',
                              style: TextStyle(
                                color: _terminalSuccess,
                                fontFamily: 'monospace',
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          TextButton(
                            onPressed: onStatus,
                            style: TextButton.styleFrom(
                              minimumSize: const Size(0, 30),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
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
                      )
                    : const SizedBox(
                        key: ValueKey<String>('standard'),
                      ),
              );
            },
          ),
          const SizedBox(width: 4),
          Semantics(
            button: true,
            enabled: !busy,
            label: 'Terminal 닫기',
            child: IconButton(
              onPressed: busy ? null : onClose,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(
                width: 32,
                height: 32,
              ),
              icon: Icon(
                Icons.close_rounded,
                size: 18,
                color: busy ? _terminalBorder : _terminalMuted,
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
        ? _PromptCommandLine(command: line.text)
        : line.type == TerminalLineType.running
            ? _RunningTerminalText(text: line.text)
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
          reduceMotion ? Duration.zero : const Duration(milliseconds: 135),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 3),
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

class _PromptCommandLine extends StatelessWidget {
  const _PromptCommandLine({required this.command});

  final String command;

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
            text: 'pelican@workspace',
            style: TextStyle(
              color: _terminalPrompt,
              fontWeight: FontWeight.w700,
            ),
          ),
          const TextSpan(text: ':', style: TextStyle(color: _terminalMuted)),
          const TextSpan(
            text: '~',
            style: TextStyle(
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

class _RunningTerminalText extends StatefulWidget {
  const _RunningTerminalText({required this.text});

  final String text;

  @override
  State<_RunningTerminalText> createState() => _RunningTerminalTextState();
}

class _RunningTerminalTextState extends State<_RunningTerminalText> {
  Timer? _timer;
  int _dots = 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _timer?.cancel();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return;
    _timer = Timer.periodic(const Duration(milliseconds: 360), (_) {
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
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final base = widget.text.replaceFirst(RegExp(r'\.+$'), '');
    final suffix = reduceMotion ? '...' : List<String>.filled(_dots, '.').join();
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

class _TerminalPrompt extends StatefulWidget {
  const _TerminalPrompt({
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.runningCommand,
    required this.errorSerial,
    required this.reduceMotion,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final String runningCommand;
  final int errorSerial;
  final bool reduceMotion;
  final VoidCallback onSubmitted;

  @override
  State<_TerminalPrompt> createState() => _TerminalPromptState();
}

class _TerminalPromptState extends State<_TerminalPrompt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shakeController;
  late final Animation<double> _shake;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
    );
    _shake = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0, end: -2), weight: 1),
      TweenSequenceItem(tween: Tween<double>(begin: -2, end: 2), weight: 2),
      TweenSequenceItem(tween: Tween<double>(begin: 2, end: 0), weight: 1),
    ]).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(covariant _TerminalPrompt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.errorSerial != oldWidget.errorSerial && !widget.reduceMotion) {
      _shakeController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(widget.reduceMotion ? 0 : _shake.value, 0),
          child: child,
        );
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
        color: _terminalHeader,
        child: Row(
          children: [
            const Text(
              'pelican@workspace',
              style: TextStyle(
                color: _terminalPrompt,
                fontFamily: 'monospace',
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Text(
              ':',
              style: TextStyle(
                color: _terminalMuted,
                fontFamily: 'monospace',
                fontSize: 12.5,
              ),
            ),
            const Text(
              '~',
              style: TextStyle(
                color: _terminalPath,
                fontFamily: 'monospace',
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
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
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                enabled: !widget.busy,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.none,
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
                onSubmitted: (_) => widget.onSubmitted(),
              ),
            ),
            AnimatedSwitcher(
              duration: widget.reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 140),
              child: widget.busy
                  ? Text(
                      widget.runningCommand.isEmpty
                          ? 'RUNNING'
                          : widget.runningCommand.toUpperCase(),
                      key: const ValueKey<String>('running'),
                      style: const TextStyle(
                        color: _terminalWarning,
                        fontFamily: 'monospace',
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                      ),
                    )
                  : const Text(
                      'ENTER',
                      key: ValueKey<String>('enter'),
                      style: TextStyle(
                        color: _terminalMuted,
                        fontFamily: 'monospace',
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
