import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../repositories/location/location_repository.dart';
import '../../../../states/area/area_state.dart';
import '../../../../states/location/location_state.dart';

class ParkingStatusPage extends StatefulWidget {
  const ParkingStatusPage({super.key});

  @override
  State<ParkingStatusPage> createState() => _ParkingStatusPageState();
}

class _ParkingStatusPageState extends State<ParkingStatusPage> {
  bool _isRefreshing = false;
  DateTime? _lastRefreshedAt;
  final Duration _cooldown = const Duration(minutes: 1);

  Future<void> _onRefreshPressed(LocationState locationState, LocationRepository repo, String area) async {
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

  Widget _buildRefreshButton(LocationState locationState, LocationRepository repo, String area) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.teal,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        label: const Text("수동 새로고침", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        onPressed: _isRefreshing ? null : () => _onRefreshPressed(locationState, repo, area),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final area = context.read<AreaState>().currentArea;
    final locationRepo = context.read<LocationRepository>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('주차장 전체 현황'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        centerTitle: true,
        elevation: 0,
      ),
      backgroundColor: Colors.white,
      body: Consumer<LocationState>(
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
              _buildRefreshButton(locationState, locationRepo, area),
              const SizedBox(height: 32),

              // 📊 제목
              const Text(
                '📊 현재 주차 현황',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // 텍스트 요약
              Text(
                '총 $totalCapacity대 중 $occupiedCount대 주차됨',
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),

              // 진행 바
              LinearProgressIndicator(
                value: usageRatio,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(
                  usageRatio >= 0.8 ? Colors.red : Colors.blueAccent,
                ),
                minHeight: 8,
              ),
              const SizedBox(height: 12),

              // 퍼센트 강조 텍스트
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
    );
  }
}
