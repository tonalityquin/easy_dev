import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/common_ui/common_ui_theme.dart';
import '../secondary/widgets/ops_console_widgets.dart';
import 'real_time_driving_plate_text.dart';
import 'real_time_elapsed_time.dart';
import 'real_time_table_row_vm.dart';

enum RealTimeRequestQueueType {
  parking,
  completed,
  departure,
}

enum RealTimeTraySortOrder {
  newestFirst,
  oldestFirst,
}

extension RealTimeRequestQueueTypeX on RealTimeRequestQueueType {
  String get label {
    switch (this) {
      case RealTimeRequestQueueType.parking:
        return '입차 요청';
      case RealTimeRequestQueueType.completed:
        return '입차 완료';
      case RealTimeRequestQueueType.departure:
        return '출차 요청';
    }
  }

  String get collection {
    switch (this) {
      case RealTimeRequestQueueType.parking:
        return 'parking_requests_view';
      case RealTimeRequestQueueType.completed:
        return 'parking_completed_view';
      case RealTimeRequestQueueType.departure:
        return 'departure_requests_view';
    }
  }

  String get sourceKey {
    switch (this) {
      case RealTimeRequestQueueType.parking:
        return 'parking';
      case RealTimeRequestQueueType.completed:
        return 'completed';
      case RealTimeRequestQueueType.departure:
        return 'departure';
    }
  }

  IconData get icon {
    switch (this) {
      case RealTimeRequestQueueType.parking:
        return Icons.login_rounded;
      case RealTimeRequestQueueType.completed:
        return Icons.local_parking_rounded;
      case RealTimeRequestQueueType.departure:
        return Icons.logout_rounded;
    }
  }

  Color statusColor(CommonUiTokens tokens) {
    switch (this) {
      case RealTimeRequestQueueType.parking:
        return tokens.statusParkingRequested;
      case RealTimeRequestQueueType.completed:
        return tokens.statusParkingCompleted;
      case RealTimeRequestQueueType.departure:
        return tokens.statusDepartureRequested;
    }
  }
}

