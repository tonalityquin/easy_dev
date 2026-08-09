import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/common_ui/common_ui_overlays.dart';
import '../../features/selector/application/dev_auth.dart';

enum DeveloperOperationState {
  running,
  success,
  failure,
}

class DeveloperOperationTrace extends ChangeNotifier {
  DeveloperOperationTrace._({
    required this.title,
    required this.developerMode,
    required this.useCommonUi,
  });

  final String title;
  final bool developerMode;
  final bool useCommonUi;

  final List<String> _lines = <String>[];
  Future<void>? _dialogFuture;
  DeveloperOperationState _state = DeveloperOperationState.running;
  String _message = '';
  double _progress = 0;

  DeveloperOperationState get state => _state;
  String get message => _message;
  double get progress => _progress;
  bool get isDone => _state != DeveloperOperationState.running;
  List<String> get lines => List<String>.unmodifiable(_lines);

  String get debugPrintCode {
    return _lines
        .map((line) => 'debugPrint(${jsonEncode(line)});')
        .join('\n');
  }

  static Future<DeveloperOperationTrace> start({
    required BuildContext context,
    required String title,
    required String initialMessage,
    required bool useCommonUi,
    String? developerModeMessage,
    String? standardModeMessage,
  }) async {
    final developerMode = await DevAuth.isDeveloperLoggedIn();
    final trace = DeveloperOperationTrace._(
      title: title,
      developerMode: developerMode,
      useCommonUi: useCommonUi,
    );
    trace.log(initialMessage, progress: 0);
    trace.log(
      developerMode
          ? developerModeMessage ??
              '개발자 모드 ON: 완료 후 앱을 유지합니다.'
          : standardModeMessage ??
              '개발자 모드 OFF: 완료 후 앱을 종료합니다.',
      progress: 0.02,
    );

    if (developerMode && context.mounted) {
      trace._dialogFuture = trace._show(context);
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }

    return trace;
  }

  void log(
    String message, {
    double? progress,
  }) {
    final normalized = message.trim();
    if (normalized.isEmpty) return;

    final now = DateTime.now();
    final stamp = _formatTimestamp(now);
    final line = '[$stamp] [$title] $normalized';
    _lines.add(line);
    _message = normalized;
    if (progress != null) {
      _progress = progress.clamp(0.0, 1.0).toDouble();
    }
    debugPrint(line);
    notifyListeners();
  }

  Future<void> succeed(String message) async {
    log(message, progress: 1);
    _state = DeveloperOperationState.success;
    notifyListeners();
    await _waitForDialog();
  }

  Future<void> fail(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) async {
    if (error != null) {
      log('오류: $error');
    }
    if (stackTrace != null) {
      log('스택 추적:\n$stackTrace');
    }
    log(message, progress: 1);
    _state = DeveloperOperationState.failure;
    notifyListeners();
    await _waitForDialog();
  }

  Future<void> _waitForDialog() async {
    final future = _dialogFuture;
    if (future != null) {
      await future;
    }
  }

  Future<void> _show(BuildContext context) async {
    Widget builder(BuildContext dialogContext) {
      return _DeveloperOperationStatusDialog(trace: this);
    }

    if (useCommonUi) {
      await showCommonOverlayDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: builder,
      );
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: builder,
    );
  }

  static String _formatTimestamp(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    String three(int number) => number.toString().padLeft(3, '0');
    return '${two(value.hour)}:${two(value.minute)}:${two(value.second)}.${three(value.millisecond)}';
  }
}

class _DeveloperOperationStatusDialog extends StatefulWidget {
  const _DeveloperOperationStatusDialog({required this.trace});

  final DeveloperOperationTrace trace;

  @override
  State<_DeveloperOperationStatusDialog> createState() =>
      _DeveloperOperationStatusDialogState();
}

