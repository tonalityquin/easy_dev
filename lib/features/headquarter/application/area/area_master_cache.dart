import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/models/capability.dart';
import '../../../dev/data/repositories/area_repo_package/firestore_area_repository.dart';
import '../../../dev/domain/repositories/area_repo_package/area_repository.dart';

class AreaMasterItem {
  final String name;
  final List<String> modes;
  final bool isHeadquarter;
  final CapSet capabilities;

  const AreaMasterItem({
    required this.name,
    required this.modes,
    required this.isHeadquarter,
    this.capabilities = const <Capability>{},
  });

  Map<String, dynamic> toJson() {
    final capabilityKeys =
        capabilities.map((capability) => capability.key).toList()..sort();

    return <String, dynamic>{
      'name': name,
      'modes': modes,
      'isHeadquarter': isHeadquarter,
      'capabilities': capabilityKeys,
    };
  }

  factory AreaMasterItem.fromJson(Map<String, dynamic> json) {
    final rawModes = json['modes'];
    final modes = rawModes is List
        ? rawModes
            .whereType<String>()
            .map((mode) => mode.trim())
            .where((mode) => mode.isNotEmpty)
            .toSet()
            .toList()
        : <String>[];
    modes.sort();

    return AreaMasterItem(
      name: (json['name'] as String? ?? '').trim(),
      modes: modes,
      isHeadquarter: json['isHeadquarter'] == true,
      capabilities: Set<Capability>.unmodifiable(
        Cap.fromDynamic(json['capabilities']),
      ),
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
      'items': items.map((item) => item.toJson()).toList(),
    };
  }

  factory AreaMasterSnapshot.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final items = rawItems is List
        ? rawItems
            .whereType<Map>()
            .map(
              (item) => AreaMasterItem.fromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .where((item) => item.name.isNotEmpty)
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
  static final Map<String, Future<AreaMasterSnapshot>> _activeRefreshes =
      <String, Future<AreaMasterSnapshot>>{};

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

    final active = _activeRefreshes[normalizedDivision];
    if (active != null) return active;

    final future = _refreshDivisionInternal(normalizedDivision);
    _activeRefreshes[normalizedDivision] = future;

    try {
      return await future;
    } finally {
      if (identical(_activeRefreshes[normalizedDivision], future)) {
        _activeRefreshes.remove(normalizedDivision);
      }
    }
  }

  static Future<AreaMasterSnapshot> _refreshDivisionInternal(
    String normalizedDivision,
  ) async {
    final records = await _repository.getAreasByDivision(normalizedDivision);

    final items = records
        .map(
          (record) => AreaMasterItem(
            name: record.name.trim(),
            modes: record.modes
                .map((mode) => mode.trim().toLowerCase())
                .where((mode) => mode.isNotEmpty)
                .toSet()
                .toList()
              ..sort(),
            isHeadquarter: record.isHeadquarter,
            capabilities: Set<Capability>.unmodifiable(record.capabilities),
          ),
        )
        .where((item) => item.name.isNotEmpty)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final refreshedAtIso = DateTime.now().toIso8601String();
    final snapshot = AreaMasterSnapshot(
      division: normalizedDivision,
      items: items,
      refreshedAtIso: refreshedAtIso,
    );
    final encoded = jsonEncode(snapshot.toJson());
    final cacheKey = _cacheKey(normalizedDivision);
    final refreshAtKey = _refreshAtKey(normalizedDivision);
    final prefs = await SharedPreferences.getInstance();

    try {
      await prefs.remove(cacheKey);
      await prefs.remove(refreshAtKey);
      await prefs.reload();

      if (prefs.containsKey(cacheKey) || prefs.containsKey(refreshAtKey)) {
        throw StateError('기존 지역 마스터 삭제 검증 실패');
      }

      final cacheSaved = await prefs.setString(cacheKey, encoded);
      final refreshAtSaved = await prefs.setString(
        refreshAtKey,
        refreshedAtIso,
      );

      if (!cacheSaved || !refreshAtSaved) {
        throw StateError('새 지역 마스터 저장 실패');
      }

      await prefs.reload();

      final verifiedCache = prefs.getString(cacheKey);
      final verifiedRefreshAt = prefs.getString(refreshAtKey);

      if (verifiedCache != encoded ||
          verifiedRefreshAt != refreshedAtIso) {
        throw StateError('새 지역 마스터 저장 검증 실패');
      }
    } catch (_) {
      try {
        await prefs.remove(cacheKey);
        await prefs.remove(refreshAtKey);
        await prefs.reload();
      } catch (_) {}
      rethrow;
    }

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
