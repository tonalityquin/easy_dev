import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

// ▼ SQLite
import '../../sql/offline_auth_db.dart';

class DepartureCompletedFieldCalendarInline extends StatefulWidget {
  const DepartureCompletedFieldCalendarInline({super.key, required this.area, required this.onSelected});

  final String area;
  final ValueChanged<DateTime> onSelected;

  @override
  State<DepartureCompletedFieldCalendarInline> createState() => _DepartureCompletedFieldCalendarInlineState();
}

class _DepartureCompletedFieldCalendarInlineState extends State<DepartureCompletedFieldCalendarInline> {
  late DateTime _focusedDay;
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDay = DateTime(now.year, now.month, now.day);
    _focusedDay = _selectedDay;
  }

  String _dateKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // 현재 포커스달 ±1개월 범위로 미정산(=is_locked_fee=0) 건수 집계
  Future<Map<String, int>> _unsettledCountByDay({
    required String area,
    required DateTime focused,
  }) async {
    final db = await OfflineAuthDb.instance.database;

    final first = DateTime(focused.year, focused.month - 1, 1);
    final last = DateTime(focused.year, focused.month + 2, 0, 23, 59, 59, 999);
    final rows = await db.query(
      OfflineAuthDb.tablePlates,
      columns: const ['request_time'],
      where: '''
        COALESCE(status_type,'') = ?
        AND LOWER(TRIM(area)) = LOWER(TRIM(?))
        AND COALESCE(is_locked_fee,0) = 0
        AND COALESCE(request_time,0) BETWEEN ? AND ?
      ''',
      whereArgs: ['departureCompleted', area, first.millisecondsSinceEpoch, last.millisecondsSinceEpoch],
    );

    final map = <String, int>{};
    for (final r in rows) {
      final ms = (r['request_time'] as int?) ?? 0;
      if (ms <= 0) continue;
      final dt = DateTime.fromMillisecondsSinceEpoch(ms);
      final ymd = DateTime(dt.year, dt.month, dt.day);
      final key = _dateKey(ymd);
      map.update(key, (v) => v + 1, ifAbsent: () => 1);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, int>>(
      future: _unsettledCountByDay(area: widget.area, focused: _focusedDay),
      builder: (context, snap) {
        final unsettledMap = snap.data ?? const <String, int>{};

        return TableCalendar(
          firstDay: DateTime.utc(2020, 1, 1),
          lastDay: DateTime.utc(2100, 12, 31),
          focusedDay: _focusedDay,
          selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
          onDaySelected: (selectedDay, focusedDay) {
            final d = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
            setState(() {
              _selectedDay = d;
              _focusedDay = focusedDay;
            });
            widget.onSelected(d);
          },
          onPageChanged: (focusedDay) => setState(() => _focusedDay = focusedDay),
          eventLoader: (day) {
            final key = _dateKey(day);
            final count = unsettledMap[key] ?? 0;
            return count > 0 ? const ['UNSETTLED'] : const [];
          },
          calendarStyle: const CalendarStyle(
            todayDecoration: BoxDecoration(color: Colors.indigoAccent, shape: BoxShape.circle),
            selectedDecoration: BoxDecoration(color: Colors.indigo, shape: BoxShape.circle),
            markerDecoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle),
            markersAlignment: Alignment.bottomCenter,
          ),
          availableGestures: AvailableGestures.horizontalSwipe,
        );
      },
    );
  }
}
