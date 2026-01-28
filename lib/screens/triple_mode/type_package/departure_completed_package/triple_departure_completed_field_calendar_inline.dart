import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../../enums/plate_type.dart';
import '../../../../models/plate_model.dart';
import '../../../../states/area/area_state.dart';
import '../../../../states/calendar/field_calendar_state.dart';
import '../../../../states/plate/triple_plate_state.dart';
import '../../../../utils/snackbar_helper.dart';

class TripleDepartureCompletedFieldCalendarInline extends StatefulWidget {
  const TripleDepartureCompletedFieldCalendarInline({super.key});

  @override
  State<TripleDepartureCompletedFieldCalendarInline> createState() =>
      _TripleDepartureCompletedFieldCalendarInlineState();
}

class _TripleDepartureCompletedFieldCalendarInlineState
    extends State<TripleDepartureCompletedFieldCalendarInline> {
  late FieldCalendarState calendar;
  late DateTime _focusedDay;

  @override
  void initState() {
    super.initState();
    calendar = FieldCalendarState();

    final now = DateTime.now();
    calendar.selectDate(DateTime(now.year, now.month, now.day));
    _focusedDay = calendar.selectedDate;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<FieldSelectedDateState>().setSelectedDate(calendar.selectedDate);
    });
  }

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';

  Map<String, int> _unsettledCountByDay({
    required Iterable<PlateModel> plates,
    required String area,
  }) {
    final map = <String, int>{};
    final a = area.trim().toLowerCase();

    for (final p in plates) {
      if (p.isLockedFee == true) continue;

      final pa = p.area.trim().toLowerCase();
      if (pa != a) continue;

      final dt = p.requestTime;
      final ymd = DateTime(dt.year, dt.month, dt.day);
      final key = _dateKey(ymd);
      map.update(key, (v) => v + 1, ifAbsent: () => 1);
    }

    return map;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final area = context.watch<AreaState>().currentArea;
    final plateState = context.watch<TriplePlateState>();

    final allCompleted = plateState.tripleGetPlatesByCollection(
      PlateType.departureCompleted,
    );

    final unsettledMap = _unsettledCountByDay(
      plates: allCompleted,
      area: area,
    );

    return TableCalendar(
      firstDay: DateTime.utc(2020, 1, 1),
      lastDay: DateTime.utc(2100, 12, 31),
      focusedDay: _focusedDay,

      selectedDayPredicate: (day) => isSameDay(calendar.selectedDate, day),

      onDaySelected: (selectedDay, focusedDay) {
        final d = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
        calendar.selectDate(d);
        context.read<FieldSelectedDateState>().setSelectedDate(d);

        setState(() => _focusedDay = focusedDay);

        showSelectedSnackbar(context, '선택된 날짜: ${calendar.formatDate(d)}');
      },

      onPageChanged: (focusedDay) => setState(() => _focusedDay = focusedDay),

      eventLoader: (day) {
        final key = _dateKey(DateTime(day.year, day.month, day.day));
        final count = unsettledMap[key] ?? 0;
        return count > 0 ? const ['UNSETTLED'] : const [];
      },

      // ✅ 브랜드 팔레트(ColorScheme)만 사용: const 제거
      calendarStyle: CalendarStyle(
        todayDecoration: BoxDecoration(
          color: cs.primaryContainer,
          shape: BoxShape.circle,
        ),
        selectedDecoration: BoxDecoration(
          color: cs.primary,
          shape: BoxShape.circle,
        ),
        markerDecoration: BoxDecoration(
          color: cs.error,
          shape: BoxShape.circle,
        ),
        markersAlignment: Alignment.bottomCenter,
        outsideDaysVisible: true,
      ),

      availableGestures: AvailableGestures.horizontalSwipe,
    );
  }
}