String realTimeRequestPlateLast4(String raw) {
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

DateTime? realTimeRequestAt(RealTimeRowVM row) {
  return row.primaryAt ?? row.createdAt ?? row.updatedAt;
}

class RealTimeRequestTray extends StatefulWidget {
  const RealTimeRequestTray({
    super.key,
    required this.type,
    required this.rows,
    required this.onRequestTap,
    required this.onClose,
    required this.sortOrder,
    required this.onSortToggle,
    this.onDebugLine,
  });

  final RealTimeRequestQueueType type;
  final List<RealTimeRowVM> rows;
  final Future<void> Function(RealTimeRowVM row) onRequestTap;
  final VoidCallback onClose;
  final RealTimeTraySortOrder sortOrder;
  final VoidCallback onSortToggle;
  final ValueChanged<String>? onDebugLine;

  @override
  State<RealTimeRequestTray> createState() => _RealTimeRequestTrayState();
}

class _RealTimeRequestTrayState extends State<RealTimeRequestTray> {
  Timer? _elapsedTicker;
  DateTime _now = DateTime.now();
  String _rowsSignature = '';

  @override
  void initState() {
    super.initState();
    _rowsSignature = _signature(widget.rows);
    _emit('request_tray_initialized');
    _scheduleElapsedTicker();
  }

  @override
  void didUpdateWidget(covariant RealTimeRequestTray oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _signature(widget.rows);
    if (next != _rowsSignature || oldWidget.type != widget.type) {
      _rowsSignature = next;
      _emit('request_tray_rows_changed');
      _scheduleElapsedTicker();
    }
  }

  @override
  void dispose() {
    _elapsedTicker?.cancel();
    super.dispose();
  }

  String _signature(List<RealTimeRowVM> rows) {
    return rows
        .map(
          (row) =>
              '${row.plateId}:${row.primaryAt?.microsecondsSinceEpoch ?? 0}:${row.isSelected}:${row.selectedBy ?? ''}',
        )
        .join('|');
  }

  void _emit(String event, [Map<String, Object?> details = const <String, Object?>{}]) {
    final payload = details.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' ');
    final line =
        '[RealTimeRequestTray] event=$event type=${widget.type.sourceKey} count=${widget.rows.length} selected=${widget.rows.where((row) => row.isSelected).length} timeFormat=table_elapsed timeBasis=primaryAt trayOwner=real_time_tabbed_table rootOverlayEntry=false $payload'
            .trim();
    debugPrint(line);
    widget.onDebugLine?.call(line);
  }

  Future<void> _tapRequest(RealTimeRowVM row) async {
    if (row.isSelected) {
      _emit(
        'request_tray_plate_tap_blocked',
        <String, Object?>{
          'reason': 'driving',
          'plateId': row.plateId,
          'plateLast4': realTimeRequestPlateLast4(row.plateNumber),
          'selectedBy': row.selectedBy ?? '-',
          'action': 'status_side_dock_blocked',
        },
      );
      return;
    }
    _emit(
      'request_tray_plate_tap',
      <String, Object?>{
        'plateId': row.plateId,
        'plateLast4': realTimeRequestPlateLast4(row.plateNumber),
        'action': 'open_status_side_dock',
      },
    );
    await widget.onRequestTap(row);
  }

  void _scheduleElapsedTicker() {
    _elapsedTicker?.cancel();
    if (!mounted || widget.rows.isEmpty) return;
    _now = DateTime.now();
    final delay = nextRealTimeElapsedTick(
      values: widget.rows.map(realTimeRequestAt),
      now: _now,
    );
    if (delay == null) return;
    _elapsedTicker = Timer(delay, () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _scheduleElapsedTicker();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = CommonUiTheme.of(context);
    final statusColor = widget.type.statusColor(tokens);
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
                  label:
                      '${widget.type.label} ${widget.rows.length}대, ${widget.sortOrder == RealTimeTraySortOrder.newestFirst ? '위에서부터 최신순' : '위에서부터 오래된순'}',
                  child: Row(
                    children: [
                      Icon(
                        widget.type.icon,
                        size: 18,
                        color: statusColor,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        '${widget.type.label} ${widget.rows.length}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Spacer(),
                      Semantics(
                        button: true,
                        label: widget.sortOrder == RealTimeTraySortOrder.newestFirst
                            ? '최신순 정렬, 오래된순으로 변경'
                            : '오래된순 정렬, 최신순으로 변경',
                        child: IconButton(
                          onPressed: () {
                            _emit(
                              'request_tray_sort_toggled',
                              <String, Object?>{
                                'from': widget.sortOrder.name,
                                'to': widget.sortOrder == RealTimeTraySortOrder.newestFirst
                                    ? RealTimeTraySortOrder.oldestFirst.name
                                    : RealTimeTraySortOrder.newestFirst.name,
                              },
                            );
                            widget.onSortToggle();
                          },
                          icon: AnimatedRotation(
                            turns: widget.sortOrder == RealTimeTraySortOrder.newestFirst
                                ? 0
                                : .5,
                            duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
                                ? Duration.zero
                                : const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            child: const Icon(
                              Icons.arrow_downward_rounded,
                              size: 16,
                            ),
                          ),
                          color: tokens.iconSecondary,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 34,
                            height: 34,
                          ),
                          splashRadius: 17,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Semantics(
                        button: true,
                        label: '${widget.type.label} 더보기 닫기',
                        child: IconButton(
                          onPressed: widget.onClose,
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
              child: ListView.separated(
                key: PageStorageKey<String>(
                  'request_tray_${widget.type.sourceKey}:${widget.sortOrder.name}',
                ),
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                itemCount: widget.rows.length,
                separatorBuilder: (_, __) => const OpsDivider(),
                itemBuilder: (context, index) {
                  final row = widget.rows[index];
                  return _RequestTrayRow(
                    key: ValueKey<String>(row.plateId),
                    type: widget.type,
                    plateLast4: realTimeRequestPlateLast4(row.plateNumber),
                    elapsedText: formatRealTimeElapsed(
                      realTimeRequestAt(row),
                      now: _now,
                    ),
                    newest: widget.sortOrder == RealTimeTraySortOrder.newestFirst
                        ? index == 0
                        : index == widget.rows.length - 1,
                    isSelected: row.isSelected,
                    selectedBy: row.selectedBy,
                    onTap: () => _tapRequest(row),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestTrayRow extends StatefulWidget {
  const _RequestTrayRow({
    super.key,
    required this.type,
    required this.plateLast4,
    required this.elapsedText,
    required this.newest,
    required this.isSelected,
    required this.selectedBy,
    required this.onTap,
  });

  final RealTimeRequestQueueType type;
  final String plateLast4;
  final String elapsedText;
  final bool newest;
  final bool isSelected;
  final String? selectedBy;
  final Future<void> Function() onTap;

  @override
  State<_RequestTrayRow> createState() => _RequestTrayRowState();
}

class _RequestTrayRowState extends State<_RequestTrayRow> {
  bool _pressed = false;

  @override
  void didUpdateWidget(covariant _RequestTrayRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected && _pressed) {
      _pressed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = CommonUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final statusColor = widget.type.statusColor(tokens);
    final duration = reduceMotion ? Duration.zero : CommonUiMotion.selection;
    final selectedBy = widget.selectedBy?.trim() ?? '';
    final drivingLabel = selectedBy.isEmpty ? '주행 중' : '주행 중 · $selectedBy';
    final plateStyle = theme.textTheme.titleSmall?.copyWith(
      color: widget.newest ? statusColor : tokens.textPrimary,
      fontWeight: widget.newest ? FontWeight.w900 : FontWeight.w800,
      letterSpacing: .45,
    );
    return Semantics(
      button: true,
      enabled: !widget.isSelected,
      label:
          '차량 번호 끝자리 ${widget.plateLast4}, ${widget.type.label}${widget.isSelected ? ', $drivingLabel, 상태 처리 불가' : ''}, 경과 시간 ${widget.elapsedText}${widget.newest ? ', 가장 최근' : ''}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.isSelected ? null : () => widget.onTap(),
          onHighlightChanged: widget.isSelected
              ? null
              : (value) {
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
                SizedBox(
                  width: 58,
                  child: RealTimeDrivingPlateText(
                    text: widget.plateLast4,
                    driving: widget.isSelected,
                    style: plateStyle,
                    overflow: TextOverflow.ellipsis,
                    lineColor: plateStyle?.color,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedSwitcher(
                      duration: duration,
                      switchInCurve: CommonUiMotion.enter,
                      switchOutCurve: CommonUiMotion.exit,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: Tween<double>(
                              begin: .96,
                              end: 1,
                            ).animate(animation),
                            alignment: Alignment.centerLeft,
                            child: child,
                          ),
                        );
                      },
                      child: widget.isSelected
                          ? Container(
                              key: ValueKey<String>('driving:$selectedBy'),
                              constraints: const BoxConstraints(maxWidth: 168),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: tokens.surfaceRaised,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: tokens.borderSubtle),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: statusColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Flexible(
                                    child: Text(
                                      drivingLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: tokens.textPrimary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : const SizedBox(
                              key: ValueKey<String>('idle'),
                              height: 1,
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  widget.elapsedText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: tokens.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedSize(
                  duration: duration,
                  curve: CommonUiMotion.standard,
                  alignment: Alignment.centerRight,
                  child: widget.isSelected
                      ? const SizedBox(
                          key: ValueKey<String>('driving_no_chevron'),
                          width: 0,
                          height: 18,
                        )
                      : Icon(
                          Icons.chevron_right_rounded,
                          key: const ValueKey<String>('ready_chevron'),
                          size: 18,
                          color: tokens.iconSecondary,
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

