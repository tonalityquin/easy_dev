import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../states/area/spot_state.dart';
import '../../../../models/location_model.dart';
import '../../../../states/location/location_state.dart';

class ParkingCompletedLocationDialog extends StatefulWidget {
  final TextEditingController locationController;
  final Function(String) onLocationSelected;

  const ParkingCompletedLocationDialog({
    super.key,
    required this.locationController,
    required this.onLocationSelected,
  });

  @override
  State<ParkingCompletedLocationDialog> createState() => _ParkingCompletedLocationDialogState();
}

class _ParkingCompletedLocationDialogState extends State<ParkingCompletedLocationDialog> {
  String? selectedParent;
  String? _previousArea;
  Future<List<LocationModel>>? _futureLocations;

  @override
  void initState() {
    super.initState();
    _prepareLocationData();
  }

  void _showSelfAgain(BuildContext outerContext) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog(
        context: outerContext,
        builder: (context) => ParkingCompletedLocationDialog(
          locationController: widget.locationController,
          onLocationSelected: widget.onLocationSelected,
        ),
      );
    });
  }

  void _prepareLocationData() {
    final currentArea = context.read<AreaState>().currentArea;
    final locationState = context.read<LocationState>();

    if (_previousArea != currentArea) {
      _previousArea = currentArea;
      _futureLocations = Future.value(locationState.locations);
    }
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

  Widget _buildLocationTile({
    required String title,
    String? subtitle,
    required IconData icon,
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
    final currentArea = context.read<AreaState>().currentArea;

    return ScaleTransitionDialog(
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.location_on, color: Colors.green),
            SizedBox(width: 8),
            Text('주차 구역 선택', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Consumer<LocationState>(
          builder: (context, locationState, _) {
            if (locationState.isLoading) {
              return const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              );
            }

            return FutureBuilder<List<LocationModel>>(
              future: _futureLocations,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 80,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return SizedBox(
                    height: 100,
                    child: Center(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('주차 구역 갱신하기'),
                        onPressed: () {
                          final outerContext = context;
                          Navigator.pop(context);
                          _showSelfAgain(outerContext);
                        },
                      ),
                    ),
                  );
                }

                final locations = snapshot.data!;
                final singles = locations.where((l) => l.type == 'single').toList();
                final composites = locations.where((l) => l.type == 'composite').toList();

                if (selectedParent != null) {
                  final subLocations = composites.where((l) => l.parent == selectedParent).toList();

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.arrow_back),
                        title: const Text('← 복합 구역 목록으로'),
                        onTap: () => setState(() => selectedParent = null),
                      ),
                      const Divider(),
                      ...subLocations.map((loc) {
                        final displayName = '${loc.parent} - ${loc.locationName}';
                        return FutureBuilder<int>(
                          future: _getPlateCount(displayName, currentArea),
                          builder: (context, countSnapshot) {
                            final subtitle =
                                countSnapshot.hasData ? '등록 ${countSnapshot.data} / 정원 ${loc.capacity}' : null;
                            return _buildLocationTile(
                              icon: Icons.subdirectory_arrow_right,
                              title: displayName,
                              subtitle: subtitle,
                              onTap: () {
                                widget.onLocationSelected(displayName);
                                Navigator.pop(context);
                              },
                            );
                          },
                        );
                      }),
                    ],
                  );
                } else {
                  final parentSet = composites.map((e) => e.parent).whereType<String>().toSet().toList();

                  return SizedBox(
                    width: double.maxFinite,
                    height: 400,
                    child: ListView(
                      children: [
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 4.0),
                          child: Text('단일 주차 구역', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        ...singles.map((loc) {
                          return FutureBuilder<int>(
                            future: _getPlateCount(loc.locationName, currentArea),
                            builder: (context, countSnapshot) {
                              final subtitle =
                                  countSnapshot.hasData ? '등록 ${countSnapshot.data} / 정원 ${loc.capacity}' : null;
                              return _buildLocationTile(
                                icon: Icons.place,
                                title: loc.locationName,
                                subtitle: subtitle,
                                onTap: () {
                                  widget.onLocationSelected(loc.locationName);
                                  Navigator.pop(context);
                                },
                              );
                            },
                          );
                        }),
                        const Divider(),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 4.0),
                          child: Text('복합 주차 구역', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        ...parentSet.map((parent) {
                          final childLocations = composites.where((loc) => loc.parent == parent).toList();
                          final totalCapacity = childLocations.fold(0, (sum, loc) => sum + loc.capacity);

                          return FutureBuilder<List<int>>(
                            future: Future.wait(
                              childLocations
                                  .map((loc) => _getPlateCount('${loc.parent} - ${loc.locationName}', currentArea)),
                            ),
                            builder: (context, snapshot) {
                              final totalCount = snapshot.hasData ? snapshot.data!.fold(0, (a, b) => a + b) : null;
                              final subtitle =
                                  totalCount != null ? '총 등록 $totalCount / 총 정원 $totalCapacity' : '총 정원 $totalCapacity';

                              return _buildLocationTile(
                                icon: Icons.layers,
                                title: parent,
                                subtitle: subtitle,
                                onTap: () => setState(() => selectedParent = parent),
                              );
                            },
                          );
                        }),
                      ],
                    ),
                  );
                }
              },
            );
          },
        ),
      ),
    );
  }
}

class ScaleTransitionDialog extends StatefulWidget {
  final Widget child;

  const ScaleTransitionDialog({super.key, required this.child});

  @override
  State<ScaleTransitionDialog> createState() => _ScaleTransitionDialogState();
}

class _ScaleTransitionDialogState extends State<ScaleTransitionDialog> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: widget.child,
    );
  }
}
