import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class StatisticsChartPage extends StatefulWidget {
  final Map<DateTime, Map<String, int>> reportDataMap;

  const StatisticsChartPage({
    super.key,
    required this.reportDataMap,
  });

  @override
  State<StatisticsChartPage> createState() => _StatisticsChartPageState();
}

class _StatisticsChartPageState extends State<StatisticsChartPage> {
  bool showInput = true;
  bool showOutput = true;
  bool showLockedFeeChart = false;

  // ✅ 차트도 좌우 스크롤 지원을 위한 컨트롤러
  final ScrollController _chartHCtrl = ScrollController();

  // ✅ 포인트 1개당 차트 폭(픽셀)
  static const double _chartPointWidth = 56.0;

  @override
  void dispose() {
    _chartHCtrl.dispose();
    super.dispose();
  }

  void _setChartMode(bool isFee) {
    setState(() => showLockedFeeChart = isFee);

    // 모드 변경 시 스크롤 위치가 너무 한쪽에 남아있는 UX 방지
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chartHCtrl.hasClients) _chartHCtrl.jumpTo(0);
    });
  }

  // ✅ 차트 가로 스크롤 래퍼
  Widget _buildScrollableChartArea({
    Key? key,
    required Widget child,
    required int pointCount,
  }) {
    return LayoutBuilder(
      key: key,
      builder: (context, constraints) {
        final minWidth = constraints.maxWidth;

        final desiredWidth = (pointCount * _chartPointWidth) + 24.0;
        final contentWidth = desiredWidth < minWidth ? minWidth : desiredWidth;

        final canScroll = contentWidth > minWidth + 1;

        return Scrollbar(
          controller: _chartHCtrl,
          thumbVisibility: canScroll,
          scrollbarOrientation: ScrollbarOrientation.bottom,
          child: SingleChildScrollView(
            controller: _chartHCtrl,
            scrollDirection: Axis.horizontal,
            physics: canScroll
                ? const BouncingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            child: SizedBox(
              width: contentWidth,
              child: child,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final sortedDates = widget.reportDataMap.keys.toList()..sort();
    final labels =
    sortedDates.map((d) => d.toIso8601String().split('T').first).toList();

    final inSpots = <FlSpot>[];
    final outSpots = <FlSpot>[];
    final feeSpots = <FlSpot>[];

    for (int i = 0; i < sortedDates.length; i++) {
      final date = sortedDates[i];
      final counts = widget.reportDataMap[date] ?? {};

      final inCount = counts['vehicleInput'] ?? counts['입차'] ?? 0;
      final outCount = counts['vehicleOutput'] ?? counts['출차'] ?? 0;
      final fee = counts['totalLockedFee'] ?? counts['정산금'] ?? 0;

      inSpots.add(FlSpot(i.toDouble(), (inCount as num).toDouble()));
      outSpots.add(FlSpot(i.toDouble(), (outCount as num).toDouble()));
      feeSpots.add(FlSpot(i.toDouble(), (fee as num).toDouble()));
    }

    if (sortedDates.length < 2) {
      return Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          title: const Text('통계 그래프'),
          centerTitle: true,
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _ModernEmptyState(
                title: '그래프를 만들 데이터가 부족합니다.',
                message: '통계 데이터가 최소 2개 이상 있어야 추이를 그래프로 표시할 수 있습니다.',
                icon: Icons.show_chart_rounded,
                onAction: () => Navigator.of(context).maybePop(),
                actionText: '뒤로가기',
              ),
            ),
          ),
        ),
      );
    }

    final dailyStats = _buildDailyStats(sortedDates, widget.reportDataMap);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('통계 그래프'),
        centerTitle: true,
        backgroundColor: cs.surface,
        surfaceTintColor: cs.surfaceTint,
        elevation: 0,
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ✅ 상단: "각각의 통계표"를 카드로 분리 -> 가로 스크롤(페이지)로 보기
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              sliver: SliverToBoxAdapter(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: _TopPanel(
                      dailyStats: dailyStats,
                      showLockedFeeChart: showLockedFeeChart,
                      onToggleMode: _setChartMode,
                      showInput: showInput,
                      showOutput: showOutput,
                      onToggleInput: (v) => setState(() => showInput = v),
                      onToggleOutput: (v) => setState(() => showOutput = v),
                    ),
                  ),
                ),
              ),
            ),

            // ✅ 하단: 그래프만(메인 컨텐츠)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              sliver: SliverFillRemaining(
                hasScrollBody: true,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth > 900
                        ? 900.0
                        : constraints.maxWidth;

                    return Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: width,
                        height: constraints.maxHeight,
                        child: _ChartCard(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            // ✅ Clip 제거(툴팁 박스 잘림 방지)
                            child: Container(
                              decoration: BoxDecoration(
                                color: cs.surface,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                switchInCurve: Curves.easeOut,
                                switchOutCurve: Curves.easeOut,
                                child: showLockedFeeChart
                                    ? _buildScrollableChartArea(
                                  key: const ValueKey('scrollFee'),
                                  pointCount: labels.length,
                                  child: LineChart(
                                    _buildFeeChartData(feeSpots, labels),
                                    key: const ValueKey('feeChart'),
                                  ),
                                )
                                    : _buildScrollableChartArea(
                                  key: const ValueKey('scrollVehicle'),
                                  pointCount: labels.length,
                                  child: _buildVehicleChartOrEmpty(
                                    inSpots,
                                    outSpots,
                                    labels,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
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

  Widget _buildVehicleChartOrEmpty(
      List<FlSpot> inSpots,
      List<FlSpot> outSpots,
      List<String> labels,
      ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (!showInput && !showOutput) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.filter_alt_off_rounded, color: cs.outline, size: 40),
              const SizedBox(height: 10),
              Text(
                '표시할 항목이 없습니다.',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                '상단에서 입차/출차 항목을 하나 이상 선택해 주세요.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return LineChart(
      _buildInputOutputChartData(inSpots, outSpots, labels),
      key: const ValueKey('vehicleChart'),
    );
  }

  // ===== ChartData 구성 =====

  LineChartData _buildInputOutputChartData(
      List<FlSpot> inSpots,
      List<FlSpot> outSpots,
      List<String> labels,
      ) {
    return LineChartData(
      titlesData: _buildTitlesData(labels),
      gridData: _buildGrid(),
      borderData: _buildBorder(),
      minY: 0,
      maxY: _calculateMaxY([...inSpots, ...outSpots]),
      lineBarsData: [
        if (showInput)
          LineChartBarData(
            spots: inSpots,
            isCurved: true,
            color: Colors.blue, // ✅ Tooltip에서 Colors.blue 기반으로 "입차" 판별 유지
            dotData: FlDotData(show: true),
            barWidth: 3,
            belowBarData: BarAreaData(show: false),
          ),
        if (showOutput)
          LineChartBarData(
            spots: outSpots,
            isCurved: true,
            color: Colors.red, // ✅ Tooltip에서 Colors.red 기반으로 "출차" 판별 유지
            dotData: FlDotData(show: true),
            barWidth: 3,
            belowBarData: BarAreaData(show: false),
          ),
      ],
      lineTouchData: _buildTouchData(labels, type: 'vehicle'),
    );
  }

  LineChartData _buildFeeChartData(List<FlSpot> feeSpots, List<String> labels) {
    return LineChartData(
      titlesData: _buildTitlesData(labels),
      gridData: _buildGrid(),
      borderData: _buildBorder(),
      minY: 0,
      maxY: _calculateMaxY(feeSpots),
      lineBarsData: [
        LineChartBarData(
          spots: feeSpots,
          isCurved: true,
          color: Colors.green,
          dotData: FlDotData(show: true),
          barWidth: 3,
          belowBarData: BarAreaData(show: false),
        ),
      ],
      lineTouchData: _buildTouchData(labels, type: 'fee'),
    );
  }

  /// ✅ 하단 날짜 겹침 방지(샘플링)
  FlTitlesData _buildTitlesData(List<String> labels) {
    final step = _axisLabelStep(labels.length, maxLabels: 7);

    return FlTitlesData(
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 44,
          interval: null,
          getTitlesWidget: (value, _) => Text(
            value.toInt().toString(),
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
            if (index < 0 || index >= labels.length) {
              return const SizedBox.shrink();
            }

            final isFirst = index == 0;
            final isLast = index == labels.length - 1;
            final shouldShow = isFirst || isLast || (index % step == 0);

            if (!shouldShow) return const SizedBox.shrink();

            return SideTitleWidget(
              axisSide: meta.axisSide,
              space: 6,
              child: Text(
                labels[index].substring(5), // MM-DD
                style: const TextStyle(fontSize: 10),
              ),
            );
          },
        ),
      ),
      topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
    );
  }

  FlGridData _buildGrid() => FlGridData(
    show: true,
    drawVerticalLine: true,
    drawHorizontalLine: true,
    getDrawingHorizontalLine: (value) => FlLine(
      color: Colors.grey.withOpacity(0.2),
      strokeWidth: 1,
    ),
    getDrawingVerticalLine: (value) => FlLine(
      color: Colors.grey.withOpacity(0.2),
      strokeWidth: 1,
    ),
  );

  FlBorderData _buildBorder() => FlBorderData(
    show: true,
    border: const Border(
      left: BorderSide(color: Colors.black),
      bottom: BorderSide(color: Colors.black),
    ),
  );

  /// ✅ Tooltip 잘림 방지: fitInsideVertically / fitInsideHorizontally
  LineTouchData _buildTouchData(List<String> labels, {required String type}) {
    return LineTouchData(
      enabled: true,
      handleBuiltInTouches: true,
      touchTooltipData: LineTouchTooltipData(
        tooltipBgColor: Colors.black87,
        fitInsideHorizontally: true,
        fitInsideVertically: true,
        // 필요 시 살짝 여유를 늘리고 싶으면 값을 조정하세요.
        tooltipMargin: 10,
        getTooltipItems: (spots) {
          return spots.map((spot) {
            final x = spot.x.toInt();
            final label = (x >= 0 && x < labels.length) ? labels[x] : '';
            final value = spot.y.toInt();
            final series = (type == 'fee')
                ? '정산금'
                : (spot.bar.color == Colors.blue ? '입차' : '출차');

            return LineTooltipItem(
              '$label\n$series: ${type == 'fee' ? '₩' : ''}$value',
              const TextStyle(color: Colors.white),
            );
          }).toList();
        },
      ),
    );
  }

  double _calculateMaxY(List<FlSpot> spots) {
    final maxY =
    spots.map((e) => e.y).fold<double>(0, (prev, e) => e > prev ? e : prev);

    // ✅ 기존 1.2 → 1.3: 상단 공간을 조금 더 확보(툴팁이 상단에서 잘리는 케이스 감소)
    return (maxY * 1.3).ceilToDouble();
  }

  // ===== 통계표 데이터 =====

  List<_DailyStat> _buildDailyStats(
      List<DateTime> sortedDates,
      Map<DateTime, Map<String, int>> dataMap,
      ) {
    return sortedDates.map((dt) {
      final counts = dataMap[dt] ?? {};
      final inCount = counts['vehicleInput'] ?? counts['입차'] ?? 0;
      final outCount = counts['vehicleOutput'] ?? counts['출차'] ?? 0;
      final fee = counts['totalLockedFee'] ?? counts['정산금'] ?? 0;

      return _DailyStat(
        date: dt,
        input: inCount,
        output: outCount,
        fee: fee,
      );
    }).toList();
  }
}

// ─────────────────────────────────────────────
// ✅ 상단 패널: 통계표(카드 3개) 가로 스크롤 + 차트 설정
// ─────────────────────────────────────────────

class _TopPanel extends StatelessWidget {
  final List<_DailyStat> dailyStats;

  final bool showLockedFeeChart;
  final ValueChanged<bool> onToggleMode;

  final bool showInput;
  final bool showOutput;
  final ValueChanged<bool> onToggleInput;
  final ValueChanged<bool> onToggleOutput;

  const _TopPanel({
    required this.dailyStats,
    required this.showLockedFeeChart,
    required this.onToggleMode,
    required this.showInput,
    required this.showOutput,
    required this.onToggleInput,
    required this.onToggleOutput,
  });

  double _calcTopTablesHeight(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    final value = h * 0.42; // 카드 내 표(검색/요약/리스트)까지 고려
    if (value < 320) return 320;
    if (value > 440) return 440;
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final tablesHeight = _calcTopTablesHeight(context);

    return Column(
      children: [
        // ✅ 통계표 카드 3개 가로 스크롤
        SizedBox(
          height: tablesHeight,
          child: _StatsTableCarousel(dailyStats: dailyStats),
        ),
        const SizedBox(height: 12),

        // ✅ 차트 설정
        Card(
          elevation: 0,
          color: cs.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: cs.outlineVariant.withOpacity(0.6)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '차트 설정',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(
                      value: false,
                      label: Text('입·출차'),
                      icon: Icon(Icons.directions_car_filled_rounded),
                    ),
                    ButtonSegment<bool>(
                      value: true,
                      label: Text('정산금'),
                      icon: Icon(Icons.payments_rounded),
                    ),
                  ],
                  selected: <bool>{showLockedFeeChart},
                  showSelectedIcon: false,
                  onSelectionChanged: (set) {
                    if (set.isEmpty) return;
                    onToggleMode(set.first);
                  },
                ),
                const SizedBox(height: 12),
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 220),
                  crossFadeState: showLockedFeeChart
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstChild: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilterChip(
                          selected: showInput,
                          onSelected: onToggleInput,
                          label: const Text('입차'),
                          avatar: const Icon(Icons.directions_car_rounded,
                              color: Colors.blue),
                          showCheckmark: false,
                        ),
                        FilterChip(
                          selected: showOutput,
                          onSelected: onToggleOutput,
                          label: const Text('출차'),
                          avatar: const Icon(Icons.exit_to_app_rounded,
                              color: Colors.red),
                          showCheckmark: false,
                        ),
                      ],
                    ),
                  ),
                  secondChild: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '정산금 모드에서는 단일 그래프만 표시됩니다.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

