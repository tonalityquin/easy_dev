import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

// ▼ SQLite
import '../../sql/offline_auth_db.dart';

/// ✅ 해당 월(±1개월 범위)의 출차 완료(status_type='departured') 건수를 집계하여 마커 표시
/// ✅ 날짜 집계는 request_time(TEXT) 대신 COALESCE(updated_at, created_at) (ms) 사용
class OfflineDepartureCompletedFieldCalendarInline extends StatefulWidget {
  const OfflineDepartureCompletedFieldCalendarInline({
    super.key,
    required this.area,
    required this.onSelected,
  });

  final String area;
  final ValueChanged<DateTime> onSelected;

  @override
  State<OfflineDepartureCompletedFieldCalendarInline> createState() =>
      _OfflineDepartureCompletedFieldCalendarInlineState();
}

class _OfflineDepartureCompletedFieldCalendarInlineState
    extends State<OfflineDepartureCompletedFieldCalendarInline> {
  late DateTime _focusedDay;
  late DateTime _selectedDay;

  static const String _kStatusDepartured = 'departured';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDay = DateTime(now.year, now.month, now.day);
    _focusedDay = _selectedDay;
  }

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';

  /// ✅ status_type='departured' 로만 집계
  /// ✅ ms epoch: COALESCE(updated_at, created_at)
  Future<Map<String, int>> _departuredCountByDay({
    required String area,
    required DateTime focused,
  }) async {
    final db = await OfflineAuthDb.instance.database;

    final first = DateTime(focused.year, focused.month - 1, 1);
    final last =
    DateTime(focused.year, focused.month + 2, 0, 23, 59, 59, 999);

    final rows = await db.query(
      OfflineAuthDb.tablePlates,
      columns: const ['updated_at', 'created_at'],
      where: '''
        COALESCE(status_type,'') = ?
        AND LOWER(TRIM(area)) = LOWER(TRIM(?))
        AND COALESCE(updated_at, created_at, 0) BETWEEN ? AND ?
      ''',
      whereArgs: [
        _kStatusDepartured,
        area,
        first.millisecondsSinceEpoch,
        last.millisecondsSinceEpoch
      ],
    );

    final map = <String, int>{};
    for (final r in rows) {
      final ms = (r['updated_at'] as int?) ?? (r['created_at'] as int?) ?? 0;
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
      future: _departuredCountByDay(area: widget.area, focused: _focusedDay),
      builder: (context, snap) {
        final completedMap = snap.data ?? const <String, int>{};

        return TableCalendar(
          firstDay: DateTime.utc(2020, 1, 1),
          lastDay: DateTime.utc(2100, 12, 31),
          focusedDay: _focusedDay,
          selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
          onDaySelected: (selectedDay, focusedDay) {
            final d =
            DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
            setState(() {
              _selectedDay = d;
              _focusedDay = focusedDay;
            });
            widget.onSelected(d);
          },
          onPageChanged: (focusedDay) =>
              setState(() => _focusedDay = focusedDay),
          eventLoader: (day) {
            final key = _dateKey(day);
            final count = completedMap[key] ?? 0;
            // 마커 유무만 사용 — 문자열 값은 의미 없음
            return count > 0 ? const ['DEPARTURED'] : const [];
          },
          calendarStyle: const CalendarStyle(
            todayDecoration:
            BoxDecoration(color: Colors.indigoAccent, shape: BoxShape.circle),
            selectedDecoration:
            BoxDecoration(color: Colors.indigo, shape: BoxShape.circle),
            markerDecoration:
            BoxDecoration(color: Colors.red, shape: BoxShape.circle),
            markersAlignment: Alignment.bottomCenter,
          ),
          availableGestures: AvailableGestures.horizontalSwipe,
        );
      },
    );
  }
}
