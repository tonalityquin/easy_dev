import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class StatisticsChartPage extends StatefulWidget {
  final Map<DateTime, Map<String, int>> reportDataMap;

  const StatisticsChartPage({super.key, required this.reportDataMap});

  @override
  State<StatisticsChartPage> createState() => _StatisticsChartPageState();
}

class _StatisticsChartPageState extends State<StatisticsChartPage> {
  bool showInput = true;
  bool showOutput = true;

  @override
  Widget build(BuildContext context) {
    final sortedDates = widget.reportDataMap.keys.toList()..sort();
    final labels = sortedDates.map((d) => d.toIso8601String().split('T').first).toList();

    final inSpots = <FlSpot>[];
    final outSpots = <FlSpot>[];

    for (int i = 0; i < sortedDates.length; i++) {
      final date = sortedDates[i];
      final counts = widget.reportDataMap[date] ?? {};
      final inCount = counts['vehicleInput'] ?? counts['입차'] ?? 0;
      final outCount = counts['vehicleOutput'] ?? counts['출차'] ?? 0;

      final inVal = (inCount as num).toDouble();
      final outVal = (outCount as num).toDouble();

      inSpots.add(FlSpot(i.toDouble(), inVal));
      outSpots.add(FlSpot(i.toDouble(), outVal));
    }

    if (inSpots.length < 2) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('입·출차 통계 그래프'),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        body: const Center(
          child: Text(
            '📊 그래프를 생성하려면 2개 이상의 통계가 필요합니다.',
            style: TextStyle(fontSize: 16),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('입·출차 그래프'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 표시 옵션
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                child: Column(
                  children: [
                    const Text('그래프 표시 항목', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Switch(
                              value: showInput,
                              onChanged: (val) => setState(() => showInput = val),
                            ),
                            const Icon(Icons.directions_car, color: Colors.blue),
                            const SizedBox(width: 4),
                            const Text("입차"),
                          ],
                        ),
                        const SizedBox(width: 20),
                        Row(
                          children: [
                            Switch(
                              value: showOutput,
                              onChanged: (val) => setState(() => showOutput = val),
                            ),
                            const Icon(Icons.exit_to_app, color: Colors.red),
                            const SizedBox(width: 4),
                            const Text("출차"),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: LineChart(
                    LineChartData(
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            interval: _calculateInterval(inSpots, outSpots),
                            getTitlesWidget: (value, _) {
                              return Text(
                                value.toInt().toString(),
                                style: const TextStyle(fontSize: 10),
                              );
                            },
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            interval: 1,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if (index < 0 || index >= labels.length) return const SizedBox.shrink();
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
                      ),
                      gridData: FlGridData(
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
                      ),
                      borderData: FlBorderData(
                        show: true,
                        border: const Border(
                          left: BorderSide(color: Colors.black),
                          bottom: BorderSide(color: Colors.black),
                        ),
                      ),
                      minY: 0,
                      maxY: _calculateMaxY(inSpots, outSpots),
                      lineBarsData: [
                        if (showInput)
                          LineChartBarData(
                            spots: inSpots,
                            isCurved: true,
                            color: Colors.blue,
                            dotData: FlDotData(show: true),
                            barWidth: 3,
                            belowBarData: BarAreaData(show: false),
                          ),
                        if (showOutput)
                          LineChartBarData(
                            spots: outSpots,
                            isCurved: true,
                            color: Colors.red,
                            dotData: FlDotData(show: true),
                            barWidth: 3,
                            belowBarData: BarAreaData(show: false),
                          ),
                      ],
                      lineTouchData: LineTouchData(
                        enabled: true,
                        touchTooltipData: LineTouchTooltipData(
                          tooltipBgColor: Colors.black87,
                          getTooltipItems: (spots) {
                            return spots.map((spot) {
                              final label = labels[spot.x.toInt()];
                              final value = spot.y.toInt();
                              final type = spot.bar.color == Colors.blue ? '입차' : '출차';
                              return LineTooltipItem(
                                '$label\n$type: $value',
                                const TextStyle(color: Colors.white),
                              );
                            }).toList();
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _calculateMaxY(List<FlSpot> inSpots, List<FlSpot> outSpots) {
    final maxIn = inSpots.map((e) => e.y).fold<double>(0, (prev, e) => e > prev ? e : prev);
    final maxOut = outSpots.map((e) => e.y).fold<double>(0, (prev, e) => e > prev ? e : prev);
    final max = maxIn > maxOut ? maxIn : maxOut;
    return (max * 1.2).ceilToDouble();
  }

  double _calculateInterval(List<FlSpot> inSpots, List<FlSpot> outSpots) {
    final maxY = _calculateMaxY(inSpots, outSpots);
    if (maxY <= 10) return 1;
    if (maxY <= 50) return 5;
    if (maxY <= 100) return 10;
    return 20;
  }
}
