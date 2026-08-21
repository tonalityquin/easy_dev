import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/utils/developer_operation_status_dialog.dart';
import '../../../design_system/common_ui/common_ui_side_dock.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../secondary/widgets/ops_console_widgets.dart';
import '../domain/models/plate_log_model.dart';
import '../domain/repositories/plate_repository.dart';

class PlateLogSideDockRequest {
  const PlateLogSideDockRequest({
    required this.plateNumber,
    required this.area,
    this.plateId,
    this.source = 'parking_status',
  });

  final String plateNumber;
  final String area;
  final String? plateId;
  final String source;
}

Future<void> showPlateLogSideDock({
  required BuildContext context,
  required PlateLogSideDockRequest request,
}) async {
  final trace = await DeveloperOperationTrace.start(
    context: context,
    title: '차량 로그 Side Dock',
    initialMessage: '차량 로그 Side Dock을 준비합니다.',
    useCommonUi: true,
    showDialogImmediately: false,
    developerModeMessage:
        '개발자 모드 ON: 로그 조회 동작을 추적하고 Status Dialog에서 debugPrint 코드를 복사할 수 있습니다.',
    standardModeMessage: '개발자 모드 OFF: 차량 로그 Side Dock을 실행합니다.',
  );
  trace.log(
    'plate_log_side_dock_open presentation=operations_right_side_dock rail=none sourceDock=${request.source} targetDock=plate_log handoffPolicy=close_then_open overlayStacking=false motion=operations_210_190 translate=22 opacity=0.90_to_1 plate=${request.plateNumber} area=${request.area} plateId=${request.plateId ?? '-'} developerMode=${trace.developerMode} debugPrint=clipboard_copy_supported',
    progress: .08,
  );

  try {
    await showOperationsRightSideDock<void>(
      context: context,
      barrierLabel: '${request.plateNumber} 로그',
      maxWidth: 360,
      widthFactor: .92,
      barrierDismissible: true,
      builder: (_) => PlateLogSideDock(
        request: request,
        trace: trace,
      ),
    );
    trace.log(
      'plate_log_side_dock_closed presentation=operations_right_side_dock returnTarget=type_page rail=none',
      progress: .94,
    );
    await trace.succeed('차량 로그 Side Dock 세션이 종료되었습니다.');
    if (trace.developerMode && context.mounted) {
      await trace.showStatusDialog(context);
    }
  } catch (error, stackTrace) {
    await trace.fail(
      '차량 로그 Side Dock 실행 중 예외가 발생했습니다.',
      error: error,
      stackTrace: stackTrace,
    );
    if (trace.developerMode && context.mounted) {
      await trace.showStatusDialog(context);
    }
    rethrow;
  }
}

class PlateLogSideDock extends StatefulWidget {
  const PlateLogSideDock({
    super.key,
    required this.request,
    required this.trace,
  });

  final PlateLogSideDockRequest request;
  final DeveloperOperationTrace trace;

  @override
  State<PlateLogSideDock> createState() => _PlateLogSideDockState();
}

