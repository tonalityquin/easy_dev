import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../features/dev/application/area_state.dart';
import '../../../../features/plate/application/triple/triple_plate_state.dart';
import '../../../../features/plate/domain/enums/plate_type.dart';
import '../../../../features/plate/domain/models/plate_model.dart';
import 'departure_completed_plate_search_bottom_sheet/triple_departure_completed_search_bottom_sheet.dart';

class TripleDepartureCompletedUnsettledTab extends StatefulWidget {
  const TripleDepartureCompletedUnsettledTab({
    super.key,
    required this.firestorePlates,
    required this.userName,
  });

  final List<PlateModel> firestorePlates;
  final String userName;

  @override
  State<TripleDepartureCompletedUnsettledTab> createState() =>
      _TripleDepartureCompletedUnsettledTabState();
}

class _TripleDepartureCompletedUnsettledTabState
    extends State<TripleDepartureCompletedUnsettledTab> {
  DateTime _sortTime(PlateModel p) => p.requestTime;

  DateTime _ymd(DateTime t) => DateTime(t.year, t.month, t.day);

  static const List<String> _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  String _formatYmdWithWeekday(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    final w = _weekdays[d.weekday - 1];
    return '${d.year}.$mm.$dd ($w)';
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final plateState = context.read<TriplePlateState>();
      final area = context.read<AreaState>().currentArea.trim();
      if (area.isEmpty) return;

      if (!plateState.isLoadingType(PlateType.departureCompleted)) {
        await plateState.tripleRefreshType(PlateType.departureCompleted);
      }
    });
  }

  Future<void> _openPlateSearchBottomSheet() async {
    final area = context.read<AreaState>().currentArea.trim();
    if (area.isEmpty) {
      return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TripleDepartureCompletedSearchBottomSheet(
        area: area,
        onSearch: (_) {},
      ),
    );
  }

  Future<void> _refreshUnsettled() async {
    final plateState = context.read<TriplePlateState>();
    final area = context.read<AreaState>().currentArea.trim();

    if (area.isEmpty) {
      return;
    }

    await plateState.tripleRefreshType(PlateType.departureCompleted);

    if (!mounted) return;

    plateState.tripleLastRefreshAtOf(PlateType.departureCompleted);
    plateState.tripleLastRefreshSourceLabelOf(PlateType.departureCompleted);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final plateState = context.watch<TriplePlateState>();

    final raw = plateState.dataOfType(PlateType.departureCompleted);

    final plates = raw.where((p) => p.isLockedFee != true).toList()
      ..sort((a, b) => _sortTime(a).compareTo(_sortTime(b)));
    final bool isRefreshing =
        plateState.isLoadingType(PlateType.departureCompleted);

    final Map<DateTime, int> dateCounts = <DateTime, int>{};
    for (final p in plates) {
      final d = _ymd(_sortTime(p));
      dateCounts[d] = (dateCounts[d] ?? 0) + 1;
    }

    final listChildren = <Widget>[
      if (plates.isEmpty)
        const _EmptyState(
          icon: Icons.inbox_outlined,
          title: '표시할 미정산 번호판이 없습니다',
          message: '데이터 갱신 또는 번호판 검색을 사용해 보세요.',
        )
      else
        ..._buildGroupedList(plates, dateCounts),
      const SizedBox(height: 12),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        color: cs.primary,
        backgroundColor: cs.surface,
        onRefresh: _refreshUnsettled,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          children: listChildren,
        ),
      ),
      bottomNavigationBar: _BottomBar(
        isRefreshing: isRefreshing,
        onRefreshPressed: isRefreshing ? null : _refreshUnsettled,
        onSearchPressed: _openPlateSearchBottomSheet,
      ),
    );
  }

  List<Widget> _buildGroupedList(
    List<PlateModel> plates,
    Map<DateTime, int> dateCounts,
  ) {
    final widgets = <Widget>[];
    DateTime? currentDate;

    for (final p in plates) {
      final t = _sortTime(p);
      final d = _ymd(t);

      if (currentDate == null || currentDate != d) {
        currentDate = d;

        if (widgets.isNotEmpty) {
          widgets.add(const SizedBox(height: 10));
        }

        final count = dateCounts[d] ?? 0;
        widgets.add(
          _DateDivider(
            label: _formatYmdWithWeekday(d),
            count: count,
          ),
        );
        widgets.add(const SizedBox(height: 10));
      }

      widgets.add(_UnsettledPlateCard(plate: p, requestTime: t));
      widgets.add(const SizedBox(height: 8));
    }

    return widgets;
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 32, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: cs.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: text.titleSmall?.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ) ??
                  TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ) ??
                  TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatUnsettledCardDateTime(DateTime t) {
  final mm = t.month.toString().padLeft(2, '0');
  final dd = t.day.toString().padLeft(2, '0');
  final hh = t.hour.toString().padLeft(2, '0');
  final mi = t.minute.toString().padLeft(2, '0');
  return '$mm.$dd $hh:$mi';
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.isRefreshing,
    required this.onRefreshPressed,
    required this.onSearchPressed,
  });

  final bool isRefreshing;
  final Future<void> Function()? onRefreshPressed;
  final Future<void> Function() onSearchPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: isRefreshing
                    ? null
                    : () async {
                        await onRefreshPressed?.call();
                      },
                icon: isRefreshing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: Text(isRefreshing ? '갱신 중' : '새로고침'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: () async {
                  await onSearchPressed();
                },
                icon: const Icon(Icons.search_rounded),
                label: const Text('번호판 검색'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateDivider extends StatelessWidget {
  const _DateDivider({
    required this.label,
    required this.count,
  });

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(child: Divider(color: cs.outlineVariant)),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: cs.surfaceVariant,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Divider(color: cs.outlineVariant)),
      ],
    );
  }
}

class _UnsettledPlateCard extends StatelessWidget {
  const _UnsettledPlateCard({
    required this.plate,
    required this.requestTime,
  });

  final PlateModel plate;
  final DateTime requestTime;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final location =
        plate.location.trim().isEmpty ? '미지정' : plate.location.trim();
    final fee = plate.lockedFeeAmount;
    final selectedBy = (plate.selectedBy ?? '').trim();
    final userName = plate.userName.trim();

    return Card(
      elevation: 0,
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    plate.plateNumber,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                if (fee != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '₩$fee',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.location_on_outlined,
                    size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    location,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.schedule_rounded,
                        size: 16, color: cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(
                      _formatUnsettledCardDateTime(requestTime),
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
                if (selectedBy.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_outline_rounded,
                          size: 16, color: cs.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Text(
                        selectedBy,
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ],
                  )
                else if (userName.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_outline_rounded,
                          size: 16, color: cs.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Text(
                        userName,
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
