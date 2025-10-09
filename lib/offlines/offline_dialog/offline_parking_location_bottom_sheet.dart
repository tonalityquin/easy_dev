// lib/screens/type_pages/offline_parking_request_package/offline_parking_location_bottom_sheet.dart
import 'package:flutter/material.dart';

// ▼ SQLite (경로는 프로젝트 구조에 맞게 조정하세요)
import '../sql/offline_auth_db.dart';
import '../sql/offline_auth_service.dart';

class OfflineParkingLocationBottomSheet extends StatefulWidget {
  final TextEditingController locationController;

  const OfflineParkingLocationBottomSheet({
    super.key,
    required this.locationController,
  });

  @override
  State<OfflineParkingLocationBottomSheet> createState() => _OfflineParkingLocationBottomSheetState();
}

// 내부 전용 간단 모델
class _Loc {
  final String area;
  final String locationName;
  final String parent; // ''(빈문자) 가능
  final String type;   // 'single' | 'composite'
  final int capacity;

  _Loc({
    required this.area,
    required this.locationName,
    required this.parent,
    required this.type,
    required this.capacity,
  });
}

class _OfflineParkingLocationBottomSheetState extends State<OfflineParkingLocationBottomSheet> {
  String? selectedParent;
  String? _currentArea;
  Future<List<_Loc>>? _futureLocations;

  @override
  void initState() {
    super.initState();
    _prepareLocationData();
  }

  // ─────────────────────────────────────────────────────────────
  // 현재 Area 결정 (세션 userId → offline_accounts 조회 → fallback isSelected=1)
  // ─────────────────────────────────────────────────────────────
  Future<String> _loadCurrentArea() async {
    final db = await OfflineAuthDb.instance.database;
    final session = await OfflineAuthService.instance.currentSession();
    final uid = (session?.userId ?? '').trim();

    String area = '';

    if (uid.isNotEmpty) {
      final r1 = await db.query(
        OfflineAuthDb.tableAccounts,
        columns: const ['currentArea', 'selectedArea'],
        where: 'userId = ?',
        whereArgs: [uid],
        limit: 1,
      );
      if (r1.isNotEmpty) {
        area = ((r1.first['currentArea'] as String?) ?? (r1.first['selectedArea'] as String?) ?? '').trim();
      }
    }

    if (area.isEmpty) {
      final r2 = await db.query(
        OfflineAuthDb.tableAccounts,
        columns: const ['currentArea', 'selectedArea'],
        where: 'isSelected = 1',
        limit: 1,
      );
      if (r2.isNotEmpty) {
        area = ((r2.first['currentArea'] as String?) ?? (r2.first['selectedArea'] as String?) ?? '').trim();
      }
    }

    return area;
  }

  // ─────────────────────────────────────────────────────────────
  // 현재 Area의 offline_locations 로드
  // ─────────────────────────────────────────────────────────────
  Future<List<_Loc>> _fetchLocationsForArea(String area) async {
    final db = await OfflineAuthDb.instance.database;
    final rows = await db.query(
      OfflineAuthDb.tableLocations,
      columns: const ['area', 'location_name', 'parent', 'type', 'capacity'],
      where: 'area = ?',
      whereArgs: [area],
      orderBy: 'type ASC, parent ASC, location_name ASC',
    );

    return rows.map((r) {
      return _Loc(
        area: (r['area'] as String?) ?? '',
        locationName: (r['location_name'] as String?) ?? '',
        parent: (r['parent'] as String?) ?? '',
        type: (r['type'] as String?) ?? 'single',
        capacity: (r['capacity'] as int?) ?? 0,
      );
    }).toList();
  }

  Future<void> _prepareLocationData() async {
    final area = await _loadCurrentArea();
    _currentArea = area.isNotEmpty ? area : null;

    if (!mounted) return;

    setState(() {
      if (_currentArea == null) {
        _futureLocations = Future.value(<_Loc>[]);
      } else {
        _futureLocations = _fetchLocationsForArea(_currentArea!);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Material(
        color: Colors.transparent,
        child: DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: FutureBuilder<List<_Loc>>(
                future: _futureLocations,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  // Area 자체를 못 불러왔거나 목록이 비었을 때
                  if (_currentArea == null || !snapshot.hasData || snapshot.data!.isEmpty) {
                    return _buildEmptyBody(context);
                  }

                  final locations = snapshot.data!;
                  final singles = locations.where((l) => l.type == 'single').toList();
                  final composites = locations.where((l) => l.type == 'composite').toList();

                  if (selectedParent != null) {
                    final sub = composites.where((l) => l.parent == selectedParent).toList();
                    return ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      children: [
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back),
                              onPressed: () => setState(() => selectedParent = null),
                              tooltip: '뒤로가기',
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '복합 구역: $selectedParent',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const Divider(),
                        ...sub.map((loc) {
                          final displayName = '${loc.parent} - ${loc.locationName}';
                          return ListTile(
                            leading: const Icon(Icons.subdirectory_arrow_right),
                            title: Text(displayName),
                            subtitle: Text('공간 ${loc.capacity}'),
                            onTap: () {
                              // 선택 값 컨트롤러에 반영(선택)
                              widget.locationController.text = displayName;
                              Navigator.pop(context, displayName);
                            },
                          );
                        }),
                      ],
                    );
                  } else {
                    final parentSet = composites.map((e) => e.parent).toSet().toList();

                    return ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                '주차 구역 선택',
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                            ),
                            if (_currentArea != null)
                              Chip(
                                label: Text(_currentArea!),
                                backgroundColor: Colors.grey.shade100,
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // 단일 구역
                        const Text(
                          '단일 주차 구역',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        ...singles.map((loc) {
                          return ListTile(
                            leading: const Icon(Icons.place),
                            title: Text(loc.locationName),
                            subtitle: Text('공간 ${loc.capacity}'),
                            onTap: () {
                              widget.locationController.text = loc.locationName;
                              Navigator.pop(context, loc.locationName);
                            },
                          );
                        }),

                        const Divider(height: 32),

                        // 복합 구역
                        const Text(
                          '복합 주차 구역',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        ...parentSet.map((parent) {
                          final sub = composites.where((l) => l.parent == parent).toList();
                          final totalCapacity = sub.fold(0, (sum, l) => sum + l.capacity);
                          return ListTile(
                            leading: const Icon(Icons.layers),
                            title: Text('복합 구역: $parent'),
                            subtitle: Text('총 공간 $totalCapacity'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => setState(() => selectedParent = parent),
                          );
                        }),

                        const SizedBox(height: 16),
                        Center(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('닫기'),
                          ),
                        ),
                      ],
                    );
                  }
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmptyBody(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '주차 구역 데이터를 불러올 수 없습니다.',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('주차 구역 갱신하기'),
            onPressed: () => Navigator.pop(context, 'refresh'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }
}