enum _StatTableKind { input, output, fee }

class _StatsTableCarousel extends StatefulWidget {
  final List<_DailyStat> dailyStats;

  const _StatsTableCarousel({
    required this.dailyStats,
  });

  @override
  State<_StatsTableCarousel> createState() => _StatsTableCarouselState();
}

class _StatsTableCarouselState extends State<_StatsTableCarousel> {
  late final PageController _pageCtrl;
  int _index = 0;

  static const _items = <_StatTableKind>[
    _StatTableKind.input,
    _StatTableKind.output,
    _StatTableKind.fee,
  ];

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController(viewportFraction: 0.92);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pageCtrl,
            itemCount: _items.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) {
              final kind = _items[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: _ChartCard(
                  child: _StatisticsTableView(
                    kind: kind,
                    dailyStats: widget.dailyStats,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_items.length, (i) {
            final active = i == _index;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              height: 8,
              width: active ? 18 : 8,
              decoration: BoxDecoration(
                color: active ? cs.primary : cs.outlineVariant.withOpacity(0.9),
                borderRadius: BorderRadius.circular(999),
              ),
            );
          }),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// ✅ 통계표(카드) 뷰
// - 카드별로: 입차 / 출차 / 정산금
// - 카드 내부에서 검색/최근N일/정렬/요약 제공
//
// ✅ 오버플로우 수정안 반영:
//   Column + Expanded(표영역) 구조 제거
//   -> 카드 내부 전체를 CustomScrollView(세로 스크롤)로 변경
// ─────────────────────────────────────────────

enum _TableSortField { date, value }

class _StatisticsTableView extends StatefulWidget {
  final _StatTableKind kind;
  final List<_DailyStat> dailyStats;

  const _StatisticsTableView({
    required this.kind,
    required this.dailyStats,
  });

  @override
  State<_StatisticsTableView> createState() => _StatisticsTableViewState();
}

class _StatisticsTableViewState extends State<_StatisticsTableView> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _vCtrl = ScrollController();

  String _query = '';
  int _quickDays = 0; // 0: 전체, 7: 최근7일, 30: 최근30일

  _TableSortField _sortField = _TableSortField.date;
  bool _ascending = false; // 기본: 날짜 내림차순(최근이 위)

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _vCtrl.dispose();
    super.dispose();
  }

  String _title() {
    switch (widget.kind) {
      case _StatTableKind.input:
        return '입차 통계표';
      case _StatTableKind.output:
        return '출차 통계표';
      case _StatTableKind.fee:
        return '정산금 통계표';
    }
  }

  IconData _icon() {
    switch (widget.kind) {
      case _StatTableKind.input:
        return Icons.directions_car_rounded;
      case _StatTableKind.output:
        return Icons.exit_to_app_rounded;
      case _StatTableKind.fee:
        return Icons.payments_rounded;
    }
  }

  Color _accentColor() {
    switch (widget.kind) {
      case _StatTableKind.input:
        return Colors.blue;
      case _StatTableKind.output:
        return Colors.red;
      case _StatTableKind.fee:
        return Colors.green;
    }
  }

  int _valueOf(_DailyStat d) {
    switch (widget.kind) {
      case _StatTableKind.input:
        return d.input;
      case _StatTableKind.output:
        return d.output;
      case _StatTableKind.fee:
        return d.fee;
    }
  }

  String _valueText(int v) {
    switch (widget.kind) {
      case _StatTableKind.fee:
        return '₩${_fmt(v)}';
      case _StatTableKind.input:
      case _StatTableKind.output:
        return _fmt(v);
    }
  }

  List<_DailyStat> _filtered() {
    final all = widget.dailyStats;
    if (all.isEmpty) return [];

    Iterable<_DailyStat> it = all;

    // 빠른 필터(최근 N일): "데이터 마지막 날짜" 기준
    if (_quickDays > 0) {
      final last = all.last.date;
      final cutoff = last.subtract(Duration(days: _quickDays - 1));
      it = it.where((e) => !e.date.isBefore(cutoff));
    }

    // 검색: yyyy-mm / yyyy-mm-dd 부분검색
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      it = it.where((e) => _dateOnly(e.date).toLowerCase().contains(q));
    }

    final list = it.toList();

    // 정렬
    list.sort((a, b) {
      int cmp;
      switch (_sortField) {
        case _TableSortField.date:
          cmp = a.date.compareTo(b.date);
          break;
        case _TableSortField.value:
          cmp = _valueOf(a).compareTo(_valueOf(b));
          break;
      }
      return _ascending ? cmp : -cmp;
    });

    return list;
  }

  void _toggleSort(_TableSortField field) {
    setState(() {
      if (_sortField == field) {
        _ascending = !_ascending;
      } else {
        _sortField = field;
        _ascending = false;
      }
    });
  }

  _MinMax<_DailyStat> _computeMinMax(List<_DailyStat> items) {
    if (items.isEmpty) return _MinMax(null, null);

    _DailyStat minD = items.first;
    _DailyStat maxD = items.first;

    for (final d in items) {
      final v = _valueOf(d);
      if (v < _valueOf(minD)) minD = d;
      if (v > _valueOf(maxD)) maxD = d;
    }
    return _MinMax(minD, maxD);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final items = _filtered();
    final mm = _computeMinMax(items);

    int sum = 0;
    for (final d in items) {
      sum += _valueOf(d);
    }
    final avg = items.isEmpty ? 0 : (sum / items.length).round();

    return CustomScrollView(
      controller: _vCtrl,
      primary: false,
      physics: const BouncingScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          sliver: SliverToBoxAdapter(
            child: Column(
              children: [
                // 카드 타이틀
                Row(
                  children: [
                    Icon(_icon(), color: _accentColor()),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _title(),
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                    _Pill(
                      text: _quickDays == 0 ? '전체' : '최근 $_quickDays일',
                      icon: Icons.calendar_month_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 검색/필터
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: '날짜 검색 (예: 2025-12 / 2025-12-13)',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                            onPressed: () => _searchController.clear(),
                            icon: const Icon(Icons.clear_rounded),
                          ),
                          filled: true,
                          fillColor: cs.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                                color: cs.outlineVariant.withOpacity(0.6)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                                color: cs.outlineVariant.withOpacity(0.6)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: cs.primary.withOpacity(0.9),
                              width: 1.2,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    PopupMenuButton<int>(
                      tooltip: '빠른 필터',
                      onSelected: (v) => setState(() => _quickDays = v),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 0, child: Text('전체')),
                        PopupMenuItem(value: 7, child: Text('최근 7일')),
                        PopupMenuItem(value: 30, child: Text('최근 30일')),
                      ],
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: cs.outlineVariant.withOpacity(0.6)),
                        ),
                        child: Row(
                          children: const [
                            Icon(Icons.tune_rounded, size: 18),
                            SizedBox(width: 8),
                            Icon(Icons.expand_more_rounded, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 요약(필터 적용 결과)
                Container(
                  width: double.infinity,
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(16),
                    border:
                    Border.all(color: cs.outlineVariant.withOpacity(0.6)),
                  ),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _Pill(
                        text: '${items.length}일',
                        icon: Icons.event_note_rounded,
                      ),
                      _MiniPill(
                        label: '합계',
                        value: _valueText(sum),
                        icon: _icon(),
                        color: _accentColor(),
                      ),
                      _MiniPill(
                        label: '평균',
                        value: _valueText(avg),
                        icon: Icons.functions_rounded,
                        color: cs.primary,
                      ),
                      if (mm.max != null)
                        _MiniPill(
                          label: 'MAX',
                          value: _valueText(_valueOf(mm.max!)),
                          icon: Icons.trending_up_rounded,
                          color: _accentColor(),
                        ),
                      if (mm.min != null)
                        _MiniPill(
                          label: 'MIN',
                          value: _valueText(_valueOf(mm.min!)),
                          icon: Icons.trending_down_rounded,
                          color: _accentColor(),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 표 헤더
                _MetricTableHeader(
                  kind: widget.kind,
                  sortField: _sortField,
                  ascending: _ascending,
                  onTapDate: () => _toggleSort(_TableSortField.date),
                  onTapValue: () => _toggleSort(_TableSortField.value),
                  valueTitle: widget.kind == _StatTableKind.fee ? '정산금' : '대수',
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),

        // 리스트 영역(오버플로우 방지를 위해 Sliver로 스크롤 처리)
        if (items.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inbox_rounded, color: cs.outline, size: 44),
                    const SizedBox(height: 10),
                    Text(
                      '표시할 데이터가 없습니다.',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '검색어 또는 필터 조건을 변경해 보세요.',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: cs.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                    (context, index) {
                  final d = items[index];
                  final isMax = mm.max != null && identical(d, mm.max);
                  final isMin = mm.min != null && identical(d, mm.min);

                  return Padding(
                    padding: EdgeInsets.only(
                        bottom: index == items.length - 1 ? 0 : 8),
                    child: _MetricTableRowCard(
                      kind: widget.kind,
                      daily: d,
                      value: _valueOf(d),
                      valueText: _valueText(_valueOf(d)),
                      isMax: isMax,
                      isMin: isMin,
                      accent: _accentColor(),
                    ),
                  );
                },
                childCount: items.length,
              ),
            ),
          ),
      ],
    );
  }
}

class _MetricTableHeader extends StatelessWidget {
  final _StatTableKind kind;
  final _TableSortField sortField;
  final bool ascending;

  final VoidCallback onTapDate;
  final VoidCallback onTapValue;

  final String valueTitle;

  const _MetricTableHeader({
    required this.kind,
    required this.sortField,
    required this.ascending,
    required this.onTapDate,
    required this.onTapValue,
    required this.valueTitle,
  });

  Widget _title(
      BuildContext context, {
        required String text,
        required bool active,
        required VoidCallback onTap,
        TextAlign align = TextAlign.left,
        int flex = 1,
      }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Expanded(
      flex: flex,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            mainAxisAlignment: align == TextAlign.right
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              Flexible(
                child: Text(
                  text,
                  textAlign: align,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: active ? cs.onSurface : cs.onSurfaceVariant,
                  ),
                ),
              ),
              if (active) ...[
                const SizedBox(width: 4),
                Icon(
                  ascending
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  size: 16,
                  color: cs.primary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
      ),
      child: Row(
        children: [
          _title(
            context,
            text: '날짜',
            active: sortField == _TableSortField.date,
            onTap: onTapDate,
            align: TextAlign.left,
            flex: 6,
          ),
          _title(
            context,
            text: valueTitle,
            active: sortField == _TableSortField.value,
            onTap: onTapValue,
            align: TextAlign.right,
            flex: 4,
          ),
        ],
      ),
    );
  }
}

class _MetricTableRowCard extends StatelessWidget {
  final _StatTableKind kind;
  final _DailyStat daily;
  final int value;
  final String valueText;
  final bool isMax;
  final bool isMin;
  final Color accent;

  const _MetricTableRowCard({
    required this.kind,
    required this.daily,
    required this.value,
    required this.valueText,
    required this.isMax,
    required this.isMin,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _dateOnly(daily.date),
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (isMax) _BadgePill(text: 'MAX', color: accent),
                    if (isMin) _BadgePill(text: 'MIN', color: accent),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                valueText,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 공용 카드 / 빈 상태
// ─────────────────────────────────────────────

class _ChartCard extends StatelessWidget {
  final Widget child;

  const _ChartCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.6)),
      ),
      // ✅ Clip.none: 툴팁 등 오버레이가 카드 라운딩에 의해 잘리는 것 방지
      clipBehavior: Clip.none,
      child: child,
    );
  }
}

