import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../states/area/area_state.dart';
import '../../../states/bill/bill_state.dart';
import '../../../states/location/location_state.dart';
import '../../../repositories/location/location_repository.dart'; // ✅ 추가

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
  bool _isRefreshing = false;

  Widget _buildRefreshButton(LocationState locationState) {
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
        onPressed: _isRefreshing
            ? null
            : () async {
          setState(() => _isRefreshing = true);
          await locationState.manualLocationRefresh();
          await context.read<BillState>().manualBillRefresh();
          setState(() => _isRefreshing = false);
        },
      ),
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

          final locations = locationState.locations;
          if (locations.isEmpty) {
            return Center(
              child: GestureDetector(
                onTap: () async {
                  setState(() => _isRefreshing = true);
                  await locationState.manualLocationRefresh();
                  await context.read<BillState>().manualBillRefresh();
                  setState(() => _isRefreshing = false);
                },
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
                        return ParkingSingleCountTile(
                          locationName: displayName,
                          area: area,
                          title: displayName,
                          capacity: loc.capacity,
                          icon: Icons.subdirectory_arrow_right,
                          onTap: widget.onLocationSelected,
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
              _buildRefreshButton(locationState),
              const SizedBox(height: 24),
              const Text(
                '단일 주차 구역',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              ...singles.map((loc) {
                return ParkingSingleCountTile(
                  locationName: loc.locationName,
                  area: area,
                  title: loc.locationName,
                  capacity: loc.capacity,
                  icon: Icons.place,
                  onTap: widget.onLocationSelected,
                );
              }),
              const Divider(),
              const Text(
                '복합 주차 구역',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              ...parentGroups.map((parent) {
                final children = composites.where((l) => l.parent == parent).toList();
                final totalCapacity = children.fold(0, (sum, l) => sum + l.capacity);

                return ParkingCompositeTile(
                  parent: parent,
                  area: area,
                  children: children,
                  totalCapacity: totalCapacity,
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

// 단일 구역 Tile
class ParkingSingleCountTile extends StatefulWidget {
  final String locationName;
  final String area;
  final String title;
  final int capacity;
  final IconData icon;
  final void Function(String locationName) onTap;

  const ParkingSingleCountTile({
    super.key,
    required this.locationName,
    required this.area,
    required this.title,
    required this.capacity,
    required this.icon,
    required this.onTap,
  });

  @override
  State<ParkingSingleCountTile> createState() => _ParkingSingleCountTileState();
}

class _ParkingSingleCountTileState extends State<ParkingSingleCountTile> {
  late Future<int> _futureCount;

  @override
  void initState() {
    super.initState();
    final repo = context.read<LocationRepository>();
    _futureCount = repo.getPlateCount(
      locationName: widget.locationName,
      area: widget.area,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: _futureCount,
      builder: (context, snapshot) {
        final subtitle = snapshot.hasData ? '입차 ${snapshot.data} / 공간 ${widget.capacity}' : null;
        return ListTile(
          leading: Icon(widget.icon, color: Colors.teal),
          title: Text(widget.title),
          subtitle: subtitle != null ? Text(subtitle) : null,
          trailing: const Icon(Icons.chevron_right),
          onTap: () => widget.onTap(widget.locationName),
        );
      },
    );
  }
}

// 복합 구역 상위 Tile
class ParkingCompositeTile extends StatefulWidget {
  final String parent;
  final String area;
  final List<dynamic> children;
  final int totalCapacity;
  final VoidCallback onTap;

  const ParkingCompositeTile({
    super.key,
    required this.parent,
    required this.area,
    required this.children,
    required this.totalCapacity,
    required this.onTap,
  });

  @override
  State<ParkingCompositeTile> createState() => _ParkingCompositeTileState();
}

class _ParkingCompositeTileState extends State<ParkingCompositeTile> {
  late Future<List<int>> _futureCounts;

  @override
  void initState() {
    super.initState();
    final repo = context.read<LocationRepository>();
    final locationNames = widget.children
        .map<String>((loc) => '${loc.parent} - ${loc.locationName}')
        .toList();

    _futureCounts = repo
        .getPlateCountsForLocations(locationNames: locationNames, area: widget.area)
        .then((map) => locationNames.map((name) => map[name] ?? 0).toList());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<int>>(
      future: _futureCounts,
      builder: (context, snap) {
        final totalCount = snap.hasData ? snap.data!.fold(0, (a, b) => a + b) : null;
        final subtitle = totalCount != null
            ? '총 입차 $totalCount / 총 공간 ${widget.totalCapacity}'
            : '총 공간 ${widget.totalCapacity}';
        return ListTile(
          leading: Icon(Icons.layers, color: Colors.teal),
          title: Text(widget.parent),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: widget.onTap,
        );
      },
    );
  }
}
