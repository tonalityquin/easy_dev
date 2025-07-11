import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../utils/snackbar_helper.dart';
import '../../../widgets/navigation/secondary_mini_navigation.dart';
import 'location_management_pages/location_setting.dart';
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

  void handleIconTapped(
      int index,
      LocationState locationState,
      BuildContext context,
      ) {
    final selectedId = locationState.selectedLocationId;

    if (locationState.navigationIcons[index] == Icons.add) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (BuildContext bottomSheetContext) {
          final currentArea = Provider.of<AreaState>(context, listen: false).currentArea;

          return LocationSettingBottomSheet(
            onSave: (location) {
              if (location is Map<String, dynamic>) {
                final type = location['type'];

                if (type == 'single') {
                  final name = location['name']?.toString() ?? '';
                  final capacity = (location['capacity'] as int?) ?? 0;

                  locationState.addSingleLocation(
                    name,
                    currentArea,
                    capacity: capacity,
                    onError: (error) =>
                        showFailedSnackbar(context, '🚨 주차 구역 추가 실패: $error'),
                  ).then((_) => showSuccessSnackbar(
                      context, '✅ 주차 구역이 추가되었습니다. 앱을 재실행하세요.'));
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

                  locationState.addCompositeLocation(
                    parent,
                    subs,
                    currentArea,
                    onError: (error) =>
                        showFailedSnackbar(context, '🚨 복합 주차 구역 추가 실패: $error'),
                  ).then((_) => showSuccessSnackbar(
                      context, '✅ 복합 주차 구역이 추가되었습니다. 앱을 재실행하세요.'));
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

      locationState.deleteLocations(
        [selectedId],
        onError: (error) =>
            showFailedSnackbar(context, '🚨 주차 구역 삭제 실패: $error'),
      );
    } else {
      showFailedSnackbar(context, '⚠️ 지원되지 않는 동작입니다.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final locationState = context.watch<LocationState>();
    final currentArea = context.watch<AreaState>().currentArea;

    final allLocations = locationState.locations
        .where((location) => location.area == currentArea)
        .toList();

    final singles =
    allLocations.where((loc) => loc.type == 'single').toList();
    final composites =
    allLocations.where((loc) => loc.type == 'composite').toList();

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
        automaticallyImplyLeading: false,
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
                ? _buildSimpleList(singles, locationState)
                : _filter == 'composite'
                ? _buildGroupedList(grouped, locationState)
                : Column(
              children: [
                if (singles.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text('단일 주차 구역'),
                  ),
                _buildSimpleList(singles, locationState),
                const Divider(),
                if (grouped.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text('복합 주차 구역'),
                  ),
                Expanded(
                  child: _buildGroupedList(grouped, locationState),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SecondaryMiniNavigation(
        icons: locationState.navigationIcons,
        onIconTapped: (index) =>
            handleIconTapped(index, locationState, context),
      ),
    );
  }

  Widget _buildSimpleList(List<LocationModel> list, LocationState state) {
    return ListView.builder(
      shrinkWrap: true,
      itemCount: list.length,
      itemBuilder: (context, index) {
        final loc = list[index];
        final isSelected = state.selectedLocationId == loc.id;

        return ListTile(
          title: Text(loc.locationName),
          subtitle: loc.capacity > 0 ? Text('공간 ${loc.capacity}대') : null,
          leading: Icon(
            loc.type == 'single' ? Icons.location_on : Icons.maps_home_work,
            color: Colors.grey[700],
          ),
          trailing: isSelected
              ? const Icon(Icons.check_circle, color: Colors.green)
              : null,
          selected: isSelected,
          onTap: () => state.toggleLocationSelection(loc.id),
        );
      },
    );
  }

  Widget _buildGroupedList(
      Map<String, List<LocationModel>> grouped,
      LocationState state,
      ) {
    return ListView(
      children: grouped.entries.map((entry) {
        final totalCapacity =
        entry.value.fold<int>(0, (sum, loc) => sum + loc.capacity);

        return ExpansionTile(
          title: Text('상위 구역: ${entry.key} (공간 $totalCapacity대)'),
          children: entry.value.map((loc) {
            final isSelected = state.selectedLocationId == loc.id;

            return ListTile(
              title: Text(loc.locationName),
              subtitle: loc.capacity > 0 ? Text('공간 ${loc.capacity}대') : null,
              leading: const Icon(Icons.subdirectory_arrow_right),
              trailing: isSelected
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : null,
              selected: isSelected,
              onTap: () => state.toggleLocationSelection(loc.id),
            );
          }).toList(),
        );
      }).toList(),
    );
  }
}
