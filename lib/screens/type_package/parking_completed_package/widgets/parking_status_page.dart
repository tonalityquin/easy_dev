// lib/screens/type_pages/parking_completed_pages/widgets/parking_status_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../states/location/location_state.dart';
import '../../../../states/area/area_state.dart';

class ParkingStatusPage extends StatefulWidget {
  final bool isLocked;

  const ParkingStatusPage({super.key, required this.isLocked});

  @override
  State<ParkingStatusPage> createState() => _ParkingStatusPageState();
}

class _ParkingStatusPageState extends State<ParkingStatusPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  int _occupiedCount = 0;     // 영역 전체의 주차 완료 총합
  bool _isCountLoading = true; // 총합 집계 로딩 상태

  @override
  void initState() {
    super.initState();
    // ⚠️ 위치별 카운트 갱신(비용 L회) 호출 제거
    // ✅ 영역별 총합 1회 집계만 수행
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final area = context.read<AreaState>().currentArea.trim();

      try {
        final snap = await _firestore
            .collection('plates')
            .where('area', isEqualTo: area)
            .where('type', isEqualTo: 'parking_completed')
            .count()
            .get();

        if (!mounted) return;
        setState(() {
          _occupiedCount = (snap.count ?? 0);
          _isCountLoading = false;
        });
      } catch (e) {
        // 실패 시 0으로 표기하고 넘어감(로깅은 필요 시 추가)
        if (!mounted) return;
        setState(() {
          _occupiedCount = 0;
          _isCountLoading = false;
        });
      }
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
              // locations 로딩(용량 합산용) 또는 총합 집계 로딩 중이면 스피너
              if (locationState.isLoading || _isCountLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              // capacity 합계는 기존처럼 로컬에 있는 locations로 계산
              final totalCapacity = locationState.locations.fold<int>(0, (sum, l) => sum + l.capacity);
              final occupiedCount = _occupiedCount;

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
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
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
                onTap: () {},
                child: const SizedBox.expand(),
              ),
            ),
        ],
      ),
    );
  }
}
