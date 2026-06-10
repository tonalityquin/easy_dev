import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../shared/secondary/widgets/ops_console_widgets.dart';
import '../../dev/application/area_state.dart';
import '../applications/bill_state.dart';
import '../domain/models/bill_model.dart';
import '../domain/models/regular_bill_model.dart';
import 'sheets/bill_bottom_sheet.dart';

class BillManagement extends StatefulWidget {
  const BillManagement({super.key});

  @override
  State<BillManagement> createState() => _BillManagementState();
}

class _BillManagementState extends State<BillManagement> {
  String _query = '';
  BillType? _typeFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<BillState>().manualBillRefresh();
    });
  }

  void _showBillSettingBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return FractionallySizedBox(
          heightFactor: 1,
          child: BillSettingBottomSheet(
            onSave: (billData) async {
              try {
                await context.read<BillState>().addBillFromMap(billData);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('정산 유형을 저장했습니다.')),
                );
              } catch (_) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('정산 유형 저장에 실패했습니다.')),
                );
              }
            },
          ),
        );
      },
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('정산 유형 삭제 확인'),
            content: const Text('선택한 정산 유형을 삭제하시겠습니까?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('삭제'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _deleteSelectedBill(BuildContext context) async {
    final billState = context.read<BillState>();
    final selectedId = billState.selectedBillId;

    if (selectedId == null) return;

    final ok = await _confirmDelete(context);
    if (!ok) return;

    try {
      await billState.deleteBill([selectedId]);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('정산 유형을 삭제했습니다.')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('정산 유형 삭제에 실패했습니다.')),
      );
    }
  }

  Future<void> _refresh(BuildContext context) async {
    await context.read<BillState>().manualBillRefresh();
  }

  bool _matchesQuery(String countType, String area, String extra) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return '$countType $area $extra'.toLowerCase().contains(q);
  }

  Widget _buildGeneralBillRow(BuildContext context, BillState state, BillModel bill, NumberFormat won) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isSelected = state.selectedBillId == bill.id;
    final titleStyle = (tt.titleMedium ?? const TextStyle(fontSize: 16)).copyWith(
      color: cs.onSurface,
      fontWeight: FontWeight.w900,
      letterSpacing: -.15,
    );

    return InkWell(
      onTap: () => state.toggleBillSelection(bill.id),
      borderRadius: BorderRadius.circular(16),
      child: OpsPanel(
        selected: isSelected,
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            Container(
              width: 6,
              height: 124,
              decoration: BoxDecoration(
                color: cs.primary,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(bill.countType, style: titleStyle, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 8),
                        OpsStatusBadge(label: '변동', color: cs.primary, icon: Icons.receipt_long_rounded),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        OpsInfoPill(text: '기본 ${bill.basicStandard ?? 0}분', icon: Icons.timer_rounded),
                        OpsInfoPill(text: '₩${won.format(bill.basicAmount ?? 0)}', icon: Icons.payments_rounded),
                        OpsInfoPill(text: '추가 ${bill.addStandard ?? 0}분', icon: Icons.more_time_rounded),
                        OpsInfoPill(text: '₩${won.format(bill.addAmount ?? 0)}', icon: Icons.add_card_rounded),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Icon(
                isSelected ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
                color: isSelected ? cs.primary : cs.onSurfaceVariant.withOpacity(.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegularBillRow(BuildContext context, BillState state, RegularBillModel bill, NumberFormat won) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isSelected = state.selectedBillId == bill.id;
    final titleStyle = (tt.titleMedium ?? const TextStyle(fontSize: 16)).copyWith(
      color: cs.onSurface,
      fontWeight: FontWeight.w900,
      letterSpacing: -.15,
    );

    return InkWell(
      onTap: () => state.toggleBillSelection(bill.id),
      borderRadius: BorderRadius.circular(16),
      child: OpsPanel(
        selected: isSelected,
        accentColor: cs.secondary,
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            Container(
              width: 6,
              height: 124,
              decoration: BoxDecoration(
                color: cs.secondary,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(bill.countType, style: titleStyle, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 8),
                        OpsStatusBadge(label: '정기', color: cs.secondary, icon: Icons.event_repeat_rounded),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        OpsInfoPill(text: bill.regularType.isEmpty ? '유형 미지정' : bill.regularType, icon: Icons.local_parking_rounded),
                        OpsInfoPill(text: '₩${won.format(bill.regularAmount)}', icon: Icons.payments_rounded),
                        OpsInfoPill(text: '기간값 ${bill.regularDurationValue}', icon: Icons.schedule_rounded),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Icon(
                isSelected ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
                color: isSelected ? cs.secondary : cs.onSurfaceVariant.withOpacity(.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommandBar(BuildContext context, int visible, int total) {
    final cs = Theme.of(context).colorScheme;
    return OpsCommandPanel(
      children: [
        OpsSearchField(
          hint: '정산명 · 기준 · 유형 검색',
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OpsFilterChip(label: '전체', selected: _typeFilter == null, icon: Icons.all_inclusive_rounded, onSelected: () => setState(() => _typeFilter = null)),
            OpsFilterChip(label: '변동', selected: _typeFilter == BillType.general, icon: Icons.receipt_long_rounded, onSelected: () => setState(() => _typeFilter = BillType.general)),
            OpsFilterChip(label: '정기', selected: _typeFilter == BillType.regular, icon: Icons.event_repeat_rounded, onSelected: () => setState(() => _typeFilter = BillType.regular)),
            OpsFilterChip(label: '$visible/$total', selected: false, icon: Icons.filter_alt_rounded, onSelected: () {}),
            IconButton.filledTonal(
              tooltip: '새로고침',
              onPressed: () => _refresh(context),
              icon: Icon(Icons.refresh_rounded, color: cs.primary),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBottomBar(BuildContext context, bool hasSelection) {
    return OpsBottomActionBar(
      children: [
        Expanded(
          child: OpsActionButton(
            label: '정산 유형 등록',
            icon: Icons.add_card_rounded,
            onPressed: () => _showBillSettingBottomSheet(context),
          ),
        ),
        if (hasSelection) ...[
          const SizedBox(width: 8),
          Expanded(
            child: OpsActionButton(
              label: '삭제',
              icon: Icons.delete_forever_rounded,
              onPressed: () => _deleteSelectedBill(context),
              danger: true,
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentArea = context.watch<AreaState>().currentArea.trim();
    final hasSelection = context.select<BillState, bool>((s) => s.selectedBillId != null);
    final won = NumberFormat.decimalPattern();
    final cs = Theme.of(context).colorScheme;
    final areaLabel = currentArea.isEmpty ? '지역 전체' : currentArea;

    return Consumer<BillState>(
      builder: (context, state, child) {
        final generalBills = state.generalBills.where((bill) => currentArea.isEmpty || bill.area.trim() == currentArea).toList();
        final regularBills = state.regularBills.where((bill) => currentArea.isEmpty || bill.area.trim() == currentArea).toList();
        final visibleGeneral = (_typeFilter == null || _typeFilter == BillType.general)
            ? generalBills.where((bill) => _matchesQuery(bill.countType, bill.area, '${bill.basicStandard} ${bill.basicAmount} ${bill.addStandard} ${bill.addAmount}')).toList()
            : <BillModel>[];
        final visibleRegular = (_typeFilter == null || _typeFilter == BillType.regular)
            ? regularBills.where((bill) => _matchesQuery(bill.countType, bill.area, '${bill.regularType} ${bill.regularAmount} ${bill.regularDurationValue}')).toList()
            : <RegularBillModel>[];
        final total = generalBills.length + regularBills.length;
        final visible = visibleGeneral.length + visibleRegular.length;

        return OpsConsoleScaffold(
          title: '정산 관리',
          icon: Icons.receipt_long_rounded,
          areaLabel: areaLabel,
          loading: state.isLoading,
          metrics: [
            OpsMetric(label: '전체', value: '$total', icon: Icons.receipt_rounded, color: cs.onInverseSurface),
            OpsMetric(label: '변동', value: '${generalBills.length}', icon: Icons.dynamic_feed_rounded, color: cs.primary),
            OpsMetric(label: '정기', value: '${regularBills.length}', icon: Icons.event_repeat_rounded, color: cs.secondary),
            OpsMetric(label: '선택', value: hasSelection ? '1' : '0', icon: Icons.touch_app_rounded, color: hasSelection ? cs.primary : cs.onInverseSurface),
          ],
          commandBar: _buildCommandBar(context, visible, total),
          bottomBar: _buildBottomBar(context, hasSelection),
          body: state.isLoading
              ? const SizedBox.shrink()
              : visible == 0
                  ? OpsEmptyState(
                      icon: Icons.receipt_long_rounded,
                      title: total == 0 ? '정산 유형이 없습니다' : '검색 결과가 없습니다',
                      message: total == 0 ? '운영 지점에 맞는 요금 기준을 등록하세요.' : '검색어와 유형 필터를 조정하세요.',
                      action: FilledButton.icon(
                        onPressed: () => _showBillSettingBottomSheet(context),
                        icon: const Icon(Icons.add_card_rounded),
                        label: const Text('정산 유형 등록'),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                      children: [
                        if (visibleGeneral.isNotEmpty) ...[
                          _BillSectionHeader(title: '변동 정산', count: visibleGeneral.length, icon: Icons.dynamic_feed_rounded),
                          const SizedBox(height: 8),
                          ...visibleGeneral.map((bill) => _buildGeneralBillRow(context, state, bill, won)),
                        ],
                        if (visibleRegular.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          _BillSectionHeader(title: '정기 정산', count: visibleRegular.length, icon: Icons.event_repeat_rounded),
                          const SizedBox(height: 8),
                          ...visibleRegular.map((bill) => _buildRegularBillRow(context, state, bill, won)),
                        ],
                      ],
                    ),
        );
      },
    );
  }
}

class _BillSectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final IconData icon;

  const _BillSectionHeader({required this.title, required this.count, required this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 0),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              style: (tt.titleSmall ?? const TextStyle(fontSize: 14)).copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          OpsInfoPill(text: '$count건'),
        ],
      ),
    );
  }
}
