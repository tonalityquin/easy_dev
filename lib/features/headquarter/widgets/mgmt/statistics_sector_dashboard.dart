import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import 'statistics_deep_model.dart';
import 'statistics_report_design.dart';

class StatisticsSectorDashboard extends StatefulWidget {
  final StatisticsDeepReport report;

  const StatisticsSectorDashboard({
    super.key,
    required this.report,
  });

  @override
  State<StatisticsSectorDashboard> createState() =>
      _StatisticsSectorDashboardState();
}

class _StatisticsSectorDashboardState
    extends State<StatisticsSectorDashboard> {
  static const int _maxSelectedSectorCount = 5;
  late Set<String> _selectedKeys;
  bool _allSelected = false;

  StatisticsSectorReport? get _sectorReport => widget.report.sectorReport;

  @override
  void initState() {
    super.initState();
    _selectedKeys = <String>{
      ...?_sectorReport?.defaultSelectedSectorKeys,
    };
    debugPrint(
      '[STAT_SECTOR] dashboard init area=${widget.report.area} '
      'groups=${_sectorReport?.groups.length ?? 0} '
      'analyzable=${_sectorReport?.analyzableVehicleCount ?? 0} '
      'unavailable=${_sectorReport?.unavailableVehicleCount ?? 0} '
      'selected=${_selectedKeys.join(',')}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final sectorReport = _sectorReport;
    if (sectorReport == null) return const SizedBox.shrink();

    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion ? Duration.zero : PromptUiMotion.layout;

    if (!sectorReport.hasAnalyzableData || sectorReport.groups.isEmpty) {
      return TweenAnimationBuilder<double>(
        duration: duration,
        curve: PromptUiMotion.enter,
        tween: Tween<double>(begin: reduceMotion ? 1 : 0, end: 1),
        builder: (context, value, child) => Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 16),
            child: child,
          ),
        ),
        child: _SectorPanel(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(
                  Icons.map_outlined,
                  size: 42,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 12),
                const Text(
                  '선택한 로그에는 방문 구역 원천 필드가 없어 Sector 통계를 생성하지 않았습니다.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  '전체 ${sectorReport.totalVehicleCount}대가 기본 통계에는 포함되며 방문 구역 분석에서만 제외됩니다.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final selectedGroups = _allSelected
        ? <StatisticsSectorGroup>[
            sectorReport.combinedGroup(label: '전체'),
          ]
        : sectorReport.groupsForKeys(_selectedKeys);
    final selectedRows = _allSelected
        ? sectorReport.rowsForKeys(
            sectorReport.selectableSectorKeys.toSet(),
          )
        : sectorReport.rowsForKeys(_selectedKeys);
    final selectedGroupCount =
        _allSelected ? sectorReport.groups.length : selectedGroups.length;
    final unavailableRows = widget.report.rows
        .where((row) => row.sectorState == StatisticsSectorState.unavailable)
        .toList()
      ..sort((a, b) {
        final dateCompare = a.dateStr.compareTo(b.dateStr);
        if (dateCompare != 0) return dateCompare;
        return a.plateNumber.compareTo(b.plateNumber);
      });
    final numberedUnavailableRows = <StatisticsDeepVehicleRow>[
      for (int i = 0; i < unavailableRows.length; i++)
        unavailableRows[i].copyWith(no: i + 1),
    ];
    final selectionKey = _allSelected
        ? 'all'
        : selectedGroups.map((e) => e.key).join('|');

    return TweenAnimationBuilder<double>(
      duration: duration,
      curve: PromptUiMotion.enter,
      tween: Tween<double>(begin: reduceMotion ? 1 : 0, end: 1),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 18),
            child: child,
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectorHeader(report: widget.report),
          const SizedBox(height: 12),
          _SectorSourceCoverageCard(report: sectorReport),
          const SizedBox(height: 12),
          _SectorIntegrityCard(integrity: sectorReport.integrity),
          const SizedBox(height: 12),
          _SectorFilterCard(
            groups: sectorReport.groups,
            selectedKeys: _selectedKeys,
            allSelected: _allSelected,
            maxSelectedCount: _maxSelectedSectorCount,
            onChanged: _onSectorChanged,
            onSelectAllTotal: _selectAllTotal,
            onSelectTop: _selectTop,
            onSelectAll: _selectAll,
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: duration,
            switchInCurve: PromptUiMotion.enter,
            switchOutCurve: PromptUiMotion.exit,
            transitionBuilder: (child, animation) {
              if (reduceMotion) return child;
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.025, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: Column(
              key: ValueKey<String>(selectionKey),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectorSelectionSummary(
                  groups: selectedGroups,
                  rows: selectedRows,
                ),
                const SizedBox(height: 12),
                _SectorVehicleBarChart(groups: selectedGroups),
                const SizedBox(height: 12),
                _SectorDailyLineChart(
                  groups: selectedGroups,
                  dateStrs: sectorReport.dateStrs,
                ),
                const SizedBox(height: 12),
                _SectorHourlyLineChart(
                  title: '시간대별 Sector 입차',
                  subtitle: '입차 시각을 기준으로 00시부터 23시까지 집계했습니다.',
                  groups: selectedGroups,
                  input: true,
                ),
                const SizedBox(height: 12),
                _SectorHourlyLineChart(
                  title: '시간대별 Sector 출차',
                  subtitle: '확정 및 보조 출차 시각을 기준으로 집계했습니다.',
                  groups: selectedGroups,
                  input: false,
                ),
                const SizedBox(height: 12),
                _SectorFeeBarChart(groups: selectedGroups),
                const SizedBox(height: 12),
                _SectorPaymentChart(groups: selectedGroups),
                const SizedBox(height: 12),
                _SectorWeekdayTable(groups: selectedGroups),
                const SizedBox(height: 12),
                _SectorFeeStatisticsTable(groups: selectedGroups),
                const SizedBox(height: 12),
                _SectorVehicleTable(
                  rows: selectedRows,
                  selectedGroupCount: selectedGroupCount,
                ),
              ],
            ),
          ),
          if (numberedUnavailableRows.isNotEmpty) ...[
            const SizedBox(height: 12),
            _SectorVehicleTable(
              rows: numberedUnavailableRows,
              selectedGroupCount: 0,
              title: '방문 구역 원천 데이터 없는 차량 로그',
              subtitle: '${numberedUnavailableRows.length}대 · Sector 통계 제외',
            ),
          ],
        ],
      ),
    );
  }

  void _onSectorChanged(String key, bool selected) {
    final next = <String>{..._selectedKeys};
    if (selected) {
      if (next.length >= _maxSelectedSectorCount) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('비교할 방문 구역은 최대 5개까지 선택할 수 있습니다.')),
        );
        debugPrint(
          '[STAT_SECTOR] filter rejected key=$key reason=maxSelection',
        );
        return;
      }
      next.add(key);
    } else {
      next.remove(key);
    }
    setState(() {
      _allSelected = next.isEmpty;
      _selectedKeys = next;
    });
    debugPrint(
      next.isEmpty
          ? '[STAT_SECTOR] filter all selected by empty selection'
          : '[STAT_SECTOR] filter selected=${next.join(',')}',
    );
  }

  void _selectTop() {
    final sectorReport = _sectorReport;
    if (sectorReport == null) return;
    setState(() {
      _allSelected = false;
      _selectedKeys = sectorReport.groups
          .where((group) => group.state == StatisticsSectorState.assigned)
          .take(3)
          .map((group) => group.key)
          .toSet();
      if (_selectedKeys.isEmpty) {
        _selectedKeys = sectorReport.groups
            .take(3)
            .map((group) => group.key)
            .toSet();
      }
    });
    debugPrint('[STAT_SECTOR] filter top selected=${_selectedKeys.join(',')}');
  }

  void _selectAllTotal() {
    setState(() {
      _allSelected = true;
      _selectedKeys = <String>{};
    });
    debugPrint('[STAT_SECTOR] filter all selected');
  }

  void _selectAll() {
    final sectorReport = _sectorReport;
    if (sectorReport == null) return;
    final next = sectorReport.groups
        .take(_maxSelectedSectorCount)
        .map((group) => group.key)
        .toSet();
    setState(() {
      _allSelected = false;
      _selectedKeys = next;
    });
    debugPrint('[STAT_SECTOR] filter first selected=${next.join(',')}');
  }
}

