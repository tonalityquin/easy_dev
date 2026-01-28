import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../models/location_model.dart';
import '../../../../states/area/area_state.dart';
import '../../../../states/location/location_state.dart';

class _Brand {
  static Color border(ColorScheme cs) => cs.outlineVariant.withOpacity(0.85);
  static Color overlay(ColorScheme cs) => cs.outlineVariant.withOpacity(0.12);
}

class TripleModifyLocationBottomSheet extends StatefulWidget {
  final TextEditingController locationController;
  final Function(String) onLocationSelected;

  const TripleModifyLocationBottomSheet({
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
      builder: (_) => TripleModifyLocationBottomSheet(
        locationController: controller,
        onLocationSelected: onSelected,
      ),
    );
  }

  @override
  State<TripleModifyLocationBottomSheet> createState() => _TripleModifyLocationBottomSheetState();
}

class _TripleModifyLocationBottomSheetState extends State<TripleModifyLocationBottomSheet> {
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
                border: Border.all(color: _Brand.border(cs)),
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
                          child: FilledButton.icon(
                            icon: const Icon(Icons.refresh),
                            label: const Text('주차 구역 갱신하기'),
                            onPressed: () => Navigator.pop(context),
                            style: FilledButton.styleFrom(
                              backgroundColor: cs.primary,
                              foregroundColor: cs.onPrimary,
                            ),
                          ),
                        );
                      }

                      final locations = snapshot.data!;
                      final singles = locations.where((l) => l.type == 'single').toList();
                      final composites = locations.where((l) => l.type == 'composite').toList();
                      final parentSet = composites.map((e) => e.parent).toSet().toList();

                      return ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        children: [
                          Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: cs.onSurfaceVariant.withOpacity(0.45),
                              borderRadius: BorderRadius.circular(2),
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
                              leading: Icon(Icons.arrow_back, color: cs.onSurface),
                              title: const Text('뒤로가기'),
                              onTap: () => setState(() => selectedParent = null),
                            ),
                            Divider(color: _Brand.border(cs)),
                            ...composites
                                .where((loc) => loc.parent == selectedParent)
                                .map((loc) {
                              final name = '${loc.parent} - ${loc.locationName}';
                              return ListTile(
                                leading: Icon(Icons.subdirectory_arrow_right, color: cs.onSurfaceVariant),
                                title: Text(name),
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
                                title: Text(loc.locationName),
                                subtitle: Text('공간 ${loc.capacity}', style: TextStyle(color: cs.onSurfaceVariant)),
                                onTap: () {
                                  widget.onLocationSelected(loc.locationName);
                                  Navigator.pop(context);
                                },
                              );
                            }),
                            const SizedBox(height: 8),
                            Divider(color: _Brand.border(cs)),
                            const SizedBox(height: 8),
                            Text(
                              '복합 주차 구역',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: cs.onSurface),
                            ),
                            const SizedBox(height: 8),
                            ...parentSet.map((parent) {
                              final sub = composites.where((l) => l.parent == parent).toList();
                              final totalCapacity = sub.fold(0, (sum, l) => sum + l.capacity);
                              return ListTile(
                                leading: Icon(Icons.layers, color: cs.primary),
                                title: Text('복합 구역: $parent'),
                                subtitle: Text('총 공간 $totalCapacity', style: TextStyle(color: cs.onSurfaceVariant)),
                                trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                                onTap: () => setState(() => selectedParent = parent),
                              );
                            }),
                            const SizedBox(height: 16),
                            Center(
                              child: TextButton(
                                onPressed: () => Navigator.pop(context),
                                style: TextButton.styleFrom(
                                  foregroundColor: cs.onSurface,
                                  overlayColor: _Brand.overlay(cs),
                                ),
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
