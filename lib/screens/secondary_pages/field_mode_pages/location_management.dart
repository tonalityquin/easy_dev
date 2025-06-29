import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/navigation/secondary_mini_navigation.dart';
import 'location_management_pages/location_setting.dart';
import '../../../widgets/container/location_container.dart';
import '../../../states/location/location_state.dart';
import '../../../states/area/area_state.dart';
import '../../../models/location_model.dart';

class LocationManagement extends StatefulWidget {
  const LocationManagement({super.key});

  @override
  State<LocationManagement> createState() => _LocationManagementState();
}

class _LocationManagementState extends State<LocationManagement> {
  String _filter = 'all'; // all, single, composite

  void handleIconTapped(int index, LocationState locationState, BuildContext context) {
    final selectedIds = locationState.selectedLocations.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList();

    if (locationState.navigationIcons[index] == Icons.add) {
      showDialog(
        context: context,
        builder: (BuildContext dialogContext) {
          final currentArea = Provider.of<AreaState>(dialogContext, listen: false).currentArea;

          return LocationSetting(
            onSave: (location) {
              if (location is Map<String, dynamic>) {
                final type = location['type'];

                if (type == 'single') {
                  final name = location['name']?.toString() ?? '';
                  locationState.addLocation(
                    name,
                    currentArea,
                    onError: (error) => showFailedSnackbar(context, '🚨 주차 구역 추가 실패: $error'),
                  ).then((_) {
                    showSuccessSnackbar(context, '✅ 주차 구역이 추가되었습니다. 앱을 재실행하세요.');
                  });

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
                    onError: (error) => showFailedSnackbar(context, '🚨 복합 주차 구역 추가 실패: $error'),
                  ).then((_) {
                    showSuccessSnackbar(context, '✅ 복합 주차 구역이 추가되었습니다. 앱을 재실행하세요.');
                  });
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
    } else if (locationState.navigationIcons[index] == Icons.delete && selectedIds.isNotEmpty) {
      locationState.deleteLocations(
        selectedIds,
        onError: (error) => showFailedSnackbar(context, '🚨 주차 구역 삭제 실패: $error'),
      );
    } else {
      showFailedSnackbar(context, '⚠️ 지원되지 않는 동작입니다.');
    }
  }


  @override
  Widget build(BuildContext context) {
    final locationState = context.watch<LocationState>();
    final currentArea = context.watch<AreaState>().currentArea;

    final allLocations = locationState.locations.where((location) => location.area == currentArea).toList();

    final singles = allLocations.where((loc) => loc.type == 'single').toList();
    final composites = allLocations.where((loc) => loc.type == 'composite').toList();

    // 복합 구역을 parent 기준으로 그룹핑
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
              ? const Center(child: Text('No locations in this area.'))
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
                          ? _buildList(singles, locationState)
                          : _filter == 'composite'
                              ? _buildGroupedList(grouped, locationState)
                              : Column(
                                  children: [
                                    if (singles.isNotEmpty)
                                      const Padding(
                                        padding: EdgeInsets.all(8.0),
                                        child: Text('단일 주차 구역'),
                                      ),
                                    _buildList(singles, locationState),
                                    const Divider(),
                                    if (grouped.isNotEmpty)
                                      const Padding(
                                        padding: EdgeInsets.all(8.0),
                                        child: Text('복합 주차 구역'),
                                      ),
                                    Expanded(child: _buildGroupedList(grouped, locationState)),
                                  ],
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

  Widget _buildList(List<LocationModel> locations, LocationState state) {
    return ListView.builder(
      shrinkWrap: true,
      itemCount: locations.length,
      itemBuilder: (context, index) {
        final location = locations[index];
        final isSelected = state.selectedLocations[location.id] ?? false;
        final subtitle = location.capacity > 0 ? '(공간 ${location.capacity}대)' : null;

        return LocationContainer(
          location: location.locationName,
          isSelected: isSelected,
          onTap: () => state.toggleLocationSelection(location.id),
          type: location.type,
          parent: location.parent,
          subtitle: subtitle,
        );
      },
    );
  }

  Widget _buildGroupedList(Map<String, List<LocationModel>> grouped, LocationState state) {
    return ListView(
      children: grouped.entries.map((entry) {
        final totalCapacity = entry.value.fold<int>(0, (sum, loc) => sum + loc.capacity);

        return ExpansionTile(
          title: Text('상위 구역: ${entry.key} (공간 $totalCapacity대)'),
          children: entry.value.map((location) {
            final isSelected = state.selectedLocations[location.id] ?? false;
            final subtitle = location.capacity > 0 ? '(공간 ${location.capacity}대)' : null;

            return LocationContainer(
              location: location.locationName,
              isSelected: isSelected,
              onTap: () => state.toggleLocationSelection(location.id),
              type: location.type,
              parent: location.parent,
              subtitle: subtitle,
            );
          }).toList(),
        );
      }).toList(),
    );
  }
}
