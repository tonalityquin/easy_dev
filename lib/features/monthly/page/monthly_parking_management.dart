import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../app/utils/status_dialog.dart';
import '../../../design_system/common_ui/common_ui_components.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../../shared/plate/domain/repositories/plate_repository.dart';
import '../../../shared/plate/domain/services/plate_status_record.dart';
import '../../../shared/secondary/application/secondary_monthly_workspace_state.dart';
import '../../../shared/secondary/widgets/ops_console_widgets.dart';
import '../../account/applications/user_state.dart';
import '../../dev/application/area_state.dart';
import '../../selector/application/dev_auth.dart';
import '../application/monthly_area_resolver.dart';
import '../domain/monthly_parking_options.dart';
import 'widgets/monthly_common_ui.dart';

class MonthlyParkingManagement extends StatefulWidget {
  const MonthlyParkingManagement({super.key});

  @override
  State<MonthlyParkingManagement> createState() =>
      _MonthlyParkingManagementState();
}

enum _MonthlyFilter { all, active, expiringSoon, expired, memo }

enum _MonthlySort { updatedDesc, endDateAsc, plateAsc, amountDesc }

enum _MonthlyStatus { active, expiringSoon, expired, unknown }

class _MonthlyParkingManagementState extends State<MonthlyParkingManagement> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final List<String> _debugLines = <String>[];
  String _query = '';
  _MonthlyFilter _filter = _MonthlyFilter.all;
  _MonthlySort _sort = _MonthlySort.updatedDesc;
  String? _selectedDocId;
  _MonthlyPlateVM? _selectedHydratedItem;
  List<Map<String, dynamic>> _records = const <Map<String, dynamic>>[];
  String _loadedArea = '';
  String? _pendingArea;
  bool _loading = false;
  bool _selectionClearScheduled = false;
  bool _devModeEnabled = false;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _devModeEnabled = DevAuth.devModeEnabled.value;
    DevAuth.devModeEnabled.addListener(_handleDevModeChanged);
    _log('mounted devMode=$_devModeEnabled uiProfile=user_management_ops rowInteraction=select_expand_footer motion=ops_common');
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final enabled = await DevAuth.isDevModeEnabled();
      if (!mounted) return;
      if (_devModeEnabled != enabled) {
        setState(() => _devModeEnabled = enabled);
      }
      _log('developer_mode_resolved enabled=$enabled');
    });
  }

  @override
  void dispose() {
    DevAuth.devModeEnabled.removeListener(_handleDevModeChanged);
    _log('disposed selected=${_selectedDocId ?? '-'}');
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _handleDevModeChanged() {
    if (!mounted) return;
    final enabled = DevAuth.devModeEnabled.value;
    if (_devModeEnabled == enabled) return;
    setState(() => _devModeEnabled = enabled);
    _log('developer_mode_changed enabled=$enabled');
  }

  void _log(String message) {
    final normalized = message.trim();
    if (normalized.isEmpty) return;
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    String three(int value) => value.toString().padLeft(3, '0');
    final stamp =
        '${two(now.hour)}:${two(now.minute)}:${two(now.second)}.${three(now.millisecond)}';
    final line = '[$stamp] [MonthlyParkingManagement] $normalized';
    _debugLines.add(line);
    if (_debugLines.length > 240) {
      _debugLines.removeRange(0, _debugLines.length - 240);
    }
    debugPrint(line);
  }

  String _dartStringLiteral(String value) {
    return jsonEncode(value).replaceAll(r'$', r'\$');
  }

  String get _debugPrintCode {
    if (_debugLines.isEmpty) {
      return 'debugPrint(${_dartStringLiteral('[MonthlyParkingManagement] 기록된 로그가 없습니다.')});';
    }
    return _debugLines
        .map((line) => 'debugPrint(${_dartStringLiteral(line)});')
        .join('\n');
  }

  Future<void> _showDeveloperStatusDialog() async {
    final enabled = await DevAuth.isDevModeEnabled();
    if (!mounted || !enabled) return;
    final allItems = _toItems(_records);
    final visibleItems = _filteredSorted(allItems);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _log(
      'developer_status_dialog_open area=${_loadedArea.isEmpty ? '-' : _loadedArea} records=${allItems.length} visible=${visibleItems.length} selected=${_selectedDocId ?? '-'} filter=${_filter.name} sort=${_sort.name} loading=$_loading error=${_loadError != null} reduceMotion=$reduceMotion uiProfile=user_management_ops motion=ops_common',
    );
    await StatusDialog.showSuccess(
      context,
      title: '정기 주차 Management 디버그',
      description:
          'area=${_loadedArea.isEmpty ? '-' : _loadedArea}\nrecords=${allItems.length}\nvisible=${visibleItems.length}\nselected=${_selectedDocId ?? '-'}\nfilter=${_filter.name}\nsort=${_sort.name}\nreduceMotion=$reduceMotion',
      copyText: _debugPrintCode,
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: Duration.zero,
      useCommonUi: true,
      awaitManualClose: true,
    );
  }

  DateTime? _parseDate(String value) {
    try {
      final parsed = DateTime.parse(value.trim());
      return DateTime(parsed.year, parsed.month, parsed.day);
    } catch (_) {
      return null;
    }
  }

  int? _daysLeft(String endDateText) {
    final end = _parseDate(endDateText);
    if (end == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return end.difference(today).inDays;
  }

  bool _hasMemo(Map<String, dynamic> data) {
    final customStatus = (data['customStatus'] ?? '').toString().trim();
    return customStatus.isNotEmpty && customStatus != '없음';
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _paymentCount(Map<String, dynamic> data) {
    final explicit = _asInt(data['paymentCount']);
    if (explicit > 0) return explicit;
    final raw = data['payment_history'];
    if (raw is List) return raw.length;
    return 0;
  }

  DateTime? _dateTimeValue(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    try {
      final dynamic dynamicValue = value;
      final converted = dynamicValue.toDate();
      if (converted is DateTime) return converted;
    } catch (_) {}
    if (value is int) {
      try {
        if (value > 100000000000) {
          return DateTime.fromMillisecondsSinceEpoch(value);
        }
        return DateTime.fromMillisecondsSinceEpoch(value * 1000);
      } catch (_) {
        return null;
      }
    }
    return DateTime.tryParse(value.toString().trim());
  }

  _MonthlyStatus _statusOf(int? daysLeft) {
    if (daysLeft == null) return _MonthlyStatus.unknown;
    if (daysLeft < 0) return _MonthlyStatus.expired;
    if (daysLeft <= 7) return _MonthlyStatus.expiringSoon;
    return _MonthlyStatus.active;
  }

  _MonthlyPlateVM _toItem(Map<String, dynamic> raw) {
    final data = Map<String, dynamic>.from(raw);
    final docId = (data['docId'] ?? '').toString();
    final docParts = docId.split('_');
    final plateNumber =
        (data['plateNumber'] ?? (docParts.isEmpty ? '' : docParts.first))
            .toString();
    final endDate = (data['endDate'] ?? '').toString();
    final daysLeft = _daysLeft(endDate);
    return _MonthlyPlateVM(
      docId: docId,
      data: data,
      plateNumber: plateNumber,
      countType: (data['countType'] ?? '').toString(),
      regularType: (data['regularType'] ?? '').toString(),
      amount: _asInt(data['regularAmount']),
      duration:
          _asInt(data['regularDurationValue'] ?? data['regularDurationHours']),
      periodUnit: (data['periodUnit'] ?? '월').toString(),
      startDate: (data['startDate'] ?? '').toString(),
      endDate: endDate,
      customStatus: (data['customStatus'] ?? '').toString(),
      paymentCount: _paymentCount(data),
      daysLeft: daysLeft,
      updatedAt: _dateTimeValue(data['updatedAt']),
      hasMemo: data['hasMemo'] == true || _hasMemo(data),
      status: _statusOf(daysLeft),
    );
  }

  _MonthlyPlateVM _toItemFromSourceRecord(PlateStatusRecord record) {
    final data = record.toMap();
    final docId = record.docId ?? '';
    data['docId'] = docId;
    data['plateNumber'] = docId.split('_').first;
    data['updatedAt'] = record.updatedAt ?? record.updatedAtRaw;
    data['paymentCount'] = record.paymentHistory.length;
    return _toItem(data);
  }

  List<_MonthlyPlateVM> _toItems(List<Map<String, dynamic>> records) {
    return records.map(_toItem).toList(growable: false);
  }

  List<_MonthlyPlateVM> _filteredSorted(List<_MonthlyPlateVM> items) {
    final query = _query.trim().toLowerCase();
    final filtered = items.where((item) {
      final queryMatch = query.isEmpty ||
          item.plateNumber.toLowerCase().contains(query) ||
          item.countType.toLowerCase().contains(query) ||
          item.regularType.toLowerCase().contains(query) ||
          item.customStatus.toLowerCase().contains(query);
      if (!queryMatch) return false;
      switch (_filter) {
        case _MonthlyFilter.all:
          return true;
        case _MonthlyFilter.active:
          return item.status == _MonthlyStatus.active;
        case _MonthlyFilter.expiringSoon:
          return item.status == _MonthlyStatus.expiringSoon;
        case _MonthlyFilter.expired:
          return item.status == _MonthlyStatus.expired;
        case _MonthlyFilter.memo:
          return item.hasMemo;
      }
    }).toList();

    switch (_sort) {
      case _MonthlySort.updatedDesc:
        filtered.sort((a, b) {
          final av = a.updatedAt?.millisecondsSinceEpoch ?? 0;
          final bv = b.updatedAt?.millisecondsSinceEpoch ?? 0;
          return bv.compareTo(av);
        });
        break;
      case _MonthlySort.endDateAsc:
        filtered.sort(
          (a, b) =>
              (a.daysLeft ?? (1 << 30)).compareTo(b.daysLeft ?? (1 << 30)),
        );
        break;
      case _MonthlySort.plateAsc:
        filtered.sort((a, b) => a.plateNumber.compareTo(b.plateNumber));
        break;
      case _MonthlySort.amountDesc:
        filtered.sort((a, b) => b.amount.compareTo(a.amount));
        break;
    }

    return filtered;
  }

  _MonthlySummary _summaryOf(List<_MonthlyPlateVM> items) {
    return _MonthlySummary(
      total: items.length,
      active: items.where((e) => e.status == _MonthlyStatus.active).length,
      expiringSoon:
          items.where((e) => e.status == _MonthlyStatus.expiringSoon).length,
      expired: items.where((e) => e.status == _MonthlyStatus.expired).length,
      memo: items.where((e) => e.hasMemo).length,
    );
  }

  void _scheduleLoadIfNeeded(String area) {
    final safeArea = area.trim();
    if (_loadedArea == safeArea || _pendingArea == safeArea || _loading) return;
    _pendingArea = safeArea;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _pendingArea ?? safeArea;
      _pendingArea = null;
      unawaited(_loadMonthlyPlateView(target));
    });
  }

  Future<void> _loadMonthlyPlateView(String area) async {
    final safeArea = area.trim();
    if (safeArea.isEmpty) {
      if (!mounted) return;
      setState(() {
        _records = const <Map<String, dynamic>>[];
        _loadedArea = '';
        _selectedDocId = null;
        _selectedHydratedItem = null;
        _loading = false;
        _loadError = null;
      });
      _log('load_skipped reason=area_empty');
      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    _log('load_started area=$safeArea');

    try {
      final records = await context
          .read<PlateRepository>()
          .fetchMonthlyPlateStatusView(area: safeArea);
      if (!mounted) return;
      final selected = _selectedDocId;
      final selectedExists = selected == null ||
          records.any((record) => (record['docId'] ?? '').toString() == selected);
      setState(() {
        _records = records;
        _loadedArea = safeArea;
        _loading = false;
        if (!selectedExists) {
          _selectedDocId = null;
          _selectedHydratedItem = null;
        } else {
          _selectedHydratedItem = null;
        }
      });
      _log(
        'load_completed area=$safeArea count=${records.length} selectionPreserved=$selectedExists',
      );
      final selectedId = _selectedDocId;
      if (selectedId != null) {
        for (final record in records) {
          if ((record['docId'] ?? '').toString() == selectedId) {
            unawaited(_hydrateSelected(_toItem(record)));
            break;
          }
        }
      }
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() {
        _records = const <Map<String, dynamic>>[];
        _loadedArea = safeArea;
        _selectedDocId = null;
        _selectedHydratedItem = null;
        _loading = false;
        _loadError = error;
      });
      _log('load_failed area=$safeArea error=$error');
      _log('load_stack=$stackTrace');
      showMonthlyCommonMessage(
        context,
        '정기 주차 목록을 불러오지 못했습니다.',
        tone: MonthlyCommonMessageTone.danger,
      );
    }
  }

  Future<void> _refreshMonthlyPlateView() async {
    final area = MonthlyAreaResolver.readCurrentArea(context);
    _log('refresh_requested area=$area');
    await _loadMonthlyPlateView(area);
  }

  Future<_MonthlyPlateVM> _hydrateFromSource(_MonthlyPlateVM item) async {
    final area = (item.data['area'] ?? _loadedArea).toString().trim();
    if (item.plateNumber.trim().isEmpty || area.isEmpty) return item;
    try {
      final record = await context.read<PlateRepository>().fetchMonthlyPlateStatus(
            plateNumber: item.plateNumber,
            area: area,
          );
      if (record == null) {
        _log('hydrate_missing doc=${item.docId} plate=${item.plateNumber}');
        return item;
      }
      _log('hydrate_completed doc=${item.docId} plate=${item.plateNumber}');
      return _toItemFromSourceRecord(record);
    } catch (error) {
      _log('hydrate_failed doc=${item.docId} error=$error');
      return item;
    }
  }

  Future<void> _hydrateSelected(_MonthlyPlateVM item) async {
    final source = await _hydrateFromSource(item);
    if (!mounted || _selectedDocId != item.docId) return;
    setState(() => _selectedHydratedItem = source);
    _log(
      'selection_hydrated doc=${item.docId} payments=${source.paymentCount} history=${_paymentHistoryCount(source.data)}',
    );
  }

  int _paymentHistoryCount(Map<String, dynamic> data) {
    final raw = data['payment_history'];
    return raw is List ? raw.length : 0;
  }

  void _openAddWorkspace() {
    FocusScope.of(context).unfocus();
    _log('add_workspace_open');
    context.read<SecondaryMonthlyWorkspaceState>().openCreate(
          source: 'monthly_management_create',
        );
  }

  Future<void> _openEditWorkspace(_MonthlyPlateVM item) async {
    FocusScope.of(context).unfocus();
    _log('edit_workspace_open doc=${item.docId} plate=${item.plateNumber}');
    final sourceItem = await _hydrateFromSource(item);
    if (!mounted) return;
    context.read<SecondaryMonthlyWorkspaceState>().openEdit(
          docId: sourceItem.docId,
          initialData: sourceItem.data,
          source: 'monthly_management_edit',
        );
  }

  Future<void> _openPaymentWorkspace(_MonthlyPlateVM item) async {
    FocusScope.of(context).unfocus();
    _log('payment_workspace_open doc=${item.docId} plate=${item.plateNumber}');
    final sourceItem = await _hydrateFromSource(item);
    if (!mounted) return;
    context.read<SecondaryMonthlyWorkspaceState>().openPayment(
          docId: sourceItem.docId,
          initialData: sourceItem.data,
          source: 'monthly_management_payment',
        );
  }

  Future<void> _deleteItem(_MonthlyPlateVM item) async {
    _log('delete_confirm_open doc=${item.docId} plate=${item.plateNumber}');
    final ok = await showMonthlyCommonConfirmation(
      context: context,
      title: '정기권 삭제',
      message: '${item.plateNumber} 정기 주차 정보를 삭제합니다. 삭제 후에는 복구할 수 없습니다.',
      confirmLabel: '삭제',
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );

    if (!ok || !mounted) {
      _log('delete_cancelled doc=${item.docId}');
      return;
    }

    try {
      _log('delete_started doc=${item.docId}');
      await context
          .read<PlateRepository>()
          .deleteMonthlyPlateStatus(documentId: item.docId);
      if (!mounted) return;
      setState(() {
        if (_selectedDocId == item.docId) {
          _selectedDocId = null;
          _selectedHydratedItem = null;
        }
      });
      _log('delete_completed doc=${item.docId}');
      showMonthlyCommonMessage(
        context,
        '정기 주차 정보가 삭제되었습니다.',
        tone: MonthlyCommonMessageTone.success,
      );
      await _refreshMonthlyPlateView();
    } catch (error, stackTrace) {
      if (!mounted) return;
      _log('delete_failed doc=${item.docId} error=$error');
      _log('delete_stack=$stackTrace');
      showMonthlyCommonMessage(
        context,
        '삭제에 실패했습니다.',
        tone: MonthlyCommonMessageTone.danger,
      );
    }
  }

  void _setQuery(String value) {
    if (_query == value) return;
    setState(() => _query = value);
    _log('query_changed length=${value.trim().length}');
  }

  void _clearQuery() {
    if (_query.isEmpty && _searchController.text.isEmpty) return;
    _searchController.clear();
    setState(() => _query = '');
    _log('query_cleared');
  }

  void _setFilter(_MonthlyFilter filter) {
    if (_filter == filter) return;
    unawaited(HapticFeedback.selectionClick());
    setState(() => _filter = filter);
    _log('filter_changed value=${filter.name}');
  }

  void _cycleSort() {
    final values = _MonthlySort.values;
    final next = values[(values.indexOf(_sort) + 1) % values.length];
    unawaited(HapticFeedback.selectionClick());
    setState(() => _sort = next);
    _log('sort_changed value=${next.name}');
  }


  void _toggleSelection(_MonthlyPlateVM item) {
    unawaited(HapticFeedback.selectionClick());
    final wasSelected = _selectedDocId == item.docId;
    setState(() {
      _selectedDocId = wasSelected ? null : item.docId;
      _selectedHydratedItem = null;
    });
    _log(
      '${wasSelected ? 'row_deselected' : 'row_selected'} doc=${item.docId} plate=${item.plateNumber} status=${item.status.name} payments=${item.paymentCount}',
    );
    if (!wasSelected) {
      unawaited(_hydrateSelected(item));
    }
  }

  void _scheduleSelectionValidation(List<_MonthlyPlateVM> visibleItems) {
    final selected = _selectedDocId;
    if (selected == null) return;
    if (visibleItems.any((item) => item.docId == selected)) return;
    if (_selectionClearScheduled) return;
    _selectionClearScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _selectionClearScheduled = false;
      if (!mounted || _selectedDocId != selected) return;
      setState(() {
        _selectedDocId = null;
        _selectedHydratedItem = null;
      });
      _log('selection_cleared reason=filtered_or_scope_changed doc=$selected');
    });
  }

  String _sortLabel(_MonthlySort sort) {
    return switch (sort) {
      _MonthlySort.updatedDesc => '최근 수정',
      _MonthlySort.endDateAsc => '만료 임박',
      _MonthlySort.plateAsc => '차량번호',
      _MonthlySort.amountDesc => '요금 높은순',
    };
  }

  Widget _buildToolbar(
    BuildContext context, {
    required bool refreshing,
  }) {
    return Row(
      children: [
        Expanded(
          child: OpsDockSearchField(
            controller: _searchController,
            query: _query,
            semanticLabel: '정기 주차 검색',
            onChanged: _setQuery,
            onClear: _clearQuery,
          ),
        ),
        const SizedBox(width: 6),
        CommonIconButton(
          icon: Icons.refresh_rounded,
          tooltip: '새로고침',
          onPressed: refreshing ? null : _refreshMonthlyPlateView,
          loading: refreshing,
          haptic: CommonHaptic.selection,
          size: 40,
          iconSize: 19,
        ),
        const SizedBox(width: 4),
        CommonIconButton(
          icon: Icons.add_rounded,
          tooltip: '정기 주차 등록',
          onPressed: _openAddWorkspace,
          haptic: CommonHaptic.selection,
          size: 40,
          iconSize: 19,
        ),
      ],
    );
  }

  Widget _buildStatusSegments(
    BuildContext context, {
    required _MonthlySummary summary,
  }) {
    final tokens = CommonUiTheme.of(context);
    return OpsDockStatusSegments<_MonthlyFilter>(
      selected: _filter,
      items: [
        OpsDockStatusSegmentItem<_MonthlyFilter>(
          value: _MonthlyFilter.all,
          label: '전체',
          count: summary.total,
          color: tokens.accent,
        ),
        OpsDockStatusSegmentItem<_MonthlyFilter>(
          value: _MonthlyFilter.active,
          label: '정상',
          count: summary.active,
          color: tokens.success,
        ),
        OpsDockStatusSegmentItem<_MonthlyFilter>(
          value: _MonthlyFilter.expiringSoon,
          label: 'D-7',
          count: summary.expiringSoon,
          color: tokens.warning,
        ),
        OpsDockStatusSegmentItem<_MonthlyFilter>(
          value: _MonthlyFilter.expired,
          label: '만료',
          count: summary.expired,
          color: tokens.danger,
        ),
        OpsDockStatusSegmentItem<_MonthlyFilter>(
          value: _MonthlyFilter.memo,
          label: '메모',
          count: summary.memo,
          color: tokens.info,
        ),
      ],
      onSelected: _setFilter,
    );
  }

  Widget _buildInfoRow(
    BuildContext context, {
    required int visibleCount,
    required String currentArea,
  }) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Row(
      children: [
        Expanded(
          child: Text(
            '$visibleCount건 표시${currentArea.isEmpty ? '' : ' · $currentArea'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (_devModeEnabled) ...[
          CommonIconButton(
            icon: Icons.bug_report_outlined,
            tooltip: '디버그 상태',
            onPressed: _showDeveloperStatusDialog,
            haptic: CommonHaptic.selection,
            size: 30,
            iconSize: 15,
          ),
          const SizedBox(width: 3),
        ],
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _cycleSort,
            borderRadius: BorderRadius.circular(CommonUiShapes.control),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.sort_rounded,
                    size: 14,
                    color: tokens.iconSecondary,
                  ),
                  const SizedBox(width: 4),
                  AnimatedSwitcher(
                    duration:
                        reduceMotion ? Duration.zero : CommonUiMotion.selection,
                    switchInCurve: CommonUiMotion.enter,
                    switchOutCurve: CommonUiMotion.exit,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, .12),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: Text(
                      _sortLabel(_sort),
                      key: ValueKey<_MonthlySort>(_sort),
                      style: textTheme.labelSmall?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(
    BuildContext context, {
    required bool noRecords,
    required bool hasError,
  }) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final queryActive = _query.trim().isNotEmpty;
    final filtered = _filter != _MonthlyFilter.all;

    late final IconData icon;
    late final String title;
    Widget? action;

    if (hasError) {
      icon = Icons.error_outline_rounded;
      title = '목록을 불러오지 못했습니다';
      action = CommonButton(
        label: '다시 시도',
        icon: Icons.refresh_rounded,
        onPressed: _refreshMonthlyPlateView,
        variant: CommonButtonVariant.secondary,
        haptic: CommonHaptic.selection,
        minHeight: 42,
      );
    } else if (noRecords) {
      icon = Icons.local_parking_rounded;
      title = '등록된 정기 주차가 없습니다';
      action = CommonButton(
        label: '정기 주차 등록',
        icon: Icons.add_rounded,
        onPressed: _openAddWorkspace,
        haptic: CommonHaptic.selection,
        minHeight: 42,
      );
    } else if (queryActive) {
      icon = Icons.manage_search_rounded;
      title = '일치하는 정기 주차가 없습니다';
      action = CommonButton(
        label: '검색 초기화',
        icon: Icons.search_off_rounded,
        onPressed: _clearQuery,
        variant: CommonButtonVariant.secondary,
        haptic: CommonHaptic.selection,
        minHeight: 42,
      );
    } else if (filtered) {
      icon = Icons.local_parking_outlined;
      title = switch (_filter) {
        _MonthlyFilter.active => '정상 정기 주차가 없습니다',
        _MonthlyFilter.expiringSoon => 'D-7 정기 주차가 없습니다',
        _MonthlyFilter.expired => '만료된 정기 주차가 없습니다',
        _MonthlyFilter.memo => '메모가 있는 정기 주차가 없습니다',
        _MonthlyFilter.all => '표시할 정기 주차가 없습니다',
      };
      action = CommonButton(
        label: '전체 보기',
        icon: Icons.local_parking_rounded,
        onPressed: () => _setFilter(_MonthlyFilter.all),
        variant: CommonButtonVariant.secondary,
        haptic: CommonHaptic.selection,
        minHeight: 42,
      );
    } else {
      icon = Icons.local_parking_outlined;
      title = '표시할 정기 주차가 없습니다';
    }

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
              child: Icon(
                icon,
                color: tokens.iconSecondary,
                size: 22,
              ),
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
            if (action != null) ...[
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: action,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildList(
    BuildContext context, {
    required List<_MonthlyPlateVM> items,
  }) {
    final tokens = CommonUiTheme.of(context);
    return OpsDockListSurface(
      child: RefreshIndicator(
        onRefresh: _refreshMonthlyPlateView,
        color: tokens.accent,
        child: ListView.separated(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: items.length,
          separatorBuilder: (context, index) => Divider(
            height: 1,
            thickness: 1,
            color: tokens.borderSubtle,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            final selected = _selectedDocId == item.docId;
            final hydrated = _selectedHydratedItem;
            final displayItem = selected && hydrated?.docId == item.docId
                ? hydrated!
                : item;
            return _MonthlyDockRow(
              key: ValueKey<String>(item.docId),
              item: displayItem,
              selected: selected,
              onTap: () => _toggleSelection(item),
            );
          },
        ),
      ),
    );
  }

  Widget _buildContextFooter(
    BuildContext context, {
    required _MonthlyPlateVM? selectedItem,
  }) {
    if (selectedItem == null) {
      return const SizedBox.shrink(key: ValueKey<String>('footer_none'));
    }
    return OpsDockContextFooter(
      key: ValueKey<String>('footer_${selectedItem.docId}'),
      children: [
        Expanded(
          child: CommonButton(
            label: '수정',
            icon: Icons.edit_rounded,
            onPressed: () => _openEditWorkspace(selectedItem),
            variant: CommonButtonVariant.secondary,
            haptic: CommonHaptic.selection,
            minHeight: 42,
            expand: true,
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: CommonButton(
            label: '결제',
            icon: Icons.payments_rounded,
            onPressed: () => _openPaymentWorkspace(selectedItem),
            haptic: CommonHaptic.selection,
            minHeight: 42,
            expand: true,
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: CommonButton(
            label: '삭제',
            icon: Icons.delete_outline_rounded,
            onPressed: () => _deleteItem(selectedItem),
            variant: CommonButtonVariant.destructive,
            haptic: CommonHaptic.medium,
            minHeight: 42,
            expand: true,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final userArea = context.select<UserState, String>(
      (state) => state.currentArea.trim(),
    );
    final areaStateArea = context.select<AreaState, String>(
      (state) => state.currentArea.trim(),
    );
    final currentArea = MonthlyAreaResolver.resolve(
      userArea: userArea,
      areaStateArea: areaStateArea,
    );

    _scheduleLoadIfNeeded(currentArea);

    final allItems = _toItems(_records);
    final summary = _summaryOf(allItems);
    final visibleItems = _filteredSorted(allItems);
    _MonthlyPlateVM? selectedItem;
    for (final item in visibleItems) {
      if (item.docId == _selectedDocId) {
        final hydrated = _selectedHydratedItem;
        selectedItem = hydrated?.docId == item.docId ? hydrated : item;
        break;
      }
    }
    final initialLoading = _loading && _records.isEmpty && _loadError == null;
    final refreshing = _loading && !initialLoading;

    _scheduleSelectionValidation(visibleItems);

    final listBody = initialLoading
        ? const SizedBox.expand(key: ValueKey<String>('initial_loading'))
        : _loadError != null && _records.isEmpty
            ? KeyedSubtree(
                key: const ValueKey<String>('load_error'),
                child: _buildEmptyState(
                  context,
                  noRecords: true,
                  hasError: true,
                ),
              )
            : _records.isEmpty
                ? KeyedSubtree(
                    key: const ValueKey<String>('empty_records'),
                    child: _buildEmptyState(
                      context,
                      noRecords: true,
                      hasError: false,
                    ),
                  )
                : visibleItems.isEmpty
                    ? KeyedSubtree(
                        key: ValueKey<String>(
                          'empty_result_${_filter.name}_${_query.trim().toLowerCase()}',
                        ),
                        child: _buildEmptyState(
                          context,
                          noRecords: false,
                          hasError: false,
                        ),
                      )
                    : KeyedSubtree(
                        key: ValueKey<String>(
                          'monthly_list_${_filter.name}_${_sort.name}_${_query.trim().toLowerCase()}_${visibleItems.length}',
                        ),
                        child: _buildList(context, items: visibleItems),
                      );

    return Material(
      color: tokens.canvas,
      child: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                child: _buildToolbar(
                  context,
                  refreshing: refreshing,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: _buildStatusSegments(
                  context,
                  summary: summary,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
                child: _buildInfoRow(
                  context,
                  visibleCount: visibleItems.length,
                  currentArea: currentArea,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                  child: OpsDockResultSwitcher(child: listBody),
                ),
              ),
              OpsDockContextFooterTransition(
                child: _buildContextFooter(
                  context,
                  selectedItem: selectedItem,
                ),
              ),
            ],
          ),
          OpsDockLoadingOverlay(loading: initialLoading),
        ],
      ),
    );
  }
}

class _MonthlySummary {
  const _MonthlySummary({
    required this.total,
    required this.active,
    required this.expiringSoon,
    required this.expired,
    required this.memo,
  });

  final int total;
  final int active;
  final int expiringSoon;
  final int expired;
  final int memo;
}

class _MonthlyPlateVM {
  const _MonthlyPlateVM({
    required this.docId,
    required this.data,
    required this.plateNumber,
    required this.countType,
    required this.regularType,
    required this.amount,
    required this.duration,
    required this.periodUnit,
    required this.startDate,
    required this.endDate,
    required this.customStatus,
    required this.paymentCount,
    required this.daysLeft,
    required this.updatedAt,
    required this.hasMemo,
    required this.status,
  });

  final String docId;
  final Map<String, dynamic> data;
  final String plateNumber;
  final String countType;
  final String regularType;
  final int amount;
  final int duration;
  final String periodUnit;
  final String startDate;
  final String endDate;
  final String customStatus;
  final int paymentCount;
  final int? daysLeft;
  final DateTime? updatedAt;
  final bool hasMemo;
  final _MonthlyStatus status;
}

class _MonthlyDockRow extends StatelessWidget {
  const _MonthlyDockRow({
    super.key,
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _MonthlyPlateVM item;
  final bool selected;
  final VoidCallback onTap;

  List<Map<String, dynamic>> _paymentHistory() {
    final raw = item.data['payment_history'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    final out = <Map<String, dynamic>>[];
    for (final value in raw) {
      if (value is Map<String, dynamic>) {
        out.add(value);
      } else if (value is Map) {
        out.add(Map<String, dynamic>.from(value));
      }
    }
    return out.reversed.toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final statusColor = _monthlyStatusColor(tokens, item.status);
    final statusLabel = _monthlyStatusLabel(item);
    final won = NumberFormat.decimalPattern('ko_KR');
    final typeText = [
      item.countType.trim().isEmpty ? '정기 주차' : item.countType.trim(),
      item.regularType.trim().isEmpty ? '타입 미지정' : item.regularType.trim(),
    ].join(' · ');
    final periodText = item.startDate.trim().isEmpty && item.endDate.trim().isEmpty
        ? '기간 미지정'
        : '${item.startDate.trim().isEmpty ? '-' : item.startDate.trim()} ~ ${item.endDate.trim().isEmpty ? '-' : item.endDate.trim()}';
    final durationText = MonthlyParkingOptions.durationLabel(
      regularType: item.regularType,
      duration: item.duration,
      periodUnit: item.periodUnit,
    );
    final history = selected ? _paymentHistory() : const <Map<String, dynamic>>[];

    return OpsDockSelectableRowSurface(
      selected: selected,
      selectionColor: tokens.accent,
      selectedContainer: tokens.accentContainer,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration:
                    reduceMotion ? Duration.zero : CommonUiMotion.selection,
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  item.plateNumber.trim().isEmpty ? '차량번호 없음' : item.plateNumber,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.1,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                statusLabel,
                style: textTheme.labelSmall?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 5),
              AnimatedSwitcher(
                duration:
                    reduceMotion ? Duration.zero : CommonUiMotion.selection,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: .9, end: 1).animate(animation),
                    child: child,
                  ),
                ),
                child: Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.chevron_right_rounded,
                  key: ValueKey<bool>(selected),
                  size: 17,
                  color: selected ? tokens.accent : tokens.iconSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            typeText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            periodText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (selected) ...[
            const SizedBox(height: 10),
            Divider(height: 1, color: tokens.borderSubtle),
            const SizedBox(height: 9),
            _MonthlyInlineValue(
              label: '요금',
              value: '₩${won.format(item.amount)}',
            ),
            _MonthlyInlineValue(
              label: '기간 단위',
              value: durationText.trim().isEmpty ? '-' : durationText,
            ),
            _MonthlyInlineValue(
              label: '결제',
              value: '${item.paymentCount}회',
            ),
            _MonthlyInlineValue(
              label: '상태 메모',
              value: item.customStatus.trim().isEmpty
                  ? '-'
                  : item.customStatus.trim(),
            ),
            if (history.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '결제 내역 ${history.length}건',
                style: textTheme.labelSmall?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              for (var index = 0; index < history.length; index++) ...[
                _MonthlyPaymentHistoryLine(
                  payment: history[index],
                  won: won,
                ),
                if (index != history.length - 1)
                  Divider(height: 9, color: tokens.borderSubtle),
              ],
            ],
          ],
        ],
      ),
    );
  }
}

class _MonthlyInlineValue extends StatelessWidget {
  const _MonthlyInlineValue({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 68,
            child: Text(
              label,
              style: textTheme.labelSmall?.copyWith(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: textTheme.labelSmall?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthlyPaymentHistoryLine extends StatelessWidget {
  const _MonthlyPaymentHistoryLine({
    required this.payment,
    required this.won,
  });

  final Map<String, dynamic> payment;
  final NumberFormat won;

  int _amountValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    final text = value?.toString().replaceAll(RegExp(r'[^0-9-]'), '') ?? '';
    return int.tryParse(text) ?? 0;
  }

  String _textValue(dynamic value, {String fallback = '-'}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  String _paidAt(dynamic raw) {
    if (raw == null) return '-';
    if (raw is DateTime) return DateFormat('yyyy.MM.dd HH:mm').format(raw);
    try {
      final dynamic value = raw;
      final converted = value.toDate();
      if (converted is DateTime) {
        return DateFormat('yyyy.MM.dd HH:mm').format(converted);
      }
    } catch (_) {}
    final text = raw.toString().trim();
    if (text.isEmpty) return '-';
    try {
      return DateFormat('yyyy.MM.dd HH:mm').format(DateTime.parse(text));
    } catch (_) {
      return text;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final amount = _amountValue(payment['paymentAmount'] ?? payment['amount']);
    final paidBy = _textValue(payment['paidBy']);
    final paidAt = _paidAt(payment['paidAt']);
    final note = _textValue(payment['note'], fallback: '');
    final extended = payment['extended'] == true ||
        payment['extended']?.toString() == 'true';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '₩${won.format(amount)}',
                  style: textTheme.labelSmall?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              if (extended)
                Text(
                  '연장',
                  style: textTheme.labelSmall?.copyWith(
                    color: tokens.success,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '$paidAt · $paidBy',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              note,
              style: textTheme.labelSmall?.copyWith(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Color _monthlyStatusColor(CommonUiTokens tokens, _MonthlyStatus status) {
  return switch (status) {
    _MonthlyStatus.active => tokens.success,
    _MonthlyStatus.expiringSoon => tokens.warning,
    _MonthlyStatus.expired => tokens.danger,
    _MonthlyStatus.unknown => tokens.info,
  };
}

String _monthlyStatusLabel(_MonthlyPlateVM item) {
  return switch (item.status) {
    _MonthlyStatus.active => item.daysLeft == null ? '정상' : 'D-${item.daysLeft}',
    _MonthlyStatus.expiringSoon =>
      item.daysLeft == 0 ? '오늘 만료' : 'D-${item.daysLeft}',
    _MonthlyStatus.expired => '만료',
    _MonthlyStatus.unknown => '기간 미상',
  };
}
