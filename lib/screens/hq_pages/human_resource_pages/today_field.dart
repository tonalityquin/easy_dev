import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../utils/google_sheets_helper.dart';

class TodayField extends StatelessWidget {
  const TodayField({super.key});

  Future<void> _generateMonthlySummary(BuildContext context) async {
    final now = DateTime.now();
    final year = now.year;
    final month = now.month;

    final snack = ScaffoldMessenger.of(context);

    snack.showSnackBar(
      const SnackBar(content: Text('📊 출퇴근/휴게 통계 시트를 생성 중입니다...')),
    );

    try {
      // 🔹 사용자 ID → 이름 매핑 생성
      final clockRows = await GoogleSheetsHelper.loadClockInOutRecords();
      final breakRows = await GoogleSheetsHelper.loadBreakRecords();

      final clockUserMap = GoogleSheetsHelper.extractUserMap(clockRows);
      final breakUserMap = GoogleSheetsHelper.extractUserMap(breakRows);

      // ✅ 출퇴근 + 휴게 통합 userMap 생성
      final userMap = {...clockUserMap, ...breakUserMap};

      await GoogleSheetsHelper.writeMonthlyClockInOutSummary(
        year: year,
        month: month,
        userMap: userMap,
      );

      await GoogleSheetsHelper.writeMonthlyBreakSummary(
        year: year,
        month: month,
        userMap: userMap,
      );

      snack.showSnackBar(
        SnackBar(content: Text('✅ ${year}년 ${month}월 통계 시트 생성 완료!')),
      );
    } catch (e) {
      snack.showSnackBar(
        SnackBar(
          content: Text('❌ 통계 시트 생성 실패: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final yearMonth = DateFormat('yyyy년 M월').format(now);

    return Scaffold(
      appBar: AppBar(
        title: const Text('통계 생성'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: Center(
        child: ElevatedButton.icon(
          icon: const Icon(Icons.auto_graph),
          label: Text('$yearMonth 통계 시트 생성'),
          onPressed: () => _generateMonthlySummary(context),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            textStyle: const TextStyle(fontSize: 18),
          ),
        ),
      ),
    );
  }
}
