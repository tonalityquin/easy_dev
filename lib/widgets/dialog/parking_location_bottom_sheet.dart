import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/location_model.dart';
import '../../../states/area/area_state.dart';
import '../../../states/location/location_state.dart';

class ParkingLocationBottomSheet extends StatefulWidget {
  final TextEditingController locationController;

  const ParkingLocationBottomSheet({
    super.key,
    required this.locationController,
  });

  @override
  State<ParkingLocationBottomSheet> createState() => _ParkingLocationBottomSheetState();
}

class _ParkingLocationBottomSheetState extends State<ParkingLocationBottomSheet> {
  String? selectedParent;
  String? _previousArea;
  Future<List<LocationModel>>? _futureLocations;

  @override
  void initState() {
    super.initState();
    _prepareLocationData();
  }

  void _prepareLocationData() {
    final currentArea = context.read<AreaState>().currentArea;
    final locationState = context.read<LocationState>();

    if (_previousArea != currentArea) {
      _previousArea = currentArea;
      _futureLocations = Future.value(locationState.locations);
    }
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
              child: Consumer<LocationState>(
                builder: (context, locationState, _) {
                  if (locationState.isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  return FutureBuilder<List<LocationModel>>(
                    future: _futureLocations,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return Center(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.refresh),
                            label: const Text('주차 구역 갱신하기'),
                            onPressed: () => Navigator.pop(context, 'refresh'),
                          ),
                        );
                      }

                      final locations = snapshot.data!;
                      final singles = locations.where((l) => l.type == 'single').toList();
                      final composites = locations.where((l) => l.type == 'composite').toList();

                      if (selectedParent != null) {
                        final subLocations = composites.where((l) => l.parent == selectedParent).toList();
                        return ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.all(16),
                          children: [
                            ListTile(
                              leading: const Icon(Icons.arrow_back),
                              title: const Text('뒤로가기'),
                              onTap: () => setState(() => selectedParent = null),
                            ),
                            const Divider(),
                            ...subLocations.map((loc) {
                              final displayName = '${loc.parent} - ${loc.locationName}';
                              return ListTile(
                                title: Text(displayName),
                                subtitle: Text('공간 ${loc.capacity}'),
                                leading: const Icon(Icons.subdirectory_arrow_right),
                                onTap: () => Navigator.pop(context, displayName),
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
                            const Text(
                              '단일 주차 구역',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 8),
                            ...singles.map((loc) {
                              return ListTile(
                                title: Text(loc.locationName),
                                subtitle: Text('공간 ${loc.capacity}'),
                                leading: const Icon(Icons.place),
                                onTap: () => Navigator.pop(context, loc.locationName),
                              );
                            }),
                            const Divider(height: 32),
                            const Text(
                              '복합 주차 구역',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 8),
                            ...parentSet.map((parent) {
                              final subLocations = composites.where((l) => l.parent == parent).toList();
                              final totalCapacity = subLocations.fold(0, (sum, l) => sum + l.capacity);

                              return ListTile(
                                title: Text('복합 구역: $parent'),
                                subtitle: Text('총 공간 $totalCapacity'),
                                leading: const Icon(Icons.layers),
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
