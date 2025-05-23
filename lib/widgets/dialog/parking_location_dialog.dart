import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/area/area_state.dart';
import '../../models/location_model.dart';
import '../../states/location/location_state.dart';

class ParkingLocationDialog extends StatefulWidget {
  final TextEditingController locationController;
  final Function(String) onLocationSelected;

  const ParkingLocationDialog({
    super.key,
    required this.locationController,
    required this.onLocationSelected,
  });

  @override
  State<ParkingLocationDialog> createState() => _ParkingLocationDialogState();
}

class _ParkingLocationDialogState extends State<ParkingLocationDialog> {
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
        content: FutureBuilder<List<LocationModel>>(
          future: _futureLocations,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              );
            }

            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text('사용 가능한 주차 구역이 없습니다.'),
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
                    return ListTile(
                      title: Text(displayName),
                      leading: const Icon(Icons.subdirectory_arrow_right),
                      onTap: () {
                        widget.onLocationSelected(displayName);
                        Navigator.pop(context);
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
                    ...singles.map((loc) {
                      return ListTile(
                        title: Text(loc.locationName),
                        leading: const Icon(Icons.place),
                        onTap: () {
                          widget.onLocationSelected(loc.locationName);
                          Navigator.pop(context);
                        },
                      );
                    }),
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