class _SectorHeader extends StatelessWidget {
  final StatisticsDeepReport report;

  const _SectorHeader({required this.report});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return _SectorPanel(
      emphasized: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.hub_rounded, color: cs.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '방문 구역 분석',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${report.area} · ${report.scopeLabel} · 당일 완료 업무 기준',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
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

class _SectorSourceCoverageCard extends StatelessWidget {
  final StatisticsSectorReport report;

  const _SectorSourceCoverageCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final complete = report.sourceFieldComplete;
    return AnimatedContainer(
      duration: MediaQuery.maybeOf(context)?.disableAnimations == true
          ? Duration.zero
          : PromptUiMotion.layout,
      curve: PromptUiMotion.enter,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: complete ? cs.primaryContainer : cs.tertiaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            complete ? Icons.dataset_rounded : Icons.info_outline_rounded,
            color: complete ? cs.onPrimaryContainer : cs.onTertiaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  complete ? '방문 구역 원천 데이터 전체 사용' : '일부 차량의 방문 구역 원천 데이터 제외',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: complete
                        ? cs.onPrimaryContainer
                        : cs.onTertiaryContainer,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '전체 ${report.totalVehicleCount}대 · 분석 가능 ${report.analyzableVehicleCount}대 · 원천 없음 ${report.unavailableVehicleCount}대 · 분석률 ${(report.analyzableRatio * 100).toStringAsFixed(1)}%',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: complete
                        ? cs.onPrimaryContainer
                        : cs.onTertiaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (!complete) ...[
                  const SizedBox(height: 4),
                  Text(
                    '원천 필드가 없는 차량은 기본 차량 통계에는 포함되지만 Sector 비중과 그래프에서는 제외됩니다.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onTertiaryContainer,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectorIntegrityCard extends StatelessWidget {
  final StatisticsSectorIntegrity integrity;

  const _SectorIntegrityCard({required this.integrity});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final valid = integrity.isValid;
    return _SectorPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                valid ? Icons.verified_rounded : Icons.error_rounded,
                color: valid ? Colors.green : cs.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  valid ? '화면·PDF 집계 무결성 정상' : '화면·PDF 집계 무결성 확인 필요',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _IntegrityPill(
                label:
                    '분석 차량 ${integrity.groupedVehicleCount}/${integrity.analyzableVehicleCount}',
                ok: integrity.vehicleCountMatched,
              ),
              _IntegrityPill(
                label: '원천 없음 ${integrity.unavailableVehicleCount}대',
                ok: integrity.unavailableVehicleCount == 0,
              ),
              _IntegrityPill(
                label:
                    '입차 ${integrity.groupedInputCount}/${integrity.inputTimestampVehicleCount}',
                ok: integrity.inputCountMatched,
              ),
              _IntegrityPill(
                label:
                    '정산 ₩${_fmt(integrity.groupedLockedFee)}/₩${_fmt(integrity.totalLockedFee)}',
                ok: integrity.lockedFeeMatched,
              ),
              _IntegrityPill(
                label: '미지정 ${integrity.unassignedVehicleCount}대',
                ok: true,
              ),
              _IntegrityPill(
                label: '확인 필요 ${integrity.invalidVehicleCount}대',
                ok: integrity.invalidVehicleCount == 0,
              ),
              _IntegrityPill(
                label: '출차 추정 ${integrity.estimatedOutputTimeCount}대',
                ok: integrity.estimatedOutputTimeCount == 0,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IntegrityPill extends StatelessWidget {
  final String label;
  final bool ok;

  const _IntegrityPill({required this.label, required this.ok});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: ok ? cs.primaryContainer : cs.errorContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: ok ? cs.onPrimaryContainer : cs.onErrorContainer,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _SectorFilterCard extends StatelessWidget {
  final List<StatisticsSectorGroup> groups;
  final Set<String> selectedKeys;
  final bool allSelected;
  final int maxSelectedCount;
  final void Function(String key, bool selected) onChanged;
  final VoidCallback onSelectAllTotal;
  final VoidCallback onSelectTop;
  final VoidCallback onSelectAll;

  const _SectorFilterCard({
    required this.groups,
    required this.selectedKeys,
    required this.allSelected,
    required this.maxSelectedCount,
    required this.onChanged,
    required this.onSelectAllTotal,
    required this.onSelectTop,
    required this.onSelectAll,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return _SectorPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.filter_alt_rounded, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '방문 구역 선택',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                allSelected ? '전체' : '${selectedKeys.length}/$maxSelectedCount',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                avatar: const Icon(Icons.select_all_rounded, size: 18),
                label: const Text('전체'),
                selected: allSelected,
                onSelected: (_) => onSelectAllTotal(),
              ),
              ActionChip(
                avatar: const Icon(Icons.leaderboard_rounded, size: 18),
                label: const Text('상위 3개'),
                onPressed: onSelectTop,
              ),
              ActionChip(
                avatar: const Icon(Icons.checklist_rounded, size: 18),
                label: const Text('앞 5개'),
                onPressed: onSelectAll,
              ),
              for (final group in groups)
                FilterChip(
                  label: Text('${group.sectorLabel} ${group.inputCount}대'),
                  selected: !allSelected && selectedKeys.contains(group.key),
                  onSelected: (selected) => onChanged(group.key, selected),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectorSelectionSummary extends StatelessWidget {
  final List<StatisticsSectorGroup> groups;
  final List<StatisticsDeepVehicleRow> rows;

  const _SectorSelectionSummary({
    required this.groups,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    final input = groups.fold<int>(0, (p, e) => p + e.inputCount);
    final output = groups.fold<int>(0, (p, e) => p + e.outputCount);
    final fee = groups.fold<int>(0, (p, e) => p + e.totalLockedFee);
    final estimated =
        groups.fold<int>(0, (p, e) => p + e.estimatedDepartureCount);
    return _SectorPanel(
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _SectorMetricTile(
            label: '선택 구역',
            value: '${groups.length}개',
            icon: Icons.hub_rounded,
          ),
          _SectorMetricTile(
            label: '완료 차량',
            value: '${rows.length}대',
            icon: Icons.directions_car_filled_rounded,
          ),
          _SectorMetricTile(
            label: '입차 집계',
            value: '${input}대',
            icon: Icons.login_rounded,
          ),
          _SectorMetricTile(
            label: '출차 집계',
            value: '${output}대',
            icon: Icons.logout_rounded,
          ),
          _SectorMetricTile(
            label: '잠금 금액',
            value: '₩${_fmt(fee)}',
            icon: Icons.payments_rounded,
          ),
          _SectorMetricTile(
            label: '출차 추정',
            value: '${estimated}대',
            icon: Icons.schedule_rounded,
          ),
        ],
      ),
    );
  }
}

class _SectorVehicleBarChart extends StatelessWidget {
  final List<StatisticsSectorGroup> groups;

  const _SectorVehicleBarChart({required this.groups});

  @override
  Widget build(BuildContext context) {
    final sorted = groups.toList()
      ..sort((a, b) {
        final cmp = b.inputCount.compareTo(a.inputCount);
        if (cmp != 0) return cmp;
        return a.sectorLabel.compareTo(b.sectorLabel);
      });
    return _ChartPanel(
      title: 'Sector별 입차 대수',
      subtitle: '당일 완료 업무 차량 중 입차 시각이 확인된 차량을 비교합니다.',
      child: SizedBox(
        height: math.max(260, sorted.length * 44).toDouble(),
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: _barMax(sorted.map((e) => e.inputCount.toDouble())),
            barTouchData: BarTouchData(
              enabled: true,
              touchTooltipData: BarTouchTooltipData(
                tooltipBgColor: Theme.of(context).colorScheme.inverseSurface,
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  final item = sorted[group.x.toInt()];
                  return BarTooltipItem(
                    '${item.sectorLabel}\n${rod.toY.toInt()}대',
                    TextStyle(
                      color: Theme.of(context).colorScheme.onInverseSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  );
                },
              ),
            ),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  getTitlesWidget: (value, meta) => Text(
                    value.toInt().toString(),
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 68,
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (index < 0 || index >= sorted.length) {
                      return const SizedBox.shrink();
                    }
                    return SideTitleWidget(
                      axisSide: meta.axisSide,
                      space: 8,
                      child: SizedBox(
                        width: 76,
                        child: Text(
                          sorted[index].sectorLabel,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    );
                  },
                ),
              ),
              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            gridData: FlGridData(show: true, drawVerticalLine: false),
            borderData: FlBorderData(show: false),
            barGroups: [
              for (int i = 0; i < sorted.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: sorted[i].inputCount.toDouble(),
                      color: Theme.of(context).colorScheme.primary,
                      width: 20,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectorDailyLineChart extends StatelessWidget {
  final List<StatisticsSectorGroup> groups;
  final List<String> dateStrs;

  const _SectorDailyLineChart({
    required this.groups,
    required this.dateStrs,
  });

  @override
  Widget build(BuildContext context) {
    final dates = <String>{...dateStrs};
    for (final group in groups) {
      dates.addAll(group.dailyInputCounts.keys);
    }
    final sortedDates = dates.toList()..sort();
    return _ChartPanel(
      title: '날짜별 Sector 입차 추이',
      subtitle: '차량의 실제 입차 날짜를 기준으로 비교합니다.',
      child: _MultiSeriesLineChart(
        labels: sortedDates.map(_shortDate).toList(),
        series: [
          for (final group in groups)
            _ChartSeries(
              label: group.sectorLabel,
              values: [
                for (final date in sortedDates)
                  (group.dailyInputCounts[date] ?? 0).toDouble(),
              ],
            ),
        ],
        valueSuffix: '대',
      ),
    );
  }
}

class _SectorHourlyLineChart extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<StatisticsSectorGroup> groups;
  final bool input;

  const _SectorHourlyLineChart({
    required this.title,
    required this.subtitle,
    required this.groups,
    required this.input,
  });

  @override
  Widget build(BuildContext context) {
    return _ChartPanel(
      title: title,
      subtitle: subtitle,
      child: _MultiSeriesLineChart(
        labels: List<String>.generate(
          24,
          (index) => index.toString().padLeft(2, '0'),
        ),
        series: [
          for (final group in groups)
            _ChartSeries(
              label: group.sectorLabel,
              values: (input
                      ? group.hourlyInputCounts
                      : group.hourlyOutputCounts)
                  .map((e) => e.toDouble())
                  .toList(),
            ),
        ],
        valueSuffix: '대',
      ),
    );
  }
}

class _SectorFeeBarChart extends StatelessWidget {
  final List<StatisticsSectorGroup> groups;

  const _SectorFeeBarChart({required this.groups});

  @override
  Widget build(BuildContext context) {
    final sorted = groups.toList()
      ..sort((a, b) {
        final cmp = b.totalLockedFee.compareTo(a.totalLockedFee);
        if (cmp != 0) return cmp;
        return a.sectorLabel.compareTo(b.sectorLabel);
      });
    return _ChartPanel(
      title: 'Sector별 잠금 금액',
      subtitle: '차량 수와 다른 단위이므로 별도 그래프로 제공합니다.',
      child: SizedBox(
        height: math.max(260, sorted.length * 44).toDouble(),
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: _barMax(sorted.map((e) => e.totalLockedFee.toDouble())),
            barTouchData: BarTouchData(
              enabled: true,
              touchTooltipData: BarTouchTooltipData(
                tooltipBgColor: Theme.of(context).colorScheme.inverseSurface,
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  final item = sorted[group.x.toInt()];
                  return BarTooltipItem(
                    '${item.sectorLabel}\n₩${_fmt(rod.toY.round())}',
                    TextStyle(
                      color: Theme.of(context).colorScheme.onInverseSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  );
                },
              ),
            ),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 54,
                  getTitlesWidget: (value, meta) => Text(
                    _compactAmount(value),
                    style: const TextStyle(fontSize: 9),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 68,
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (index < 0 || index >= sorted.length) {
                      return const SizedBox.shrink();
                    }
                    return SideTitleWidget(
                      axisSide: meta.axisSide,
                      space: 8,
                      child: SizedBox(
                        width: 76,
                        child: Text(
                          sorted[index].sectorLabel,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    );
                  },
                ),
              ),
              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            gridData: FlGridData(show: true, drawVerticalLine: false),
            borderData: FlBorderData(show: false),
            barGroups: [
              for (int i = 0; i < sorted.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: sorted[i].totalLockedFee.toDouble(),
                      color: Theme.of(context).colorScheme.tertiary,
                      width: 20,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectorPaymentChart extends StatelessWidget {
  final List<StatisticsSectorGroup> groups;

  const _SectorPaymentChart({required this.groups});

  @override
  Widget build(BuildContext context) {
    final methods = <String>{};
    for (final group in groups) {
      methods.addAll(group.feeByPaymentMethod.keys);
    }
    final sortedMethods = methods.toList()..sort();
    final colors = _seriesColors(
      context,
      math.max(sortedMethods.length, 1).toInt(),
    );
    final maxTotal = groups.fold<int>(
      0,
      (maxValue, group) => math
          .max(
            maxValue,
            group.feeByPaymentMethod.values.fold<int>(
              0,
              (p, e) => p + e,
            ),
          )
          .toInt(),
    );

    return _ChartPanel(
      title: 'Sector별 결제수단 금액',
      subtitle: '선택한 방문 구역의 결제수단별 잠금 금액을 누적 막대로 표시합니다.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              for (int i = 0; i < sortedMethods.length; i++)
                _LegendItem(
                  color: colors[i],
                  label: sortedMethods[i],
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 280,
            child: groups.isEmpty
                ? const Center(child: Text('표시할 방문 구역을 선택해 주세요.'))
                : BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: _barMax(<double>[maxTotal.toDouble()]),
                      barTouchData: BarTouchData(enabled: true),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 54,
                            getTitlesWidget: (value, meta) => Text(
                              _compactAmount(value),
                              style: const TextStyle(fontSize: 9),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 64,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if (index < 0 || index >= groups.length) {
                                return const SizedBox.shrink();
                              }
                              return SideTitleWidget(
                                axisSide: meta.axisSide,
                                space: 8,
                                child: SizedBox(
                                  width: 72,
                                  child: Text(
                                    groups[index].sectorLabel,
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        topTitles:
                            AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles:
                            AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      gridData:
                          FlGridData(show: true, drawVerticalLine: false),
                      borderData: FlBorderData(show: false),
                      barGroups: [
                        for (int groupIndex = 0;
                            groupIndex < groups.length;
                            groupIndex++)
                          _paymentBarGroup(
                            groupIndex: groupIndex,
                            group: groups[groupIndex],
                            methods: sortedMethods,
                            colors: colors,
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  BarChartGroupData _paymentBarGroup({
    required int groupIndex,
    required StatisticsSectorGroup group,
    required List<String> methods,
    required List<Color> colors,
  }) {
    var cursor = 0.0;
    final stackItems = <BarChartRodStackItem>[];
    for (int i = 0; i < methods.length; i++) {
      final value = (group.feeByPaymentMethod[methods[i]] ?? 0).toDouble();
      if (value <= 0) continue;
      stackItems.add(
        BarChartRodStackItem(cursor, cursor + value, colors[i]),
      );
      cursor += value;
    }
    return BarChartGroupData(
      x: groupIndex,
      barRods: [
        BarChartRodData(
          toY: cursor,
          width: 24,
          borderRadius: BorderRadius.circular(6),
          rodStackItems: stackItems,
          color: colors.first,
        ),
      ],
    );
  }
}

class _SectorWeekdayTable extends StatelessWidget {
  final List<StatisticsSectorGroup> groups;

  const _SectorWeekdayTable({required this.groups});

  @override
  Widget build(BuildContext context) {
    return _ChartPanel(
      title: '요일별 Sector 상세 분석',
      subtitle: '실제 입차일의 요일을 기준으로 합계와 1일 평균을 계산합니다.',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: DataTable(
          columns: const [
            DataColumn(label: Text('방문 구역')),
            DataColumn(label: Text('요일')),
            DataColumn(label: Text('입차 합계')),
            DataColumn(label: Text('대상 일수')),
            DataColumn(label: Text('1일 평균')),
          ],
          rows: [
            for (final group in groups)
              for (int weekday = 1; weekday <= 7; weekday++)
                if ((group.weekdayDateCounts[weekday] ?? 0) > 0)
                  DataRow(
                    cells: [
                      DataCell(Text(group.sectorLabel)),
                      DataCell(Text('${_weekdayName(weekday)}요일')),
                      DataCell(
                        Text('${group.weekdayInputCounts[weekday] ?? 0}대'),
                      ),
                      DataCell(
                        Text('${group.weekdayDateCounts[weekday] ?? 0}일'),
                      ),
                      DataCell(
                        Text(
                          '${group.inputAverageForWeekday(weekday).toStringAsFixed(1)}대',
                        ),
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}

class _SectorFeeStatisticsTable extends StatelessWidget {
  final List<StatisticsSectorGroup> groups;

  const _SectorFeeStatisticsTable({required this.groups});

  @override
  Widget build(BuildContext context) {
    return _ChartPanel(
      title: 'Sector별 평균 정산액 고급 비교',
      subtitle: '금액이 존재하는 차량만 분모로 사용하며 표본 수를 함께 제공합니다.',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: DataTable(
          columns: const [
            DataColumn(label: Text('방문 구역')),
            DataColumn(label: Text('표본')),
            DataColumn(label: Text('평균')),
            DataColumn(label: Text('중앙값')),
            DataColumn(label: Text('최솟값')),
            DataColumn(label: Text('최댓값')),
            DataColumn(label: Text('25%')),
            DataColumn(label: Text('75%')),
          ],
          rows: [
            for (final group in groups)
              DataRow(
                cells: [
                  DataCell(Text(group.sectorLabel)),
                  DataCell(Text('${group.feeVehicleCount}대')),
                  DataCell(Text(_moneyOrDash(group.averageLockedFee))),
                  DataCell(Text(_moneyOrDash(group.medianLockedFee))),
                  DataCell(Text(_moneyOrDash(group.minLockedFee))),
                  DataCell(Text(_moneyOrDash(group.maxLockedFee))),
                  DataCell(Text(_moneyOrDash(group.lowerQuartileLockedFee))),
                  DataCell(Text(_moneyOrDash(group.upperQuartileLockedFee))),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _SectorVehicleTable extends StatelessWidget {
  final List<StatisticsDeepVehicleRow> rows;
  final int selectedGroupCount;
  final String title;
  final String? subtitle;

  const _SectorVehicleTable({
    required this.rows,
    required this.selectedGroupCount,
    this.title = '선택 Sector 차량 로그',
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _ChartPanel(
      title: title,
      subtitle: subtitle ?? '$selectedGroupCount개 방문 구역 · ${rows.length}대',
      child: rows.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('표시할 차량 데이터가 없습니다.')),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: DataTable(
                headingRowColor:
                    WidgetStatePropertyAll(cs.surfaceContainerHighest),
                columns: const [
                  DataColumn(label: Text('번호')),
                  DataColumn(label: Text('날짜')),
                  DataColumn(label: Text('차량 번호')),
                  DataColumn(label: Text('방문 구역')),
                  DataColumn(label: Text('입차 시간')),
                  DataColumn(label: Text('출차 시간')),
                  DataColumn(label: Text('정산액')),
                  DataColumn(label: Text('결제수단')),
                ],
                rows: [
                  for (final row in rows)
                    DataRow(
                      cells: [
                        DataCell(Text(row.no.toString())),
                        DataCell(Text(row.dateStr)),
                        DataCell(Text(row.plateNumber)),
                        DataCell(Text(row.sectorLabel)),
                        DataCell(Text(_fmtTime(row.createdAt))),
                        DataCell(
                          Text(
                            row.departureTimeEstimated
                                ? '${_fmtTime(row.departureAt)} · 추정'
                                : _fmtTime(row.departureAt),
                          ),
                        ),
                        DataCell(
                          Text(row.fee == null ? '-' : '₩${_fmt(row.fee!)}'),
                        ),
                        DataCell(Text(row.paymentMethodLabel)),
                      ],
                    ),
                ],
              ),
            ),
    );
  }
}

class _MultiSeriesLineChart extends StatelessWidget {
  final List<String> labels;
  final List<_ChartSeries> series;
  final String valueSuffix;

  const _MultiSeriesLineChart({
    required this.labels,
    required this.series,
    required this.valueSuffix,
  });

  @override
  Widget build(BuildContext context) {
    if (series.isEmpty || labels.isEmpty) {
      return const SizedBox(
        height: 220,
        child: Center(child: Text('표시할 방문 구역을 선택해 주세요.')),
      );
    }
    final colors = _seriesColors(context, series.length);
    final maxValue = series
        .expand((e) => e.values)
        .fold<double>(0, (p, e) => math.max(p, e));
    final cs = Theme.of(context).colorScheme;
    final width = math.max(640, labels.length * 34).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            for (int i = 0; i < series.length; i++)
              _LegendItem(color: colors[i], label: series[i].label),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: SizedBox(
            width: width,
            height: 280,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: (labels.length - 1).toDouble(),
                minY: 0,
                maxY: maxValue <= 0 ? 5 : (maxValue * 1.3).ceilToDouble(),
                gridData: FlGridData(
                  show: true,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: cs.outlineVariant.withOpacity(0.45),
                    strokeWidth: 1,
                  ),
                  getDrawingVerticalLine: (value) => FlLine(
                    color: cs.outlineVariant.withOpacity(0.28),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border(
                    left: BorderSide(color: cs.outline),
                    bottom: BorderSide(color: cs.outline),
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 42,
                      getTitlesWidget: (value, meta) => Text(
                        value.toInt().toString(),
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      reservedSize: 44,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= labels.length) {
                          return const SizedBox.shrink();
                        }
                        return SideTitleWidget(
                          axisSide: meta.axisSide,
                          space: 8,
                          child: Text(
                            labels[index],
                            style: const TextStyle(fontSize: 10),
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                lineBarsData: [
                  for (int i = 0; i < series.length; i++)
                    LineChartBarData(
                      spots: [
                        for (int j = 0; j < series[i].values.length; j++)
                          FlSpot(j.toDouble(), series[i].values[j]),
                      ],
                      isCurved: true,
                      color: colors[i],
                      barWidth: 3,
                      dotData: FlDotData(show: labels.length <= 31),
                      belowBarData: BarAreaData(
                        show: i == 0,
                        color: colors[i].withOpacity(0.06),
                      ),
                    ),
                ],
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    tooltipBgColor: cs.inverseSurface,
                    getTooltipItems: (spots) => spots.map((spot) {
                      final seriesIndex = spot.barIndex;
                      final labelIndex = spot.x.toInt();
                      final axisLabel = labelIndex >= 0 && labelIndex < labels.length
                          ? labels[labelIndex]
                          : '-';
                      return LineTooltipItem(
                        '${series[seriesIndex].label}\n$axisLabel · ${spot.y.toInt()}$valueSuffix',
                        TextStyle(
                          color: cs.onInverseSurface,
                          fontWeight: FontWeight.w800,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ChartSeries {
  final String label;
  final List<double> values;

  const _ChartSeries({required this.label, required this.values});
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _SectorMetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _SectorMetricTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      width: 166,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: cs.primary, size: 20),
          const SizedBox(height: 8),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectorPanel extends StatelessWidget {
  final Widget child;
  final bool emphasized;

  const _SectorPanel({
    required this.child,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: StatisticsReportDesign.screenPanel(
        context,
        emphasized: emphasized,
      ),
      child: child,
    );
  }
}

class _ChartPanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _ChartPanel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return _SectorPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

List<Color> _seriesColors(BuildContext context, int count) {
  final cs = Theme.of(context).colorScheme;
  final base = <Color>[
    cs.primary,
    cs.secondary,
    cs.tertiary,
    cs.error,
    cs.inversePrimary,
  ];
  return List<Color>.generate(count, (index) {
    if (index < base.length) return base[index];
    final color = base[index % base.length];
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withHue(((hsl.hue + index * 37) % 360).toDouble())
        .withSaturation(math.max(0.45, hsl.saturation).toDouble())
        .toColor();
  });
}

double _barMax(Iterable<double> values) {
  final maxValue = values.fold<double>(
    0,
    (p, e) => math.max(p, e).toDouble(),
  );
  if (maxValue <= 0) return 5;
  return (maxValue * 1.25).ceilToDouble();
}

String _fmt(int value) {
  final text = value.abs().toString();
  final buffer = StringBuffer();
  for (int i = 0; i < text.length; i++) {
    if (i > 0 && (text.length - i) % 3 == 0) buffer.write(',');
    buffer.write(text[i]);
  }
  return value < 0 ? '-$buffer' : buffer.toString();
}

String _moneyOrDash(num? value) {
  if (value == null) return '-';
  return '₩${_fmt(value.round())}';
}

String _compactAmount(double value) {
  if (value.abs() >= 100000000) {
    return '${(value / 100000000).toStringAsFixed(1)}억';
  }
  if (value.abs() >= 10000) {
    return '${(value / 10000).toStringAsFixed(0)}만';
  }
  return value.toInt().toString();
}

String _shortDate(String value) {
  if (value.length >= 10) return value.substring(5);
  return value;
}

String _fmtTime(DateTime? value) {
  if (value == null) return '-';
  return '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}:'
      '${value.second.toString().padLeft(2, '0')}';
}

String _weekdayName(int weekday) {
  switch (weekday) {
    case 1:
      return '월';
    case 2:
      return '화';
    case 3:
      return '수';
    case 4:
      return '목';
    case 5:
      return '금';
    case 6:
      return '토';
    case 7:
      return '일';
  }
  return '-';
}
