import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../states/area/area_state.dart';
import '../../../states/location/location_state.dart';
import '../../../repositories/location/location_repository.dart';

class ParkingCompletedLocationPicker extends StatefulWidget {
  final Function(String locationName) onLocationSelected;
  final bool isLocked;

  const ParkingCompletedLocationPicker({
    super.key,
    required this.onLocationSelected,
    required this.isLocked,
  });

  @override
  State<ParkingCompletedLocationPicker> createState() => _ParkingCompletedLocationPickerState();
}

class _ParkingCompletedLocationPickerState extends State<ParkingCompletedLocationPicker> {
  String? selectedParent;
  bool _isRefreshing = false;
  DateTime? _lastRefreshedAt;
  final Duration _cooldown = const Duration(minutes: 1);

  Future<void> _onRefreshPressed(
      LocationState locationState,
      LocationRepository repo,
      String area,
      ) async {
    final now = DateTime.now();
    if (_lastRefreshedAt != null && now.difference(_lastRefreshedAt!) < _cooldown) {
      final remaining = _cooldown - now.difference(_lastRefreshedAt!);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${remaining.inSeconds}초 후 다시 시도해주세요')),
      );
      return;
    }

    setState(() => _isRefreshing = true);
    try {
      await locationState.updatePlateCountsFromRepository(repo);
      _lastRefreshedAt = DateTime.now();
    } catch (e) {
      debugPrint('🚨 새로고침 중 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("새로고침 중 오류가 발생했습니다")),
        );
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Widget _buildRefreshButton(
      LocationState locationState,
      LocationRepository repo,
      String area,
      ) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.teal,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        icon: _isRefreshing
            ? const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            strokeWidth: 2,
          ),
        )
            : const Icon(Icons.refresh),
        label: const Text(
          "수동 새로고침",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        onPressed: _isRefreshing ? null : () => _onRefreshPressed(locationState, repo, area),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final area = context.read<AreaState>().currentArea;
    final locationRepo = context.read<LocationRepository>();

    return Scaffold(
      backgroundColor: Colors.white,
      body: Consumer<LocationState>(
        builder: (context, locationState, _) {
          return AbsorbPointer(
            absorbing: widget.isLocked,
            child: Builder(builder: (context) {
              if (locationState.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              final locations = locationState.locations;
              if (locations.isEmpty) {
                return Center(
                  child: GestureDetector(
                    onTap: () => _onRefreshPressed(locationState, locationRepo, area),
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
                );
              }

              final singles = locations.where((l) => l.type == 'single').toList();
              final composites = locations.where((l) => l.type == 'composite').toList();

              if (selectedParent != null) {
                final children = composites.where((loc) => loc.parent == selectedParent).toList();

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
                              leading: const Icon(Icons.subdirectory_arrow_right, color: Colors.teal),
                              title: Text(displayName),
                              subtitle: Text('입차 ${loc.plateCount} / 공간 ${loc.capacity}'),
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
                  _buildRefreshButton(locationState, locationRepo, area),
                  const SizedBox(height: 24),
                  const Text('단일 주차 구역', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  ...singles.map((loc) => ListTile(
                    leading: const Icon(Icons.place, color: Colors.teal),
                    title: Text(loc.locationName),
                    subtitle: Text('입차 ${loc.plateCount} / 공간 ${loc.capacity}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => widget.onLocationSelected(loc.locationName),
                  )),
                  const Divider(),
                  const Text('복합 주차 구역', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  ...parentGroups.map((parent) {
                    final children = composites.where((l) => l.parent == parent).toList();
                    final totalCapacity = children.fold(0, (sum, l) => sum + l.capacity);
                    final totalCount = children.fold(0, (sum, l) => sum + l.plateCount);

                    return ListTile(
                      leading: const Icon(Icons.layers, color: Colors.teal),
                      title: Text(parent),
                      subtitle: Text('총 입차 $totalCount / 총 공간 $totalCapacity'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => setState(() => selectedParent = parent),
                    );
                  }),
                  const SizedBox(height: 16),
                ],
              );
            }),
          );
        },
      ),
    );
  }
}
