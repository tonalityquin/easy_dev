import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/personal_todo_item.dart';

class PersonalTodoStore {
  static const String prefsKey = 'personal_todos_v1';

  Future<List<PersonalTodoItem>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.trim().isEmpty) return const <PersonalTodoItem>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <PersonalTodoItem>[];
      final out = <PersonalTodoItem>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final todo = PersonalTodoItem.fromMap(Map<String, dynamic>.from(item));
        if (todo.title.trim().isNotEmpty) out.add(todo);
      }
      out.sort((a, b) {
        if (a.done != b.done) return a.done ? 1 : -1;
        final ad = a.dueDate ?? DateTime(9999);
        final bd = b.dueDate ?? DateTime(9999);
        final c = ad.compareTo(bd);
        if (c != 0) return c;
        return b.updatedAt.compareTo(a.updatedAt);
      });
      return List<PersonalTodoItem>.unmodifiable(out);
    } catch (_) {
      return const <PersonalTodoItem>[];
    }
  }

  Future<void> saveAll(List<PersonalTodoItem> todos) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(todos.map((e) => e.toMap()).toList());
    await prefs.setString(prefsKey, encoded);
  }

  Future<void> upsert(PersonalTodoItem todo) async {
    final list = List<PersonalTodoItem>.of(await load());
    final idx = list.indexWhere((e) => e.id == todo.id);
    if (idx >= 0) {
      list[idx] = todo.copyWith(updatedAt: DateTime.now());
    } else {
      list.insert(0, todo);
    }
    await saveAll(list);
  }

  Future<void> remove(String id) async {
    final list = List<PersonalTodoItem>.of(await load())..removeWhere((e) => e.id == id);
    await saveAll(list);
  }
}
