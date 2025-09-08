import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:googleapis_auth/auth_io.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../sections/service_event_editor_bottom_sheet.dart';

const String serviceAccountPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json';

/// ✅ Google API 클라이언트 생성
Future<AutoRefreshingAuthClient> getAuthClient({bool write = false}) async {
  final jsonString = await rootBundle.loadString(serviceAccountPath);
  final credentials = ServiceAccountCredentials.fromJson(jsonString);

  final scopes = write
      ? [
    calendar.CalendarApi.calendarScope,
    'https://www.googleapis.com/auth/spreadsheets',
  ]
      : [
    calendar.CalendarApi.calendarReadonlyScope,
  ];

  return await clientViaServiceAccount(credentials, scopes);
}

/// 이벤트 불러오기
Future<Map<DateTime, List<calendar.Event>>> loadEventsForMonth({
  required DateTime month,
  required Map<String, bool> filterStates,
  required String calendarId,
}) async {
  final firstDay = DateTime(month.year, month.month, 1);
  final lastDay = DateTime(month.year, month.month + 1, 0);

  final client = await getAuthClient();
  final calendarApi = calendar.CalendarApi(client);

  final result = await calendarApi.events.list(
    calendarId,
    timeMin: firstDay.toUtc(),
    timeMax: lastDay.add(const Duration(days: 1)).toUtc(),
    singleEvents: true,
    orderBy: 'startTime',
  );

  final items = result.items ?? [];
  final eventsMap = <DateTime, List<calendar.Event>>{};

  for (var event in items) {
    final title = event.summary?.trim() ?? '무제';
    filterStates.putIfAbsent(title, () => false);

    final startUtc = event.start?.date;
    final endUtc = event.end?.date;

    final start = startUtc != null ? DateTime(startUtc.year, startUtc.month, startUtc.day) : null;
    final end =
    endUtc != null ? DateTime(endUtc.year, endUtc.month, endUtc.day).subtract(const Duration(days: 1)) : null;

    if (start != null && end != null) {
      for (DateTime date = start; !date.isAfter(end); date = date.add(const Duration(days: 1))) {
        final normalized = DateTime(date.year, date.month, date.day);
        eventsMap.putIfAbsent(normalized, () => []).add(event);
      }
    }
  }

  return eventsMap;
}

/// 이벤트 생성
Future<void> addEvent({
  required context,
  required DateTime focusedDay,
  required void Function(Map<DateTime, List<calendar.Event>>) updateEvents,
  required Map<String, bool> filterStates,
  required String calendarId,
}) async {
  final result = await showEventEditorBottomSheet(context: context); // ✅ attendees 제거
  if (result == null) return;

  try {
    final client = await getAuthClient(write: true);
    final calendarApi = calendar.CalendarApi(client);

    final newEvent = calendar.Event()
      ..summary = result.title.trim()
      ..description = result.description
      ..start = calendar.EventDateTime(
        date: DateTime.utc(result.start.year, result.start.month, result.start.day),
      )
      ..end = calendar.EventDateTime(
        date: DateTime.utc(result.end.year, result.end.month, result.end.day),
      )
      ..colorId = result.colorId;

    await calendarApi.events.insert(
      newEvent,
      calendarId,
      sendUpdates: 'all',
    );

    final updated = await loadEventsForMonth(
      month: focusedDay,
      filterStates: filterStates,
      calendarId: calendarId,
    );
    updateEvents(updated);
  } catch (e) {
    debugPrint('이벤트 추가 실패: $e');
  }
}

/// 이벤트 수정
Future<void> editEvent({
  required context,
  required calendar.Event event,
  required DateTime focusedDay,
  required void Function(Map<DateTime, List<calendar.Event>>) updateEvents,
  required Map<String, bool> filterStates,
  required String calendarId,
}) async {
  final startUtc = event.start?.date;
  final endUtc = event.end?.date;

  final start = startUtc != null ? DateTime(startUtc.year, startUtc.month, startUtc.day) : DateTime.now();
  final end = endUtc != null ? DateTime(endUtc.year, endUtc.month, endUtc.day) : start.add(const Duration(days: 1));

  final checklist = parseChecklistFromDescription(event.description);

  final result = await showEventEditorBottomSheet(
    context: context,
    initialTitle: event.summary,
    initialStart: start,
    initialEnd: end,
    initialChecklist: checklist,
    initialColorId: event.colorId,
  );

  if (result == null) return;

  final client = await getAuthClient(write: true);
  final calendarApi = calendar.CalendarApi(client);

  if (result.deleted) {
    if (event.id != null) {
      await calendarApi.events.delete(calendarId, event.id!);
      final updated = await loadEventsForMonth(
        month: focusedDay,
        filterStates: filterStates,
        calendarId: calendarId,
      );
      updateEvents(updated);
    }
    return;
  }

  event.summary = result.title.trim();
  event.description = result.description;
  event.start = calendar.EventDateTime(
    date: DateTime.utc(result.start.year, result.start.month, result.start.day),
  );
  event.end = calendar.EventDateTime(
    date: DateTime.utc(result.end.year, result.end.month, result.end.day),
  );
  event.colorId = result.colorId;

  await calendarApi.events.update(
    event,
    calendarId,
    event.id!,
    sendUpdates: 'all',
  );

  final updated = await loadEventsForMonth(
    month: focusedDay,
    filterStates: filterStates,
    calendarId: calendarId,
  );
  updateEvents(updated);
}

/// 체크리스트 파싱
List<ChecklistItem> parseChecklistFromDescription(String? description) {
  if (description == null) return [];
  final lines = description.split('\n').where((line) => line.startsWith('- [')).toList();
  return lines.map((line) {
    final checked = line.contains('- [x]');
    final text = line.replaceFirst(RegExp(r'- \[[ x]\]'), '').trim();
    return ChecklistItem(text: text, checked: checked);
  }).toList();
}

/// 필터 상태 저장
Future<void> saveFilterStates(Map<String, bool> filterStates) async {
  final prefs = await SharedPreferences.getInstance();
  final jsonString = jsonEncode(filterStates);
  await prefs.setString('filterStates', jsonString);
}

/// 필터 상태 불러오기
Future<Map<String, bool>> loadFilterStates() async {
  final prefs = await SharedPreferences.getInstance();
  final jsonString = prefs.getString('filterStates');
  if (jsonString != null) {
    final Map<String, dynamic> decoded = jsonDecode(jsonString);
    return decoded.map((key, value) => MapEntry(key.trim(), value as bool));
  }
  return {};
}
