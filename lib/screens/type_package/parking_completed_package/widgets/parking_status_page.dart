// lib/screens/type_pages/parking_completed_pages/widgets/parking_status_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../states/location/location_state.dart';
import '../../../../states/area/area_state.dart';

// ✅ UsageReporter: "파이어베이스가 발생하는 로직만" 계측 (읽기/쓰기/삭제 중 '읽기'만 사용)
import '../../../../utils/usage_reporter.dart';

/// 주차 현황 페이지
/// - Firestore Aggregate COUNT 1회 수행 (parking_completed 문서 수)
/// - ✅ 계측은 Firestore 작업(읽기) 시점에만 수행
class ParkingStatusPage extends StatefulWidget {
  final bool isLocked;

  const ParkingStatusPage({super.key, required this.isLocked});

  @override
  State<ParkingStatusPage> createState() => _ParkingStatusPageState();
}

class _ParkingStatusPageState extends State<ParkingStatusPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  int _occupiedCount = 0;      // 영역 전체의 주차 완료 총합
  bool _isCountLoading = true; // 총합 집계 로딩 상태

  @override
  void initState() {
    super.initState();

    // 첫 프레임 이후 영역 읽고 Firestore 집계 1회 수행
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      final area = context.read<AreaState>().currentArea.trim();

      try {
        final aggQuery = _firestore
            .collection('plates')
            .where('area', isEqualTo: area)
            .where('type', isEqualTo: 'parking_completed')
            .count();

        final snap = await aggQuery.get();
        final cnt = (snap.count ?? 0);

        // ✅ 계측: Firestore READ (aggregate count)
        try {
          await UsageReporter.instance.report(
            area: area,
            action: 'read', // 읽기
            n: cnt,
            source: 'parkingStatus.count.query(parking_completed).aggregate',
          );
        } catch (_) {
          // 계측 실패는 UX에 영향 없음
        }

        if (!mounted) return;
        setState(() {
          _occupiedCount = cnt;
          _isCountLoading = false;
        });
      } catch (e) {
        // ✅ 계측: Firestore READ 실패도 읽기 시도로 기록(n=0)
        try {
          await UsageReporter.instance.report(
            area: area,
            action: 'read',
            n: 0,
            source:
            'parkingStatus.count.query(parking_completed).aggregate.error',
          );
        } catch (_) {}

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

              // capacity 합계는 로컬 state로 계산
              final totalCapacity = locationState.locations
                  .fold<int>(0, (sum, l) => sum + l.capacity);
              final occupiedCount = _occupiedCount;

              final double usageRatio =
              totalCapacity == 0 ? 0 : occupiedCount / totalCapacity;
              final String usagePercent =
              (usageRatio * 100).toStringAsFixed(1);

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
                        fontSize: 18, fontWeight: FontWeight.w600),
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
