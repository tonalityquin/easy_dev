import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:googleapis_auth/auth_io.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../sections/tablet_event_editor_bottom_sheet.dart';

const String calendarId = 'surge1868@gmail.com';
const String serviceAccountPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json';

/// 구글 인증 클라이언트 생성 함수
/// - write: true일 경우 쓰기 권한 포함, false일 경우 읽기 전용
Future<AutoRefreshingAuthClient> getAuthClient({bool write = false}) async {
  final jsonString = await rootBundle.loadString(serviceAccountPath);
  final credentials = ServiceAccountCredentials.fromJson(jsonString);
  final scopes = write
      ? [calendar.CalendarApi.calendarScope]
      : [calendar.CalendarApi.calendarReadonlyScope];
  return await clientViaServiceAccount(credentials, scopes);
}

/// 지정한 월(month)에 해당하는 이벤트들을 불러오고 날짜별로 그룹화하여 반환
Future<Map<DateTime, List<calendar.Event>>> loadEventsForMonth({
  required DateTime month,
  required Map<String, bool> filterStates,
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
    final end = endUtc != null
        ? DateTime(endUtc.year, endUtc.month, endUtc.day).subtract(const Duration(days: 1))
        : null;

    if (start != null && end != null) {
      // 이벤트가 다일간일 경우 날짜별로 반복해서 추가
      for (DateTime date = start; !date.isAfter(end); date = date.add(const Duration(days: 1))) {
        final normalized = DateTime(date.year, date.month, date.day);
        eventsMap.putIfAbsent(normalized, () => []).add(event);
      }
    }
  }

  return eventsMap;
}

/// 이벤트 생성 함수
/// - 바텀시트를 통해 입력받은 정보를 Google Calendar에 추가
Future<void> addEvent({
  required context,
  required DateTime focusedDay,
  required void Function(Map<DateTime, List<calendar.Event>>) updateEvents,
  required Map<String, bool> filterStates,
}) async {
  final result = await showTabletEventEditorBottomSheet(context: context);
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

    await calendarApi.events.insert(newEvent, calendarId);

    // 이벤트 추가 후 이벤트 목록 새로 불러오기
    final updated = await loadEventsForMonth(
      month: focusedDay,
      filterStates: filterStates,
    );
    updateEvents(updated);
  } catch (e) {
    debugPrint('이벤트 추가 실패: $e');
  }
}

/// 기존 이벤트 수정 또는 삭제 처리 함수
Future<void> editEvent({
  required context,
  required calendar.Event event,
  required DateTime focusedDay,
  required void Function(Map<DateTime, List<calendar.Event>>) updateEvents,
  required Map<String, bool> filterStates,
}) async {
  final startUtc = event.start?.date;
  final endUtc = event.end?.date;

  final start = startUtc != null ? DateTime(startUtc.year, startUtc.month, startUtc.day) : DateTime.now();
  final end = endUtc != null ? DateTime(endUtc.year, endUtc.month, endUtc.day) : start.add(const Duration(days: 1));

  // 기존 설명에서 체크리스트 정보 추출
  final checklist = parseChecklistFromDescription(event.description);

  // 바텀시트 열기 (기존 정보 전달)
  final result = await showTabletEventEditorBottomSheet(
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
    // 삭제 요청 처리
    if (event.id != null) {
      await calendarApi.events.delete(calendarId, event.id!);
      final updated = await loadEventsForMonth(month: focusedDay, filterStates: filterStates);
      updateEvents(updated);
    }
    return;
  }

  // 수정된 정보 적용
  event.summary = result.title.trim();
  event.description = result.description;
  event.start = calendar.EventDateTime(
    date: DateTime.utc(result.start.year, result.start.month, result.start.day),
  );
  event.end = calendar.EventDateTime(
    date: DateTime.utc(result.end.year, result.end.month, result.end.day),
  );
  event.colorId = result.colorId;

  await calendarApi.events.update(event, calendarId, event.id!);

  final updated = await loadEventsForMonth(month: focusedDay, filterStates: filterStates);
  updateEvents(updated);
}

/// Google Calendar 이벤트 설명(description) 필드에서 체크리스트 항목을 추출
List<ChecklistItem> parseChecklistFromDescription(String? description) {
  if (description == null) return [];
  final lines = description.split('\n').where((line) => line.startsWith('- [')).toList();
  return lines.map((line) {
    final checked = line.contains('- [x]');
    final text = line.replaceFirst(RegExp(r'- \[[ x]\]'), '').trim();
    return ChecklistItem(text: text, checked: checked);
  }).toList();
}

/// 필터 상태를 SharedPreferences에 저장 (JSON 직렬화)
Future<void> saveFilterStates(Map<String, bool> filterStates) async {
  final prefs = await SharedPreferences.getInstance();
  final jsonString = jsonEncode(filterStates);
  await prefs.setString('filterStates', jsonString);
}

/// SharedPreferences에서 필터 상태 불러오기
Future<Map<String, bool>> loadFilterStates() async {
  final prefs = await SharedPreferences.getInstance();
  final jsonString = prefs.getString('filterStates');
  if (jsonString != null) {
    final Map<String, dynamic> decoded = jsonDecode(jsonString);
    return decoded.map((key, value) => MapEntry(key.trim(), value as bool));
  }
  return {};
}
