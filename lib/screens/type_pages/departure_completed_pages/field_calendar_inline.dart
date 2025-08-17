import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../../enums/plate_type.dart';
import '../../../../models/plate_model.dart';
import '../../../../states/area/area_state.dart';
import '../../../../states/calendar/field_calendar_state.dart';
import '../../../../states/calendar/field_calendar_state.dart' show FieldSelectedDateState;
import '../../../../states/plate/plate_state.dart';
import '../../../../utils/snackbar_helper.dart';

class FieldCalendarInline extends StatefulWidget {
  const FieldCalendarInline({super.key});

  @override
  State<FieldCalendarInline> createState() => _FieldCalendarInlineState();
}

class _FieldCalendarInlineState extends State<FieldCalendarInline> {
  late FieldCalendarState calendar;
  late DateTime _focusedDay;

  @override
  void initState() {
    super.initState();
    calendar = FieldCalendarState();
    final now = DateTime.now();
    calendar.selectDate(DateTime(now.year, now.month, now.day));
    _focusedDay = calendar.selectedDate;

    // 캘린더 최초 진입 시 전역 선택일도 오늘로 동기화
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FieldSelectedDateState>().setSelectedDate(calendar.selectedDate);
    });
  }

  /// YYYY-MM-DD 키
  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';

  /// area와 isLockedFee 기준으로 “미정산” 건수를 날짜별로 집계
  Map<String, int> _unsettledCountByDay({
    required Iterable<PlateModel> plates,
    required String area,
  }) {
    final map = <String, int>{};
    for (final p in plates) {
      // 지역 일치 + 미정산(!isLockedFee)만 집계
      if (p.isLockedFee) continue;
      if (p.area.trim().toLowerCase() != area.trim().toLowerCase()) continue;

      final dt = p.requestTime; // Firestore 필드: request_time
      final ymd = DateTime(dt.year, dt.month, dt.day);
      final key = _dateKey(ymd);
      map.update(key, (v) => v + 1, ifAbsent: () => 1);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final area = context.watch<AreaState>().currentArea;
    final plateState = context.watch<PlateState>();

    // 전체 departureCompleted 데이터를 가져오되,
    // 달력에 표시할 용도이므로 날짜 필터 없이 가져와 날짜별 집계에 사용
    final allCompleted = plateState.getPlatesByCollection(
      PlateType.departureCompleted,
      // selectedDate: null  // ← 인자 생략 시 전체(또는 캐시된 전체) 반환하도록 구현되어 있다면 생략
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

      // 날짜 선택 시 전역 선택일 동기화 + 스낵바
      onDaySelected: (selectedDay, focusedDay) {
        final d = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
        calendar.selectDate(d);
        context.read<FieldSelectedDateState>().setSelectedDate(d);
        setState(() => _focusedDay = focusedDay);

        showSelectedSnackbar(context, '선택된 날짜: ${calendar.formatDate(d)}');
      },

      onPageChanged: (focusedDay) => setState(() => _focusedDay = focusedDay),

      // ✅ eventLoader: 해당 날짜에 “미정산 데이터가 1건 이상” 있으면 dot 표시
      eventLoader: (day) {
        final key = _dateKey(day);
        final count = unsettledMap[key] ?? 0;
        // dot 유무만 필요하면 한 개의 이벤트만 반환 (여러 개면 dot도 여러 개)
        return count > 0 ? const ['UNSETTLED'] : const [];
      },

      // dot 스타일(색상 등) — 필요 시 조정
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
