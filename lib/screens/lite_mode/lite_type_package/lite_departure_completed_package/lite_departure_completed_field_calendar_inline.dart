import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../../enums/plate_type.dart';
import '../../../../models/plate_model.dart';
import '../../../../states/area/area_state.dart';
import '../../../../states/calendar/field_calendar_state.dart';
import '../../../../states/plate/lite_plate_state.dart';
import '../../../../utils/snackbar_helper.dart';

class LiteDepartureCompletedFieldCalendarInline extends StatefulWidget {
  const LiteDepartureCompletedFieldCalendarInline({super.key});

  @override
  State<LiteDepartureCompletedFieldCalendarInline> createState() => _LiteDepartureCompletedFieldCalendarInlineState();
}

class _LiteDepartureCompletedFieldCalendarInlineState extends State<LiteDepartureCompletedFieldCalendarInline> {
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
      context.read<FieldSelectedDateState>().setSelectedDate(calendar.selectedDate);
    });
  }

  String _dateKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Map<String, int> _unsettledCountByDay({
    required Iterable<PlateModel> plates,
    required String area,
  }) {
    final map = <String, int>{};
    for (final p in plates) {
      if (p.isLockedFee) continue;
      if (p.area.trim().toLowerCase() != area.trim().toLowerCase()) continue;

      final dt = p.requestTime;
      final ymd = DateTime(dt.year, dt.month, dt.day);
      final key = _dateKey(ymd);
      map.update(key, (v) => v + 1, ifAbsent: () => 1);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final area = context.watch<AreaState>().currentArea;
    final plateState = context.watch<LitePlateState>();

    final allCompleted = plateState.liteGetPlatesByCollection(
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
  }
}
