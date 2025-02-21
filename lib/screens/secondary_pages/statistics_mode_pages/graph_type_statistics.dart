import 'package:flutter/material.dart';
import 'dart:math';

class GraphTypeStatistics extends StatefulWidget {
  @override
  _GraphTypeStatisticsState createState() => _GraphTypeStatisticsState();
}

class _GraphTypeStatisticsState extends State<GraphTypeStatistics> {
  bool isBarChart = true; // 현재 그래프 타입 (true: Bar Chart, false: Line Chart)
  final Random random = Random();

  /// 📊 막대 그래프 데이터 (월별 데이터 예제)
  List<int> barData = List.generate(12, (index) => Random().nextInt(100));

  /// 📈 선 그래프 데이터 (주별 데이터 예제)
  List<int> lineData = List.generate(10, (index) => Random().nextInt(50));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("📊 Graph Type Statistics"),
        actions: [
          IconButton(
            icon: Icon(isBarChart ? Icons.show_chart : Icons.bar_chart),
            onPressed: () {
              setState(() {
                isBarChart = !isBarChart; // 그래프 타입 변경
              });
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              isBarChart ? "📊 월별 통계 (Bar Chart)" : "📈 주별 통계 (Line Chart)",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: isBarChart
                  ? CustomPaint(
                painter: BarChartPainter(barData),
                child: Container(),
              )
                  : CustomPaint(
                painter: LineChartPainter(lineData),
                child: Container(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 📊 막대 그래프 (Bar Chart)
class BarChartPainter extends CustomPainter {
  final List<int> data;
  BarChartPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;

    double barWidth = size.width / (data.length * 2);
    double maxValue = data.reduce((a, b) => a > b ? a : b).toDouble();

    for (int i = 0; i < data.length; i++) {
      double barHeight = (data[i] / maxValue) * size.height;
      double x = i * (barWidth * 2) + barWidth / 2;
      double y = size.height - barHeight;

      Rect bar = Rect.fromLTWH(x, y, barWidth, barHeight);
      canvas.drawRect(bar, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// 📈 선 그래프 (Line Chart)
class LineChartPainter extends CustomPainter {
  final List<int> data;
  LineChartPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    double stepX = size.width / (data.length - 1);
    double maxValue = data.reduce((a, b) => a > b ? a : b).toDouble();

    Path path = Path();
    for (int i = 0; i < data.length; i++) {
      double x = i * stepX;
      double y = size.height - (data[i] / maxValue) * size.height;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
