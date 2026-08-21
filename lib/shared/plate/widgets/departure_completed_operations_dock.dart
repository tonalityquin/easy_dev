import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/utils/status_dialog.dart';
import '../../../design_system/common_ui/common_ui_components.dart';
import '../../../design_system/common_ui/common_ui_side_rail.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../../features/selector/application/dev_auth.dart';
import '../../secondary/widgets/ops_console_widgets.dart';
import '../data/repositories/firestore_plate_repository.dart';
import '../domain/models/plate_log_model.dart';
import '../domain/models/plate_model.dart';
import 'departure_completed_history_workspace.dart';
import 'parking_completed_status_widgets.dart';

enum DepartureCompletedDockSection {
  unsettled,
  today,
  history,
}

typedef DepartureCompletedStatusOpener = Future<PlateModel?> Function(
  BuildContext context,
  PlateModel plate,
);

typedef DepartureCompletedImageOpener = Future<void> Function(
  BuildContext context,
  String plateNumber,
);

class DepartureCompletedOperationsDock extends StatefulWidget {
  const DepartureCompletedOperationsDock({
    super.key,
    required this.modeLabel,
    required this.area,
    required this.division,
    required this.selectedDate,
    required this.unsettledPlates,
    required this.refreshing,
    required this.onRefresh,
    required this.onDateChanged,
    required this.onOpenStatus,
    required this.onOpenImage,
    required this.onClose,
  });

  final String modeLabel;
  final String area;
  final String division;
  final DateTime selectedDate;
  final List<PlateModel> unsettledPlates;
  final bool refreshing;
  final Future<void> Function() onRefresh;
  final ValueChanged<DateTime> onDateChanged;
  final DepartureCompletedStatusOpener onOpenStatus;
  final DepartureCompletedImageOpener onOpenImage;
  final VoidCallback onClose;

  @override
  State<DepartureCompletedOperationsDock> createState() =>
      _DepartureCompletedOperationsDockState();
}

