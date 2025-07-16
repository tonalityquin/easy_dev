import 'package:flutter/material.dart';
import '../../../utils/google_sheets_helper.dart';

class AppStrings {
  static const String title = '통계 생성';
  static const String hintYear = '연도';
  static const String hintMonth = '월';
  static const String buttonGenerating = '생성 중...';
  static const String generatingMessage = '📊 출퇴근/휴게 통계 시트를 생성 중입니다...';
  static const String successPrefix = '✅';
  static const String failPrefix = '❌ 통계 시트 생성 실패: ';
}

class TodayField extends StatefulWidget {
  const TodayField({super.key});

  @override
  State<TodayField> createState() => _TodayFieldState();
}

class _TodayFieldState extends State<TodayField> {
  bool isLoading = false;
  late int selectedYear;
  late int selectedMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    selectedYear = now.year;
    selectedMonth = now.month;
  }

  Future<void> _generateMonthlySummary(BuildContext context) async {
    if (isLoading) return;

    setState(() => isLoading = true);
    final snack = ScaffoldMessenger.of(context);

    snack.showSnackBar(
      const SnackBar(content: Text(AppStrings.generatingMessage)),
    );

    try {
      final clockRows = await GoogleSheetsHelper.loadClockInOutRecords();
      final breakRows = await GoogleSheetsHelper.loadBreakRecords();

      final clockUserMap = GoogleSheetsHelper.extractUserMap(clockRows);
      final breakUserMap = GoogleSheetsHelper.extractUserMap(breakRows);
      final userMap = {...clockUserMap, ...breakUserMap};

      await GoogleSheetsHelper.writeMonthlyClockInOutSummary(
        year: selectedYear,
        month: selectedMonth,
        userMap: userMap,
      );

      await GoogleSheetsHelper.writeMonthlyBreakSummary(
        year: selectedYear,
        month: selectedMonth,
        userMap: userMap,
      );

      snack.showSnackBar(
        SnackBar(content: Text('${AppStrings.successPrefix} $selectedYear년 $selectedMonth월 통계 시트 생성 완료!')),
      );
    } catch (e) {
      snack.showSnackBar(
        SnackBar(
          content: Text('${AppStrings.failPrefix}$e'),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.title),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            /// ✅ 연도 + 월 + 버튼 한 줄
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                DropdownButton<int>(
                  value: selectedYear,
                  hint: const Text(AppStrings.hintYear),
                  items: years.map((year) {
                    return DropdownMenuItem(
                      value: year,
                      child: Text('$year년'),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => selectedYear = value);
                    }
                  },
                ),
                const SizedBox(width: 12),
                DropdownButton<int>(
                  value: selectedMonth,
                  hint: const Text(AppStrings.hintMonth),
                  items: months.map((month) {
                    return DropdownMenuItem(
                      value: month,
                      child: Text('$month월'),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => selectedMonth = value);
                    }
                  },
                ),
                const SizedBox(width: 12),

                /// 📊 통계 버튼 (아이콘만)
                Tooltip(
                  message: '통계 시트 생성',
                  child: ElevatedButton(
                    onPressed: isLoading ? null : () => _generateMonthlySummary(context),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(12),
                      shape: const CircleBorder(),
                    ),
                    child: isLoading
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                        : const Icon(Icons.insert_chart),
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
