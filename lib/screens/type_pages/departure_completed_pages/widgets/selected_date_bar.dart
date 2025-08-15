import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../states/calendar/field_calendar_state.dart'; // 통합 파일을 쓰지 않는다면 FieldSelectedDateState 경로를 맞춰주세요
// 통합 파일이 아니라면 아래 import가 필요할 수 있습니다.
// import '../../../../../states/calendar/field_selected_date_state.dart';

class SelectedDateBar extends StatelessWidget {
  const SelectedDateBar({super.key});

  String _format(DateTime d) {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    // DateTime.weekday: 1(월) ~ 7(일)
    final w = weekdays[d.weekday - 1];
    return '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')} ($w)';
  }

  bool _isSameYMD(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final selected =
        context.watch<FieldSelectedDateState>().selectedDate ?? DateTime.now();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selectedYmd = DateTime(selected.year, selected.month, selected.day);
    final isToday = _isSameYMD(selectedYmd, today);

    return SizedBox( // ✅ 바 전체 높이 고정
      height: 44,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          children: [
            Icon(Icons.event, size: 18, color: Colors.grey[700]),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '선택일: ${_format(selected)}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
                maxLines: 1, // ✅ 한 줄 고정
              ),
            ),
            const SizedBox(width: 8),

            // ✅ 항상 TextButton 유지: 활성/비활성만 전환
            SizedBox(
              height: 32, // ✅ 버튼 높이 고정
              child: TextButton(
                onPressed: isToday
                    ? null // 비활성(이미 오늘)
                    : () {
                  final n = DateTime.now();
                  final todayYmd = DateTime(n.year, n.month, n.day);
                  // 선택일 전역 상태를 “오늘”로 복귀
                  context
                      .read<FieldSelectedDateState>()
                      .setSelectedDate(todayYmd);

                  // 달력 모델도 함께 이동시키고 싶다면 주석 해제:
                  // context.read<FieldCalendarState>().selectDate(todayYmd);
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32), // ✅ 최소 높이/폭 제한
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap, // ✅ 터치 여백 축소
                ),
                child: Text(
                  '오늘',
                  style: TextStyle(
                    fontSize: 13,
                    color: isToday ? Colors.grey : null, // 비활성일 땐 회색
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
