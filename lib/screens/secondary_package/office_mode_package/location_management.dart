import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../utils/snackbar_helper.dart';
import '../../../widgets/navigation/secondary_mini_navigation.dart';
import 'location_management_package/location_setting.dart';
import '../../../states/location/location_state.dart';
import '../../../states/area/area_state.dart';
import '../../../models/location_model.dart';

class LocationManagement extends StatefulWidget {
  const LocationManagement({super.key});

  @override
  State<LocationManagement> createState() => _LocationManagementState();
}

class _LocationManagementState extends State<LocationManagement> {
  String _filter = 'all';

  Future<void> handleIconTapped(
      int index,
      LocationState locationState,
      BuildContext context,
      ) async {
    final selectedId = locationState.selectedLocationId;

    if (locationState.navigationIcons[index] == Icons.add) {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (sheetCtx) {
          final currentArea = Provider.of<AreaState>(context, listen: false).currentArea;

          return LocationSettingBottomSheet(
            onSave: (location) {
              if (location is Map<String, dynamic>) {
                final type = location['type'];

                if (type == 'single') {
                  final name = location['name']?.toString() ?? '';
                  final capacity = (location['capacity'] as int?) ?? 0;

                  locationState
                      .addSingleLocation(
                    name,
                    currentArea,
                    capacity: capacity,
                    onError: (error) => showFailedSnackbar(context, '🚨 주차 구역 추가 실패: $error'),
                  )
                      .then((_) => showSuccessSnackbar(context, '✅ 주차 구역이 추가되었습니다.'));
                } else if (type == 'composite') {
                  final parent = location['parent']?.toString() ?? '';
                  final rawSubs = location['subs'];

                  final subs = (rawSubs is List)
                      ? rawSubs
                      .map<Map<String, dynamic>>((sub) => {
                    'name': sub['name']?.toString() ?? '',
                    'capacity': sub['capacity'] ?? 0,
                  })
                      .toList()
                      : <Map<String, dynamic>>[];

                  locationState
                      .addCompositeLocation(
                    parent,
                    subs,
                    currentArea,
                    onError: (error) => showFailedSnackbar(context, '🚨 복합 주차 구역 추가 실패: $error'),
                  )
                      .then((_) => showSuccessSnackbar(context, '✅ 복합 주차 구역이 추가되었습니다.'));
                } else {
                  showFailedSnackbar(context, '❗ 알 수 없는 주차 구역 유형입니다.');
                }
              } else {
                showFailedSnackbar(context, '❗ 알 수 없는 형식의 주차 구역 데이터입니다.');
              }
            },
          );
        },
      );
    } else if (locationState.navigationIcons[index] == Icons.delete) {
      if (selectedId == null) {
        showFailedSnackbar(context, '⚠️ 삭제할 항목을 선택하세요.');
        return;
      }

      final ok = await _confirmDelete(context);
      if (!ok) return;

      locationState.deleteLocations(
        [selectedId],
        onError: (error) => showFailedSnackbar(context, '🚨 주차 구역 삭제 실패: $error'),
      );
    } else {
      showFailedSnackbar(context, '⚠️ 지원되지 않는 동작입니다.');
    }
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('삭제 확인'),
        content: const Text('선택한 주차 구역을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final locationState = context.watch<LocationState>();
    final cs = Theme.of(context).colorScheme;
    final currentArea = context.watch<AreaState>().currentArea;

    final allLocations =
    locationState.locations.where((location) => location.area == currentArea).toList();

    final singles = allLocations.where((loc) => loc.type == 'single').toList();
    final composites = allLocations.where((loc) => loc.type == 'composite').toList();

    final Map<String, List<LocationModel>> grouped = {};
    for (final loc in composites) {
      final parent = loc.parent ?? '기타';
      grouped.putIfAbsent(parent, () => []).add(loc);
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text('주차구역', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        automaticallyImplyLeading: false, // ✅ 오타 수정
      ),
      body: locationState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : allLocations.isEmpty
          ? const Center(child: Text('현재 지역에 주차 구역이 없습니다.'))
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text('전체'),
                  selected: _filter == 'all',
                  onSelected: (_) => setState(() => _filter = 'all'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('단일'),
                  selected: _filter == 'single',
                  onSelected: (_) => setState(() => _filter = 'single'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('복합'),
                  selected: _filter == 'composite',
                  onSelected: (_) => setState(() => _filter = 'composite'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _filter == 'single'
                ? _buildSimpleList(singles, locationState, colorScheme: cs)
                : _filter == 'composite'
                ? _buildGroupedList(grouped, locationState, colorScheme: cs)
                : _buildAllListView(
              singles: singles,
              grouped: grouped,
              state: locationState,
              colorScheme: cs,
            ),
          ),
        ],
      ),
      bottomNavigationBar: SecondaryMiniNavigation(
        icons: locationState.navigationIcons,
        onIconTapped: (index) => handleIconTapped(index, locationState, context),
      ),
    );
  }