class _DepartureCompletedOperationsDockState
    extends State<DepartureCompletedOperationsDock> {
  final TextEditingController _unsettledQueryController = TextEditingController();
  final TextEditingController _todayQueryController = TextEditingController();
  final List<String> _debugLines = <String>[];

  DepartureCompletedDockSection _section =
      DepartureCompletedDockSection.unsettled;
  String _unsettledQuery = '';
  String _todayQuery = '';
  String? _selectedUnsettledId;
  String? _selectedTodayId;
  List<PlateModel> _todayResults = const <PlateModel>[];
  bool _todayLoading = false;
  bool _todaySearched = false;
  bool _devModeEnabled = false;

  @override
  void initState() {
    super.initState();
    _devModeEnabled = DevAuth.devModeEnabled.value;
    DevAuth.devModeEnabled.addListener(_handleDevModeChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _log(
        'mounted mode=${widget.modeLabel} area=${widget.area} section=${_section.name} presentation=operations_right_side_dock rail=left',
      );
    });
  }

  @override
  void didUpdateWidget(covariant DepartureCompletedOperationsDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.area.trim() != widget.area.trim()) {
      _selectedUnsettledId = null;
      _selectedTodayId = null;
      _todayResults = const <PlateModel>[];
      _todaySearched = false;
      _todayQueryController.clear();
      _todayQuery = '';
      _log('area_changed from=${oldWidget.area} to=${widget.area} reset=true');
    }
    if (_selectedUnsettledId != null &&
        !widget.unsettledPlates.any((p) => p.id == _selectedUnsettledId)) {
      _selectedUnsettledId = null;
    }
  }

  @override
  void dispose() {
    DevAuth.devModeEnabled.removeListener(_handleDevModeChanged);
    _unsettledQueryController.dispose();
    _todayQueryController.dispose();
    super.dispose();
  }

  void _handleDevModeChanged() {
    final next = DevAuth.devModeEnabled.value;
    if (_devModeEnabled == next || !mounted) return;
    setState(() => _devModeEnabled = next);
    _log('developer_mode enabled=$next');
  }

  void _log(String message) {
    final line = '[DepartureCompletedDock] $message';
    debugPrint(line);
    _debugLines.add(line);
    if (_debugLines.length > 240) {
      _debugLines.removeRange(0, _debugLines.length - 240);
    }
  }

  String get _debugPrintCode {
    return _debugLines.map((line) {
      final encoded = jsonEncode(line).replaceAll(r'$', r'\$');
      return 'debugPrint($encoded);';
    }).join('\n');
  }

  Future<void> _showDeveloperStatus() async {
    final enabled = await DevAuth.isDevModeEnabled();
    if (!mounted || !enabled) return;
    final selectedUnsettled = _selectedUnsettled;
    final selectedToday = _selectedToday;
    _log('status_dialog_open section=${_section.name}');
    await StatusDialog.showSuccess(
      context,
      title: '출차 완료 Side Dock 디버그',
      description: [
        'mode=${widget.modeLabel}',
        'area=${widget.area}',
        'section=${_section.name}',
        'unsettled=${widget.unsettledPlates.length}',
        'unsettledQuery=${_unsettledQuery.trim()}',
        'todayQuery=${_todayQuery.trim()}',
        'todayResults=${_todayResults.length}',
        'selectedUnsettled=${selectedUnsettled?.plateNumber ?? "none"}',
        'selectedToday=${selectedToday?.plateNumber ?? "none"}',
        'motion=operations_side_dock+rail_selection+result_fade+row_selection+footer_slide',
      ].join('\n'),
      copyText: _debugPrintCode,
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: Duration.zero,
      useCommonUi: true,
      awaitManualClose: true,
    );
  }

  PlateModel? get _selectedUnsettled {
    final id = _selectedUnsettledId;
    if (id == null) return null;
    for (final plate in widget.unsettledPlates) {
      if (plate.id == id) return plate;
    }
    return null;
  }

  PlateModel? get _selectedToday {
    final id = _selectedTodayId;
    if (id == null) return null;
    for (final plate in _todayResults) {
      if (plate.id == id) return plate;
    }
    return null;
  }

  void _selectSection(DepartureCompletedDockSection section) {
    if (_section == section) return;
    HapticFeedback.selectionClick();
    setState(() {
      _section = section;
      _selectedUnsettledId = null;
      _selectedTodayId = null;
    });
    _log('rail_selected section=${section.name}');
  }

  void _setUnsettledQuery(String value) {
    final next = value.trim();
    if (_unsettledQuery == next) return;
    setState(() {
      _unsettledQuery = next;
      _selectedUnsettledId = null;
    });
    _log('unsettled_query_changed value=$next');
  }

  void _clearUnsettledQuery() {
    _unsettledQueryController.clear();
    _setUnsettledQuery('');
  }

  void _setTodayQuery(String value) {
    final next = value.trim();
    if (_todayQuery == next) return;
    setState(() {
      _todayQuery = next;
      _selectedTodayId = null;
      if (next.length != 4) {
        _todaySearched = false;
        _todayResults = const <PlateModel>[];
      }
    });
    _log('today_query_changed value=$next');
  }

  void _clearTodayQuery() {
    _todayQueryController.clear();
    setState(() {
      _todayQuery = '';
      _todaySearched = false;
      _todayResults = const <PlateModel>[];
      _selectedTodayId = null;
    });
    _log('today_query_cleared');
  }

  bool get _todayQueryValid => RegExp(r'^\d{4}$').hasMatch(_todayQuery.trim());

  Future<void> _searchToday() async {
    final query = _todayQuery.trim();
    if (!RegExp(r'^\d{4}$').hasMatch(query) || _todayLoading) return;
    setState(() {
      _todayLoading = true;
      _selectedTodayId = null;
    });
    _log('today_search_start query=$query area=${widget.area}');
    try {
      final items = await FirestorePlateRepository().fourDigitDepartureCompletedQuery(
        plateFourDigit: query,
        area: widget.area,
      );
      if (!mounted) return;
      items.sort((a, b) => b.requestTime.compareTo(a.requestTime));
      setState(() {
        _todayResults = items;
        _todaySearched = true;
        _todayLoading = false;
        if (items.length == 1) {
          _selectedTodayId = items.first.id;
        }
      });
      _log('today_search_complete query=$query results=${items.length}');
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() => _todayLoading = false);
      _log('today_search_failed query=$query error=$error stack=$stackTrace');
    }
  }

  Future<void> _refreshUnsettled() async {
    _log('unsettled_refresh_start');
    try {
      await widget.onRefresh();
      _log('unsettled_refresh_complete');
    } catch (error, stackTrace) {
      _log('unsettled_refresh_failed error=$error stack=$stackTrace');
      rethrow;
    }
  }

  Future<void> _pickDate() async {
    final current = DateTime(
      widget.selectedDate.year,
      widget.selectedDate.month,
      widget.selectedDate.day,
    );
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null || !mounted) return;
    widget.onDateChanged(DateTime(picked.year, picked.month, picked.day));
    _selectedUnsettledId = null;
    _log('date_changed value=${_formatDate(picked)}');
  }

  Future<void> _openSelectedStatus() async {
    final plate = _selectedUnsettled;
    if (plate == null) return;
    _log('status_open plate=${plate.plateNumber}');
    final updated = await widget.onOpenStatus(context, plate);
    if (!mounted) return;
    if (updated != null) {
      _selectedUnsettledId = null;
      await _refreshUnsettled();
      if (mounted) setState(() {});
      _log('status_return plate=${plate.plateNumber} changed=true');
    } else {
      _log('status_return plate=${plate.plateNumber} changed=false');
    }
  }

  Future<void> _openSelectedImage() async {
    final plate = _section == DepartureCompletedDockSection.unsettled
        ? _selectedUnsettled
        : _selectedToday;
    if (plate == null) return;
    _log('image_open plate=${plate.plateNumber} section=${_section.name}');
    await widget.onOpenImage(context, plate.plateNumber);
  }

  String _formatDate(DateTime date) {
    const weekdays = <String>['월', '화', '수', '목', '금', '토', '일'];
    final mm = date.month.toString().padLeft(2, '0');
    final dd = date.day.toString().padLeft(2, '0');
    return '${date.year}.$mm.$dd (${weekdays[date.weekday - 1]})';
  }

  String _formatWon(int? amount) {
    if (amount == null) return '—';
    final source = amount.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < source.length; i++) {
      if (i > 0 && (source.length - i) % 3 == 0) buffer.write(',');
      buffer.write(source[i]);
    }
    return '${buffer.toString()}원';
  }

  List<PlateModel> get _filteredUnsettled {
    final query = _unsettledQuery.trim().toLowerCase();
    if (query.isEmpty) return widget.unsettledPlates;
    return widget.unsettledPlates.where((plate) {
      final values = <String>[
        plate.plateNumber,
        plate.plateFourDigit,
        plate.location,
        plate.userName,
        plate.billingType ?? '',
      ].join(' ').toLowerCase();
      return values.contains(query);
    }).toList();
  }

  Widget _buildRail(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final media = MediaQuery.maybeOf(context);
        final metrics = CommonSideRailMetrics.resolve(
          dockHeight: constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : media?.size.height ?? 720,
          textScale: media?.textScaler.scale(1) ?? 1,
        );
        final items = <(
          DepartureCompletedDockSection,
          IconData,
          String,
          String
        )>[
          (
            DepartureCompletedDockSection.unsettled,
            Icons.pending_actions_rounded,
            '미정',
            '미정산',
          ),
          (
            DepartureCompletedDockSection.today,
            Icons.receipt_long_rounded,
            '오늘',
            '오늘 로그',
          ),
          (
            DepartureCompletedDockSection.history,
            Icons.history_rounded,
            '이력',
            '과거 로그',
          ),
        ];
        return CommonSideRailSurface(
          title: '출차',
          metrics: metrics,
          semanticsLabel: '출차 완료 탐색',
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: metrics.actionInsetHorizontal,
              vertical: metrics.actionInsetVertical,
            ),
            child: Column(
              children: [
                for (var index = 0; index < items.length; index++) ...[
                  CommonSideRailActionButton(
                    semanticLabel: items[index].$4,
                    visualLabel: items[index].$3,
                    icon: items[index].$2,
                    selected: _section == items[index].$1,
                    enabled: true,
                    compact: metrics.compact,
                    extent: metrics.minimumButtonExtent,
                    tooltip: items[index].$4,
                    onTap: () => _selectSection(items[index].$1),
                  ),
                  if (index != items.length - 1)
                    SizedBox(height: metrics.actionInsetVertical * 2),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final isUnsettled = _section == DepartureCompletedDockSection.unsettled;
    final isToday = _section == DepartureCompletedDockSection.today;
    final controller = isUnsettled
        ? _unsettledQueryController
        : _todayQueryController;
    final query = isUnsettled ? _unsettledQuery : _todayQuery;

    return Column(
      children: [
        Row(
          children: [
            if (_section != DepartureCompletedDockSection.history) ...[
              Expanded(
                child: OpsDockSearchField(
                  controller: controller,
                  query: query,
                  semanticLabel:
                      isUnsettled ? '미정산 차량 검색' : '오늘 로그 번호판 4자리 검색',
                  onChanged: isUnsettled ? _setUnsettledQuery : _setTodayQuery,
                  onClear:
                      isUnsettled ? _clearUnsettledQuery : _clearTodayQuery,
                  keyboardType: isToday ? TextInputType.number : null,
                  inputFormatters: isToday
                      ? <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ]
                      : null,
                  maxLength: isToday ? 4 : null,
                  onSubmitted: isToday
                      ? (_) {
                          if (_todayQueryValid && !_todayLoading) {
                            _searchToday();
                          }
                        }
                      : null,
                ),
              ),
              const SizedBox(width: 6),
            ] else
              const Spacer(),
            if (isToday)
              CommonIconButton(
                icon: Icons.search_rounded,
                tooltip: '오늘 로그 검색',
                onPressed: _todayQueryValid && !_todayLoading
                    ? _searchToday
                    : null,
                loading: _todayLoading,
                size: 40,
                iconSize: 19,
                haptic: CommonHaptic.selection,
              ),
            if (isUnsettled) ...[
              CommonIconButton(
                icon: Icons.refresh_rounded,
                tooltip: '새로고침',
                onPressed: widget.refreshing ? null : _refreshUnsettled,
                loading: widget.refreshing,
                size: 40,
                iconSize: 19,
                haptic: CommonHaptic.selection,
              ),
              const SizedBox(width: 4),
              CommonIconButton(
                icon: Icons.event_rounded,
                tooltip: '날짜 선택',
                onPressed: _pickDate,
                size: 40,
                iconSize: 19,
                haptic: CommonHaptic.selection,
              ),
            ],
            if (_devModeEnabled) ...[
              const SizedBox(width: 4),
              CommonIconButton(
                icon: Icons.bug_report_rounded,
                tooltip: '디버그 상태',
                onPressed: _showDeveloperStatus,
                size: 40,
                iconSize: 18,
                haptic: CommonHaptic.selection,
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: MediaQuery.maybeOf(context)?.disableAnimations == true
                    ? Duration.zero
                    : CommonUiMotion.selection,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, .08),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: Text(
                  key: ValueKey<DepartureCompletedDockSection>(_section),
                  switch (_section) {
                    DepartureCompletedDockSection.unsettled =>
                      '${_formatDate(widget.selectedDate)} · ${_filteredUnsettled.length}건',
                    DepartureCompletedDockSection.today =>
                      _todaySearched
                          ? '검색 결과 ${_todayResults.length}건'
                          : '오늘 로그',
                    DepartureCompletedDockSection.history => '과거 입차 로그',
                  },
                  style: textTheme.labelSmall?.copyWith(
                    color: tokens.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (_section == DepartureCompletedDockSection.unsettled &&
                !_isToday(widget.selectedDate))
              CommonButton(
                label: '오늘',
                onPressed: () {
                  final now = DateTime.now();
                  final today = DateTime(now.year, now.month, now.day);
                  widget.onDateChanged(today);
                  setState(() => _selectedUnsettledId = null);
                  _log('date_changed source=today value=${_formatDate(today)}');
                },
                variant: CommonButtonVariant.tertiary,
                haptic: CommonHaptic.selection,
                minHeight: 32,
              ),
          ],
        ),
      ],
    );
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  Widget _buildUnsettledWorkspace(BuildContext context) {
    final items = _filteredUnsettled;
    final Widget child;
    if (items.isEmpty) {
      child = _buildEmptyState(
        context,
        icon: _unsettledQuery.trim().isEmpty
            ? Icons.pending_actions_rounded
            : Icons.manage_search_rounded,
        title: _unsettledQuery.trim().isEmpty
            ? '표시할 미정산 차량이 없습니다'
            : '일치하는 미정산 차량이 없습니다',
        actionLabel: _unsettledQuery.trim().isEmpty ? '새로고침' : '검색 초기화',
        actionIcon: _unsettledQuery.trim().isEmpty
            ? Icons.refresh_rounded
            : Icons.search_off_rounded,
        onAction: _unsettledQuery.trim().isEmpty
            ? _refreshUnsettled
            : _clearUnsettledQuery,
      );
    } else {
      final tokens = CommonUiTheme.of(context);
      child = OpsDockListSurface(
        child: RefreshIndicator(
          color: tokens.accent,
          onRefresh: _refreshUnsettled,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: items.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              thickness: 1,
              color: tokens.borderSubtle,
            ),
            itemBuilder: (context, index) {
              final plate = items[index];
              final selected = plate.id == _selectedUnsettledId;
              return OpsDockSelectableRowSurface(
                selected: selected,
                selectionColor: tokens.warning,
                selectedContainer: tokens.warningContainer,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _selectedUnsettledId = selected ? null : plate.id;
                  });
                  _log(
                    'unsettled_row_${selected ? "deselected" : "selected"} plate=${plate.plateNumber}',
                  );
                },
                child: _DeparturePlateRow(
                  plate: plate,
                  selected: selected,
                  statusLabel: '미정산',
                  statusColor: tokens.warning,
                  detail: selected
                      ? <(String, String)>[
                          (
                            '위치',
                            plate.location.trim().isEmpty ? '—' : plate.location,
                          ),
                          ('요청', _formatDateTime(plate.requestTime)),
                          (
                            '정산 유형',
                            (plate.billingType ?? '').trim().isEmpty
                                ? '—'
                                : plate.billingType!.trim(),
                          ),
                          (
                            '담당자',
                            plate.userName.trim().isEmpty
                                ? '—'
                                : plate.userName.trim(),
                          ),
                        ]
                      : const <(String, String)>[],
                ),
              );
            },
          ),
        ),
      );
    }
    return OpsDockResultSwitcher(
      child: KeyedSubtree(
        key: ValueKey<String>(
          'unsettled-${items.length}-${_unsettledQuery.trim()}',
        ),
        child: child,
      ),
    );
  }

  Widget _buildTodayWorkspace(BuildContext context) {
    final Widget child;
    if (!_todaySearched) {
      child = _buildEmptyState(
        context,
        icon: Icons.receipt_long_rounded,
        title: '오늘 로그',
      );
    } else if (_todayResults.isEmpty) {
      child = _buildEmptyState(
        context,
        icon: Icons.manage_search_rounded,
        title: '검색 결과가 없습니다',
        actionLabel: '검색 초기화',
        actionIcon: Icons.search_off_rounded,
        onAction: _clearTodayQuery,
      );
    } else {
      final tokens = CommonUiTheme.of(context);
      child = OpsDockListSurface(
        child: ListView.separated(
          padding: EdgeInsets.zero,
          itemCount: _todayResults.length,
          separatorBuilder: (_, __) => Divider(
            height: 1,
            thickness: 1,
            color: tokens.borderSubtle,
          ),
          itemBuilder: (context, index) {
            final plate = _todayResults[index];
            final selected = plate.id == _selectedTodayId;
            return OpsDockSelectableRowSurface(
              selected: selected,
              selectionColor: tokens.accent,
              selectedContainer: tokens.accentContainer,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _selectedTodayId = selected ? null : plate.id);
                _log(
                  'today_row_${selected ? "deselected" : "selected"} plate=${plate.plateNumber}',
                );
              },
              child: _DeparturePlateRow(
                plate: plate,
                selected: selected,
                statusLabel: plate.isLockedFee ? '정산' : '출차',
                statusColor: plate.isLockedFee ? tokens.success : tokens.accent,
                detail: selected
                    ? <(String, String)>[
                        (
                          '위치',
                          plate.location.trim().isEmpty ? '—' : plate.location,
                        ),
                        ('요청', _formatDateTime(plate.requestTime)),
                        ('확정 요금', _formatWon(plate.lockedFeeAmount)),
                        (
                          '결제 수단',
                          (plate.paymentMethod ?? '').trim().isEmpty
                              ? '—'
                              : plate.paymentMethod!.trim(),
                        ),
                      ]
                    : const <(String, String)>[],
                trailingContent: selected
                    ? _TodayLogPreview(
                        logs: plate.logs ?? const <PlateLogModel>[],
                      )
                    : null,
              ),
            );
          },
        ),
      );
    }
    return OpsDockResultSwitcher(
      child: KeyedSubtree(
        key: ValueKey<String>(
          'today-${_todaySearched ? _todayResults.length : -1}-${_todayQuery.trim()}',
        ),
        child: child,
      ),
    );
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mi = local.minute.toString().padLeft(2, '0');
    return '$mm.$dd $hh:$mi';
  }

  Widget _buildHistoryWorkspace(BuildContext context) {
    return DepartureCompletedHistoryWorkspace(
      division: widget.division,
      area: widget.area,
      onOpenImage: widget.onOpenImage,
      onDebug: _log,
    );
  }

  Widget _buildEmptyState(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? actionLabel,
    IconData? actionIcon,
    CommonAction? onAction,
  }) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: tokens.surfaceRaised,
                borderRadius: BorderRadius.circular(CommonUiShapes.control),
                border: Border.all(color: tokens.borderSubtle),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: tokens.iconSecondary, size: 22),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: CommonButton(
                  label: actionLabel,
                  icon: actionIcon,
                  onPressed: onAction,
                  variant: CommonButtonVariant.secondary,
                  haptic: CommonHaptic.selection,
                  minHeight: 42,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    final selected = _section == DepartureCompletedDockSection.unsettled
        ? _selectedUnsettled
        : _section == DepartureCompletedDockSection.today
            ? _selectedToday
            : null;
    if (selected == null) {
      return const SizedBox.shrink(
        key: ValueKey<String>('departure-footer-empty'),
      );
    }
    return OpsDockContextFooter(
      key: ValueKey<String>('departure-footer-${_section.name}-${selected.id}'),
      children: [
        Expanded(
          child: CommonButton(
            label: '사진',
            icon: Icons.photo_rounded,
            onPressed: _openSelectedImage,
            variant: CommonButtonVariant.secondary,
            haptic: CommonHaptic.selection,
          ),
        ),
        if (_section == DepartureCompletedDockSection.unsettled) ...[
          const SizedBox(width: 8),
          Expanded(
            child: CommonButton(
              label: '상태 처리',
              icon: Icons.tune_rounded,
              onPressed: _openSelectedStatus,
              haptic: CommonHaptic.selection,
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final workspace = switch (_section) {
      DepartureCompletedDockSection.unsettled => _buildUnsettledWorkspace(context),
      DepartureCompletedDockSection.today => _buildTodayWorkspace(context),
      DepartureCompletedDockSection.history => _buildHistoryWorkspace(context),
    };

    return ParkingStatusSideDockFrame(
      title: '출차 완료',
      subtitle: '${widget.modeLabel} · ${widget.area.trim().isEmpty ? "지역 미지정" : widget.area.trim()}',
      icon: Icons.exit_to_app_rounded,
      onClose: widget.onClose,
      leadingRail: _buildRail(context),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 2, 2, 8),
                child: _buildToolbar(context),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  layoutBuilder: (currentChild, previousChildren) => Stack(
                    fit: StackFit.expand,
                    children: [
                      ...previousChildren,
                      if (currentChild != null) currentChild,
                    ],
                  ),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(.035, 0),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey<DepartureCompletedDockSection>(_section),
                    child: workspace,
                  ),
                ),
              ),
              OpsDockContextFooterTransition(child: _buildFooter()),
            ],
          ),
          OpsDockLoadingOverlay(
            loading: _section == DepartureCompletedDockSection.today &&
                _todayLoading,
          ),
        ],
      ),
    );
  }
}

