// lib/screens/type_pages/parking_completed_pages/widgets/parking_status_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../states/location/location_state.dart';
import '../../../../states/area/area_state.dart';

// import '../../../../utils/usage_reporter.dart';

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

  // 🔒 UI 표시 시점에만 1회 집계하도록 제어
  bool _didCountRun = false;

  @override
  void initState() {
    super.initState();
    // 첫 프레임 이후에 라우트 가시성 확인 → 표시 중일 때만 집계
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRunCount());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 라우트 바인딩이 늦게 잡히는 경우를 대비해 한 번 더 시도
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRunCount());
  }

  void _maybeRunCount() {
    if (_didCountRun) return;
    // 현재 라우트가 실제로 화면에 표시될 때만 실행
    final route = ModalRoute.of(context);
    final isVisible = route == null ? true : (route.isCurrent || route.isActive);
    if (!isVisible) return;
    _didCountRun = true;
    _runAggregateCount();
  }

  Future<void> _runAggregateCount() async {
    if (!mounted) return;

    final area = context.read<AreaState>().currentArea.trim();

    setState(() {
      _isCountLoading = true;
    });

    try {
      final aggQuery = _firestore
          .collection('plates')
          .where('area', isEqualTo: area)
          .where('type', isEqualTo: 'parking_completed')
          .count();

      final snap = await aggQuery.get();
      final cnt = (snap.count ?? 0);

      try {
        /*await UsageReporter.instance.report(
          area: area,
          action: 'read', // 읽기
          n: 1,           // ← 고정(집계 1회당 read 1회)
          source: 'parkingStatus.count.query(parking_completed).aggregate',
        );*/
      } catch (_) {
        // 계측 실패는 UX에 영향 없음
      }

      if (!mounted) return;
      setState(() {
        _occupiedCount = cnt;
        _isCountLoading = false;
      });
    } catch (e) {
      try {
        /*await UsageReporter.instance.report(
          area: context.read<AreaState>().currentArea.trim(),
          action: 'read',
          n: 1, // ← 실패여도 1회 시도로 고정
          source: 'parkingStatus.count.query(parking_completed).aggregate.error',
        );*/
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _occupiedCount = 0;
        _isCountLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 빌드 후에도 가시성 변화가 있으면 한 번 더 시도(이미 실행되었으면 무시됨)
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRunCount());

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
