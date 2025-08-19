import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../states/location/location_state.dart';
import '../../../../repositories/location/location_repository.dart';

class ParkingStatusPage extends StatefulWidget {
  final bool isLocked;

  const ParkingStatusPage({super.key, required this.isLocked});

  @override
  State<ParkingStatusPage> createState() => _ParkingStatusPageState();
}

class _ParkingStatusPageState extends State<ParkingStatusPage> {
  @override
  void initState() {
    super.initState();

    Future.microtask(() {
      final locationRepo = context.read<LocationRepository>();
      context.read<LocationState>().updatePlateCountsFromRepository(locationRepo);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Consumer<LocationState>(
            builder: (context, locationState, _) {
              if (locationState.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              final totalCapacity = locationState.locations.fold<int>(0, (sum, loc) => sum + loc.capacity);
              final occupiedCount = locationState.locations.fold<int>(0, (sum, loc) => sum + loc.plateCount);
              final double usageRatio = totalCapacity == 0 ? 0 : occupiedCount / totalCapacity;
              final String usagePercent = (usageRatio * 100).toStringAsFixed(1);

              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text(
                    '📊 현재 주차 현황',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '총 $totalCapacity대 중 $occupiedCount대 주차됨',
                    style: const TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: usageRatio,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      usageRatio >= 0.8 ? Colors.red : Colors.blueAccent,
                    ),
                    minHeight: 8,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '$usagePercent% 사용 중',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              );
            },
          ),

          if (widget.isLocked)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {}, // 아무 반응 없음 (탭 막기)
                child: const SizedBox.expand(),
              ),
            ),
        ],
      ),
    );
  }
}
