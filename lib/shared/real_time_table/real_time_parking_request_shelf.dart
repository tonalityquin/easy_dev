import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/common_ui/common_ui_theme.dart';
import '../secondary/widgets/ops_console_widgets.dart';
import 'real_time_table_row_vm.dart';

typedef RealTimeParkingRequestTap = Future<void> Function(
  RealTimeRowVM row,
  String source,
);

class RealTimeParkingRequestShelf extends StatefulWidget {
  const RealTimeParkingRequestShelf({
    super.key,
    required this.rows,
    required this.onRequestTap,
    this.onDebugLine,
    this.onUserActivity,
    this.onTrayOpen,
    this.onTrayClose,
  });

  final List<RealTimeRowVM> rows;
  final RealTimeParkingRequestTap onRequestTap;
  final ValueChanged<String>? onDebugLine;
  final VoidCallback? onUserActivity;
  final VoidCallback? onTrayOpen;
  final VoidCallback? onTrayClose;

  @override
  State<RealTimeParkingRequestShelf> createState() =>
      _RealTimeParkingRequestShelfState();
}

class _RealTimeParkingRequestShelfState
    extends State<RealTimeParkingRequestShelf> with TickerProviderStateMixin {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _trayEntry;
  late final AnimationController _trayController;
  bool _reduceMotion = false;
  String _rowsSignature = '';

  @override
  void initState() {
    super.initState();
    _trayController = AnimationController(
      vsync: this,
      duration: CommonUiMotion.component,
      reverseDuration: CommonUiMotion.selection,
    );
    _rowsSignature = _signature(widget.rows);
    _emit(
      'parking_request_shelf_initialized',
      <String, Object?>{
        'count': widget.rows.length,
        'sort': 'createdAt_desc',
        'shelfSortLabel': '최신→',
        'traySortLabel': '최신↓',
        'plateLabel': 'last4',
        'presentation': 'list_surface',
        'morePresentation': 'anchored_list_surface',
        'firebaseAdditionalRead': 0,
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  @override
  void didUpdateWidget(covariant RealTimeParkingRequestShelf oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextSignature = _signature(widget.rows);
    if (nextSignature == _rowsSignature) return;
    final previousCount = oldWidget.rows.length;
    _rowsSignature = nextSignature;
    _emit(
      'parking_request_shelf_rows_changed',
      <String, Object?>{
        'beforeCount': previousCount,
        'afterCount': widget.rows.length,
        'sort': 'createdAt_desc',
        'shelfSortLabel': '최신→',
        'traySortLabel': '최신↓',
        'motion': _reduceMotion ? 'reduced' : 'horizontal_list_reflow',
        'firebaseAdditionalRead': 0,
      },
    );
    if (_trayEntry != null) {
      if (widget.rows.isEmpty) {
        unawaited(_closeTray(reason: 'rows_empty'));
      } else {
        _trayEntry?.markNeedsBuild();
      }
    }
  }

  @override
  void dispose() {
    final hadTray = _trayEntry != null;
    _trayEntry?.remove();
    _trayEntry = null;
    if (hadTray) {
      widget.onTrayClose?.call();
    }
    _trayController.dispose();
    super.dispose();
  }

  String _signature(List<RealTimeRowVM> rows) {
    return rows
        .map(
          (row) =>
              '${row.plateId}|${row.plateNumber}|${row.createdAt?.microsecondsSinceEpoch ?? 0}|${row.updatedAt?.microsecondsSinceEpoch ?? 0}',
        )
        .join('>');
  }

  String _plateLast4(String raw) {
    final normalized = raw.trim();
    if (normalized.isEmpty) return '—';
    final match = RegExp(r'(\d{4})$').firstMatch(normalized);
    if (match != null) return match.group(1) ?? '—';
    final digits = RegExp(r'\d+')
        .allMatches(normalized)
        .map((match) => match.group(0) ?? '')
        .join();
    if (digits.length >= 4) return digits.substring(digits.length - 4);
    return normalized.length <= 4
        ? normalized
        : normalized.substring(normalized.length - 4);
  }

  DateTime? _requestAt(RealTimeRowVM row) {
    return row.createdAt ?? row.updatedAt ?? row.primaryAt;
  }

  void _emit(String event, Map<String, Object?> details) {
    final payload = details.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' ');
    final line = '[RealTimeParkingRequestShelf] event=$event $payload'.trim();
    debugPrint(line);
    widget.onDebugLine?.call(line);
  }

  Future<void> _tapRequest(RealTimeRowVM row, String source) async {
    widget.onUserActivity?.call();
    HapticFeedback.selectionClick();
    _emit(
      'parking_request_shelf_plate_tap',
      <String, Object?>{
        'source': source,
        'plateId': row.plateId,
        'plateLast4': _plateLast4(row.plateNumber),
        'createdAt': row.createdAt?.toIso8601String() ?? '-',
        'updatedAt': row.updatedAt?.toIso8601String() ?? '-',
        'sort': 'createdAt_desc',
        'sortLabel': source == 'status_parking_request_tray' ? '최신↓' : '최신→',
        'sortFlow': source == 'status_parking_request_tray'
            ? 'top_to_bottom'
            : 'left_to_right',
        'collection': 'parking_requests_view',
        'action': 'open_status_side_dock',
      },
    );
    if (source == 'status_parking_request_tray') {
      await _closeTray(reason: 'plate_tap');
    }
    await widget.onRequestTap(row, source);
  }

  Future<void> _openTray() async {
    if (_trayEntry != null || widget.rows.isEmpty) return;
    widget.onUserActivity?.call();
    final overlay = Overlay.of(context, rootOverlay: true);
    final media = MediaQuery.of(context);
    final screenSize = media.size;
    final horizontalInset = screenSize.width < 420 ? 12.0 : 16.0;
    final trayWidth = math.min(
      screenSize.width - horizontalInset * 2,
      screenSize.width < 600 ? 420.0 : 480.0,
    ).toDouble();
    final trayMaxHeight = math.min(
      screenSize.height * (screenSize.height < 700 ? .40 : .46),
      390.0,
    ).toDouble();
    _trayController.value = _reduceMotion ? 1 : 0;
    _trayEntry = OverlayEntry(
      builder: (overlayContext) {
        final tokens = CommonUiTheme.of(overlayContext);
        final progress = _reduceMotion
            ? const AlwaysStoppedAnimation<double>(1)
            : CurvedAnimation(
                parent: _trayController,
                curve: CommonUiMotion.enter,
                reverseCurve: CommonUiMotion.exit,
              );
        final slide = _reduceMotion
            ? const AlwaysStoppedAnimation<Offset>(Offset.zero)
            : Tween<Offset>(
                begin: const Offset(0, -0.025),
                end: Offset.zero,
              ).animate(progress);
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => _closeTray(reason: 'outside_tap'),
                child: ColoredBox(
                  color: tokens.scrim.withOpacity(.05),
                ),
              ),
            ),
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              targetAnchor: Alignment.bottomRight,
              followerAnchor: Alignment.topRight,
              offset: const Offset(0, 6),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: trayWidth,
                  maxHeight: trayMaxHeight,
                ),
                child: SizeTransition(
                  sizeFactor: progress,
                  axisAlignment: -1,
                  child: FadeTransition(
                    opacity: progress,
                    child: SlideTransition(
                      position: slide,
                      child: _ParkingRequestTray(
                        rows: widget.rows,
                        plateLast4: _plateLast4,
                        requestAt: _requestAt,
                        onTap: (row) => _tapRequest(
                          row,
                          'status_parking_request_tray',
                        ),
                        onClose: () => _closeTray(reason: 'close_button'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_trayEntry!);
    widget.onTrayOpen?.call();
    HapticFeedback.selectionClick();
    _emit(
      'parking_request_shelf_open_tray',
      <String, Object?>{
        'count': widget.rows.length,
        'layout': 'anchored_list_surface',
        'sort': 'createdAt_desc',
        'sortLabel': '최신↓',
        'sortFlow': 'top_to_bottom',
        'rowDetail': 'plate_last4_relative_time',
        'maxWidth': trayWidth.toStringAsFixed(1),
        'maxHeight': trayMaxHeight.toStringAsFixed(1),
        'dotMapResize': false,
        'motion': _reduceMotion ? 'reduced' : 'fade_vertical_reveal_230ms',
      },
    );
    if (!_reduceMotion) {
      await _trayController.forward();
    }
  }

  Future<void> _closeTray({required String reason}) async {
    final entry = _trayEntry;
    if (entry == null) return;
    _emit(
      'parking_request_shelf_close_tray',
      <String, Object?>{
        'reason': reason,
        'layout': 'anchored_list_surface',
        'motion': _reduceMotion ? 'reduced' : 'reverse_190ms',
      },
    );
    if (!_reduceMotion && _trayController.value > 0) {
      try {
        await _trayController.reverse();
      } catch (_) {}
    }
    if (identical(_trayEntry, entry)) {
      entry.remove();
      _trayEntry = null;
      widget.onTrayClose?.call();
      widget.onUserActivity?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = CommonUiTheme.of(context);
    final duration = _reduceMotion ? Duration.zero : CommonUiMotion.selection;
    return CompositedTransformTarget(
      link: _layerLink,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
        child: OpsDockListSurface(
          child: Material(
            color: Colors.transparent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 31,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Semantics(
                      header: true,
                      label: '입차 요청 ${widget.rows.length}대, 왼쪽부터 최신순',
                      child: Row(
                        children: [
                          Icon(
                            Icons.login_rounded,
                            size: 17,
                            color: tokens.statusParkingRequested,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '입차 요청',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: tokens.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 5),
                          AnimatedSwitcher(
                            duration: duration,
                            switchInCurve: CommonUiMotion.enter,
                            switchOutCurve: CommonUiMotion.exit,
                            child: Text(
                              '${widget.rows.length}',
                              key: ValueKey<int>(widget.rows.length),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: tokens.statusParkingRequested,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '최신',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: tokens.textSecondary,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: .1,
                                ),
                              ),
                              const SizedBox(width: 2),
                              Icon(
                                Icons.arrow_forward_rounded,
                                size: 14,
                                color: tokens.iconSecondary,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const OpsDivider(),
                SizedBox(
                  height: 41,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final total = widget.rows.length;
                      const itemWidth = 61.0;
                      const moreWidth = 86.0;
                      const maxVisible = 5;
                      final maxWithoutMore = math.max(
                        1,
                        math.min(
                          maxVisible,
                          (constraints.maxWidth / itemWidth).floor(),
                        ),
                      ).toInt();
                      final needsMore = total > maxWithoutMore;
                      final maxWithMore = math.max(
                        1,
                        math.min(
                          maxVisible,
                          ((constraints.maxWidth - moreWidth) / itemWidth)
                              .floor(),
                        ),
                      ).toInt();
                      final visibleCount = needsMore
                          ? math.min(total, maxWithMore).toInt()
                          : math.min(total, maxWithoutMore).toInt();
                      final visibleRows =
                          widget.rows.take(visibleCount).toList(growable: false);
                      final overflow = total - visibleRows.length;
                      final listKey = visibleRows
                          .map(
                            (row) =>
                                '${row.plateId}:${row.createdAt?.microsecondsSinceEpoch ?? 0}:${row.updatedAt?.microsecondsSinceEpoch ?? 0}',
                          )
                          .join('|');
                      return AnimatedSwitcher(
                        duration: duration,
                        switchInCurve: CommonUiMotion.enter,
                        switchOutCurve: CommonUiMotion.exit,
                        transitionBuilder: (child, animation) {
                          final slide = Tween<Offset>(
                            begin: const Offset(-0.04, 0),
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
                        child: Row(
                          key: ValueKey<String>(
                            '$listKey|overflow=$overflow|width=${constraints.maxWidth.floor()}',
                          ),
                          children: [
                            for (var index = 0;
                                index < visibleRows.length;
                                index++) ...[
                              SizedBox(
                                width: itemWidth,
                                child: _ParkingRequestInlineRow(
                                  plateLast4: _plateLast4(
                                    visibleRows[index].plateNumber,
                                  ),
                                  newest: index == 0,
                                  onTap: () => _tapRequest(
                                    visibleRows[index],
                                    'status_parking_request_shelf',
                                  ),
                                ),
                              ),
                              if (index != visibleRows.length - 1)
                                VerticalDivider(
                                  width: 1,
                                  thickness: 1,
                                  color: tokens.borderSubtle,
                                ),
                            ],
                            if (overflow > 0) ...[
                              const Spacer(),
                              VerticalDivider(
                                width: 1,
                                thickness: 1,
                                color: tokens.borderSubtle,
                              ),
                              SizedBox(
                                width: moreWidth,
                                child: _ParkingRequestMoreRow(
                                  overflow: overflow,
                                  onTap: _openTray,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
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

class _ParkingRequestInlineRow extends StatefulWidget {
  const _ParkingRequestInlineRow({
    required this.plateLast4,
    required this.newest,
    required this.onTap,
  });

  final String plateLast4;
  final bool newest;
  final Future<void> Function() onTap;

  @override
  State<_ParkingRequestInlineRow> createState() =>
      _ParkingRequestInlineRowState();
}

class _ParkingRequestInlineRowState
    extends State<_ParkingRequestInlineRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = CommonUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Semantics(
      button: true,
      label: widget.newest
          ? '차량 번호 끝자리 ${widget.plateLast4}, 가장 최근 입차 요청'
          : '차량 번호 끝자리 ${widget.plateLast4}, 입차 요청',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => widget.onTap(),
          onHighlightChanged: (value) {
            if (!mounted) return;
            setState(() => _pressed = value);
          },
          child: AnimatedContainer(
            duration: reduceMotion ? Duration.zero : CommonUiMotion.instant,
            curve: CommonUiMotion.standard,
            color: _pressed
                ? tokens.surfaceSelected.withOpacity(.55)
                : Colors.transparent,
            alignment: Alignment.center,
            child: AnimatedDefaultTextStyle(
              duration: reduceMotion ? Duration.zero : CommonUiMotion.instant,
              curve: CommonUiMotion.standard,
              style: (theme.textTheme.labelLarge ?? const TextStyle()).copyWith(
                color: widget.newest
                    ? tokens.statusParkingRequested
                    : tokens.textPrimary,
                fontWeight: widget.newest ? FontWeight.w900 : FontWeight.w800,
                letterSpacing: .45,
              ),
              child: Text(
                widget.plateLast4,
                maxLines: 1,
                overflow: TextOverflow.clip,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ParkingRequestMoreRow extends StatefulWidget {
  const _ParkingRequestMoreRow({
    required this.overflow,
    required this.onTap,
  });

  final int overflow;
  final Future<void> Function() onTap;

  @override
  State<_ParkingRequestMoreRow> createState() =>
      _ParkingRequestMoreRowState();
}

class _ParkingRequestMoreRowState extends State<_ParkingRequestMoreRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = CommonUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Semantics(
      button: true,
      label: '입차 요청 ${widget.overflow}대 더 보기',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => widget.onTap(),
          onHighlightChanged: (value) {
            if (!mounted) return;
            setState(() => _pressed = value);
          },
          child: AnimatedContainer(
            duration: reduceMotion ? Duration.zero : CommonUiMotion.instant,
            curve: CommonUiMotion.standard,
            color: _pressed
                ? tokens.surfaceSelected.withOpacity(.55)
                : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    '더보기 ${widget.overflow}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: tokens.accent,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 17,
                  color: tokens.accent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ParkingRequestTray extends StatefulWidget {
  const _ParkingRequestTray({
    required this.rows,
    required this.plateLast4,
    required this.requestAt,
    required this.onTap,
    required this.onClose,
  });

  final List<RealTimeRowVM> rows;
  final String Function(String) plateLast4;
  final DateTime? Function(RealTimeRowVM row) requestAt;
  final Future<void> Function(RealTimeRowVM row) onTap;
  final Future<void> Function() onClose;

  @override
  State<_ParkingRequestTray> createState() => _ParkingRequestTrayState();
}

class _ParkingRequestTrayState extends State<_ParkingRequestTray> {
  Timer? _relativeTimeTicker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _relativeTimeTicker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _relativeTimeTicker?.cancel();
    super.dispose();
  }

  String _relativeTime(DateTime? value) {
    if (value == null) return '시간 정보 없음';
    final elapsed = _now.difference(value);
    if (elapsed.isNegative || elapsed.inSeconds < 60) return '방금';
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}분 전';
    if (elapsed.inHours < 24) return '${elapsed.inHours}시간 전';
    if (elapsed.inDays < 7) return '${elapsed.inDays}일 전';
    return '${value.month}/${value.day}';
  }

  String _rowsSignature() {
    return widget.rows
        .map(
          (row) =>
              '${row.plateId}:${row.createdAt?.microsecondsSinceEpoch ?? 0}:${row.updatedAt?.microsecondsSinceEpoch ?? 0}',
        )
        .join('|');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = CommonUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion ? Duration.zero : CommonUiMotion.selection;
    return OpsDockListSurface(
      child: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 42,
              child: Padding(
                padding: const EdgeInsets.only(left: 12, right: 4),
                child: Semantics(
                  header: true,
                  label: '입차 요청 ${widget.rows.length}대, 위에서부터 최신순',
                  child: Row(
                    children: [
                      Icon(
                        Icons.login_rounded,
                        size: 18,
                        color: tokens.statusParkingRequested,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        '입차 요청 ${widget.rows.length}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '최신',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: tokens.textSecondary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            Icons.arrow_downward_rounded,
                            size: 14,
                            color: tokens.iconSecondary,
                          ),
                        ],
                      ),
                      const SizedBox(width: 4),
                      Semantics(
                        button: true,
                        label: '입차 요청 더보기 닫기',
                        child: IconButton(
                          onPressed: () => widget.onClose(),
                          icon: const Icon(Icons.close_rounded, size: 20),
                          color: tokens.iconSecondary,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 36,
                            height: 36,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const OpsDivider(),
            Flexible(
              child: AnimatedSwitcher(
                duration: duration,
                switchInCurve: CommonUiMotion.enter,
                switchOutCurve: CommonUiMotion.exit,
                transitionBuilder: (child, animation) {
                  final slide = Tween<Offset>(
                    begin: const Offset(0, -0.025),
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
                child: ListView.separated(
                  key: ValueKey<String>(_rowsSignature()),
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  itemCount: widget.rows.length,
                  separatorBuilder: (_, __) => const OpsDivider(),
                  itemBuilder: (context, index) {
                    final row = widget.rows[index];
                    return _ParkingRequestTrayRow(
                      plateLast4: widget.plateLast4(row.plateNumber),
                      relativeTime: _relativeTime(widget.requestAt(row)),
                      newest: index == 0,
                      onTap: () => widget.onTap(row),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParkingRequestTrayRow extends StatefulWidget {
  const _ParkingRequestTrayRow({
    required this.plateLast4,
    required this.relativeTime,
    required this.newest,
    required this.onTap,
  });

  final String plateLast4;
  final String relativeTime;
  final bool newest;
  final Future<void> Function() onTap;

  @override
  State<_ParkingRequestTrayRow> createState() =>
      _ParkingRequestTrayRowState();
}

class _ParkingRequestTrayRowState extends State<_ParkingRequestTrayRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = CommonUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Semantics(
      button: true,
      label: widget.newest
          ? '차량 번호 끝자리 ${widget.plateLast4}, ${widget.relativeTime}, 가장 최근 입차 요청'
          : '차량 번호 끝자리 ${widget.plateLast4}, ${widget.relativeTime}, 입차 요청',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => widget.onTap(),
          onHighlightChanged: (value) {
            if (!mounted) return;
            setState(() => _pressed = value);
          },
          child: AnimatedContainer(
            duration: reduceMotion ? Duration.zero : CommonUiMotion.instant,
            curve: CommonUiMotion.standard,
            color: _pressed
                ? tokens.surfaceSelected.withOpacity(.55)
                : Colors.transparent,
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.plateLast4,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: widget.newest
                          ? tokens.statusParkingRequested
                          : tokens.textPrimary,
                      fontWeight:
                          widget.newest ? FontWeight.w900 : FontWeight.w800,
                      letterSpacing: .45,
                    ),
                  ),
                ),
                Text(
                  widget.relativeTime,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: tokens.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: tokens.iconSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