class _DeveloperOperationStatusDialogState
    extends State<_DeveloperOperationStatusDialog>
    with TickerProviderStateMixin {
  late final AnimationController _entryController;
  late final AnimationController _pulseController;
  late final Animation<double> _entryOpacity;
  late final Animation<double> _entryScale;
  Timer? _copyTimer;
  bool _copied = false;
  bool _motionConfigured = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
      lowerBound: 0.94,
      upperBound: 1.04,
    );
    _entryOpacity = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
    );
    _entryScale = Tween<double>(begin: 0.94, end: 1).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: Curves.easeOutBack,
      ),
    );
    widget.trace.addListener(_handleTraceChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_motionConfigured && reduceMotion == _reduceMotion) return;
    _motionConfigured = true;
    _reduceMotion = reduceMotion;
    if (_reduceMotion) {
      _entryController.stop();
      _entryController.value = 1;
      _pulseController.stop();
      _pulseController.value = 1;
      return;
    }
    if (_entryController.value < 1) {
      _entryController.forward();
    }
    if (!widget.trace.isDone && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _copyTimer?.cancel();
    widget.trace.removeListener(_handleTraceChanged);
    _entryController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _handleTraceChanged() {
    if (!mounted) return;
    if (widget.trace.isDone && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.value = 1;
    }
    setState(() {});
  }

  Future<void> _copyDebugPrintCode() async {
    await Clipboard.setData(
      ClipboardData(text: widget.trace.debugPrintCode),
    );
    if (!mounted) return;
    _copyTimer?.cancel();
    setState(() => _copied = true);
    _copyTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  Color _statusColor(ColorScheme colorScheme) {
    switch (widget.trace.state) {
      case DeveloperOperationState.running:
        return colorScheme.primary;
      case DeveloperOperationState.success:
        return Colors.green;
      case DeveloperOperationState.failure:
        return colorScheme.error;
    }
  }

  IconData _statusIcon() {
    switch (widget.trace.state) {
      case DeveloperOperationState.running:
        return Icons.sync_rounded;
      case DeveloperOperationState.success:
        return Icons.check_circle_rounded;
      case DeveloperOperationState.failure:
        return Icons.error_rounded;
    }
  }

  String _stateLabel() {
    switch (widget.trace.state) {
      case DeveloperOperationState.running:
        return '실행 중';
      case DeveloperOperationState.success:
        return '완료';
      case DeveloperOperationState.failure:
        return '실패';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColor = _statusColor(colorScheme);
    final logs = widget.trace.lines;
    final visibleLogs = logs.length > 12
        ? logs.sublist(logs.length - 12)
        : logs;
    final fastMotion =
        _reduceMotion ? Duration.zero : const Duration(milliseconds: 220);
    final standardMotion =
        _reduceMotion ? Duration.zero : const Duration(milliseconds: 260);
    final progressMotion =
        _reduceMotion ? Duration.zero : const Duration(milliseconds: 360);

    return PopScope(
      canPop: widget.trace.isDone,
      child: FadeTransition(
        opacity: _entryOpacity,
        child: ScaleTransition(
          scale: _entryScale,
          child: AlertDialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 24,
            ),
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            actionsPadding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            title: Row(
              children: [
                ScaleTransition(
                  scale: widget.trace.state == DeveloperOperationState.running &&
                          !_reduceMotion
                      ? _pulseController
                      : const AlwaysStoppedAnimation<double>(1),
                  child: AnimatedContainer(
                    duration: standardMotion,
                    curve: Curves.easeOutCubic,
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: statusColor.withOpacity(0.42),
                      ),
                    ),
                    child: AnimatedSwitcher(
                      duration: standardMotion,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: animation,
                            child: child,
                          ),
                        );
                      },
                      child: Icon(
                        _statusIcon(),
                        key: ValueKey<DeveloperOperationState>(
                          widget.trace.state,
                        ),
                        color: statusColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.trace.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      AnimatedSwitcher(
                        duration: fastMotion,
                        child: Text(
                          _stateLabel(),
                          key: ValueKey<DeveloperOperationState>(
                            widget.trace.state,
                          ),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 620,
                maxHeight: 560,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AnimatedContainer(
                      duration: standardMotion,
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: statusColor.withOpacity(0.3),
                        ),
                      ),
                      child: AnimatedSwitcher(
                        duration: standardMotion,
                        transitionBuilder: (child, animation) {
                          final offset = Tween<Offset>(
                            begin: const Offset(0.03, 0),
                            end: Offset.zero,
                          ).animate(animation);
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: offset,
                              child: child,
                            ),
                          );
                        },
                        child: Text(
                          widget.trace.message,
                          key: ValueKey<String>(widget.trace.message),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TweenAnimationBuilder<double>(
                      duration: progressMotion,
                      curve: Curves.easeOutCubic,
                      tween: Tween<double>(
                        begin: 0,
                        end: widget.trace.progress,
                      ),
                      builder: (context, value, _) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            LinearProgressIndicator(
                              value: value,
                              minHeight: 8,
                              color: statusColor,
                            ),
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                '${(value * 100).round()}%',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          Icons.terminal_rounded,
                          size: 18,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          'debugPrint',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${logs.length}개',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    AnimatedSize(
                      duration: standardMotion,
                      curve: Curves.easeOutCubic,
                      child: AnimatedSwitcher(
                        duration: fastMotion,
                        transitionBuilder: (child, animation) {
                          final offset = Tween<Offset>(
                            begin: const Offset(0, 0.02),
                            end: Offset.zero,
                          ).animate(animation);
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: offset,
                              child: child,
                            ),
                          );
                        },
                        child: Container(
                          key: ValueKey<int>(logs.length),
                          width: double.infinity,
                          constraints: const BoxConstraints(
                            minHeight: 120,
                            maxHeight: 250,
                          ),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: colorScheme.outlineVariant,
                            ),
                          ),
                          child: SingleChildScrollView(
                            reverse: true,
                            child: SelectableText(
                              visibleLogs.join('\n'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                height: 1.45,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              OutlinedButton.icon(
                onPressed: _copyDebugPrintCode,
                icon: AnimatedSwitcher(
                  duration: fastMotion,
                  child: Icon(
                    _copied ? Icons.check_rounded : Icons.copy_all_rounded,
                    key: ValueKey<bool>(_copied),
                  ),
                ),
                label: AnimatedSwitcher(
                  duration: fastMotion,
                  child: Text(
                    _copied ? '복사 완료' : 'debugPrint 코드 복사',
                    key: ValueKey<bool>(_copied),
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: standardMotion,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: animation,
                      child: child,
                    ),
                  );
                },
                child: widget.trace.isDone
                    ? FilledButton.icon(
                        key: const ValueKey<String>('close'),
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(
                          widget.trace.state == DeveloperOperationState.success
                              ? Icons.check_rounded
                              : Icons.close_rounded,
                        ),
                        label: Text(
                          widget.trace.state == DeveloperOperationState.success
                              ? '확인'
                              : '닫기',
                        ),
                      )
                    : const SizedBox.shrink(
                        key: ValueKey<String>('running'),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
