// lib/offlines/offline_type_package/offline_departure_completed_package/widgets/offline_departure_completed_selected_date_bar.dart
//
// 리팩터링 요약
// - Provider(OfflineFieldCalendarState) 의존 제거
// - 외부에서 selectedDate를 주입받아 표시만 담당
// - onPrev/onNext 콜백으로 날짜 전환 트리거 가능(옵션)

import 'package:flutter/material.dart';

class OfflineDepartureCompletedSelectedDateBar extends StatelessWidget {
  const OfflineDepartureCompletedSelectedDateBar({
    super.key,
    this.visible = true,
    required this.selectedDate,
    this.onPrev,
    this.onNext,
  });

  final bool visible;
  final DateTime selectedDate;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  String _format(DateTime d) {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final w = weekdays[d.weekday - 1];
    return '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')} ($w)';
  }

  bool _isSameYMD(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selectedYmd = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    final isToday = _isSameYMD(selectedYmd, today);

    return SizedBox(
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
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: '이전 날짜',
              onPressed: onPrev,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            const SizedBox(width: 4),
            Icon(Icons.event, size: 18, color: Colors.grey[700]),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '선택일: ${_format(selectedDate)}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 32,
              child: TextButton(
                onPressed: isToday ? null : onNext == null && onPrev == null
                    ? null
                    : () {
                  // 별도 today 핸들러가 필요하면 외부에서 onPrev/onNext 조합으로 구현
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  '오늘',
                  style: TextStyle(
                    fontSize: 13,
                    color: isToday ? Colors.grey : null,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: '다음 날짜',
              onPressed: onNext,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
      ),
    );
  }
}