  /// ‘전체’ 탭은 하나의 ListView로 합쳐 스크롤러를 1개만 유지(오버플로우/중첩 스크롤 방지)
  Widget _buildAllListView({
    required List<LocationModel> singles,
    required Map<String, List<LocationModel>> grouped,
    required LocationState state,
    required ColorScheme colorScheme,
  }) {
    final tiles = <Widget>[];

    if (singles.isNotEmpty) {
      tiles.add(const Padding(
        padding: EdgeInsets.all(8.0),
        child: Text('단일 주차 구역'),
      ));
      tiles.addAll(_buildSimpleTiles(singles, state, colorScheme));
    }

    if (singles.isNotEmpty && grouped.isNotEmpty) {
      tiles.add(const Divider());
    }

    if (grouped.isNotEmpty) {
      tiles.add(const Padding(
        padding: EdgeInsets.all(8.0),
        child: Text('복합 주차 구역'),
      ));
      tiles.addAll(_buildGroupedTiles(grouped, state, colorScheme));
    }

    return ListView(children: tiles);
  }

  List<Widget> _buildSimpleTiles(
      List<LocationModel> list,
      LocationState state,
      ColorScheme cs,
      ) {
    return List<Widget>.generate(list.length, (index) {
      final loc = list[index];
      final isSelected = state.selectedLocationId == loc.id;

      return ListTile(
        title: Text(loc.locationName),
        subtitle: loc.capacity > 0 ? Text('공간 ${loc.capacity}대') : null,
        leading: Icon(
          loc.type == 'single' ? Icons.location_on : Icons.maps_home_work,
          color: cs.onSurfaceVariant,
        ),
        trailing: isSelected ? Icon(Icons.check_circle, color: cs.primary) : null,
        selected: isSelected,
        onTap: () => state.toggleLocationSelection(loc.id),
      );
    });
  }

  List<Widget> _buildGroupedTiles(
      Map<String, List<LocationModel>> grouped,
      LocationState state,
      ColorScheme cs,
      ) {
    return grouped.entries.map((entry) {
      final totalCapacity = entry.value.fold<int>(0, (sum, loc) => sum + loc.capacity);

      return ExpansionTile(
        title: Text('상위 구역: ${entry.key} (공간 $totalCapacity대)'),
        children: entry.value.map((loc) {
          final isSelected = state.selectedLocationId == loc.id;

          return ListTile(
            title: Text(loc.locationName),
            subtitle: loc.capacity > 0 ? Text('공간 ${loc.capacity}대') : null,
            leading: const Icon(Icons.subdirectory_arrow_right),
            trailing: isSelected ? Icon(Icons.check_circle, color: cs.primary) : null,
            selected: isSelected,
            onTap: () => state.toggleLocationSelection(loc.id),
          );
        }).toList(),
      );
    }).toList();
  }

  /// 단일 탭 전용 리스트
  Widget _buildSimpleList(
      List<LocationModel> list,
      LocationState state, {
        required ColorScheme colorScheme,
      }) {
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (context, index) {
        final loc = list[index];
        final isSelected = state.selectedLocationId == loc.id;

        return ListTile(
          title: Text(loc.locationName),
          subtitle: loc.capacity > 0 ? Text('공간 ${loc.capacity}대') : null,
          leading: Icon(
            loc.type == 'single' ? Icons.location_on : Icons.maps_home_work,
            color: colorScheme.onSurfaceVariant,
          ),
          trailing: isSelected ? Icon(Icons.check_circle, color: colorScheme.primary) : null,
          selected: isSelected,
          onTap: () => state.toggleLocationSelection(loc.id),
        );
      },
    );
  }

  /// 복합 탭 전용 리스트
  Widget _buildGroupedList(
      Map<String, List<LocationModel>> grouped,
      LocationState state, {
        required ColorScheme colorScheme,
      }) {
    return ListView(
      children: grouped.entries.map((entry) {
        final totalCapacity = entry.value.fold<int>(0, (sum, loc) => sum + loc.capacity);

        return ExpansionTile(
          title: Text('상위 구역: ${entry.key} (공간 $totalCapacity대)'),
          children: entry.value.map((loc) {
            final isSelected = state.selectedLocationId == loc.id;

            return ListTile(
              title: Text(loc.locationName),
              subtitle: loc.capacity > 0 ? Text('공간 ${loc.capacity}대') : null,
              leading: const Icon(Icons.subdirectory_arrow_right),
              trailing: isSelected ? Icon(Icons.check_circle, color: colorScheme.primary) : null,
              selected: isSelected,
              onTap: () => state.toggleLocationSelection(loc.id),
            );
          }).toList(),
        );
      }).toList(),
    );
  }
}
