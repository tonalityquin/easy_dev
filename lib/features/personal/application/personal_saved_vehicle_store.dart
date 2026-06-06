import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/personal_saved_vehicle.dart';

class PersonalSavedVehicleStore {
  static const String prefsKey = 'personal_saved_vehicles_v1';

  Future<List<PersonalSavedVehicle>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.trim().isEmpty) return const <PersonalSavedVehicle>[];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <PersonalSavedVehicle>[];
      final out = <PersonalSavedVehicle>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final vehicle = PersonalSavedVehicle.fromMap(Map<String, dynamic>.from(item));
        if (vehicle.compactPlate.isNotEmpty) out.add(vehicle);
      }
      out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return List<PersonalSavedVehicle>.unmodifiable(out);
    } catch (_) {
      return const <PersonalSavedVehicle>[];
    }
  }

  Future<void> saveAll(List<PersonalSavedVehicle> vehicles) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = <PersonalSavedVehicle>[];
    final seen = <String>{};
    for (final vehicle in vehicles) {
      final compact = vehicle.compactPlate;
      if (compact.isEmpty || seen.contains(compact)) continue;
      seen.add(compact);
      normalized.add(vehicle.copyWith(
        id: personalVehicleIdFromPlate(compact),
        plateNumber: compact,
      ));
    }
    final encoded = jsonEncode(normalized.map((e) => e.toMap()).toList());
    await prefs.setString(prefsKey, encoded);
  }

  Future<void> upsert(PersonalSavedVehicle vehicle) async {
    final now = DateTime.now();
    final compact = vehicle.compactPlate;
    if (compact.isEmpty) return;
    final list = List<PersonalSavedVehicle>.of(await load());
    final idx = list.indexWhere((e) => e.compactPlate == compact || e.id == vehicle.id);
    final normalized = vehicle.copyWith(
      id: personalVehicleIdFromPlate(compact),
      plateNumber: compact,
      updatedAt: now,
      createdAt: idx >= 0 ? list[idx].createdAt : vehicle.createdAt,
    );
    if (idx >= 0) {
      list[idx] = normalized;
    } else {
      list.insert(0, normalized);
    }
    await saveAll(list);
  }

  Future<void> remove(String vehicleId) async {
    final list = List<PersonalSavedVehicle>.of(await load())
      ..removeWhere((e) => e.id == vehicleId);
    await saveAll(list);
  }

  Future<void> markUsed(String vehicleId) async {
    final list = List<PersonalSavedVehicle>.of(await load());
    final idx = list.indexWhere((e) => e.id == vehicleId);
    if (idx < 0) return;
    final now = DateTime.now();
    list[idx] = list[idx].copyWith(lastUsedAt: now, updatedAt: now);
    await saveAll(list);
  }
}
