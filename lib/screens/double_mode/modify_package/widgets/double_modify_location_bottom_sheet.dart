import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../models/location_model.dart';
import '../../../../states/area/area_state.dart';
import '../../../../states/location/location_state.dart';

class DoubleModifyLocationBottomSheet extends StatefulWidget {
  final TextEditingController locationController;
  final Function(String) onLocationSelected;

  const DoubleModifyLocationBottomSheet({
    super.key,
    required this.locationController,
    required this.onLocationSelected,
  });

  static Future<void> show(
      BuildContext context,
      TextEditingController controller,
      Function(String) onSelected,
      ) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DoubleModifyLocationBottomSheet(
        locationController: controller,
        onLocationSelected: onSelected,
      ),
    );
  }

  @override
  State<DoubleModifyLocationBottomSheet> createState() => _DoubleModifyLocationBottomSheetState();
}

class _DoubleModifyLocationBottomSheetState extends State<DoubleModifyLocationBottomSheet> {
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
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: Material(
        color: Colors.transparent,
        child: DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
              ),
              child: Consumer<LocationState>(
                builder: (context, locationState, _) {
                  if (locationState.isLoading) {
                    return Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                      ),
                    );
                  }

                  return FutureBuilder<List<LocationModel>>(
                    future: _futureLocations,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                          ),
                        );
                      }

                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return Center(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.refresh),
                            label: const Text('주차 구역 갱신하기'),
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: cs.primary,
                              foregroundColor: cs.onPrimary,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            ),
                          ),
                        );
                      }

                      final locations = snapshot.data!;
                      final singles = locations.where((l) => l.type == 'single').toList();
                      final composites = locations.where((l) => l.type == 'composite').toList();

                      final parentSet = composites.map((e) => (e.parent ?? '').trim()).where((s) => s.isNotEmpty).toSet().toList();

                      return ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        children: [
                          // Top Handle
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: cs.outlineVariant.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),

                          Text(
                            '주차 구역 선택',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 16),

                          if (selectedParent != null) ...[
                            ListTile(
                              leading: Icon(Icons.arrow_back, color: cs.onSurfaceVariant),
                              title: Text('뒤로가기', style: TextStyle(color: cs.onSurface)),
                              onTap: () => setState(() => selectedParent = null),
                            ),
                            Divider(color: cs.outlineVariant.withOpacity(0.85)),
                            ...composites.where((loc) => (loc.parent ?? '').trim() == selectedParent).map((loc) {
                              final name = '${loc.parent} - ${loc.locationName}';
                              return ListTile(
                                leading: Icon(Icons.subdirectory_arrow_right, color: cs.onSurfaceVariant),
                                title: Text(name, style: TextStyle(color: cs.onSurface)),
                                subtitle: Text('공간 ${loc.capacity}', style: TextStyle(color: cs.onSurfaceVariant)),
                                onTap: () {
                                  widget.onLocationSelected(name);
                                  Navigator.pop(context);
                                },
                              );
                            }),
                          ] else ...[
                            Text(
                              '단일 주차 구역',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: cs.onSurface),
                            ),
                            const SizedBox(height: 8),
                            ...singles.map((loc) {
                              return ListTile(
                                leading: Icon(Icons.place, color: cs.primary),
                                title: Text(loc.locationName, style: TextStyle(color: cs.onSurface)),
                                subtitle: Text('공간 ${loc.capacity}', style: TextStyle(color: cs.onSurfaceVariant)),
                                onTap: () {
                                  widget.onLocationSelected(loc.locationName);
                                  Navigator.pop(context);
                                },
                              );
                            }),
                            const SizedBox(height: 8),
                            Divider(height: 32, color: cs.outlineVariant.withOpacity(0.85)),
                            Text(
                              '복합 주차 구역',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: cs.onSurface),
                            ),
                            const SizedBox(height: 8),
                            ...parentSet.map((parent) {
                              final sub = composites.where((l) => (l.parent ?? '').trim() == parent).toList();
                              final totalCapacity = sub.fold(0, (sum, l) => sum + l.capacity);

                              return ListTile(
                                leading: Icon(Icons.layers, color: cs.primary),
                                title: Text('복합 구역: $parent', style: TextStyle(color: cs.onSurface)),
                                subtitle: Text('총 공간 $totalCapacity', style: TextStyle(color: cs.onSurfaceVariant)),
                                trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                                onTap: () => setState(() => selectedParent = parent),
                              );
                            }),
                            const SizedBox(height: 16),
                            Center(
                              child: TextButton(
                                onPressed: () => Navigator.pop(context),
                                style: TextButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
                                child: const Text('닫기'),
                              ),
                            ),
                          ],
                        ],
                      );
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
