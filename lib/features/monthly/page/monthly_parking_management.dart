import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../shared/plate/domain/repositories/plate_repository.dart';
import '../../../shared/plate/domain/services/plate_status_record.dart';
import '../../account/applications/user_state.dart';
import '../../dev/application/area_state.dart';
import '../application/monthly_area_resolver.dart';
import '../controllers/monthly_plate_controller.dart';
import '../domain/monthly_parking_options.dart';
import 'sheets/monthly_plate_bottom_sheet.dart';
import 'sheets/monthly_plate_payment_bottom_sheet.dart';

const _opsInk = Color(0xFF101828);
const _opsMuted = Color(0xFF667085);
const _opsCanvas = Color(0xFFF3F6FA);
const _opsPanel = Color(0xFFFFFFFF);
const _opsLine = Color(0xFFD8DEE8);
const _opsBlue = Color(0xFF2563EB);
const _opsGreen = Color(0xFF059669);
const _opsAmber = Color(0xFFD97706);
const _opsRed = Color(0xFFDC2626);
const _opsSlate = Color(0xFF334155);

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
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('정기 주차 목록을 불러오지 못했습니다. 아래로 당겨 다시 시도해주세요.'),
            behavior: SnackBarBehavior.floating,
          ),
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
    await showDialog<void>(
      context: context,
      useSafeArea: true,
      barrierDismissible: true,
      builder: (_) => const MonthlyPlateBottomSheet(),
    );
    if (mounted) await _refreshMonthlyPlateView();
  }

  Future<void> _openEditDialog(_MonthlyPlateVM item) async {
    FocusScope.of(context).unfocus();
    final sourceItem = await _hydrateFromSource(item);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      useSafeArea: true,
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

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
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
    final ok = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => _MonthlyDeleteDialog(plateNumber: item.plateNumber),
        ) ??
        false;

    if (!ok || !mounted) return;

    try {
      await context.read<PlateRepository>().deleteMonthlyPlateStatus(documentId: item.docId);
      if (!mounted) return;
      setState(() {
        if (_selectedDocId == item.docId) _selectedDocId = null;
      });
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('정기 주차 정보가 삭제되었습니다.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      await _refreshMonthlyPlateView();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('삭제에 실패했습니다. 다시 시도해주세요.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _openDetailSheet(_MonthlyPlateVM item) async {
    FocusScope.of(context).unfocus();
    setState(() => _selectedDocId = item.docId);
    final sourceItem = await _hydrateFromSource(item);
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
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
      color: _opsBlue,
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
              selected: _selectedDocId == item.docId,
              onTap: () => _openDetailSheet(item),
              onPay: () => _openPaymentDialog(item),
            );
          },
        ),
      );
    }

    return Scaffold(
      backgroundColor: _opsCanvas,
      body: Column(
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
    final top = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(16, top + 14, 16, 14),
      decoration: const BoxDecoration(
        color: _opsInk,
        border: Border(bottom: BorderSide(color: Color(0xFF1D2939))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _opsBlue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.local_parking_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '정기 주차 관리',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        letterSpacing: -.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      area.isEmpty ? '현재 지점 미선택' : '$area 운영 콘솔',
                      style: const TextStyle(
                        color: Color(0xFFB8C2D6),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: onAdd,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: _opsInk,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text(
                  '신규 등록',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _SummaryCell(label: '전체', value: summary.total, color: Colors.white),
                _SummaryCell(label: '정상', value: summary.active, color: const Color(0xFF8CE7C4)),
                _SummaryCell(label: 'D-7', value: summary.expiringSoon, color: const Color(0xFFFFD38A)),
                _SummaryCell(label: '만료', value: summary.expired, color: const Color(0xFFFFA3A3)),
                _SummaryCell(label: '메모', value: summary.memo, color: const Color(0xFFBFD7FF)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCell extends StatelessWidget {
  const _SummaryCell({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF182230),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2B3A4F)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFB8C2D6),
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value.toString(),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 22,
              height: 1,
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
    switch (value) {
      case _MonthlyFilter.all:
        return '전체';
      case _MonthlyFilter.active:
        return '정상';
      case _MonthlyFilter.expiringSoon:
        return 'D-7';
      case _MonthlyFilter.expired:
        return '만료';
      case _MonthlyFilter.memo:
        return '메모';
    }
  }

  IconData _filterIcon(_MonthlyFilter value) {
    switch (value) {
      case _MonthlyFilter.all:
        return Icons.dashboard_customize_outlined;
      case _MonthlyFilter.active:
        return Icons.verified_outlined;
      case _MonthlyFilter.expiringSoon:
        return Icons.timer_outlined;
      case _MonthlyFilter.expired:
        return Icons.warning_amber_rounded;
      case _MonthlyFilter.memo:
        return Icons.sticky_note_2_outlined;
    }
  }

  String _sortLabel(_MonthlySort value) {
    switch (value) {
      case _MonthlySort.updatedDesc:
        return '최근 업데이트';
      case _MonthlySort.endDateAsc:
        return '종료일 빠른순';
      case _MonthlySort.plateAsc:
        return '번호판 오름차순';
      case _MonthlySort.amountDesc:
        return '요금 높은순';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _opsCanvas,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: _opsPanel,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _opsLine),
                  ),
                  child: TextField(
                    controller: controller,
                    onChanged: onQueryChanged,
                    style: const TextStyle(
                      color: _opsInk,
                      fontWeight: FontWeight.w800,
                    ),
                    decoration: InputDecoration(

                      hintStyle: const TextStyle(
                        color: _opsMuted,
                        fontWeight: FontWeight.w700,
                      ),
                      border: InputBorder.none,
                      prefixIcon: const Icon(Icons.search, color: _opsSlate),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: '검색어 지우기',
                              onPressed: onQueryClear,
                              icon: const Icon(Icons.close, color: _opsSlate),
                            ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: _opsPanel,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _opsLine),
                ),
                child: DropdownButton<_MonthlySort>(
                  value: sort,
                  underline: const SizedBox.shrink(),
                  borderRadius: BorderRadius.circular(14),
                  icon: const Icon(Icons.swap_vert, color: _opsSlate, size: 20),
                  items: _MonthlySort.values.map((value) {
                    return DropdownMenuItem<_MonthlySort>(
                      value: value,
                      child: Text(
                        _sortLabel(value),
                        style: const TextStyle(
                          color: _opsInk,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) onSortChanged(value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _MonthlyFilter.values.map((value) {
                      final active = filter == value;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InkWell(
                          onTap: () => onFilterChanged(value),
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: active ? _opsInk : _opsPanel,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: active ? _opsInk : _opsLine),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _filterIcon(value),
                                  size: 16,
                                  color: active ? Colors.white : _opsSlate,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _filterLabel(value),
                                  style: TextStyle(
                                    color: active ? Colors.white : _opsInk,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$visibleCount/$totalCount',
                style: const TextStyle(
                  color: _opsMuted,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MonthlyPlateOpsRow extends StatelessWidget {
  const _MonthlyPlateOpsRow({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.onPay,
  });

  final _MonthlyPlateVM item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onPay;

  Color get _statusColor {
    switch (item.status) {
      case _MonthlyStatus.active:
        return _opsGreen;
      case _MonthlyStatus.expiringSoon:
        return _opsAmber;
      case _MonthlyStatus.expired:
        return _opsRed;
      case _MonthlyStatus.unknown:
        return _opsSlate;
    }
  }

  String get _statusLabel {
    switch (item.status) {
      case _MonthlyStatus.active:
        return item.daysLeft == null ? '정상' : 'D-${item.daysLeft}';
      case _MonthlyStatus.expiringSoon:
        return item.daysLeft == 0 ? '오늘 만료' : 'D-${item.daysLeft}';
      case _MonthlyStatus.expired:
        return '만료';
      case _MonthlyStatus.unknown:
        return '기간 미상';
    }
  }

  @override
  Widget build(BuildContext context) {
    final won = NumberFormat.decimalPattern('ko_KR');
    return Material(
      color: _opsPanel,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      elevation: selected ? 3 : 0,
      shadowColor: Colors.black.withOpacity(.10),
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: selected ? _opsBlue : _opsLine, width: selected ? 1.6 : 1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 6, color: _statusColor),
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
                                style: const TextStyle(
                                  color: _opsInk,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 19,
                                  letterSpacing: -.2,
                                ),
                              ),
                            ),
                            _StatusBadge(label: _statusLabel, color: _statusColor),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${item.countType.isEmpty ? '정기 주차' : item.countType} · ${item.regularType.isEmpty ? '주차 타입 미지정' : item.regularType}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _opsSlate,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _InfoPill(icon: Icons.calendar_month_outlined, label: '${item.startDate} ~ ${item.endDate}'),
                            _InfoPill(icon: Icons.payments_outlined, label: '₩${won.format(item.amount)}'),
                            _InfoPill(icon: Icons.history, label: '결제 ${item.paymentCount}회'),
                            if (item.hasMemo) const _InfoPill(icon: Icons.sticky_note_2_outlined, label: '메모 있음'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: 72,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      border: Border(left: BorderSide(color: _opsLine)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          tooltip: '결제',
                          onPressed: onPay,
                          icon: const Icon(Icons.payments_outlined, color: _opsBlue),
                        ),
                        const Text(
                          '결제',
                          style: TextStyle(
                            color: _opsBlue,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ],
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

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: _opsLine),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _opsMuted),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: _opsMuted,
              fontWeight: FontWeight.w800,
              fontSize: 12,
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

  Color get _statusColor {
    switch (item.status) {
      case _MonthlyStatus.active:
        return _opsGreen;
      case _MonthlyStatus.expiringSoon:
        return _opsAmber;
      case _MonthlyStatus.expired:
        return _opsRed;
      case _MonthlyStatus.unknown:
        return _opsSlate;
    }
  }

  String get _statusLabel {
    switch (item.status) {
      case _MonthlyStatus.active:
        return item.daysLeft == null ? '정상' : 'D-${item.daysLeft}';
      case _MonthlyStatus.expiringSoon:
        return item.daysLeft == 0 ? '오늘 만료' : 'D-${item.daysLeft}';
      case _MonthlyStatus.expired:
        return '만료';
      case _MonthlyStatus.unknown:
        return '기간 미상';
    }
  }

  List<Map<String, dynamic>> _paymentHistory() {
    final rawHistory = item.data['payment_history'];
    if (rawHistory is! List) return <Map<String, dynamic>>[];

    final history = <Map<String, dynamic>>[];
    for (final entry in rawHistory) {
      if (entry is! Map) continue;
      final converted = <String, dynamic>{};
      entry.forEach((key, value) {
        converted[key.toString()] = value;
      });
      history.add(converted);
    }
    return history.reversed.toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final won = NumberFormat.decimalPattern('ko_KR');
    final history = _paymentHistory();

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.58,
      maxChildSize: 0.96,
      builder: (context, scrollController) {
        return SafeArea(
          top: false,
          child: Container(
            decoration: const BoxDecoration(
              color: _opsCanvas,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              border: Border(top: BorderSide(color: _opsLine)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: _opsInk,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.assignment_turned_in_outlined, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.plateNumber,
                              style: const TextStyle(
                                color: _opsInk,
                                fontWeight: FontWeight.w900,
                                fontSize: 22,
                                letterSpacing: -.3,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              item.countType.isEmpty ? '정기 주차' : item.countType,
                              style: const TextStyle(
                                color: _opsMuted,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _StatusBadge(label: _statusLabel, color: _statusColor),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: '닫기',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, color: _opsSlate),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                    children: [
                      _OpsPanel(
                        title: '정기권 정보',
                        icon: Icons.fact_check_outlined,
                        children: [
                          _KV(label: '정산명', value: item.countType.isEmpty ? '-' : item.countType),
                          _KV(label: '주차 타입', value: item.regularType.isEmpty ? '-' : item.regularType),
                          _KV(label: '요금', value: '₩${won.format(item.amount)}'),
                          _KV(
                            label: '기간 단위',
                            value: MonthlyParkingOptions.durationLabel(
                              regularType: item.regularType,
                              duration: item.duration,
                              periodUnit: item.periodUnit,
                            ),
                          ),
                          _KV(label: '사용 기간', value: '${item.startDate} ~ ${item.endDate}'),
                          _KV(label: '상태 메모', value: item.customStatus.trim().isEmpty ? '-' : item.customStatus),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _OpsPanel(
                        title: '결제 내역',
                        icon: Icons.receipt_long_outlined,
                        trailing: Text(
                          '${history.length}건',
                          style: const TextStyle(
                            color: _opsMuted,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        children: history.isEmpty
                            ? const [
                                Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Text(
                                    '아직 저장된 결제 내역이 없습니다.',
                                    style: TextStyle(color: _opsMuted, fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ]
                            : history.map((payment) => _PaymentHistoryRow(payment: payment, won: won)).toList(),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  decoration: const BoxDecoration(
                    color: _opsPanel,
                    border: Border(top: BorderSide(color: _opsLine)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _OpsActionButton(
                          label: '수정',
                          icon: Icons.edit_outlined,
                          color: _opsSlate,
                          onPressed: onEdit,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _OpsActionButton(
                          label: '결제',
                          icon: Icons.payments_outlined,
                          color: _opsBlue,
                          onPressed: onPay,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _OpsActionButton(
                          label: '삭제',
                          icon: Icons.delete_outline,
                          color: _opsRed,
                          onPressed: onDelete,
                        ),
                      ),
                    ],
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _opsPanel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _opsLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _opsInk, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: _opsInk,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
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
  const _KV({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(
                color: _opsMuted,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: _opsInk,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentHistoryRow extends StatelessWidget {
  const _PaymentHistoryRow({required this.payment, required this.won});

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
    if (raw is DateTime) {
      return DateFormat('yyyy.MM.dd HH:mm').format(raw);
    }

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
    final amount = _amountValue(payment['paymentAmount'] ?? payment['amount']);
    final paidBy = _textValue(payment['paidBy']);
    final note = _textValue(payment['note'], fallback: '');
    final extended = payment['extended'] == true || payment['extended']?.toString() == 'true';
    final paidAt = _paidAt(payment['paidAt']);
    final regularType = _textValue(payment['regularType'], fallback: '');
    final periodUnit = _textValue(payment['periodUnit'], fallback: '');
    final duration = _amountValue(payment['durationValue'] ?? payment['regularDurationValue']);
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
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _opsLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '₩${won.format(amount)}',
                  style: const TextStyle(
                    color: _opsInk,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
              if (extended) const _StatusBadge(label: '연장', color: _opsBlue),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$paidAt · $paidBy',
            style: const TextStyle(
              color: _opsMuted,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          if (regularType.isNotEmpty || durationText.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              [regularType, durationText].where((e) => e.trim().isNotEmpty).join(' · '),
              style: const TextStyle(
                color: _opsSlate,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ],
          if (hasRange) ...[
            const SizedBox(height: 5),
            Text(
              '적용 기간 $startDate ~ $endDate',
              style: const TextStyle(
                color: _opsGreen,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ],
          if (note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              note,
              style: const TextStyle(
                color: _opsSlate,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OpsActionButton extends StatelessWidget {
  const _OpsActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withOpacity(.35), width: 1.4),
        backgroundColor: color.withOpacity(.06),
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _MonthlyDeleteDialog extends StatelessWidget {
  const _MonthlyDeleteDialog({required this.plateNumber});

  final String plateNumber;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _opsPanel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: const Text(
        '정기권 삭제',
        style: TextStyle(color: _opsInk, fontWeight: FontWeight.w900),
      ),
      content: Text(
        '$plateNumber 정기 주차 정보를 삭제합니다. 삭제 후에는 복구할 수 없습니다.',
        style: const TextStyle(color: _opsSlate, fontWeight: FontWeight.w700),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(backgroundColor: _opsRed),
          child: const Text('삭제'),
        ),
      ],
    );
  }
}

class _MonthlyLoadErrorState extends StatelessWidget {
  const _MonthlyLoadErrorState({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, color: _opsRed, size: 48),
          const SizedBox(height: 12),
          const Text(
            '목록을 불러오지 못했습니다.',
            style: TextStyle(color: _opsInk, fontWeight: FontWeight.w900, fontSize: 17),
          ),
          const SizedBox(height: 8),
          const Text(
            '아래로 당기거나 다시 시도 버튼을 눌러 갱신하세요.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _opsMuted, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {
              onRetry();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('다시 시도'),
          ),
        ],
      ),
    );
  }
}

class _MonthlyLoadingView extends StatelessWidget {
  const _MonthlyLoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: _opsBlue),
    );
  }
}

class _MonthlyEmptyState extends StatelessWidget {
  const _MonthlyEmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _opsPanel,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _opsLine),
              ),
              child: const Icon(Icons.local_parking_outlined, color: _opsSlate, size: 34),
            ),
            const SizedBox(height: 14),
            const Text(
              '등록된 정기 주차가 없습니다.',
              style: TextStyle(color: _opsInk, fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text(
              '신규 등록으로 첫 정기권을 추가하세요.',
              style: TextStyle(color: _opsMuted, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onAdd,
              style: FilledButton.styleFrom(backgroundColor: _opsInk),
              icon: const Icon(Icons.add),
              label: const Text('신규 등록'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthlyNoResultState extends StatelessWidget {
  const _MonthlyNoResultState({required this.onReset});

  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.manage_search, color: _opsSlate, size: 48),
            const SizedBox(height: 12),
            const Text(
              '조건에 맞는 정기권이 없습니다.',
              style: TextStyle(color: _opsInk, fontWeight: FontWeight.w900, fontSize: 17),
            ),
            const SizedBox(height: 8),
            const Text(
              '검색어와 필터를 초기화해보세요.',
              style: TextStyle(color: _opsMuted, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.refresh),
              label: const Text('초기화'),
            ),
          ],
        ),
      ),
    );
  }
}
