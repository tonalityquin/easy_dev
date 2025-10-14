// lib/screens/type_pages/offline_parking_completed_package/offline_parking_completed_location_picker.dart
//
// 리팩터링 요약
// - Provider(LocationState) / Repository(LocationRepository) 제거
// - SQLite(offline_auth_db / offline_auth_service)만 사용
//   · 주차 구역: offline_locations (columns: area, location_name, type['single'|'composite'], parent, capacity)
//   · 입차 수:   offline_plates   (status_type='parkingCompleted', area=?, GROUP BY location)
// - 항목별 새로고침/쿨다운 유지(단일 항목만 카운트 재집계)
//
import 'package:flutter/material.dart';

// ▼ SQLite / 세션
import '../../sql/offline_auth_db.dart';
import '../../sql/offline_auth_service.dart';

import '../../../utils/snackbar_helper.dart';

/// Offline Service Palette (오프라인 카드와 동일 계열)
class _Palette {
  static const base = Color(0xFFF4511E); // primary (주황 계열)
}

// status_type 키(PlateType 의존 제거)
const String _kStatusParkingCompleted = 'parkingCompleted';

class OfflineParkingCompletedLocationPicker extends StatefulWidget {
  final Function(String locationName) onLocationSelected;
  final bool isLocked;

  const OfflineParkingCompletedLocationPicker({
    super.key,
    required this.onLocationSelected,
    required this.isLocked,
  });

  @override
  State<OfflineParkingCompletedLocationPicker> createState() =>
      _OfflineParkingCompletedLocationPickerState();
}

