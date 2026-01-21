import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../states/location/location_state.dart';

/// Deep Blue 팔레트(서비스 카드와 동일 계열)
class _Palette {
  static const base = Color(0xFF0D47A1); // primary
}

class MinorParkingCompletedLocationPicker extends StatefulWidget {
  final Function(String locationName) onLocationSelected;

  const MinorParkingCompletedLocationPicker({
    super.key,
    required this.onLocationSelected,
  });

  @override
  State<MinorParkingCompletedLocationPicker> createState() =>
      _MinorParkingCompletedLocationPickerState();
}

class _MinorParkingCompletedLocationPickerState
    extends State<MinorParkingCompletedLocationPicker> {
  String? selectedParent;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Consumer<LocationState>(
        builder: (context, locationState, _) {
          if (locationState.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final locations = locationState.locations;
          if (locations.isEmpty) {
            return const Center(
              child: Text('표시할 주차 구역이 없습니다.'),
            );
          }

          final singles = locations.where((l) => l.type == 'single').toList();
          final composites =
          locations.where((l) => l.type == 'composite').toList();

          // ▶ 부모 선택 상태면 자식 리스트
          if (selectedParent != null) {
            final children =
            composites.where((loc) => loc.parent == selectedParent).toList();

            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Divider(),
                      ...children.map((loc) {
                        final displayName = '${loc.parent} - ${loc.locationName}';

                        return ListTile(
                          key: ValueKey(displayName),
                          leading: const Icon(
                            Icons.subdirectory_arrow_right,
                            color: _Palette.base,
                          ),
                          title: Text(displayName),
                          subtitle: Text(
                            '입차 ${loc.plateCount} / 공간 ${loc.capacity}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
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
                        vertical: 16.0,
                        horizontal: 16.0,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.arrow_back, color: Colors.black54),
                          SizedBox(width: 8),
                          Text(
                            '되돌아가기',
                            style: TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          }

          // ▶ 루트(단일/부모 그룹 리스트)
          final parentGroups = composites
              .map((loc) => loc.parent)
              .whereType<String>()
              .toSet()
              .toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 단일 주차 구역
              const Text(
                '단일 주차 구역',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              ...singles.map((loc) {
                final displayName = loc.locationName;

                return ListTile(
                  key: ValueKey(displayName),
                  leading: const Icon(Icons.place, color: _Palette.base),
                  title: Text(displayName),
                  subtitle: Text(
                    '입차 ${loc.plateCount} / 공간 ${loc.capacity}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => widget.onLocationSelected(displayName),
                );
              }),
              const Divider(),

              // 복합 주차 구역 (부모) — ✅ 총 입차(합계) + 총 공간(합계) 표시
              const Text(
                '복합 주차 구역',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              ...parentGroups.map((parent) {
                final children =
                composites.where((l) => l.parent == parent).toList();

                final totalCapacity = children.fold(
                  0,
                      (sum, l) => sum + l.capacity,
                );

                final totalPlateCount = children.fold(
                  0,
                      (sum, l) => sum + l.plateCount,
                );

                return ListTile(
                  key: ValueKey('parent:$parent'),
                  leading: const Icon(Icons.layers, color: _Palette.base),
                  title: Text(parent),
                  subtitle: Text('총 입차 $totalPlateCount / 총 공간 $totalCapacity'),
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
  }
}