class _ModernEmptyState extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;
  final VoidCallback? onAction;
  final String? actionText;

  const _ModernEmptyState({
    required this.title,
    required this.message,
    required this.icon,
    this.onAction,
    this.actionText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: cs.primary),
            const SizedBox(height: 12),
            Text(
              title,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
              textAlign: TextAlign.center,
            ),
            if (onAction != null && actionText != null) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onAction,
                  child: Text(actionText!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final IconData icon;

  const _Pill({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: cs.primary),
          const SizedBox(width: 6),
          Text(
            text,
            style: theme.textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _MiniPill extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MiniPill({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: theme.textTheme.labelMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.labelMedium
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _BadgePill extends StatelessWidget {
  final String text;
  final Color color;

  const _BadgePill({
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: theme.textTheme.labelSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Models + Helpers
// ─────────────────────────────────────────────

class _DailyStat {
  final DateTime date;
  final int input;
  final int output;
  final int fee;

  const _DailyStat({
    required this.date,
    required this.input,
    required this.output,
    required this.fee,
  });
}

class _MinMax<T> {
  final T? min;
  final T? max;
  const _MinMax(this.min, this.max);
}

String _dateOnly(DateTime dt) => dt.toIso8601String().split('T').first;

/// ✅ 천 단위 콤마(음수 대응 포함)
String _fmt(int value) {
  final negative = value < 0;
  final n = negative ? -value : value;

  final s = n.toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    final idxFromEnd = s.length - i;
    buf.write(s[i]);
    if (idxFromEnd > 1 && idxFromEnd % 3 == 1) {
      buf.write(',');
    }
  }

  return negative ? '-${buf.toString()}' : buf.toString();
}

/// ✅ 라벨 샘플링 스텝 계산(최대 maxLabels개 수준으로 표시)
int _axisLabelStep(int len, {int maxLabels = 7}) {
  if (len <= 0) return 1;
  if (len <= maxLabels) return 1;
  final step = (len / maxLabels).ceil();
  return step < 1 ? 1 : step;
}
