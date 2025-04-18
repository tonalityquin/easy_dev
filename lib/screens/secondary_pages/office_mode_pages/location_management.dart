import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/navigation/secondary_mini_navigation.dart';
import 'location_management_pages/location_setting.dart';
import '../../../widgets/container/location_container.dart';
import '../../../states/location/location_state.dart';
import '../../../states/area/area_state.dart';
class LocationManagement extends StatelessWidget {
  const LocationManagement({super.key});

  void handleIconTapped(int index, LocationState locationState, BuildContext context) {
    final selectedIds = locationState.selectedLocations.keys.where((id) => locationState.selectedLocations[id] == true).toList();

    if (locationState.navigationIcons[index] == Icons.add) {
      showDialog(
        context: context,
        builder: (BuildContext dialogContext) {
          final currentArea = Provider.of<AreaState>(dialogContext, listen: false).currentArea;
          return LocationSetting(
            onSave: (locationName) {
              locationState.addLocation(
                locationName,
                currentArea,
                onError: (error) {
                  showFailedSnackbar(context, '🚨 주차 구역 추가 실패: $error');
                },
              );
            },
          );
        },
      );
    } else if (locationState.navigationIcons[index] == Icons.delete && selectedIds.isNotEmpty) {
      locationState.deleteLocations(
        selectedIds,
        onError: (error) {
          showFailedSnackbar(context, '🚨 주차 구역 삭제 실패: $error');
        },
      );
    } else {
      showFailedSnackbar(context, '⚠️ 지원되지 않는 동작입니다.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final locationState = context.watch<LocationState>();
    final currentArea = context.watch<AreaState>().currentArea;
    final filteredLocations = locationState.locations.where((location) => location.area == currentArea).toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text(
          '주차구역',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: locationState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : filteredLocations.isEmpty
          ? const Center(child: Text('No locations in this area.'))
          : ListView.builder(
        itemCount: filteredLocations.length,
        itemBuilder: (context, index) {
          final location = filteredLocations[index];
          final isSelected = locationState.selectedLocations[location.id] ?? false;
          return LocationContainer(
            location: location.locationName,
            isSelected: isSelected,
            onTap: () => locationState.toggleSelection(location.id),
          );
        },
      ),
      bottomNavigationBar: SecondaryMiniNavigation(
        icons: locationState.navigationIcons,
        onIconTapped: (index) => handleIconTapped(index, locationState, context),
      ),
    );
  }
}
