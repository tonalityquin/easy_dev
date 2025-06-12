import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class StatisticsChartPage extends StatelessWidget {
  final Map<DateTime, Map<String, int>> reportDataMap;

  const StatisticsChartPage({super.key, required this.reportDataMap});

  @override
  Widget build(BuildContext context) {
    final sortedDates = reportDataMap.keys.toList()..sort();
    final labels = sortedDates.map((d) => d.toIso8601String().split('T').first).toList();

    final inSpots = <FlSpot>[];
    final outSpots = <FlSpot>[];

    for (int i = 0; i < sortedDates.length; i++) {
      final date = sortedDates[i];
      final counts = reportDataMap[date] ?? {};
      final inCount = counts['vehicleInput'] ?? counts['입차'] ?? 0;
      final outCount = counts['vehicleOutput'] ?? counts['출차'] ?? 0;

      final inVal = (inCount as num).toDouble();
      final outVal = (outCount as num).toDouble();

      debugPrint('📊 [$date] 입차: $inVal, 출차: $outVal');

      inSpots.add(FlSpot(i.toDouble(), inVal));
      outSpots.add(FlSpot(i.toDouble(), outVal));
    }

    if (inSpots.length < 2) {
      return Scaffold(
        appBar: AppBar(title: const Text('입·출차 통계 그래프'),
            centerTitle: true,
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            elevation: 0),
        body: const Center(
          child: Text(
            '📊 그래프를 생성하려면 2개 이상의 통계가 필요합니다.',
            style: TextStyle(fontSize: 16),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('입·출차 그래프')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: const [
                Icon(Icons.circle, size: 10, color: Colors.blue),
                SizedBox(width: 4),
                Text("입차", style: TextStyle(fontSize: 12)),
                SizedBox(width: 12),
                Icon(Icons.circle, size: 10, color: Colors.red),
                SizedBox(width: 4),
                Text("출차", style: TextStyle(fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
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
                    LineChartBarData(
                      spots: inSpots,
                      isCurved: true,
                      color: Colors.blue,
                      dotData: FlDotData(show: true),
                      barWidth: 3,
                      belowBarData: BarAreaData(show: false),
                    ),
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
          ],
        ),
      ),
    );
  }

  double _calculateMaxY(List<FlSpot> inSpots, List<FlSpot> outSpots) {
    final maxIn = inSpots.map((e) => e.y).fold<double>(0, (prev, e) => e > prev ? e : prev);
    final maxOut = outSpots.map((e) => e.y).fold<double>(0, (prev, e) => e > prev ? e : prev);
    final max = maxIn > maxOut ? maxIn : maxOut;
    return (max * 1.2).ceilToDouble(); // 최대값보다 20% 여유
  }

  double _calculateInterval(List<FlSpot> inSpots, List<FlSpot> outSpots) {
    final maxY = _calculateMaxY(inSpots, outSpots);
    if (maxY <= 10) return 1;
    if (maxY <= 50) return 5;
    if (maxY <= 100) return 10;
    return 20;
  }
}
