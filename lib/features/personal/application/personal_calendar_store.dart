import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/personal_calendar_event.dart';

class PersonalCalendarStore {
  static const String prefsKey = 'personal_calendar_events_v1';

  Future<List<PersonalCalendarEvent>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.trim().isEmpty) return const <PersonalCalendarEvent>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <PersonalCalendarEvent>[];
      final out = <PersonalCalendarEvent>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final event = PersonalCalendarEvent.fromMap(Map<String, dynamic>.from(item));
        if (event.title.trim().isNotEmpty) out.add(event);
      }
      out.sort((a, b) {
        final c = a.dayOnly.compareTo(b.dayOnly);
        if (c != 0) return c;
        return b.updatedAt.compareTo(a.updatedAt);
      });
      return List<PersonalCalendarEvent>.unmodifiable(out);
    } catch (_) {
      return const <PersonalCalendarEvent>[];
    }
  }

  Future<void> saveAll(List<PersonalCalendarEvent> events) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(events.map((e) => e.toMap()).toList());
    await prefs.setString(prefsKey, encoded);
  }

  Future<void> upsert(PersonalCalendarEvent event) async {
    final list = List<PersonalCalendarEvent>.of(await load());
    final idx = list.indexWhere((e) => e.id == event.id);
    if (idx >= 0) {
      list[idx] = event.copyWith(updatedAt: DateTime.now());
    } else {
      list.add(event);
    }
    await saveAll(list);
  }

  Future<void> remove(String id) async {
    final list = List<PersonalCalendarEvent>.of(await load())..removeWhere((e) => e.id == id);
    await saveAll(list);
  }
}
