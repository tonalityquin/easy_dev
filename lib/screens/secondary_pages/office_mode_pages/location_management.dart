import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../widgets/navigation/secondary_role_navigation.dart';
import '../../../widgets/navigation/secondary_mini_navigation.dart';
import 'location_management_pages/location_setting.dart';
import '../../../widgets/container/location_container.dart';
import '../../../states/location_state.dart';
import '../../../states/area_state.dart';

/// 주차 구역 관리 화면
/// - 현재 선택된 지역에 따라 주차 구역을 필터링하고 표시
/// - 주차 구역 추가 및 삭제 기능 제공
class LocationManagement extends StatelessWidget {
  const LocationManagement({Key? key}) : super(key: key);

  /// 특정 아이콘 클릭에 따른 동작 처리 함수
  void handleIconTapped(int index, LocationState locationState, BuildContext context) {
    final selectedIds =
        locationState.selectedLocations.keys.where((id) => locationState.selectedLocations[id] == true).toList();

    if (locationState.navigationIcons[index] == Icons.add) {
      // 주차 구역 추가 다이얼로그 표시
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('🚨 주차 구역 추가 실패: $error')),
                  );
                },
              );
            },
          );
        },
      );
    } else if (locationState.navigationIcons[index] == Icons.delete && selectedIds.isNotEmpty) {
      // 선택된 주차 구역 삭제
      locationState.deleteLocations(
        selectedIds,
        onError: (error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('🚨 주차 구역 삭제 실패: $error')),
          );
        },
      );
    } else {
      // 기본 처리 (예상하지 못한 Index)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unsupported action')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final locationState = context.watch<LocationState>(); // 위치 상태 관리
    final currentArea = context.watch<AreaState>().currentArea; // 현재 선택된 지역

    // 현재 지역에 해당하는 주차 구역 필터링
    final filteredLocations = locationState.locations.where((location) => location['area'] == currentArea).toList();

    return Scaffold(
      appBar: const SecondaryRoleNavigation(), // 상단 내비게이션
      body: locationState.isLoading
          ? const Center(child: CircularProgressIndicator()) // 로딩 상태 표시
          : filteredLocations.isEmpty
              ? const Center(child: Text('No locations in this area.')) // 주차 구역 없음
              : ListView.builder(
                  itemCount: filteredLocations.length,
                  itemBuilder: (context, index) {
                    final location = filteredLocations[index];
                    final isSelected = locationState.selectedLocations[location['id']] ?? false;
                    return LocationContainer(
                      location: location['locationName']!,
                      isSelected: isSelected,
                      onTap: () => locationState.toggleSelection(location['id']!), // 선택 상태 토글
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
