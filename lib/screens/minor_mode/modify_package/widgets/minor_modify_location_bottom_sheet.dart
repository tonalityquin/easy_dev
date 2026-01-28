import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../models/location_model.dart';
import '../../../../states/area/area_state.dart';
import '../../../../states/location/location_state.dart';

class MinorModifyLocationBottomSheet extends StatefulWidget {
  final TextEditingController locationController;
  final Function(String) onLocationSelected;

  const MinorModifyLocationBottomSheet({
    super.key,
    required this.locationController,
    required this.onLocationSelected,
  });

  static Future<void> show(
      BuildContext context,
      TextEditingController controller,
      Function(String) onSelected,
      ) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MinorModifyLocationBottomSheet(
        locationController: controller,
        onLocationSelected: onSelected,
      ),
    );
  }

  @override
  State<MinorModifyLocationBottomSheet> createState() =>
      _MinorModifyLocationBottomSheetState();
}

class _MinorModifyLocationBottomSheetState
    extends State<MinorModifyLocationBottomSheet> {
  String? _selectedParent;

  // ✅ area 변경 감지용
  String? _previousArea;

  // ✅ 검색어
  String _query = '';

  // ✅ Consumer(LocationState) 변화를 실제 리스트에 반영하기 위한 스냅샷(캐시)
  List<LocationModel> _locationsSnapshot = <LocationModel>[];

  // ✅ area가 비어있을 때 방어
  String get _currentArea => context.read<AreaState>().currentArea.trim();

  @override
  void initState() {
    super.initState();
    _syncLocationsSnapshot();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // ✅ area가 바뀌면 parent selection/검색 상태를 초기화하고 스냅샷 갱신
    final area = _currentArea;
    if (_previousArea != area) {
      _previousArea = area;
      _selectedParent = null;
      _query = '';
      _syncLocationsSnapshot();
    }
  }

  void _syncLocationsSnapshot() {
    try {
      final ls = context.read<LocationState>();
      _locationsSnapshot = List<LocationModel>.of(ls.locations);
    } catch (_) {
      _locationsSnapshot = <LocationModel>[];
    }
  }

  void _closeSheet() {
    Navigator.of(context).maybePop();
  }

  void _selectAndClose(String name) {
    final trimmed = name.trim();
    widget.onLocationSelected(trimmed);
    _closeSheet();
  }

  // ✅ 정렬 기준 통일(표시명 기준)
  String _displayName(LocationModel loc) {
    final type = (loc.type ?? '').trim();
    final parent = (loc.parent ?? '').trim();
    final leaf = loc.locationName.trim();

    if (type == 'composite' && parent.isNotEmpty && leaf.isNotEmpty) {
      return '$parent - $leaf';
    }
    return leaf;
  }

  bool _isComposite(LocationModel loc) =>
      (loc.type ?? '').trim() == 'composite' &&
          (loc.parent ?? '').trim().isNotEmpty;

  bool _isSingle(LocationModel loc) => (loc.type ?? '').trim() == 'single';

  List<LocationModel> _sorted(List<LocationModel> list) {
    final out = List<LocationModel>.of(list);
    out.sort((a, b) => _displayName(a)
        .toLowerCase()
        .compareTo(_displayName(b).toLowerCase()));
    return out;
  }

  bool _matchQuery(LocationModel loc, String q) {
    if (q.isEmpty) return true;
    final dn = _displayName(loc).toLowerCase();
    final leaf = loc.locationName.trim().toLowerCase();
    final parent = (loc.parent ?? '').trim().toLowerCase();

    return dn.contains(q) || leaf.contains(q) || parent.contains(q);
  }

  @override
  Widget build(BuildContext context) {
    // ✅ rootNavigator push/pop 정책과 일치시키기 위한 rootContext

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
              child: Consumer<LocationState>(
                builder: (context, locationState, _) {
                  // ✅ state가 갱신되면 스냅샷 갱신(렌더는 snapshot 기반)
                  _locationsSnapshot = List<LocationModel>.of(locationState.locations);

                  final area = _currentArea;
                  final q = _query.trim().toLowerCase();

                  // 로딩
                  if (locationState.isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  // area 방어
                  if (area.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline, size: 34),
                            const SizedBox(height: 10),
                            const Text(
                              '현재 지역(area)이 설정되지 않아\n주차 구역을 표시할 수 없습니다.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: _closeSheet,
                              child: const Text('닫기'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  // 데이터 없음
                  if (_locationsSnapshot.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.inbox_outlined, size: 34),
                            const SizedBox(height: 10),
                            const Text(
                              '주차 구역 데이터가 없습니다.',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              '설정/개발 메뉴에서 주차 구역을 갱신한 뒤 다시 시도해주세요.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.black54),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: _closeSheet,
                              icon: const Icon(Icons.close),
                              label: const Text('닫기'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  // 분류
                  final allSingles =
                  _sorted(_locationsSnapshot.where(_isSingle).toList());
                  final allComposites =
                  _sorted(_locationsSnapshot.where(_isComposite).toList());

                  // parent 목록
                  final parentList = allComposites
                      .map((e) => (e.parent ?? '').trim())
                      .where((p) => p.isNotEmpty)
                      .toSet()
                      .toList()
                    ..sort((a, b) =>
                        a.toLowerCase().compareTo(b.toLowerCase()));

                  // 검색 필터 적용
                  final singles =
                  allSingles.where((l) => _matchQuery(l, q)).toList();
                  final composites =
                  allComposites.where((l) => _matchQuery(l, q)).toList();

                  // child 화면(선택된 parent가 있을 때)
                  final compositeChildren = (_selectedParent == null)
                      ? <LocationModel>[]
                      : composites
                      .where((loc) =>
                  (loc.parent ?? '').trim() == _selectedParent)
                      .toList();

                  // parent 화면(검색 고려)
                  final filteredParents = parentList.where((p) {
                    if (q.isEmpty) return true;
                    if (p.toLowerCase().contains(q)) return true;

                    // parent 이름이 검색에 안 걸려도,
                    // 그 parent의 자식 중 하나라도 검색에 걸리면 표시
                    return composites.any(
                          (loc) => (loc.parent ?? '').trim() == p,
                    );
                  }).toList();

                  return ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Handle
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

                      // Title row + close
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '주차 구역 선택',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: '닫기',
                            onPressed: _closeSheet,
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),

                      const SizedBox(height: 6),

                      // Area label
                      Row(
                        children: [
                          const Icon(Icons.location_on, size: 16, color: Colors.black54),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '지역: $area',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.black54,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Search
                      TextField(
                        onChanged: (v) => setState(() => _query = v),
                        decoration: InputDecoration(
                          hintText: '주차 구역 검색',
                          prefixIcon: const Icon(Icons.search),
                          isDense: true,
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.black12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.black12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.primary.withOpacity(0.55),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Back to parent (composite child view)
                      if (_selectedParent != null) ...[
                        ListTile(
                          leading: const Icon(Icons.arrow_back),
                          title: const Text('뒤로가기'),
                          subtitle: Text(
                            '복합 구역: $_selectedParent',
                            style: const TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                          onTap: () => setState(() => _selectedParent = null),
                        ),
                        const Divider(),
                        if (compositeChildren.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Center(
                              child: Text(
                                '검색 결과가 없습니다.',
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          )
                        else
                          ...compositeChildren.map((loc) {
                            final name = _displayName(loc);
                            return ListTile(
                              leading: const Icon(Icons.subdirectory_arrow_right),
                              title: Text(
                                name,
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                              subtitle: Text('공간 ${loc.capacity}'),
                              onTap: () => _selectAndClose(name),
                            );
                          }),
                        const SizedBox(height: 8),
                      ] else ...[
                        // Singles section
                        const Text(
                          '단일 주차 구역',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        if (singles.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Text(
                              '표시할 단일 주차 구역이 없습니다.',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                          )
                        else
                          ...singles.map((loc) {
                            final name = _displayName(loc);
                            return ListTile(
                              leading: const Icon(Icons.place),
                              title: Text(
                                name,
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                              subtitle: Text('공간 ${loc.capacity}'),
                              onTap: () => _selectAndClose(name),
                            );
                          }),

                        const Divider(height: 32),

                        // Composite section
                        const Text(
                          '복합 주차 구역',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),

                        if (filteredParents.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Text(
                              '표시할 복합 주차 구역이 없습니다.',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                          )
                        else
                          ...filteredParents.map((parent) {
                            final sub = allComposites
                                .where((l) => (l.parent ?? '').trim() == parent)
                                .toList();

                            final totalCapacity = sub.fold<int>(0, (sum, l) => sum + l.capacity);

                            return ListTile(
                              leading: const Icon(Icons.layers),
                              title: Text(
                                '복합 구역: $parent',
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                              subtitle: Text('총 공간 $totalCapacity'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => setState(() => _selectedParent = parent),
                            );
                          }),

                        const SizedBox(height: 16),

                        Center(
                          child: TextButton(
                            onPressed: _closeSheet,
                            child: const Text('닫기'),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