class _PlateLogSideDockState extends State<PlateLogSideDock> {
  bool _descending = false;
  bool _loading = true;
  bool _refreshing = false;
  String? _errorMessage;
  List<PlateLogModel> _logs = <PlateLogModel>[];
  int _loadGeneration = 0;
  int _sortGeneration = 0;
  int _refreshCount = 0;

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  String get _sortLabel => _descending ? '최신순' : '오래된순';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.trace.log(
        'plate_log_content_mounted presentation=operations_right_side_dock rail=none sort=oldest_first resultSurface=OpsDockListSurface resultTransition=OpsDockResultSwitcher refreshPlacement=fixed_bottom reduceMotion=$_reduceMotion',
        progress: .14,
      );
    });
    unawaited(_loadLogs(initial: true));
  }

  @override
  void dispose() {
    _loadGeneration += 1;
    super.dispose();
  }

  Future<void> _loadLogs({required bool initial}) async {
    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() {
        if (initial || _logs.isEmpty) {
          _loading = true;
        } else {
          _refreshing = true;
        }
        _errorMessage = null;
      });
    }
    if (!initial) {
      _refreshCount += 1;
    }
    widget.trace.log(
      'plate_log_load_started initial=$initial refreshCount=$_refreshCount sort=${_descending ? 'newest_first' : 'oldest_first'} plate=${widget.request.plateNumber} area=${widget.request.area} plateId=${widget.request.plateId ?? '-'}',
      progress: initial ? .2 : .48,
    );

    final stopwatch = Stopwatch()..start();
    try {
      final logs = await context.read<PlateRepository>().fetchPlateLogs(
            plateId: widget.request.plateId,
            plateNumber: widget.request.plateNumber,
            area: widget.request.area,
            descending: _descending,
          );
      stopwatch.stop();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _logs = logs;
        _loading = false;
        _refreshing = false;
        _errorMessage = null;
      });
      widget.trace.log(
        'plate_log_load_completed initial=$initial logCount=${logs.length} loadMs=${stopwatch.elapsedMilliseconds} sort=${_descending ? 'newest_first' : 'oldest_first'} refreshCount=$_refreshCount',
        progress: .68,
      );
    } on PlateLogReadException catch (error) {
      stopwatch.stop();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _errorMessage = error.message;
      });
      widget.trace.log(
        'plate_log_load_failed type=PlateLogReadException loadMs=${stopwatch.elapsedMilliseconds} message=${error.message}',
        progress: .68,
      );
    } on StateError catch (error) {
      stopwatch.stop();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _errorMessage = error.message.toString();
      });
      widget.trace.log(
        'plate_log_load_failed type=StateError loadMs=${stopwatch.elapsedMilliseconds} message=${error.message}',
        progress: .68,
      );
    } catch (error, stackTrace) {
      stopwatch.stop();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _errorMessage = '로그를 불러오는 중 오류가 발생했습니다. ($error)';
      });
      widget.trace.log(
        'plate_log_load_failed type=unexpected loadMs=${stopwatch.elapsedMilliseconds} error=$error',
        progress: .68,
      );
      widget.trace.log('plate_log_load_stacktrace $stackTrace');
    }
  }

  Future<void> _toggleSort() async {
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    setState(() {
      _descending = !_descending;
      _logs = _logs.reversed.toList(growable: false);
      _sortGeneration += 1;
    });
    widget.trace.log(
      'plate_log_sort_changed sort=${_descending ? 'newest_first' : 'oldest_first'} logCount=${_logs.length} networkRead=false animation=${_reduceMotion ? 'none' : 'fade'}',
      progress: .74,
    );
  }

  Future<void> _refresh() async {
    if (_loading || _refreshing) {
      widget.trace.log(
        'plate_log_refresh_ignored reason=busy loading=$_loading refreshing=$_refreshing',
      );
      return;
    }
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    widget.trace.log(
      'plate_log_refresh_requested nextRefreshCount=${_refreshCount + 1} preserveSort=true preserveVisibleResults=${_logs.isNotEmpty}',
      progress: .46,
    );
    await _loadLogs(initial: false);
  }

  Future<void> _showDeveloperStatus() async {
    if (!widget.trace.developerMode || !mounted) return;
    widget.trace.log(
      'plate_log_status_dialog_open presentation=operations_right_side_dock rail=none plate=${widget.request.plateNumber} area=${widget.request.area} logCount=${_logs.length} sort=${_descending ? 'newest_first' : 'oldest_first'} loading=$_loading refreshing=$_refreshing refreshCount=$_refreshCount resultSurface=OpsDockListSurface resultTransition=OpsDockResultSwitcher refreshPlacement=fixed_bottom handoffPolicy=close_then_open sourceDock=${widget.request.source} targetDock=plate_log overlayStacking=false reduceMotion=$_reduceMotion debugPrint=clipboard_copy_supported',
    );
    await widget.trace.showStatusDialog(context);
  }

  void _close() {
    widget.trace.log(
      'plate_log_close_button logCount=${_logs.length} sort=${_descending ? 'newest_first' : 'oldest_first'} refreshCount=$_refreshCount',
      progress: .9,
    );
    HapticFeedback.lightImpact();
    Navigator.of(context).pop();
  }

  String _formatTimestamp(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  String _formatIntWithComma(int value) {
    final source = value.toString();
    final buffer = StringBuffer();
    for (var index = 0; index < source.length; index++) {
      if (index != 0 && (source.length - index) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(source[index]);
    }
    return buffer.toString();
  }

  String _formatWon(dynamic value) {
    if (value == null) return '-';
    final parsed = value is num ? value.toInt() : int.tryParse(value.toString());
    if (parsed == null) return value.toString();
    return '₩${_formatIntWithComma(parsed)}';
  }

  String _maskName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    final runes = trimmed.runes.toList();
    if (runes.length <= 1) return trimmed;
    final mask = List<String>.filled(runes.length - 1, '*').join();
    return '${String.fromCharCode(runes.first)}$mask';
  }

  IconData _actionIcon(String action) {
    if (action.contains('사전 정산')) return Icons.receipt_long_rounded;
    if (action.contains('입차 완료')) return Icons.local_parking_rounded;
    if (action.contains('출차')) return Icons.exit_to_app_rounded;
    if (action.contains('취소')) return Icons.undo_rounded;
    if (action.contains('생성')) return Icons.add_circle_outline_rounded;
    return Icons.history_rounded;
  }

  Color _actionColor(ColorScheme colors, String action) {
    if (action.contains('사전 정산')) return colors.tertiary;
    if (action.contains('출차')) return colors.primary;
    if (action.contains('취소')) return colors.error;
    if (action.contains('생성')) return colors.primary;
    return colors.onSurfaceVariant;
  }

  Widget _buildResult() {
    if (_loading && _logs.isEmpty) {
      return const _PlateLogState(
        key: ValueKey<String>('loading'),
        icon: Icons.hourglass_top_rounded,
        title: '로그를 불러오는 중입니다.',
      );
    }
    final error = _errorMessage;
    if (error != null && _logs.isEmpty) {
      return _PlateLogState(
        key: const ValueKey<String>('error'),
        icon: Icons.error_outline_rounded,
        title: '로그를 불러오지 못했습니다.',
        message: error,
        danger: true,
      );
    }
    if (_logs.isEmpty) {
      return const _PlateLogState(
        key: ValueKey<String>('empty'),
        icon: Icons.inbox_outlined,
        title: '로그가 없습니다.',
        message: '현재 차량에 저장된 상태 처리 이력이 없습니다.',
      );
    }

    final colors = Theme.of(context).colorScheme;
    return OpsDockListSurface(
      key: ValueKey<String>('logs_$_sortGeneration'),
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: _logs.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          thickness: 1,
          color: CommonUiTheme.of(context).borderSubtle,
        ),
        itemBuilder: (_, index) {
          final log = _logs[index];
          final actionColor = _actionColor(colors, log.action);
          final feeText = log.lockedFee == null ? null : _formatWon(log.lockedFee);
          final paymentText = log.paymentMethod?.trim();
          final reasonText = log.reason?.trim();
          return _PlateLogRow(
            log: log,
            actionColor: actionColor,
            actionIcon: _actionIcon(log.action),
            timestamp: _formatTimestamp(log.timestamp),
            maskedPerformer: _maskName(log.performedBy),
            feeText: feeText,
            paymentText: paymentText == null || paymentText.isEmpty
                ? null
                : paymentText,
            reasonText:
                reasonText == null || reasonText.isEmpty ? null : reasonText,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final subtitle = '${widget.request.area} · 차량 상태 처리 이력';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ExcludeSemantics(
              child: IgnorePointer(
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: tokens.accentContainer,
                    borderRadius: BorderRadius.circular(CommonUiShapes.control),
                    border: Border.all(color: tokens.borderSubtle),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.history_rounded,
                    size: 20,
                    color: tokens.onAccentContainer,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${widget.request.plateNumber} 로그',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelMedium?.copyWith(
                      color: tokens.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _PlateLogHeaderButton(
              semanticLabel: '로그 정렬 $_sortLabel',
              onPressed: _toggleSort,
              child: AnimatedSwitcher(
                duration: _reduceMotion
                    ? Duration.zero
                    : CommonUiMotion.selection,
                switchInCurve: CommonUiMotion.enter,
                switchOutCurve: CommonUiMotion.exit,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: .92, end: 1).animate(animation),
                    child: child,
                  ),
                ),
                child: Row(
                  key: ValueKey<bool>(_descending),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _descending ? Icons.south_rounded : Icons.north_rounded,
                      size: 17,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      _sortLabel,
                      style: textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.trace.developerMode) ...[
              const SizedBox(width: 4),
              _PlateLogHeaderButton(
                semanticLabel: '개발자 상태 보기',
                onPressed: _showDeveloperStatus,
                child: const Icon(Icons.bug_report_rounded, size: 18),
              ),
            ],
            const SizedBox(width: 4),
            _PlateLogHeaderButton(
              semanticLabel: '로그 닫기',
              onPressed: () async => _close(),
              child: const Icon(Icons.close_rounded, size: 19),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: OpsDockResultSwitcher(
                  child: KeyedSubtree(
                    key: ValueKey<String>(
                      '${_loading && _logs.isEmpty}|${_errorMessage != null && _logs.isEmpty}|${_logs.isEmpty}|$_sortGeneration',
                    ),
                    child: _buildResult(),
                  ),
                ),
              ),
              OpsDockLoadingOverlay(loading: _refreshing),
            ],
          ),
        ),
        const SizedBox(height: 8),
        OpsDockContextFooter(
          children: [
            Expanded(
              child: _PlateLogRefreshButton(
                busy: _loading || _refreshing,
                onPressed: _refresh,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PlateLogRow extends StatelessWidget {
  const _PlateLogRow({
    required this.log,
    required this.actionColor,
    required this.actionIcon,
    required this.timestamp,
    required this.maskedPerformer,
    required this.feeText,
    required this.paymentText,
    required this.reasonText,
  });

  final PlateLogModel log;
  final Color actionColor;
  final IconData actionIcon;
  final String timestamp;
  final String maskedPerformer;
  final String? feeText;
  final String? paymentText;
  final String? reasonText;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final transition = log.from.isEmpty && log.to.isEmpty
        ? ''
        : '${log.from} → ${log.to}';
    final metadata = <String>[
      if (maskedPerformer.isNotEmpty) '담당자 $maskedPerformer',
      if (feeText != null) feeText!,
      if (paymentText != null) paymentText!,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(11, 10, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: IgnorePointer(
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(actionIcon, size: 19, color: actionColor),
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.action,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    color: actionColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (transition.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    transition,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (metadata.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    metadata.join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelSmall?.copyWith(
                      color: tokens.textSecondary,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                ],
                if (reasonText != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    '사유 $reasonText',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelSmall?.copyWith(
                      color: tokens.textSecondary,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  timestamp,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelSmall?.copyWith(
                    color: tokens.textDisabled,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlateLogState extends StatelessWidget {
  const _PlateLogState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final foreground = danger ? tokens.danger : tokens.textSecondary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: foreground),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlateLogHeaderButton extends StatefulWidget {
  const _PlateLogHeaderButton({
    required this.semanticLabel,
    required this.onPressed,
    required this.child,
  });

  final String semanticLabel;
  final Future<void> Function() onPressed;
  final Widget child;

  @override
  State<_PlateLogHeaderButton> createState() =>
      _PlateLogHeaderButtonState();
}

class _PlateLogHeaderButtonState extends State<_PlateLogHeaderButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: widget.semanticLabel,
      child: AnimatedScale(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
        curve: CommonUiMotion.enter,
        scale: _pressed ? .96 : 1,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(CommonUiShapes.control),
            onHighlightChanged: (value) {
              if (!mounted) return;
              setState(() => _pressed = value);
            },
            onTap: () => unawaited(widget.onPressed()),
            child: AnimatedContainer(
              duration:
                  reduceMotion ? Duration.zero : CommonUiMotion.selection,
              curve: CommonUiMotion.standard,
              constraints: const BoxConstraints(minHeight: 36),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(
                color: _pressed
                    ? tokens.surfaceSelected.withOpacity(.62)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(CommonUiShapes.control),
              ),
              alignment: Alignment.center,
              child: IconTheme(
                data: IconThemeData(color: tokens.textSecondary),
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: tokens.textSecondary),
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlateLogRefreshButton extends StatefulWidget {
  const _PlateLogRefreshButton({
    required this.busy,
    required this.onPressed,
  });

  final bool busy;
  final Future<void> Function() onPressed;

  @override
  State<_PlateLogRefreshButton> createState() =>
      _PlateLogRefreshButtonState();
}

class _PlateLogRefreshButtonState extends State<_PlateLogRefreshButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Semantics(
      button: true,
      excludeSemantics: true,
      enabled: !widget.busy,
      label: widget.busy ? '로그 새로고침 중' : '로그 새로고침',
      child: AnimatedScale(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
        curve: CommonUiMotion.enter,
        scale: _pressed ? .98 : 1,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(CommonUiShapes.control),
            onHighlightChanged: (value) {
              if (!mounted) return;
              setState(() => _pressed = value);
            },
            onTap: widget.busy ? null : () => unawaited(widget.onPressed()),
            child: AnimatedContainer(
              duration:
                  reduceMotion ? Duration.zero : CommonUiMotion.selection,
              curve: CommonUiMotion.standard,
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: tokens.accent,
                borderRadius: BorderRadius.circular(CommonUiShapes.control),
                border: Border.all(color: tokens.borderSubtle),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedSwitcher(
                    duration:
                        reduceMotion ? Duration.zero : CommonUiMotion.selection,
                    child: widget.busy
                        ? SizedBox(
                            key: const ValueKey<String>('busy'),
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: tokens.onAccent,
                            ),
                          )
                        : Icon(
                            Icons.refresh_rounded,
                            key: const ValueKey<String>('idle'),
                            size: 19,
                            color: tokens.onAccent,
                          ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    widget.busy ? '불러오는 중' : '새로고침',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: tokens.onAccent,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
