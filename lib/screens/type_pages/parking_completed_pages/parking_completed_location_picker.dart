import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../models/location_model.dart';
import '../../../states/area/spot_state.dart';
import '../../../states/location/location_state.dart';

class ParkingCompletedLocationPicker extends StatefulWidget {
  final Function(String locationName) onLocationSelected;

  const ParkingCompletedLocationPicker({
    super.key,
    required this.onLocationSelected,
  });

  @override
  State<ParkingCompletedLocationPicker> createState() => _ParkingCompletedLocationPickerState();
}

class _ParkingCompletedLocationPickerState extends State<ParkingCompletedLocationPicker> {
  String? selectedParent;
  late Future<List<LocationModel>> _futureLocations;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _futureLocations = _loadLocations();
  }

  Future<List<LocationModel>> _loadLocations() async {
    final locationState = context.read<LocationState>();
    return locationState.locations;
  }

  Future<int> _getPlateCount(String locationName, String area) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('plates')
        .where('location', isEqualTo: locationName)
        .where('area', isEqualTo: area)
        .where('type', isEqualTo: 'parking_completed')
        .count()
        .get();

    return snapshot.count ?? 0;
  }

  Widget _buildTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.teal),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final area = context.read<AreaState>().currentArea;

    return Material(
      color: Colors.white,
      child: Consumer<LocationState>(
        builder: (context, locationState, _) {
          if (locationState.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return FutureBuilder<List<LocationModel>>(
            future: _futureLocations,
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return Center(
                  child: AnimatedScale(
                    scale: _isRefreshing ? 0.95 : 1.0,
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeInOut,
                    child: GestureDetector(
                      onTapDown: (_) => setState(() => _isRefreshing = true),
                      onTapUp: (_) async {
                        setState(() => _isRefreshing = false);
                        await Future.delayed(const Duration(milliseconds: 100));
                        setState(() {
                          _futureLocations = _loadLocations();
                        });
                      },
                      onTapCancel: () => setState(() => _isRefreshing = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.teal),
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.teal.withOpacity(0.05),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.refresh, color: Colors.teal),
                            SizedBox(width: 8),
                            Text(
                              "주차 구역 갱신",
                              style: TextStyle(
                                color: Colors.teal,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }

              final locations = snapshot.data!;
              final singles = locations.where((l) => l.type == 'single').toList();
              final composites = locations.where((l) => l.type == 'composite').toList();

              if (selectedParent != null) {
                final children = composites.where((loc) => loc.parent == selectedParent).toList();

                return Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            const Divider(),
                            ...children.map((loc) {
                              final displayName = '${loc.parent} - ${loc.locationName}';
                              return FutureBuilder<int>(
                                future: _getPlateCount(displayName, area),
                                builder: (context, countSnap) {
                                  final subtitle =
                                      countSnap.hasData ? '입차 ${countSnap.data} / 공간 ${loc.capacity}' : null;
                                  return _buildTile(
                                    icon: Icons.subdirectory_arrow_right,
                                    title: displayName,
                                    subtitle: subtitle,
                                    onTap: () => widget.onLocationSelected(displayName),
                                  );
                                },
                              );
                            }),
                          ],
                        ),
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

              final parentGroups = composites.map((loc) => loc.parent).whereType<String>().toSet().toList();

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('단일 주차 구역', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...singles.map((loc) {
                    return FutureBuilder<int>(
                      future: _getPlateCount(loc.locationName, area),
                      builder: (context, countSnap) {
                        final subtitle = countSnap.hasData ? '입차 ${countSnap.data} / 공간 ${loc.capacity}' : null;
                        return _buildTile(
                          icon: Icons.place,
                          title: loc.locationName,
                          subtitle: subtitle,
                          onTap: () => widget.onLocationSelected(loc.locationName),
                        );
                      },
                    );
                  }),
                  const Divider(),
                  const Text('복합 주차 구역', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...parentGroups.map((parent) {
                    final children = composites.where((l) => l.parent == parent).toList();
                    final totalCapacity = children.fold(0, (sum, l) => sum + l.capacity);

                    return FutureBuilder<List<int>>(
                      future: Future.wait(children.map(
                        (l) => _getPlateCount('${l.parent} - ${l.locationName}', area),
                      )),
                      builder: (context, snap) {
                        final totalCount = snap.hasData ? snap.data!.fold(0, (a, b) => a + b) : null;
                        final subtitle =
                            totalCount != null ? '총 입차 $totalCount / 총 공간 $totalCapacity' : '총 공간 $totalCapacity';

                        return _buildTile(
                          icon: Icons.layers,
                          title: parent,
                          subtitle: subtitle,
                          onTap: () => setState(() => selectedParent = parent),
                        );
                      },
                    );
                  }),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
