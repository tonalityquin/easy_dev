import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../../states/calendar/field_calendar_state.dart';
import '../../../../states/calendar/field_selected_date_state.dart';
import '../../../../utils/snackbar_helper.dart';

class FieldCalendarPage extends StatefulWidget {
  const FieldCalendarPage({super.key});

  @override
  State<FieldCalendarPage> createState() => _FieldCalendarPageState();
}

class _FieldCalendarPageState extends State<FieldCalendarPage> {
  late FieldCalendarState calendar;
  Map<String, String> _memoMap = {};

  String? _memoKey;
  String division = 'default';
  String area = 'default';

  @override
  void initState() {
    super.initState();
    calendar = FieldCalendarState();
    calendar.selectDate(DateTime.now());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FieldSelectedDateState>().setSelectedDate(DateTime.now());
    });

    _initUserData();
  }

  Future<void> _initUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('phone') ?? 'unknown';
    division = prefs.getString('division') ?? 'default';
    area = prefs.getString('area') ?? 'default';
    final key = 'memoMap_${phone}_$area';

    setState(() {
      _memoKey = key;
    });

    await _loadMemoData();
  }

  Future<void> _loadMemoData() async {
    if (_memoKey == null) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_memoKey!);
    if (raw != null) {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      setState(() {
        _memoMap = decoded.map((key, value) => MapEntry(key, value.toString()));
      });
    } else {
      setState(() {
        _memoMap = {};
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 캘린더만 렌더링 (MergedLogSection 제거)
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        centerTitle: true,
        title: const Text(
          "출차 기록은 2주일까지만 보관",
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _buildCalendar(context),
      ),
    );
  }

  Widget _buildCalendar(BuildContext context) {
    return TableCalendar(
      firstDay: DateTime.utc(2020, 1, 1),
      lastDay: DateTime.utc(2100, 12, 31),
      focusedDay: calendar.selectedDate,
      selectedDayPredicate: (day) => isSameDay(calendar.selectedDate, day),
      onDaySelected: (selectedDay, focusedDay) async {
        setState(() {
          calendar.selectDate(selectedDay);
        });
        context.read<FieldSelectedDateState>().setSelectedDate(selectedDay);
        showSelectedSnackbar(context, '선택된 날짜: ${calendar.formatDate(selectedDay)}');
        // ✅ MergedLogSection 제거: merged logs 로딩 호출도 제거
      },
      onPageChanged: (focusedDay) {
        setState(() {
          calendar.setCurrentMonth(focusedDay);
        });
      },
      eventLoader: (day) {
        final key = calendar.dateKey(day);
        return _memoMap.containsKey(key) ? ['메모 있음'] : [];
      },
      calendarStyle: const CalendarStyle(
        todayDecoration: BoxDecoration(
          color: Colors.indigoAccent,
          shape: BoxShape.circle,
        ),
        selectedDecoration: BoxDecoration(
          color: Colors.indigo,
          shape: BoxShape.circle,
        ),
        markerDecoration: BoxDecoration(
          color: Colors.red,
          shape: BoxShape.circle,
        ),
      ),
      availableGestures: AvailableGestures.horizontalSwipe,
    );
  }
}

class FieldCalendarInline extends StatefulWidget {
  const FieldCalendarInline({super.key});

  @override
  State<FieldCalendarInline> createState() => _FieldCalendarInlineState();
}

class _FieldCalendarInlineState extends State<FieldCalendarInline> {
  late FieldCalendarState calendar;
  Map<String, String> _memoMap = {};
  String? _memoKey;
  String division = 'default';
  String area = 'default';

  @override
  void initState() {
    super.initState();
    calendar = FieldCalendarState();
    calendar.selectDate(DateTime.now());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FieldSelectedDateState>().setSelectedDate(DateTime.now());
    });
    _initUserData();
  }

  Future<void> _initUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('phone') ?? 'unknown';
    division = prefs.getString('division') ?? 'default';
    area = prefs.getString('area') ?? 'default';
    _memoKey = 'memoMap_${phone}_$area';
    await _loadMemoData();
    if (mounted) setState(() {});
  }

  Future<void> _loadMemoData() async {
    if (_memoKey == null) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_memoKey!);
    if (raw != null) {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _memoMap = decoded.map((k, v) => MapEntry(k, v.toString()));
    } else {
      _memoMap = {};
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // 인라인 버전도 캘린더만 렌더링 (MergedLogSection 제거)
    return _buildCalendar(context);
  }

  Widget _buildCalendar(BuildContext context) {
    return TableCalendar(
      firstDay: DateTime.utc(2020, 1, 1),
      lastDay: DateTime.utc(2100, 12, 31),
      focusedDay: calendar.selectedDate,
      selectedDayPredicate: (day) => isSameDay(calendar.selectedDate, day),
      onDaySelected: (selectedDay, focusedDay) async {
        calendar.selectDate(selectedDay);
        context.read<FieldSelectedDateState>().setSelectedDate(selectedDay);
        showSelectedSnackbar(context, '선택된 날짜: ${calendar.formatDate(selectedDay)}');
        if (mounted) setState(() {});
        // ✅ MergedLogSection 제거: merged logs 로딩 호출도 제거
      },
      onPageChanged: (focusedDay) => calendar.setCurrentMonth(focusedDay),
      eventLoader: (day) {
        final key = calendar.dateKey(day);
        return _memoMap.containsKey(key) ? ['메모 있음'] : [];
      },
      calendarStyle: const CalendarStyle(
        todayDecoration: BoxDecoration(color: Colors.indigoAccent, shape: BoxShape.circle),
        selectedDecoration: BoxDecoration(color: Colors.indigo, shape: BoxShape.circle),
        markerDecoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle),
      ),
      availableGestures: AvailableGestures.horizontalSwipe,
    );
  }
}