class _OfflineParkingCompletedLocationPickerState
    extends State<OfflineParkingCompletedLocationPicker> {
  String? selectedParent;

  // 로딩/데이터
  bool _isLoading = true;
  String _area = '';
  List<_LocRow> _singles = [];
  List<_LocRow> _composites = [];
  // location_name 기준 카운트
  final Map<String, int> _countsByLoc = {};

  // ▶ 항목별 새로고침 상태/쿨다운
  final Set<String> _refreshingNames = {};
  final Map<String, DateTime> _lastItemRefreshedAt = {};
  final Duration _itemCooldown = const Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  // 세션에서 area 로드 (없으면 isSelected=1 폴백)
  Future<String> _loadCurrentArea() async {
    final db = await OfflineAuthDb.instance.database;
    final session = await OfflineAuthService.instance.currentSession();
    final uid = (session?.userId ?? '').trim();

    Map<String, Object?>? row;
    if (uid.isNotEmpty) {
      final r1 = await db.query(
        OfflineAuthDb.tableAccounts,
        columns: const ['currentArea', 'selectedArea'],
        where: 'userId = ?',
        whereArgs: [uid],
        limit: 1,
      );
      if (r1.isNotEmpty) row = r1.first;
    }
    row ??= (await db.query(
      OfflineAuthDb.tableAccounts,
      columns: const ['currentArea', 'selectedArea'],
      where: 'isSelected = 1',
      limit: 1,
    ))
        .firstOrNull;

    final area = ((row?['currentArea'] as String?) ??
        (row?['selectedArea'] as String?) ??
        '')
        .trim();
    return area;
  }

  // 모든 위치/카운트 로드
  Future<void> _loadAll() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final db = await OfflineAuthDb.instance.database;
      final area = await _loadCurrentArea();

      // 위치 로드
      final rows = await db.query(
        OfflineAuthDb.tableLocations,
        columns: const ['type', 'location_name', 'parent', 'capacity'],
        where: 'area = ?',
        whereArgs: [area],
        orderBy: 'type, parent, location_name',
      );

      final singles = <_LocRow>[];
      final composites = <_LocRow>[];

      for (final r in rows) {
        final type = (r['type'] as String?)?.trim() ?? 'single';
        final name = (r['location_name'] as String?)?.trim() ?? '';
        final parent = (r['parent'] as String?)?.trim();
        final capacity = (r['capacity'] as int?) ?? 0;
        final loc = _LocRow(type: type, name: name, parent: parent, capacity: capacity);
        if (type == 'composite') {
          composites.add(loc);
        } else {
          singles.add(loc);
        }
      }

      // 카운트 묶음 조회(GROUP BY location)
      _countsByLoc.clear();
      final cntRows = await db.rawQuery(
        '''
        SELECT location, COUNT(*) AS c
          FROM ${OfflineAuthDb.tablePlates}
         WHERE COALESCE(status_type,'') = ?
           AND area = ?
         GROUP BY location
        ''',
        [_kStatusParkingCompleted, area],
      );
      for (final r in cntRows) {
        final loc = (r['location'] as String?)?.trim() ?? '';
        final c = (r['c'] as int?) ?? 0;
        if (loc.isNotEmpty) _countsByLoc[loc] = c;
      }

      if (!mounted) return;
      setState(() {
        _area = area;
        _singles = singles;
        _composites = composites;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      showFailedSnackbar(context, '주차 구역을 불러오지 못했습니다: $e');
    }
  }

  // displayName → location_name 파싱
  String _locFromDisplayName(String displayName) {
    final idx = displayName.lastIndexOf(' - ');
    if (idx == -1) return displayName.trim();
    return displayName.substring(idx + 3).trim();
  }

  /// ▶ 단일 displayName만 갱신 (쿨다운 포함)
  Future<void> _refreshOne(String displayName) async {
    final now = DateTime.now();
    final last = _lastItemRefreshedAt[displayName];
    if (last != null && now.difference(last) < _itemCooldown) {
      final remain = _itemCooldown - now.difference(last);
      debugPrint('🧊 [item] "$displayName" 쿨다운 ${remain.inSeconds}s 남음');
      showSelectedSnackbar(context, '${remain.inSeconds}초 후 다시 시도해주세요');
      return;
    }

    if (_refreshingNames.contains(displayName)) return;
    setState(() => _refreshingNames.add(displayName));

    try {
      final db = await OfflineAuthDb.instance.database;
      final loc = _locFromDisplayName(displayName);

      final res = await db.rawQuery(
        '''
        SELECT COUNT(*) AS c
          FROM ${OfflineAuthDb.tablePlates}
         WHERE COALESCE(status_type,'') = ?
           AND area = ?
           AND location = ?
        ''',
        [_kStatusParkingCompleted, _area, loc],
      );
      final c = (res.isNotEmpty ? res.first['c'] : 0) as int? ?? 0;

      setState(() {
        _countsByLoc[loc] = c;
        _lastItemRefreshedAt[displayName] = DateTime.now();
      });
      debugPrint('✅ [item] 갱신 완료 → "$displayName": $c');
    } catch (e) {
      debugPrint('💥 [item] 갱신 실패("$displayName"): $e');
      if (mounted) showFailedSnackbar(context, '갱신 중 오류가 발생했습니다');
    } finally {
      if (mounted) setState(() => _refreshingNames.remove(displayName));
    }
  }

  int _countOfLoc(String locName) => _countsByLoc[locName.trim()] ?? 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: AbsorbPointer(
        absorbing: widget.isLocked,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Builder(
          builder: (context) {
            final locationsEmpty = _singles.isEmpty && _composites.isEmpty;
            if (locationsEmpty) {
              return const Center(child: Text('표시할 주차 구역이 없습니다.'));
            }

            // ▶ 부모 선택 상태면 자식 리스트
            if (selectedParent != null) {
              final children =
              _composites.where((loc) => (loc.parent ?? '') == selectedParent).toList();

              return Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        const Divider(),
                        ...children.map((loc) {
                          final displayName = '${loc.parent} - ${loc.name}';
                          final busy = _refreshingNames.contains(displayName);
                          final plateCount = _countOfLoc(loc.name);

                          return ListTile(
                            key: ValueKey(displayName),
                            leading: const Icon(
                              Icons.subdirectory_arrow_right,
                              color: _Palette.base,
                            ),
                            title: Text(displayName),
                            subtitle: Text('입차 $plateCount / 공간 ${loc.capacity}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (busy)
                                  const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                else
                                  IconButton(
                                    icon: const Icon(Icons.refresh),
                                    tooltip: '이 항목만 새로고침',
                                    onPressed: () => _refreshOne(displayName),
                                  ),
                                const Icon(Icons.chevron_right),
                              ],
                            ),
                            onTap: () => widget.onLocationSelected(displayName),
                          );
                        }),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: InkWell(
                      onTap: () => setState(() => selectedParent = null),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            vertical: 16.0, horizontal: 16.0),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: const [
                            Icon(Icons.arrow_back, color: Colors.black54),
                            SizedBox(width: 8),
                            Text('되돌아가기', style: TextStyle(fontSize: 16)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }

            // ▶ 루트(단일/부모 그룹 리스트)
            final parentGroups =
            _composites.map((loc) => loc.parent).whereType<String>().toSet().toList();

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 단일 주차 구역
                const Text(
                  '단일 주차 구역',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                ..._singles.map((loc) {
                  final displayName = loc.name; // single은 이름 그대로 표시/선택
                  final busy = _refreshingNames.contains(displayName);
                  final plateCount = _countOfLoc(loc.name);

                  return ListTile(
                    key: ValueKey(displayName),
                    leading: const Icon(Icons.place, color: _Palette.base),
                    title: Text(displayName),
                    subtitle: Text('입차 $plateCount / 공간 ${loc.capacity}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (busy)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            tooltip: '이 항목만 새로고침',
                            onPressed: () => _refreshOne(displayName),
                          ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: () => widget.onLocationSelected(displayName),
                  );
                }),

                const Divider(),

                // 복합 주차 구역 (부모) — 총 공간만 표시
                const Text(
                  '복합 주차 구역',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                ...parentGroups.map((parent) {
                  final children =
                  _composites.where((l) => l.parent == parent).toList();
                  final totalCapacity =
                  children.fold<int>(0, (sum, l) => sum + l.capacity);

                  return ListTile(
                    key: ValueKey('parent:$parent'),
                    leading: const Icon(Icons.layers, color: _Palette.base),
                    title: Text(parent),
                    subtitle: Text('총 공간 $totalCapacity'),
                    // ⛔️ 새로고침 버튼 없음 — 진입만 가능
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => setState(() => selectedParent = parent),
                  );
                }),
                const SizedBox(height: 16),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LocRow {
  final String type; // 'single' | 'composite'
  final String name; // location_name
  final String? parent; // composite일 때 상위 이름
  final int capacity;

  _LocRow({
    required this.type,
    required this.name,
    required this.parent,
    required this.capacity,
  });
}
