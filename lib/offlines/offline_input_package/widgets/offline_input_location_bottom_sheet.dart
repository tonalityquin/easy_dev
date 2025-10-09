import 'package:flutter/material.dart';

// ▼ SQLite / 세션 (경로는 프로젝트에 맞게 조정하세요)
import '../../sql/offline_auth_db.dart';        // ← 경로 조정
import '../../sql/offline_auth_service.dart';   // ← 경로 조정

class OfflineInputLocationBottomSheet extends StatefulWidget {
  final TextEditingController locationController;
  final Function(String) onLocationSelected;

  const OfflineInputLocationBottomSheet({
    super.key,
    required this.locationController,
    required this.onLocationSelected,
  });

  /// 바텀시트 호출 헬퍼
  static Future<void> show(
      BuildContext context,
      TextEditingController controller,
      Function(String) onSelected,
      ) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      builder: (_) {
        return FractionallySizedBox(
          heightFactor: 1, // 최상단까지
          child: OfflineInputLocationBottomSheet(
            locationController: controller,
            onLocationSelected: onSelected,
          ),
        );
      },
    );
  }

  @override
  State<OfflineInputLocationBottomSheet> createState() =>
      _OfflineInputLocationBottomSheetState();
}

class _OfflineInputLocationBottomSheetState
    extends State<OfflineInputLocationBottomSheet> {
  String? _selectedParent;
  String? _currentArea;
  Future<List<_Loc>>? _futureLocations;

  @override
  void initState() {
    super.initState();
    _loadAndQuery();
  }

  Future<void> _loadAndQuery() async {
    final area = await _loadCurrentArea();
    if (!mounted) return;
    setState(() {
      _currentArea = area;
      _futureLocations = _fetchLocations(area);
    });
  }

  /// 현재 Area 로딩: (userId 기준) → 없으면 isSelected=1 폴백
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
        area = ((r1.first['currentArea'] as String?) ??
            (r1.first['selectedArea'] as String?) ??
            '')
            .trim();
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
        area = ((r2.first['currentArea'] as String?) ??
            (r2.first['selectedArea'] as String?) ??
            '')
            .trim();
      }
    }

    return area;
  }

  /// SQLite에서 locations 조회
  Future<List<_Loc>> _fetchLocations(String area) async {
    final db = await OfflineAuthDb.instance.database;
    final rows = await db.query(
      OfflineAuthDb.tableLocations,
      columns: const [
        'location_name',
        'parent',
        'type',
        'capacity',
      ],
      where: 'area = ?',
      whereArgs: [area],
      orderBy: "CASE type WHEN 'composite' THEN 0 ELSE 1 END, parent, location_name",
    );
    return rows
        .map((m) => _Loc(
      locationName: (m['location_name'] as String?)?.trim() ?? '',
      parent: (m['parent'] as String?)?.trim() ?? '',
      type: (m['type'] as String?)?.trim() ?? 'single',
      capacity: (m['capacity'] as int?) ?? 0,
    ))
        .where((e) => e.locationName.isNotEmpty)
        .toList();
  }

  void _selectAndClose(String value) {
    widget.locationController.text = value;
    widget.onLocationSelected(value);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Material(
        color: Colors.white,
        child: FutureBuilder<List<_Loc>>(
          future: _futureLocations,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator(strokeWidth: 3));
            }
            if (snap.hasError) {
              return _ErrorView(
                message: '주차 구역을 불러오지 못했습니다.\n${snap.error}',
                onClose: () => Navigator.of(context).pop(),
              );
            }
            final data = snap.data ?? const <_Loc>[];
            if (data.isEmpty) {
              return _EmptyView(
                area: _currentArea ?? '',
                onClose: () => Navigator.of(context).pop(),
              );
            }

            // 분류
            final singles = data.where((e) => e.type == 'single').toList();
            final composites = data.where((e) => e.type == 'composite').toList();
            final parentSet = {
              for (final e in composites) e.parent,
            }..removeWhere((p) => p.isEmpty);

            return DraggableScrollableSheet(
              initialChildSize: 0.9,
              minChildSize: 0.4,
              maxChildSize: 0.95,
              builder: (context, scrollController) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: ListView(
                    controller: scrollController,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 12),
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
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                          ),
                          if (_currentArea != null && _currentArea!.isNotEmpty)
                            Text(
                              _currentArea!,
                              style: const TextStyle(color: Colors.grey),
                            ),
                          IconButton(
                            tooltip: '새로고침',
                            icon: const Icon(Icons.refresh),
                            onPressed: _loadAndQuery,
                          ),
                          IconButton(
                            tooltip: '닫기',
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // 부모 선택 상태면 하위 composite만
                      if (_selectedParent != null) ...[
                        ListTile(
                          leading: const Icon(Icons.arrow_back),
                          title: const Text('뒤로가기'),
                          onTap: () => setState(() => _selectedParent = null),
                        ),
                        const Divider(),
                        ...composites
                            .where((loc) => loc.parent == _selectedParent)
                            .map((loc) {
                          final name = '${loc.parent} - ${loc.locationName}';
                          return ListTile(
                            leading: const Icon(Icons.subdirectory_arrow_right),
                            title: Text(name),
                            subtitle: Text('공간 ${loc.capacity}'),
                            onTap: () => _selectAndClose(name),
                          );
                        }),
                      ] else ...[
                        // 단일 구역
                        if (singles.isNotEmpty) ...[
                          const Text(
                            '단일 주차 구역',
                            style:
                            TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          ...singles.map((loc) => ListTile(
                            leading: const Icon(Icons.place),
                            title: Text(loc.locationName),
                            subtitle: Text('공간 ${loc.capacity}'),
                            onTap: () => _selectAndClose(loc.locationName),
                          )),
                          const SizedBox(height: 12),
                          const Divider(),
                        ],

                        // 복합 구역 그룹
                        const SizedBox(height: 4),
                        const Text(
                          '복합 주차 구역',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        if (parentSet.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text('등록된 복합 구역이 없습니다.',
                                style: TextStyle(color: Colors.grey)),
                          )
                        else
                          ...parentSet.map((parent) {
                            final subs =
                            composites.where((l) => l.parent == parent).toList();
                            final totalCapacity =
                            subs.fold<int>(0, (sum, l) => sum + l.capacity);
                            return ListTile(
                              leading: const Icon(Icons.layers),
                              title: Text('복합 구역: $parent'),
                              subtitle: Text('총 공간 $totalCapacity'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => setState(() => _selectedParent = parent),
                            );
                          }),
                        const SizedBox(height: 16),
                        Center(
                          child: TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('닫기'),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// 내부 전용 Location 모델
class _Loc {
  final String locationName;
  final String parent; // '' or parent group name
  final String type;   // 'single' | 'composite'
  final int capacity;

  _Loc({
    required this.locationName,
    required this.parent,
    required this.type,
    required this.capacity,
  });
}

class _EmptyView extends StatelessWidget {
  final String area;
  final VoidCallback onClose;

  const _EmptyView({required this.area, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline, size: 36, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              area.isNotEmpty
                  ? '현재 지역("$area")에 등록된 주차 구역이 없습니다.'
                  : '현재 지역 정보를 확인할 수 없습니다.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: onClose, child: const Text('닫기')),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onClose;

  const _ErrorView({required this.message, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 36, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: onClose, child: const Text('닫기')),
          ],
        ),
      ),
    );
  }
}
