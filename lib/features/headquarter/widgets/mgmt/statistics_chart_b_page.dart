import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'statistics_deep_model.dart';
import 'statistics_report_design.dart';

class StatisticsChartBPage extends StatefulWidget {
  final StatisticsDeepReport report;

  const StatisticsChartBPage({
    super.key,
    required this.report,
  });

  @override
  State<StatisticsChartBPage> createState() => _StatisticsChartBPageState();
}

class _StatisticsChartBPageState extends State<StatisticsChartBPage> {
  final ScrollController _scrollController = ScrollController();
  late final Map<String, GlobalKey> _sectionKeys;
  String _selectedId = 'cover';
  bool _tocOpen = false;

  @override
  void initState() {
    super.initState();
    _sectionKeys = <String, GlobalKey>{
      'cover': GlobalKey(),
      'summary': GlobalKey(),
      for (final section in widget.report.sections) section.id: GlobalKey(),
    };
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pop(widget.report);
        return false;
      },
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          leading: BackButton(
            onPressed: () => Navigator.of(context).pop(widget.report),
          ),
          title: const Text('통계 그래프 B'),
          centerTitle: true,
          backgroundColor: cs.surface,
          foregroundColor: cs.onSurface,
          surfaceTintColor: cs.surfaceTint,
          elevation: 0,
          actions: [
            IconButton(
              tooltip: _tocOpen ? '목차 닫기' : '목차 열기',
              onPressed: () => setState(() => _tocOpen = !_tocOpen),
              icon: Icon(_tocOpen ? Icons.close_rounded : Icons.menu_book_rounded),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _ReportCover(
                            key: _sectionKeys['cover'],
                            report: widget.report,
                          ),
                          const SizedBox(height: 14),
                          _ReportSummary(
                            key: _sectionKeys['summary'],
                            report: widget.report,
                          ),
                          const SizedBox(height: 14),
                          _DeepSectionView(
                            key: _sectionKeys[widget.report.overallSection.id],
                            section: widget.report.overallSection,
                          ),
                          const SizedBox(height: 14),
                          _GroupTitle(
                            icon: Icons.event_note_rounded,
                            title: '날짜별 심화 통계',
                            subtitle: '${widget.report.dailySections.length}개 날짜 기준으로 각각 생성했습니다.',
                          ),
                          const SizedBox(height: 10),
                          for (final section in widget.report.dailySections) ...[
                            _DeepSectionView(
                              key: _sectionKeys[section.id],
                              section: section,
                            ),
                            const SizedBox(height: 14),
                          ],
                          _GroupTitle(
                            icon: Icons.calendar_view_week_rounded,
                            title: '요일별 심화 통계',
                            subtitle: widget.report.weekdaySections.isEmpty
                                ? '동일 요일이 2일 이상 포함된 데이터가 없어 요일별 섹션을 만들지 않았습니다.'
                                : '${widget.report.weekdaySections.length}개 요일 기준으로 통산 합계와 평균을 생성했습니다.',
                          ),
                          const SizedBox(height: 10),
                          if (widget.report.weekdaySections.isEmpty)
                            const _EmptyReportPanel(text: '동일 요일이 겹치는 날짜가 없습니다.')
                          else
                            for (final section in widget.report.weekdaySections) ...[
                              _DeepSectionView(
                                key: _sectionKeys[section.id],
                                section: section,
                              ),
                              const SizedBox(height: 14),
                            ],
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
                  if (_tocOpen)
                    _ReportTocOverlay(
                      width: math.min(390.0, math.max(300.0, constraints.maxWidth * 0.86)),
                      report: widget.report,
                      selectedId: _selectedId,
                      onTap: _scrollTo,
                      onClose: () => setState(() => _tocOpen = false),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _scrollTo(String id) async {
    if (id.endsWith('_group')) return;
    final key = _sectionKeys[id];
    final context = key?.currentContext;
    if (context == null) return;
    setState(() {
      _selectedId = id;
      _tocOpen = false;
    });
    await Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      alignment: 0.02,
    );
  }
}

class _ReportTocOverlay extends StatelessWidget {
  final double width;
  final StatisticsDeepReport report;
  final String selectedId;
  final ValueChanged<String> onTap;
  final VoidCallback onClose;

  const _ReportTocOverlay({
    required this.width,
    required this.report,
    required this.selectedId,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            child: Container(color: Colors.black.withOpacity(0.26)),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: SizedBox(
                width: width,
                height: double.infinity,
                child: _ReportTocPanel(
                  report: report,
                  selectedId: selectedId,
                  onTap: onTap,
                  onClose: onClose,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportCover extends StatelessWidget {
  final StatisticsDeepReport report;

  const _ReportCover({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: StatisticsReportDesign.screenPanel(context, emphasized: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(Icons.auto_graph_rounded, color: cs.onPrimary, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Deep Statistics Report',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '통계 그래프 B',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            '${report.division} / ${report.area}',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            report.scopeLabel,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatisticsReportDesign.screenPill(context: context, icon: Icons.event_rounded, text: '${report.dateStrs.length}일', strong: true),
              StatisticsReportDesign.screenPill(context: context, icon: Icons.directions_car_rounded, text: '${report.rows.length}대'),
              StatisticsReportDesign.screenPill(context: context, icon: Icons.storage_rounded, text: '파일 ${report.objectNames.length}개'),
              StatisticsReportDesign.screenPill(context: context, icon: Icons.payments_rounded, text: '₩${_fmt(report.totalFee)}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReportSummary extends StatelessWidget {
  final StatisticsDeepReport report;

  const _ReportSummary({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: StatisticsReportDesign.screenPanel(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeaderLine(
            icon: Icons.dashboard_rounded,
            title: '보고서 요약',
            subtitle: '전체, 날짜별, 요일별 섹션이 동일한 데이터 모델에서 생성됩니다.',
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetricTile(label: '대상 차량', value: '${report.rows.length}대', icon: Icons.directions_car_filled_rounded),
              _MetricTile(label: '입차 집계', value: '${_fmt(report.totalInput)}대', icon: Icons.login_rounded),
              _MetricTile(label: '출차 집계', value: '${_fmt(report.totalOutput)}대', icon: Icons.logout_rounded),
              _MetricTile(label: '정산액 합계', value: '₩${_fmt(report.totalFee)}', icon: Icons.payments_rounded),
              _MetricTile(label: '날짜별 페이지', value: '${report.dailySections.length}개', icon: Icons.event_note_rounded),
              _MetricTile(label: '요일별 페이지', value: '${report.weekdaySections.length}개', icon: Icons.calendar_view_week_rounded),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReportTocPanel extends StatelessWidget {
  final StatisticsDeepReport report;
  final String selectedId;
  final ValueChanged<String> onTap;
  final VoidCallback onClose;

  const _ReportTocPanel({
    required this.report,
    required this.selectedId,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      constraints: const BoxConstraints(maxHeight: double.infinity),
      padding: const EdgeInsets.all(14),
      decoration: StatisticsReportDesign.screenTocPanel(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.segment_rounded, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '목차',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                tooltip: '목차 닫기',
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              physics: const BouncingScrollPhysics(),
              itemCount: report.tocItems.length,
              itemBuilder: (context, index) {
                final item = report.tocItems[index];
                if (item.isGroup) {
                  return Padding(
                    padding: EdgeInsets.fromLTRB(8 + item.level * 12.0, 14, 8, 6),
                    child: Text(
                      item.title,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  );
                }
                final selected = selectedId == item.id;
                return Padding(
                  padding: EdgeInsets.only(left: item.level * 12.0, bottom: 6),
                  child: Material(
                    color: selected ? cs.primaryContainer : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => onTap(item.id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                        child: Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: selected ? cs.onPrimaryContainer : cs.onSurface,
                            fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DeepSectionView extends StatelessWidget {
  final StatisticsDeepSection section;

  const _DeepSectionView({super.key, required this.section});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: StatisticsReportDesign.screenPanel(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeaderLine(
            icon: _iconFor(section.type),
            title: section.title,
            subtitle: _sectionSubtitle(section),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetricTile(label: '차량', value: '${section.rows.length}대', icon: Icons.directions_car_rounded),
              _MetricTile(label: '대상 날짜', value: '${section.sourceDateCount}일', icon: Icons.event_rounded),
              _MetricTile(label: '입차 합계', value: '${_fmt(section.metrics.inputTotalSum)}대', icon: Icons.login_rounded),
              _MetricTile(label: '출차 합계', value: '${_fmt(section.metrics.outputTotalSum)}대', icon: Icons.logout_rounded),
              _MetricTile(label: '정산액', value: '₩${_fmt(section.totalFee)}', icon: Icons.payments_rounded),
            ],
          ),
          const SizedBox(height: 14),
          _ChartGrid(section: section),
          const SizedBox(height: 14),
          _VehicleTableCard(rows: section.rows),
        ],
      ),
    );
  }

  IconData _iconFor(StatisticsDeepSectionType type) {
    switch (type) {
      case StatisticsDeepSectionType.overall:
        return Icons.public_rounded;
      case StatisticsDeepSectionType.date:
        return Icons.event_rounded;
      case StatisticsDeepSectionType.weekday:
        return Icons.calendar_view_week_rounded;
    }
  }

  String _sectionSubtitle(StatisticsDeepSection section) {
    if (section.type == StatisticsDeepSectionType.date) {
      return '${section.subtitle} / 해당 날짜 단일 집계';
    }
    if (section.showAverageCharts) {
      return '${section.subtitle} / 통산 합계와 ${section.sourceDateCount}일 기준 평균';
    }
    return section.subtitle;
  }
}

class _ChartGrid extends StatelessWidget {
  final StatisticsDeepSection section;

  const _ChartGrid({required this.section});

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      _HourlyChartCard(
        title: '입차 통산 합계',
        subtitle: '생성 시간 기준',
        values: section.metrics.inputTotalCounts.map((e) => e.toDouble()).toList(),
        icon: Icons.login_rounded,
        valueSuffix: '대',
      ),
      _HourlyChartCard(
        title: '출차 통산 합계',
        subtitle: '출차 시간 기준',
        values: section.metrics.outputTotalCounts.map((e) => e.toDouble()).toList(),
        icon: Icons.logout_rounded,
        valueSuffix: '대',
      ),
    ];

    if (section.showAverageCharts) {
      children.addAll([
        _HourlyChartCard(
          title: '입차 평균',
          subtitle: '${section.sourceDateCount}일 기준 시간대별 평균',
          values: section.metrics.inputAverageCounts,
          icon: Icons.stacked_line_chart_rounded,
          valueSuffix: '대',
          decimal: true,
        ),
        _HourlyChartCard(
          title: '출차 평균',
          subtitle: '${section.sourceDateCount}일 기준 시간대별 평균',
          values: section.metrics.outputAverageCounts,
          icon: Icons.show_chart_rounded,
          valueSuffix: '대',
          decimal: true,
        ),
      ]);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumn = constraints.maxWidth >= 920;
        if (!twoColumn) {
          return Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i != children.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        }
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final child in children)
              SizedBox(
                width: (constraints.maxWidth - 12) / 2,
                child: child,
              ),
          ],
        );
      },
    );
  }
}

class _HourlyChartCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<double> values;
  final IconData icon;
  final String valueSuffix;
  final bool decimal;

  const _HourlyChartCard({
    required this.title,
    required this.subtitle,
    required this.values,
    required this.icon,
    required this.valueSuffix,
    this.decimal = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasData = values.fold<double>(0, (p, e) => p + e) > 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = math.max(constraints.maxWidth, 24 * 45.0);
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: SizedBox(
                  width: width,
                  height: 240,
                  child: hasData
                      ? LineChart(_chartData(context))
                      : const Center(child: Text('표시할 데이터가 없습니다.')),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  LineChartData _chartData(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LineChartData(
      minX: 0,
      maxX: 23,
      minY: 0,
      maxY: _maxY(values),
      gridData: FlGridData(
        show: true,
        drawHorizontalLine: true,
        drawVerticalLine: true,
        getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.withOpacity(0.2), strokeWidth: 1),
        getDrawingVerticalLine: (value) => FlLine(color: Colors.grey.withOpacity(0.2), strokeWidth: 1),
      ),
      borderData: FlBorderData(
        show: true,
        border: const Border(
          left: BorderSide(color: Colors.black54),
          bottom: BorderSide(color: Colors.black54),
        ),
      ),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 42,
            getTitlesWidget: (value, _) => Text(
              decimal ? value.toStringAsFixed(1) : value.toInt().toString(),
              style: const TextStyle(fontSize: 10),
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 1,
            reservedSize: 34,
            getTitlesWidget: (value, meta) {
              final index = value.toInt();
              if (index < 0 || index > 23) return const SizedBox.shrink();
              return SideTitleWidget(
                axisSide: meta.axisSide,
                space: 6,
                child: Text(index.toString().padLeft(2, '0'), style: const TextStyle(fontSize: 10)),
              );
            },
          ),
        ),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: List.generate(24, (i) => FlSpot(i.toDouble(), values[i])),
          isCurved: true,
          color: cs.primary,
          barWidth: 3,
          dotData: FlDotData(show: true),
          belowBarData: BarAreaData(show: true, color: cs.primary.withOpacity(0.08)),
        ),
      ],
      lineTouchData: LineTouchData(
        enabled: true,
        touchTooltipData: LineTouchTooltipData(
          tooltipBgColor: Colors.black87,
          getTooltipItems: (spots) => spots.map((spot) {
            final hour = spot.x.toInt().clamp(0, 23);
            final value = decimal ? spot.y.toStringAsFixed(1) : spot.y.toInt().toString();
            return LineTooltipItem(
              '${hour.toString().padLeft(2, '0')}시\n$value$valueSuffix',
              const TextStyle(color: Colors.white),
            );
          }).toList(),
        ),
      ),
    );
  }

  double _maxY(List<double> values) {
    final maxValue = values.fold<double>(0, (p, e) => e > p ? e : p);
    if (maxValue <= 0) return decimal ? 5 : 10;
    return (maxValue * 1.3).ceilToDouble();
  }
}

class _VehicleTableCard extends StatelessWidget {
  final List<StatisticsDeepVehicleRow> rows;

  const _VehicleTableCard({required this.rows});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.table_chart_rounded, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('차량 상세표', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
              ),
              StatisticsReportDesign.screenPill(context: context, icon: Icons.directions_car_filled_rounded, text: '${rows.length}대'),
            ],
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('표시할 차량 데이터가 없습니다.')),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: DataTable(
                headingRowColor: WidgetStatePropertyAll(cs.surfaceContainerHighest),
                columns: const [
                  DataColumn(label: Text('넘버링')),
                  DataColumn(label: Text('날짜')),
                  DataColumn(label: Text('차량 번호')),
                  DataColumn(label: Text('생성 시간')),
                  DataColumn(label: Text('출차 시간')),
                  DataColumn(label: Text('정산액')),
                ],
                rows: [
                  for (final row in rows)
                    DataRow(
                      cells: [
                        DataCell(Text(row.no.toString())),
                        DataCell(Text(row.dateStr)),
                        DataCell(Text(row.plateNumber)),
                        DataCell(Text(_fmtTime(row.createdAt))),
                        DataCell(Text(_fmtTime(row.departureAt))),
                        DataCell(Text(row.fee == null ? '-' : '₩${_fmt(row.fee!)}')),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      width: 170,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
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
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _SectionHeaderLine extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionHeaderLine({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: cs.onPrimaryContainer),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GroupTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _GroupTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Row(
        children: [
          Icon(icon, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
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

class _EmptyReportPanel extends StatelessWidget {
  final String text;

  const _EmptyReportPanel({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: StatisticsReportDesign.screenPanel(context),
      child: Center(
        child: Text(
          text,
          style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

String _fmtTime(DateTime? dt) {
  if (dt == null) return '-';
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

String _fmt(int value) {
  final negative = value < 0;
  final n = negative ? -value : value;
  final s = n.toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    final idxFromEnd = s.length - i;
    buf.write(s[i]);
    if (idxFromEnd > 1 && idxFromEnd % 3 == 1) buf.write(',');
  }
  return negative ? '-${buf.toString()}' : buf.toString();
}
