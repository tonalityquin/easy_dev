import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../states/location/location_state.dart';
import '../../../repositories/location_repo_services/location_repository.dart';
import '../../../utils/snackbar_helper.dart';
import 'ui/parking_completed_table_sheet.dart'; // ✅ 커스텀 스낵바 헬퍼 사용


/// Deep Blue 팔레트(서비스 카드와 동일 계열)
class _Palette {
  static const base = Color(0xFF0D47A1); // primary
}

class ParkingCompletedLocationPicker extends StatefulWidget {
  final Function(String locationName) onLocationSelected;
  final bool isLocked;

  const ParkingCompletedLocationPicker({
    super.key,
    required this.onLocationSelected,
    required this.isLocked,
  });

  @override
  State<ParkingCompletedLocationPicker> createState() => _ParkingCompletedLocationPickerState();
}

class _ParkingCompletedLocationPickerState extends State<ParkingCompletedLocationPicker> {
  String? selectedParent;

  // ▶ 항목별 새로고침 상태/쿨다운
  final Set<String> _refreshingNames = {};
  final Map<String, DateTime> _lastItemRefreshedAt = {};
  final Duration _itemCooldown = const Duration(seconds: 20);

  /// ▶ 단일 displayName만 갱신
  Future<void> _refreshOne(
      LocationState state,
      LocationRepository repo,
      String displayName,
      ) async {
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
      debugPrint('🎯 [item] 갱신 요청 → "$displayName"');
      await state.updatePlateCountsForNames(repo, [displayName]);
      _lastItemRefreshedAt[displayName] = DateTime.now();
      debugPrint('✅ [item] 갱신 완료 → "$displayName"');
    } catch (e) {
      debugPrint('💥 [item] 갱신 실패("$displayName"): $e');
      if (mounted) showFailedSnackbar(context, '갱신 중 오류가 발생했습니다');
    } finally {
      if (mounted) setState(() => _refreshingNames.remove(displayName));
    }
  }

  @override
  Widget build(BuildContext context) {
    final locationRepo = context.read<LocationRepository>();

    return Scaffold(
      backgroundColor: Colors.white,
      body: Consumer<LocationState>(
        builder: (context, locationState, _) {
          return AbsorbPointer(
            absorbing: widget.isLocked,
            child: Builder(
              builder: (context) {
                if (locationState.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                final locations = locationState.locations;
                if (locations.isEmpty) {
                  // 실제로는 "주차 구역 없음" 케이스가 없다고 하셨지만, 안전망 유지
                  return const Center(
                    child: Text('표시할 주차 구역이 없습니다.'),
                  );
                }

                final singles = locations.where((l) => l.type == 'single').toList();
                final composites = locations.where((l) => l.type == 'composite').toList();

                // ▶ 부모 선택 상태면 자식 리스트
                if (selectedParent != null) {
                  final children = composites.where((loc) => loc.parent == selectedParent).toList();

                  return Column(
                    children: [
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            const Divider(),
                            ...children.map((loc) {
                              final displayName = '${loc.parent} - ${loc.locationName}';
                              final busy = _refreshingNames.contains(displayName);

                              return ListTile(
                                key: ValueKey(displayName),
                                leading: const Icon(
                                  Icons.subdirectory_arrow_right,
                                  color: _Palette.base,
                                ),
                                title: Text(displayName),
                                subtitle: Text('입차 ${loc.plateCount} / 공간 ${loc.capacity}'),
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
                                        onPressed: () => _refreshOne(
                                          locationState,
                                          locationRepo,
                                          displayName,
                                        ),
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
                            padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
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
                final parentGroups = composites.map((loc) => loc.parent).whereType<String>().toSet().toList();

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // ================================
                    // ✅ 액션 바: "테이블 열기" 버튼 (신규)
                    // ================================
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '데이터 뷰어',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                        // 호환성을 위해 ElevatedButton.icon 사용
                        ElevatedButton.icon(
                          onPressed: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => const ParkingCompletedTableSheet(),
                            );
                          },
                          icon: const Icon(Icons.table_chart_outlined),
                          label: const Text('테이블 열기'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // 단일 주차 구역ㄱ
                    const Text(
                      '단일 주차 구역',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    ...singles.map((loc) {
                      final displayName = loc.locationName;
                      final busy = _refreshingNames.contains(displayName);

                      return ListTile(
                        key: ValueKey(displayName),
                        leading: const Icon(Icons.place, color: _Palette.base),
                        title: Text(displayName),
                        subtitle: Text('입차 ${loc.plateCount} / 공간 ${loc.capacity}'),
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
                                onPressed: () => _refreshOne(
                                  locationState,
                                  locationRepo,
                                  displayName,
                                ),
                              ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: () => widget.onLocationSelected(displayName),
                      );
                    }),

                    const Divider(),

                    // 복합 주차 구역 (부모) — 총 입차 수 표시 제거(총 공간만 표시)
                    const Text(
                      '복합 주차 구역',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    ...parentGroups.map((parent) {
                      final children = composites.where((l) => l.parent == parent).toList();
                      final totalCapacity = children.fold(0, (sum, l) => sum + l.capacity);

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
          );
        },
      ),
    );
  }
}
