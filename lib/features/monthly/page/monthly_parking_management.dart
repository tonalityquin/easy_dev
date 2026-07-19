import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../../shared/plate/domain/repositories/plate_repository.dart';
import '../../../shared/plate/domain/services/plate_status_record.dart';
import '../../account/applications/user_state.dart';
import '../../dev/application/area_state.dart';
import '../application/monthly_area_resolver.dart';
import '../controllers/monthly_plate_controller.dart';
import '../domain/monthly_parking_options.dart';
import 'sheets/monthly_plate_bottom_sheet.dart';
import 'sheets/monthly_plate_payment_bottom_sheet.dart';
import 'widgets/monthly_prompt_ui.dart';

class MonthlyParkingManagement extends StatefulWidget {
  const MonthlyParkingManagement({super.key});

  @override
  State<MonthlyParkingManagement> createState() => _MonthlyParkingManagementState();
}

enum _MonthlyFilter { all, active, expiringSoon, expired, memo }

enum _MonthlySort { updatedDesc, endDateAsc, plateAsc, amountDesc }

class _MonthlyParkingManagementState extends State<MonthlyParkingManagement> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  _MonthlyFilter _filter = _MonthlyFilter.all;
  _MonthlySort _sort = _MonthlySort.updatedDesc;
  String? _selectedDocId;
  List<Map<String, dynamic>> _records = const <Map<String, dynamic>>[];
  String _loadedArea = '';
  String? _pendingArea;
  bool _loading = false;
  Object? _loadError;

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
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
    if (customStatus.isNotEmpty && customStatus != '없음') return true;
    final statusList = data['statusList'];
    return statusList is List && statusList.isNotEmpty;
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
    final plateNumber = (data['plateNumber'] ?? (docId.split('_').isEmpty ? '' : docId.split('_').first)).toString();
    final endDate = (data['endDate'] ?? '').toString();
    final daysLeft = _daysLeft(endDate);
    return _MonthlyPlateVM(
      docId: docId,
      data: data,
      plateNumber: plateNumber,
      countType: (data['countType'] ?? '').toString(),
      regularType: (data['regularType'] ?? '').toString(),
      amount: _asInt(data['regularAmount']),
      duration: _asInt(data['regularDurationValue'] ?? data['regularDurationHours']),
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
    var filtered = items.where((item) {
      if (query.isEmpty) return true;
      return item.plateNumber.toLowerCase().contains(query) ||
          item.countType.toLowerCase().contains(query) ||
          item.regularType.toLowerCase().contains(query);
    }).where((item) {
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
        filtered.sort((a, b) => (a.daysLeft ?? (1 << 30)).compareTo(b.daysLeft ?? (1 << 30)));
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
      expiringSoon: items.where((e) => e.status == _MonthlyStatus.expiringSoon).length,
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
      _loadMonthlyPlateView(target);
    });
  }

  Future<void> _loadMonthlyPlateView(String area) async {
    final safeArea = area.trim();
    if (safeArea.isEmpty) {
      if (!mounted) return;
      setState(() {
        _records = const <Map<String, dynamic>>[];
        _loadedArea = '';
        _loading = false;
        _loadError = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final records = await context.read<PlateRepository>().fetchMonthlyPlateStatusView(area: safeArea);
      if (!mounted) return;
      setState(() {
        _records = records;
        _loadedArea = safeArea;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _records = const <Map<String, dynamic>>[];
        _loadedArea = safeArea;
        _loading = false;
        _loadError = e;
      });
      showMonthlyPromptMessage(
        context,
        '정기 주차 목록을 불러오지 못했습니다. 아래로 당겨 다시 시도해주세요.',
        tone: MonthlyPromptMessageTone.danger,
      );
    }
  }

  Future<void> _refreshMonthlyPlateView() async {
    final area = MonthlyAreaResolver.readCurrentArea(context);
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
      if (record == null) return item;
      return _toItemFromSourceRecord(record);
    } catch (_) {
      return item;
    }
  }

  Future<void> _openAddDialog() async {
    FocusScope.of(context).unfocus();
    await showPromptOverlayDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const MonthlyPlateBottomSheet(),
    );
    if (mounted) await _refreshMonthlyPlateView();
  }

  Future<void> _openEditDialog(_MonthlyPlateVM item) async {
    FocusScope.of(context).unfocus();
    final sourceItem = await _hydrateFromSource(item);
    if (!mounted) return;
    await showPromptOverlayDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => MonthlyPlateBottomSheet(
        isEditMode: true,
        initialDocId: sourceItem.docId,
        initialData: sourceItem.data,
      ),
    );
    if (mounted) await _refreshMonthlyPlateView();
  }

  Future<void> _openPaymentDialog(_MonthlyPlateVM item) async {
    FocusScope.of(context).unfocus();

    final nameController = TextEditingController();
    final amountController = TextEditingController();
    final durationController = TextEditingController();
    final startDateController = TextEditingController();
    final endDateController = TextEditingController();
    final controller = MonthlyPlateController(
      nameController: nameController,
      amountController: amountController,
      durationController: durationController,
      startDateController: startDateController,
      endDateController: endDateController,
      regularAmountController: amountController,
      regularDurationController: durationController,
    );

    final sourceItem = await _hydrateFromSource(item);
    await controller.loadExistingData(sourceItem.data, docId: sourceItem.docId);
    controller.showKeypad = false;

    if (!mounted) {
      controller.dispose();
      nameController.dispose();
      amountController.dispose();
      durationController.dispose();
      startDateController.dispose();
      endDateController.dispose();
      return;
    }

    await showPromptOverlayBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      transparentBackground: true,
      builder: (_) => MonthlyPaymentBottomSheet(controller: controller),
    );

    controller.dispose();
    nameController.dispose();
    amountController.dispose();
    durationController.dispose();
    startDateController.dispose();
    endDateController.dispose();
    if (mounted) await _refreshMonthlyPlateView();
  }

  Future<void> _deleteItem(_MonthlyPlateVM item) async {
    final ok = await showMonthlyPromptConfirmation(
      context: context,
      title: '정기권 삭제',
      message: '${item.plateNumber} 정기 주차 정보를 삭제합니다. 삭제 후에는 복구할 수 없습니다.',
      confirmLabel: '삭제',
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );

    if (!ok || !mounted) return;

    try {
      await context.read<PlateRepository>().deleteMonthlyPlateStatus(documentId: item.docId);
      if (!mounted) return;
      setState(() {
        if (_selectedDocId == item.docId) _selectedDocId = null;
      });
      showMonthlyPromptMessage(
        context,
        '정기 주차 정보가 삭제되었습니다.',
        tone: MonthlyPromptMessageTone.success,
      );
      await _refreshMonthlyPlateView();
    } catch (_) {
      if (!mounted) return;
      showMonthlyPromptMessage(
        context,
        '삭제에 실패했습니다. 다시 시도해주세요.',
        tone: MonthlyPromptMessageTone.danger,
      );
    }
  }

  Future<void> _openDetailSheet(_MonthlyPlateVM item) async {
    FocusScope.of(context).unfocus();
    setState(() => _selectedDocId = item.docId);
    final sourceItem = await _hydrateFromSource(item);
    if (!mounted) return;

    await showPromptOverlayBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      transparentBackground: true,
      builder: (_) => _MonthlyDetailPanel(
        item: sourceItem,
        onEdit: () async {
          Navigator.of(context).pop();
          await _openEditDialog(sourceItem);
        },
        onPay: () async {
          Navigator.of(context).pop();
          await _openPaymentDialog(sourceItem);
        },
        onDelete: () async {
          Navigator.of(context).pop();
          await _deleteItem(sourceItem);
        },
      ),
    );

    if (mounted) setState(() {});
  }

  Widget _refreshableBody({
    required Widget child,
  }) {
    return RefreshIndicator(
      onRefresh: _refreshMonthlyPlateView,
      color: PromptUiTheme.of(context).accent,
      child: child,
    );
  }

  Widget _centerScrollBody(Widget child) {
    return _refreshableBody(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 42),
              child: Center(child: child),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userArea = context.select<UserState, String>((state) => state.currentArea.trim());
    final areaStateArea = context.select<AreaState, String>((state) => state.currentArea.trim());
    final currentArea = MonthlyAreaResolver.resolve(
      userArea: userArea,
      areaStateArea: areaStateArea,
    );

    _scheduleLoadIfNeeded(currentArea);

    final allItems = _toItems(_records);
    final summary = _summaryOf(allItems);
    final visibleItems = _filteredSorted(allItems);

    Widget body;
    if (_loading && _records.isEmpty) {
      body = const _MonthlyLoadingView();
    } else if (_loadError != null && _records.isEmpty) {
      body = _centerScrollBody(
        _MonthlyLoadErrorState(onRetry: _refreshMonthlyPlateView),
      );
    } else if (_records.isEmpty) {
      body = _centerScrollBody(_MonthlyEmptyState(onAdd: _openAddDialog));
    } else if (visibleItems.isEmpty) {
      body = _centerScrollBody(
        _MonthlyNoResultState(onReset: () {
          _searchController.clear();
          setState(() {
            _query = '';
            _filter = _MonthlyFilter.all;
            _sort = _MonthlySort.updatedDesc;
          });
        }),
      );
    } else {
      body = _refreshableBody(
        child: ListView.separated(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          itemCount: visibleItems.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final item = visibleItems[index];
            return _MonthlyPlateOpsRow(
              item: item,
              delay: Duration(milliseconds: index.clamp(0, 10).toInt() * 28),
              selected: _selectedDocId == item.docId,
              onTap: () => _openDetailSheet(item),
              onPay: () => _openPaymentDialog(item),
            );
          },
        ),
      );
    }

    final tokens = PromptUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return PromptUiScope(
      child: Scaffold(
        backgroundColor: tokens.canvas,
        body: AnimatedSwitcher(
          duration: reduceMotion ? Duration.zero : PromptUiMotion.component,
          switchInCurve: PromptUiMotion.enter,
          switchOutCurve: PromptUiMotion.exit,
          child: Column(
            key: ValueKey<String>(currentArea),
        children: [
          _MonthlyOpsHeader(
            area: currentArea,
            summary: summary,
            onAdd: _openAddDialog,
          ),
          _MonthlyCommandBar(
            controller: _searchController,
            query: _query,
            filter: _filter,
            sort: _sort,
            totalCount: summary.total,
            visibleCount: visibleItems.length,
            onQueryChanged: (value) => setState(() => _query = value.trim()),
            onQueryClear: () {
              _searchController.clear();
              setState(() => _query = '');
            },
            onFilterChanged: (value) => setState(() => _filter = value),
            onSortChanged: (value) => setState(() => _sort = value),
          ),
              Expanded(child: body),
            ],
          ),
        ),
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

enum _MonthlyStatus { active, expiringSoon, expired, unknown }

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

class _MonthlyOpsHeader extends StatelessWidget {
  const _MonthlyOpsHeader({
    required this.area,
    required this.summary,
    required this.onAdd,
  });

  final String area;
  final _MonthlySummary summary;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

    return PromptAnimatedReveal(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          border: Border(bottom: BorderSide(color: tokens.borderSubtle)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tokens.accentContainer,
                    borderRadius: BorderRadius.circular(PromptUiShapes.control),
                    border: Border.all(
                      color: tokens.accent.withOpacity(
                        tokens.isDark ? 0.56 : 0.34,
                      ),
                    ),
                  ),
                  child: Icon(
                    Icons.local_parking_rounded,
                    color: tokens.onAccentContainer,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '정기 주차 관리',
                        style: textTheme.titleLarge?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        area.isEmpty ? '현재 지점 미선택' : '$area 운영 현황',
                        style: textTheme.bodySmall?.copyWith(
                          color: tokens.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                PromptButton(
                  label: '신규 등록',
                  icon: Icons.add_rounded,
                  minHeight: 46,
                  haptic: PromptHaptic.medium,
                  onPressed: onAdd,
                ),
              ],
            ),
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _SummaryCell(
                    label: '전체',
                    value: summary.total,
                    icon: Icons.dashboard_customize_outlined,
                    tone: MonthlyPromptMessageTone.info,
                  ),
                  _SummaryCell(
                    label: '정상',
                    value: summary.active,
                    icon: Icons.verified_outlined,
                    tone: MonthlyPromptMessageTone.success,
                  ),
                  _SummaryCell(
                    label: 'D-7',
                    value: summary.expiringSoon,
                    icon: Icons.timer_outlined,
                    tone: MonthlyPromptMessageTone.warning,
                  ),
                  _SummaryCell(
                    label: '만료',
                    value: summary.expired,
                    icon: Icons.warning_amber_rounded,
                    tone: MonthlyPromptMessageTone.danger,
                  ),
                  _SummaryCell(
                    label: '메모',
                    value: summary.memo,
                    icon: Icons.sticky_note_2_outlined,
                    tone: MonthlyPromptMessageTone.info,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCell extends StatelessWidget {
  const _SummaryCell({
    required this.label,
    required this.value,
    required this.icon,
    required this.tone,
  });

  final String label;
  final int value;
  final IconData icon;
  final MonthlyPromptMessageTone tone;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final foreground = _toneForeground(tokens, tone);
    final background = _toneBackground(tokens, tone);

    return Container(
      width: 104,
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(PromptUiShapes.card),
        border: Border.all(color: foreground.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: foreground),
              const SizedBox(width: 5),
              Text(
                label,
                style: textTheme.labelMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value.toString(),
            style: textTheme.titleLarge?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w800,
              height: 1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthlyCommandBar extends StatelessWidget {
  const _MonthlyCommandBar({
    required this.controller,
    required this.query,
    required this.filter,
    required this.sort,
    required this.totalCount,
    required this.visibleCount,
    required this.onQueryChanged,
    required this.onQueryClear,
    required this.onFilterChanged,
    required this.onSortChanged,
  });

  final TextEditingController controller;
  final String query;
  final _MonthlyFilter filter;
  final _MonthlySort sort;
  final int totalCount;
  final int visibleCount;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onQueryClear;
  final ValueChanged<_MonthlyFilter> onFilterChanged;
  final ValueChanged<_MonthlySort> onSortChanged;

  String _filterLabel(_MonthlyFilter value) {
    return switch (value) {
      _MonthlyFilter.all => '전체',
      _MonthlyFilter.active => '정상',
      _MonthlyFilter.expiringSoon => 'D-7',
      _MonthlyFilter.expired => '만료',
      _MonthlyFilter.memo => '메모',
    };
  }

  IconData _filterIcon(_MonthlyFilter value) {
    return switch (value) {
      _MonthlyFilter.all => Icons.dashboard_customize_outlined,
      _MonthlyFilter.active => Icons.verified_outlined,
      _MonthlyFilter.expiringSoon => Icons.timer_outlined,
      _MonthlyFilter.expired => Icons.warning_amber_rounded,
      _MonthlyFilter.memo => Icons.sticky_note_2_outlined,
    };
  }

  String _sortLabel(_MonthlySort value) {
    return switch (value) {
      _MonthlySort.updatedDesc => '최근 업데이트',
      _MonthlySort.endDateAsc => '종료일 빠른순',
      _MonthlySort.plateAsc => '번호판 오름차순',
      _MonthlySort.amountDesc => '요금 높은순',
    };
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

    return PromptAnimatedReveal(
      delay: const Duration(milliseconds: 45),
      child: Container(
        color: tokens.canvas,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 520;
                final searchField = TextField(
                  controller: controller,
                  onChanged: onQueryChanged,
                  style: textTheme.bodyLarge?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: monthlyPromptInputDecoration(
                    context,
                    label: '차량번호·정산명 검색',
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: tokens.iconSecondary,
                    ),
                    suffixIcon: query.isEmpty
                        ? null
                        : PromptIconButton(
                            icon: Icons.close_rounded,
                            tooltip: '검색어 지우기',
                            size: 40,
                            iconSize: 19,
                            haptic: PromptHaptic.selection,
                            onPressed: onQueryClear,
                          ),
                  ),
                );
                final sortField = DropdownButtonFormField<_MonthlySort>(
                  value: sort,
                  isExpanded: true,
                  decoration: monthlyPromptInputDecoration(
                    context,
                    label: '정렬',
                    prefixIcon: Icon(
                      Icons.swap_vert_rounded,
                      color: tokens.iconSecondary,
                    ),
                  ),
                  dropdownColor: tokens.surfaceRaised,
                  iconEnabledColor: tokens.iconSecondary,
                  style: textTheme.bodyMedium?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  selectedItemBuilder: (_) => _MonthlySort.values
                      .map(
                        (value) => Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _sortLabel(value),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  items: _MonthlySort.values
                      .map(
                        (value) => DropdownMenuItem<_MonthlySort>(
                          value: value,
                          child: Text(
                            _sortLabel(value),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) onSortChanged(value);
                  },
                );

                if (compact) {
                  return Column(
                    children: [
                      searchField,
                      const SizedBox(height: 10),
                      SizedBox(width: double.infinity, child: sortField),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: searchField),
                    const SizedBox(width: 10),
                    SizedBox(width: 200, child: sortField),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final value in _MonthlyFilter.values)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: PromptButton(
                              label: _filterLabel(value),
                              icon: _filterIcon(value),
                              minHeight: 40,
                              selected: filter == value,
                              variant: filter == value
                                  ? PromptButtonVariant.secondary
                                  : PromptButtonVariant.tertiary,
                              haptic: PromptHaptic.selection,
                              onPressed: () => onFilterChanged(value),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                MonthlyPromptBadge(
                  label: '$visibleCount / $totalCount',
                  icon: Icons.format_list_numbered_rounded,
                  tone: MonthlyPromptMessageTone.info,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthlyPlateOpsRow extends StatelessWidget {
  const _MonthlyPlateOpsRow({
    required this.item,
    required this.delay,
    required this.selected,
    required this.onTap,
    required this.onPay,
  });

  final _MonthlyPlateVM item;
  final Duration delay;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final won = NumberFormat.decimalPattern('ko_KR');
    final tone = _statusTone(item.status);
    final statusColor = _toneForeground(tokens, tone);

    return PromptAnimatedReveal(
      delay: reduceMotion ? Duration.zero : delay,
      child: Material(
        color: tokens.transparent,
        borderRadius: BorderRadius.circular(PromptUiShapes.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
            curve: PromptUiMotion.standard,
            decoration: BoxDecoration(
              color: selected ? tokens.surfaceSelected : tokens.surfaceRaised,
              border: Border.all(
                color: selected ? tokens.accent : tokens.borderSubtle,
                width: selected ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(PromptUiShapes.card),
              boxShadow: [
                if (selected)
                  BoxShadow(
                    color: tokens.shadow,
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
              ],
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 6, color: statusColor),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.plateNumber,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.titleMedium?.copyWith(
                                    color: tokens.textPrimary,
                                    fontWeight: FontWeight.w800,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                              MonthlyPromptBadge(
                                label: _statusLabel(item),
                                icon: _statusIcon(item.status),
                                tone: tone,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${item.countType.isEmpty ? '정기 주차' : item.countType} · ${item.regularType.isEmpty ? '주차 타입 미지정' : item.regularType}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodyMedium?.copyWith(
                              color: tokens.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _InfoPill(
                                icon: Icons.calendar_month_outlined,
                                label: '${item.startDate} ~ ${item.endDate}',
                              ),
                              _InfoPill(
                                icon: Icons.payments_outlined,
                                label: '₩${won.format(item.amount)}',
                              ),
                              _InfoPill(
                                icon: Icons.history_rounded,
                                label: '결제 ${item.paymentCount}회',
                              ),
                              if (item.hasMemo)
                                const _InfoPill(
                                  icon: Icons.sticky_note_2_outlined,
                                  label: '메모 있음',
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    width: 70,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border(left: BorderSide(color: tokens.borderSubtle)),
                    ),
                    child: PromptIconButton(
                      icon: Icons.payments_outlined,
                      tooltip: '결제',
                      haptic: PromptHaptic.medium,
                      onPressed: onPay,
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

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: tokens.surfaceOverlay,
        borderRadius: BorderRadius.circular(PromptUiShapes.control),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: tokens.iconSecondary),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ],
      ),
    );
  }
}

class _MonthlyDetailPanel extends StatelessWidget {
  const _MonthlyDetailPanel({
    required this.item,
    required this.onEdit,
    required this.onPay,
    required this.onDelete,
  });

  final _MonthlyPlateVM item;
  final VoidCallback onEdit;
  final VoidCallback onPay;
  final VoidCallback onDelete;

  List<Map<String, dynamic>> _paymentHistory() {
    final rawHistory = item.data['payment_history'];
    if (rawHistory is! List) return <Map<String, dynamic>>[];
    final history = <Map<String, dynamic>>[];
    for (final value in rawHistory) {
      if (value is Map<String, dynamic>) {
        history.add(value);
      } else if (value is Map) {
        history.add(Map<String, dynamic>.from(value));
      }
    }
    return history.reversed.toList();
  }

  @override
  Widget build(BuildContext context) {
    final won = NumberFormat.decimalPattern('ko_KR');
    final history = _paymentHistory();

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.6,
      maxChildSize: 0.97,
      builder: (context, scrollController) {
        final tokens = PromptUiTheme.of(context);
        return PromptSheetScaffold(
          title: item.plateNumber,
          icon: Icons.assignment_turned_in_outlined,
          onClose: () => Navigator.of(context).pop(),
          body: Column(
            children: [
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: MonthlyPromptBadge(
                        label: _statusLabel(item),
                        icon: _statusIcon(item.status),
                        tone: _statusTone(item.status),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _OpsPanel(
                      title: '정기권 정보',
                      icon: Icons.fact_check_outlined,
                      children: [
                        _KV(
                          label: '정산명',
                          value: item.countType.isEmpty ? '-' : item.countType,
                        ),
                        _KV(
                          label: '주차 타입',
                          value: item.regularType.isEmpty
                              ? '-'
                              : item.regularType,
                        ),
                        _KV(label: '요금', value: '₩${won.format(item.amount)}'),
                        _KV(
                          label: '기간 단위',
                          value: MonthlyParkingOptions.durationLabel(
                            regularType: item.regularType,
                            duration: item.duration,
                            periodUnit: item.periodUnit,
                          ),
                        ),
                        _KV(
                          label: '사용 기간',
                          value: '${item.startDate} ~ ${item.endDate}',
                        ),
                        _KV(
                          label: '상태 메모',
                          value: item.customStatus.trim().isEmpty
                              ? '-'
                              : item.customStatus,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _OpsPanel(
                      title: '결제 내역',
                      icon: Icons.receipt_long_outlined,
                      trailing: MonthlyPromptBadge(
                        label: '${history.length}건',
                        icon: Icons.history_rounded,
                      ),
                      children: history.isEmpty
                          ? [
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                child: Text(
                                  '아직 저장된 결제 내역이 없습니다.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: tokens.textSecondary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ),
                            ]
                          : [
                              for (var index = 0;
                                  index < history.length;
                                  index++)
                                PromptAnimatedReveal(
                                  delay: MediaQuery.maybeOf(context)
                                              ?.disableAnimations ??
                                          false
                                      ? Duration.zero
                                      : Duration(milliseconds: index * 30),
                                  child: _PaymentHistoryRow(
                                    payment: history[index],
                                    won: won,
                                  ),
                                ),
                            ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                decoration: BoxDecoration(
                  color: tokens.surfaceRaised,
                  border: Border(top: BorderSide(color: tokens.borderSubtle)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: PromptButton(
                        label: '수정',
                        icon: Icons.edit_outlined,
                        variant: PromptButtonVariant.secondary,
                        haptic: PromptHaptic.selection,
                        onPressed: onEdit,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: PromptButton(
                        label: '결제',
                        icon: Icons.payments_outlined,
                        haptic: PromptHaptic.medium,
                        onPressed: onPay,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: PromptButton(
                        label: '삭제',
                        icon: Icons.delete_outline_rounded,
                        variant: PromptButtonVariant.destructive,
                        haptic: PromptHaptic.heavy,
                        onPressed: onDelete,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OpsPanel extends StatelessWidget {
  const _OpsPanel({
    required this.title,
    required this.icon,
    required this.children,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(PromptUiShapes.card),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: tokens.iconPrimary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: textTheme.titleMedium?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _KV extends StatelessWidget {
  const _KV({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: textTheme.bodyMedium?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentHistoryRow extends StatelessWidget {
  const _PaymentHistoryRow({
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
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final amount = _amountValue(payment['paymentAmount'] ?? payment['amount']);
    final paidBy = _textValue(payment['paidBy']);
    final note = _textValue(payment['note'], fallback: '');
    final extended = payment['extended'] == true ||
        payment['extended']?.toString() == 'true';
    final paidAt = _paidAt(payment['paidAt']);
    final regularType = _textValue(payment['regularType'], fallback: '');
    final periodUnit = _textValue(payment['periodUnit'], fallback: '');
    final duration = _amountValue(
      payment['durationValue'] ?? payment['regularDurationValue'],
    );
    final startDate = _textValue(payment['startDate'], fallback: '');
    final endDate = _textValue(payment['endDate'], fallback: '');
    final durationText = duration > 0
        ? MonthlyParkingOptions.durationLabel(
            regularType: regularType,
            duration: duration,
            periodUnit: periodUnit,
          )
        : '';
    final hasRange = startDate.isNotEmpty && endDate.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.surfaceOverlay,
        borderRadius: BorderRadius.circular(PromptUiShapes.control),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '₩${won.format(amount)}',
                  style: textTheme.titleMedium?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              if (extended)
                const MonthlyPromptBadge(
                  label: '연장',
                  icon: Icons.update_rounded,
                  tone: MonthlyPromptMessageTone.success,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$paidAt · $paidBy',
            style: textTheme.bodySmall?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (regularType.isNotEmpty || durationText.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              [regularType, durationText]
                  .where((value) => value.trim().isNotEmpty)
                  .join(' · '),
              style: textTheme.bodyMedium?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (hasRange) ...[
            const SizedBox(height: 5),
            Text(
              '적용 기간 $startDate ~ $endDate',
              style: textTheme.bodySmall?.copyWith(
                color: tokens.success,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              note,
              style: textTheme.bodyMedium?.copyWith(
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

class _MonthlyLoadErrorState extends StatelessWidget {
  const _MonthlyLoadErrorState({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return _MonthlyStateCard(
      icon: Icons.error_outline_rounded,
      title: '목록을 불러오지 못했습니다.',
      message: '아래로 당기거나 다시 시도 버튼을 눌러 갱신하세요.',
      tone: MonthlyPromptMessageTone.danger,
      action: PromptButton(
        label: '다시 시도',
        icon: Icons.refresh_rounded,
        variant: PromptButtonVariant.secondary,
        haptic: PromptHaptic.selection,
        onPressed: onRetry,
      ),
    );
  }
}

class _MonthlyLoadingView extends StatelessWidget {
  const _MonthlyLoadingView();

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    return Center(
      child: PromptAnimatedReveal(
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: tokens.surfaceRaised,
            borderRadius: BorderRadius.circular(PromptUiShapes.card),
            border: Border.all(color: tokens.borderSubtle),
          ),
          child: CircularProgressIndicator(color: tokens.accent),
        ),
      ),
    );
  }
}

class _MonthlyEmptyState extends StatelessWidget {
  const _MonthlyEmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return _MonthlyStateCard(
      icon: Icons.local_parking_outlined,
      title: '등록된 정기 주차가 없습니다.',
      message: '신규 등록으로 첫 정기권을 추가하세요.',
      tone: MonthlyPromptMessageTone.info,
      action: PromptButton(
        label: '신규 등록',
        icon: Icons.add_rounded,
        haptic: PromptHaptic.medium,
        onPressed: onAdd,
      ),
    );
  }
}

class _MonthlyNoResultState extends StatelessWidget {
  const _MonthlyNoResultState({required this.onReset});

  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return _MonthlyStateCard(
      icon: Icons.manage_search_rounded,
      title: '조건에 맞는 정기권이 없습니다.',
      message: '검색어와 필터를 초기화해보세요.',
      tone: MonthlyPromptMessageTone.warning,
      action: PromptButton(
        label: '초기화',
        icon: Icons.refresh_rounded,
        variant: PromptButtonVariant.secondary,
        haptic: PromptHaptic.selection,
        onPressed: onReset,
      ),
    );
  }
}

class _MonthlyStateCard extends StatelessWidget {
  const _MonthlyStateCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.tone,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final MonthlyPromptMessageTone tone;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final foreground = _toneForeground(tokens, tone);
    final background = _toneBackground(tokens, tone);
    return PromptAnimatedReveal(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(PromptUiShapes.card),
          border: Border.all(color: tokens.borderSubtle),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 62,
              height: 62,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(PromptUiShapes.card),
                border: Border.all(color: foreground.withOpacity(0.22)),
              ),
              child: Icon(icon, color: foreground, size: 32),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: textTheme.titleMedium?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: tokens.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            action,
          ],
        ),
      ),
    );
  }
}

MonthlyPromptMessageTone _statusTone(_MonthlyStatus status) {
  return switch (status) {
    _MonthlyStatus.active => MonthlyPromptMessageTone.success,
    _MonthlyStatus.expiringSoon => MonthlyPromptMessageTone.warning,
    _MonthlyStatus.expired => MonthlyPromptMessageTone.danger,
    _MonthlyStatus.unknown => MonthlyPromptMessageTone.info,
  };
}

String _statusLabel(_MonthlyPlateVM item) {
  return switch (item.status) {
    _MonthlyStatus.active => item.daysLeft == null ? '정상' : 'D-${item.daysLeft}',
    _MonthlyStatus.expiringSoon =>
      item.daysLeft == 0 ? '오늘 만료' : 'D-${item.daysLeft}',
    _MonthlyStatus.expired => '만료',
    _MonthlyStatus.unknown => '기간 미상',
  };
}

IconData _statusIcon(_MonthlyStatus status) {
  return switch (status) {
    _MonthlyStatus.active => Icons.verified_outlined,
    _MonthlyStatus.expiringSoon => Icons.timer_outlined,
    _MonthlyStatus.expired => Icons.warning_amber_rounded,
    _MonthlyStatus.unknown => Icons.help_outline_rounded,
  };
}

Color _toneForeground(
  PromptUiTokens tokens,
  MonthlyPromptMessageTone tone,
) {
  return switch (tone) {
    MonthlyPromptMessageTone.info => tokens.onInfoContainer,
    MonthlyPromptMessageTone.success => tokens.onSuccessContainer,
    MonthlyPromptMessageTone.warning => tokens.onWarningContainer,
    MonthlyPromptMessageTone.danger => tokens.onDangerContainer,
  };
}

Color _toneBackground(
  PromptUiTokens tokens,
  MonthlyPromptMessageTone tone,
) {
  return switch (tone) {
    MonthlyPromptMessageTone.info => tokens.infoContainer,
    MonthlyPromptMessageTone.success => tokens.successContainer,
    MonthlyPromptMessageTone.warning => tokens.warningContainer,
    MonthlyPromptMessageTone.danger => tokens.dangerContainer,
  };
}
