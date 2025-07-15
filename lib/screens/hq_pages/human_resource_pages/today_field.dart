import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../utils/google_sheets_helper.dart';

class TodayField extends StatefulWidget {
  const TodayField({super.key});

  @override
  State<TodayField> createState() => _TodayFieldState();
}

class _TodayFieldState extends State<TodayField> {
  bool isLoading = false;
  int? selectedYear;
  int? selectedMonth;

  /// 📊 통계 시트 생성
  Future<void> _generateMonthlySummary(BuildContext context) async {
    if (isLoading || selectedYear == null || selectedMonth == null) return;

    setState(() => isLoading = true);

    final snack = ScaffoldMessenger.of(context);
    snack.showSnackBar(
      const SnackBar(content: Text('📊 출퇴근/휴게 통계 시트를 생성 중입니다...')),
    );

    try {
      final clockRows = await GoogleSheetsHelper.loadClockInOutRecords();
      final breakRows = await GoogleSheetsHelper.loadBreakRecords();

      final clockUserMap = GoogleSheetsHelper.extractUserMap(clockRows);
      final breakUserMap = GoogleSheetsHelper.extractUserMap(breakRows);
      final userMap = {...clockUserMap, ...breakUserMap};

      await GoogleSheetsHelper.writeMonthlyClockInOutSummary(
        year: selectedYear!,
        month: selectedMonth!,
        userMap: userMap,
      );

      await GoogleSheetsHelper.writeMonthlyBreakSummary(
        year: selectedYear!,
        month: selectedMonth!,
        userMap: userMap,
      );

      snack.showSnackBar(
        SnackBar(content: Text('✅ ${selectedYear}년 ${selectedMonth}월 통계 시트 생성 완료!')),
      );
    } catch (e) {
      snack.showSnackBar(
        SnackBar(
          content: Text('❌ 통계 시트 생성 실패: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final years = [for (int y = now.year - 1; y <= now.year + 1; y++) y];
    final months = List.generate(12, (i) => i + 1);

    final label = (selectedYear != null && selectedMonth != null)
        ? '$selectedYear년 $selectedMonth월'
        : '연도와 월을 선택하세요';

    return Scaffold(
      appBar: AppBar(
        title: const Text('통계 생성'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                DropdownButton<int>(
                  value: selectedYear,
                  hint: const Text('연도'),
                  items: years.map((year) {
                    return DropdownMenuItem(
                      value: year,
                      child: Text('$year년'),
                    );
                  }).toList(),
                  onChanged: (value) => setState(() => selectedYear = value),
                ),
                const SizedBox(width: 20),
                DropdownButton<int>(
                  value: selectedMonth,
                  hint: const Text('월'),
                  items: months.map((month) {
                    return DropdownMenuItem(
                      value: month,
                      child: Text('$month월'),
                    );
                  }).toList(),
                  onChanged: (value) => setState(() => selectedMonth = value),
                ),
              ],
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              icon: isLoading
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
                  : const Icon(Icons.auto_graph),
              label: Text(isLoading ? '생성 중...' : '통계 시트 생성'),
              onPressed: isLoading || selectedYear == null || selectedMonth == null
                  ? null
                  : () => _generateMonthlySummary(context),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
