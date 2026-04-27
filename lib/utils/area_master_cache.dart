import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../features/dev/data/repositories/area_repo_package/firestore_area_repository.dart';
import '../features/dev/domain/repositories/area_repo_package/area_repository.dart';

class AreaMasterItem {
  final String name;
  final List<String> modes;
  final bool isHeadquarter;

  const AreaMasterItem({
    required this.name,
    required this.modes,
    required this.isHeadquarter,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'modes': modes,
      'isHeadquarter': isHeadquarter,
    };
  }

  factory AreaMasterItem.fromJson(Map<String, dynamic> json) {
    final rawModes = json['modes'];
    final modes = rawModes is List
        ? rawModes
            .whereType<String>()
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
        : <String>[];

    return AreaMasterItem(
      name: (json['name'] as String? ?? '').trim(),
      modes: modes,
      isHeadquarter: json['isHeadquarter'] == true,
    );
  }
}

class AreaMasterSnapshot {
  final String division;
  final List<AreaMasterItem> items;
  final String refreshedAtIso;

  const AreaMasterSnapshot({
    required this.division,
    required this.items,
    required this.refreshedAtIso,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'division': division,
      'refreshedAtIso': refreshedAtIso,
      'items': items.map((e) => e.toJson()).toList(),
    };
  }

  factory AreaMasterSnapshot.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final items = rawItems is List
        ? rawItems
            .whereType<Map>()
            .map((e) => AreaMasterItem.fromJson(Map<String, dynamic>.from(e)))
            .where((e) => e.name.isNotEmpty)
            .toList()
        : <AreaMasterItem>[];

    return AreaMasterSnapshot(
      division: (json['division'] as String? ?? '').trim(),
      refreshedAtIso: (json['refreshedAtIso'] as String? ?? '').trim(),
      items: items,
    );
  }
}

class AreaMasterSelectableData {
  final bool hasCache;
  final List<String> selectableAreas;
  final Map<String, bool> isHeadquarterByName;

  const AreaMasterSelectableData({
    required this.hasCache,
    required this.selectableAreas,
    required this.isHeadquarterByName,
  });
}

class AreaMasterCache {
  static AreaRepository _repository = FirestoreAreaRepository();

  static void configureRepository(AreaRepository repository) {
    _repository = repository;
  }

  static String _cacheKey(String division) => 'area_master_$division';

  static String _refreshAtKey(String division) =>
      'area_master_last_refresh_at_$division';

  static Future<AreaMasterSnapshot?> readSnapshot(String division) async {
    final normalizedDivision = division.trim();
    if (normalizedDivision.isEmpty) return null;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey(normalizedDivision));
    if (raw == null || raw.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final snapshot = AreaMasterSnapshot.fromJson(decoded);
      if (snapshot.division.isEmpty) {
        return AreaMasterSnapshot(
          division: normalizedDivision,
          items: snapshot.items,
          refreshedAtIso: snapshot.refreshedAtIso,
        );
      }
      return snapshot;
    } catch (_) {
      return null;
    }
  }

  static Future<AreaMasterSnapshot> refreshDivision(String division) async {
    final normalizedDivision = division.trim();
    if (normalizedDivision.isEmpty) {
      throw ArgumentError('division is empty');
    }

    final records = await _repository.getAreasByDivision(normalizedDivision);

    final items = records
        .map((record) => AreaMasterItem(
              name: record.name,
              modes: record.modes.toSet().toList()..sort(),
              isHeadquarter: record.isHeadquarter,
            ))
        .where((item) => item.name.isNotEmpty)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final refreshedAtIso = DateTime.now().toIso8601String();
    final snapshot = AreaMasterSnapshot(
      division: normalizedDivision,
      items: items,
      refreshedAtIso: refreshedAtIso,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cacheKey(normalizedDivision),
      jsonEncode(snapshot.toJson()),
    );
    await prefs.setString(_refreshAtKey(normalizedDivision), refreshedAtIso);

    return snapshot;
  }

  static Future<String> readLastRefreshAt(String division) async {
    final normalizedDivision = division.trim();
    if (normalizedDivision.isEmpty) return '';

    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_refreshAtKey(normalizedDivision)) ?? '').trim();
  }

  static Future<AreaMasterSelectableData> readSelectableAreas({
    required String division,
    required List<String> userAreas,
    required String modeKey,
  }) async {
    final snapshot = await readSnapshot(division);
    if (snapshot == null) {
      return const AreaMasterSelectableData(
        hasCache: false,
        selectableAreas: <String>[],
        isHeadquarterByName: <String, bool>{},
      );
    }

    final itemByName = <String, AreaMasterItem>{
      for (final item in snapshot.items) item.name: item,
    };
    final isHeadquarterByName = <String, bool>{
      for (final item in snapshot.items) item.name: item.isHeadquarter,
    };

    final selectableAreas = <String>[];
    for (final area in userAreas) {
      final name = area.trim();
      if (name.isEmpty) continue;
      final item = itemByName[name];
      if (item == null) continue;
      if (!item.modes.contains(modeKey)) continue;
      selectableAreas.add(name);
    }

    return AreaMasterSelectableData(
      hasCache: true,
      selectableAreas: selectableAreas,
      isHeadquarterByName: isHeadquarterByName,
    );
  }
}