class _DeparturePlateRow extends StatelessWidget {
  const _DeparturePlateRow({
    required this.plate,
    required this.selected,
    required this.statusLabel,
    required this.statusColor,
    required this.detail,
    this.trailingContent,
  });

  final PlateModel plate;
  final bool selected;
  final String statusLabel;
  final Color statusColor;
  final List<(String, String)> detail;
  final Widget? trailingContent;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plate.plateNumber,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    plate.location.trim().isEmpty ? plate.area : plate.location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelSmall?.copyWith(
                      color: tokens.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AnimatedSwitcher(
              duration: MediaQuery.maybeOf(context)?.disableAnimations == true
                  ? Duration.zero
                  : CommonUiMotion.selection,
              child: selected
                  ? Icon(
                      Icons.check_circle_rounded,
                      key: const ValueKey<String>('selected'),
                      size: 19,
                      color: statusColor,
                    )
                  : Row(
                      key: const ValueKey<String>('status'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          statusLabel,
                          style: textTheme.labelSmall?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w900,
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
          ],
        ),
        if (selected && detail.isNotEmpty) ...[
          const SizedBox(height: 10),
          Divider(height: 1, color: tokens.borderSubtle),
          const SizedBox(height: 8),
          for (final entry in detail)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(
                      entry.$1,
                      style: textTheme.labelSmall?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      entry.$2,
                      style: textTheme.labelSmall?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (selected && trailingContent != null) ...[
          const SizedBox(height: 8),
          trailingContent!,
        ],
      ],
    );
  }
}

class _TodayLogPreview extends StatelessWidget {
  const _TodayLogPreview({required this.logs});

  final List<PlateLogModel> logs;

  String _time(DateTime date) {
    final local = date.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final sorted = List<PlateLogModel>.of(logs)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final visible = sorted.take(4).toList();
    if (visible.isEmpty) {
      return Text(
        '기록 없음',
        style: textTheme.labelSmall?.copyWith(
          color: tokens.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface.withOpacity(.72),
        borderRadius: BorderRadius.circular(CommonUiShapes.control),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Column(
        children: [
          for (var index = 0; index < visible.length; index++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              child: Row(
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 15,
                    color: tokens.iconSecondary,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      visible[index].action.trim().isEmpty
                          ? '기록'
                          : visible[index].action.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _time(visible[index].timestamp),
                    style: textTheme.labelSmall?.copyWith(
                      color: tokens.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (index != visible.length - 1)
              Divider(height: 1, color: tokens.borderSubtle),
          ],
        ],
      ),
    );
  }
}
