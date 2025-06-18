import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../states/area/area_state.dart';
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
                        title: const Text('뒤로가기'),
                        onTap: () => setState(() => selectedParent = null),
                      ),
                      const Divider(),
                      ...subLocations.map((loc) {
                        final displayName = '${loc.parent} - ${loc.locationName}';
                        return FutureBuilder<int>(
                          future: _getPlateCount(displayName, currentArea),
                          builder: (context, countSnapshot) {
                            final countText = countSnapshot.hasData ? '(${countSnapshot.data})' : '';
                            return ListTile(
                              title: Text('$displayName $countText'),
                              leading: const Icon(Icons.subdirectory_arrow_right),
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
                  final parentSet = composites.map((e) => e.parent).toSet().toList();
                  return SizedBox(
                    width: double.maxFinite,
                    height: 300,
                    child: ListView(
                      children: [
                        ...singles.map((loc) => FutureBuilder<int>(
                              future: _getPlateCount(loc.locationName, currentArea),
                              builder: (context, countSnapshot) {
                                final countText = countSnapshot.hasData ? '(${countSnapshot.data})' : '';
                                return ListTile(
                                  title: Text('${loc.locationName} $countText'),
                                  leading: const Icon(Icons.place),
                                  onTap: () {
                                    widget.onLocationSelected(loc.locationName);
                                    Navigator.pop(context);
                                  },
                                );
                              },
                            )),
                        const Divider(),
                        ...parentSet.map((parent) {
                          return ListTile(
                            title: Text('복합 구역: $parent'),
                            leading: const Icon(Icons.layers),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => setState(() => selectedParent = parent),
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
