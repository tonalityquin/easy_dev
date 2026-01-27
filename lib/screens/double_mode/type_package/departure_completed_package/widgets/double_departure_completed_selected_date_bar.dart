import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../states/calendar/field_calendar_state.dart';

class DoubleDepartureCompletedSelectedDateBar extends StatelessWidget {
  const DoubleDepartureCompletedSelectedDateBar({
    super.key,
    this.visible = true,
  });

  final bool visible;

  String _format(DateTime d) {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final w = weekdays[d.weekday - 1];
    return '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')} ($w)';
  }

  bool _isSameYMD(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;

    final selected = context.watch<FieldSelectedDateState>().selectedDate ?? DateTime.now();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selectedYmd = DateTime(selected.year, selected.month, selected.day);
    final isToday = _isSameYMD(selectedYmd, today);

    return SizedBox(
      height: 44,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
        ),
        child: Row(
          children: [
            Icon(Icons.event, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '선택일: ${_format(selected)}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 32,
              child: TextButton(
                onPressed: isToday
                    ? null
                    : () {
                  final n = DateTime.now();
                  final todayYmd = DateTime(n.year, n.month, n.day);
                  context.read<FieldSelectedDateState>().setSelectedDate(todayYmd);
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: cs.primary,
                  disabledForegroundColor: cs.onSurfaceVariant,
                ),
                child: Text(
                  '오늘',
                  style: TextStyle(
                    fontSize: 13,
                    color: isToday ? cs.onSurfaceVariant : cs.primary,
                    fontWeight: FontWeight.w700,
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
