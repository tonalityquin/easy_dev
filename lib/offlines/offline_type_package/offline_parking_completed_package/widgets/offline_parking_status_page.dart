// lib/screens/type_pages/offline_parking_completed_package/widgets/offline_parking_status_page.dart
//
// 리팩터링 요약
// - Firestore/Provider(LocationState, AreaState) 제거
// - SQLite(offline_auth_db/offline_auth_service)만 사용해 집계
//   · 총 수용 대수: offline_locations.capacity 합계(area 기준)
//   · 주차 완료 대수: offline_plates.status_type='parkingCompleted' AND area=?
// - 화면 가시성일 때 1회 집계 + area 변경 감지 시 재집계
//
import 'package:flutter/material.dart';

// ▼ SQLite / 세션
import '../../../sql/offline_auth_db.dart';
import '../../../sql/offline_auth_service.dart';

class OfflineParkingStatusPage extends StatefulWidget {
  final bool isLocked;

  const OfflineParkingStatusPage({super.key, required this.isLocked});

  @override
  State<OfflineParkingStatusPage> createState() => _OfflineParkingStatusPageState();
}

class _OfflineParkingStatusPageState extends State<OfflineParkingStatusPage> {
  // status_type 키 (PlateType 의존 제거)
  static const String _kStatusParkingCompleted = 'parkingCompleted';

  // 집계값
  int _occupiedCount = 0; // 영역 전체의 주차 완료 총합
  int _totalCapacity = 0; // 영역 전체의 수용 가능 대수 합계

  bool _isLoading = true; // 집계 로딩 상태
  bool _hadError = false; // 에러 상태 플래그

  // 🔒 UI 표시 시점에만 1회 집계하도록 제어 + area 변경 시 재집계
  bool _didAggregateRun = false;
  String? _lastArea; // Area 변경 감지용

  @override
  void initState() {
    super.initState();
    // 첫 프레임 이후에 라우트 가시성 확인 → 표시 중일 때만 집계
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRunAggregate());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 라우트 바인딩이 늦게 잡히는 경우를 대비해 한 번 더 시도
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRunAggregate());
  }

  // 현재 세션의 area 불러오기 (없으면 isSelected=1 계정의 currentArea/selectedArea 폴백)
  Future<String> _loadCurrentArea() async {
    final db = await OfflineAuthDb.instance.database;
    final session = await OfflineAuthService.instance.currentSession();
    final uid = (session?.userId ?? '').trim();

    Map<String, Object?>? row;
    if (uid.isNotEmpty) {
      final r1 = await db.query(
        OfflineAuthDb.tableAccounts,
        columns: const ['currentArea', 'selectedArea'],
        where: 'userId = ?',
        whereArgs: [uid],
        limit: 1,
      );
      if (r1.isNotEmpty) row = r1.first;
    }
    row ??= (await db.query(
      OfflineAuthDb.tableAccounts,
      columns: const ['currentArea', 'selectedArea'],
      where: 'isSelected = 1',
      limit: 1,
    ))
        .firstOrNull;

    final area = ((row?['currentArea'] as String?) ??
        (row?['selectedArea'] as String?) ??
        '')
        .trim();
    return area;
  }

  // 집계 실행 필요 여부 확인 후 실행
  Future<void> _maybeRunAggregate() async {
    if (!mounted) return;

    // 현재 라우트가 실제로 화면에 표시될 때만 실행
    final route = ModalRoute.of(context);
    final isVisible = route == null ? true : (route.isCurrent || route.isActive);
    if (!isVisible) return;

    // 현재 area 로드
    final area = await _loadCurrentArea();

    // 최초 1회 또는 area 변경 시에만 집계
    if (!_didAggregateRun || _lastArea == null || _lastArea != area) {
      _lastArea = area;
      _didAggregateRun = true;
      await _runAggregate(area);
    }
  }

  Future<void> _runAggregate(String area) async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _hadError = false;
    });

    try {
      final db = await OfflineAuthDb.instance.database;

      // 1) 총 수용대수(offline_locations.capacity 합계)
      final capRes = await db.rawQuery(
        '''
        SELECT COALESCE(SUM(capacity), 0) AS cap
          FROM ${OfflineAuthDb.tableLocations}
         WHERE area = ?
        ''',
        [area],
      );
      final totalCap = ((capRes.isNotEmpty ? capRes.first['cap'] : 0) as int?) ?? 0;

      // 2) 주차 완료 대수(offline_plates에서 status_type='parkingCompleted')
      final cntRes = await db.rawQuery(
        '''
        SELECT COUNT(*) AS c
          FROM ${OfflineAuthDb.tablePlates}
         WHERE COALESCE(status_type,'') = ?
           AND area = ?
        ''',
        [_kStatusParkingCompleted, area],
      );
      final cnt = ((cntRes.isNotEmpty ? cntRes.first['c'] : 0) as int?) ?? 0;

      if (!mounted) return;
      setState(() {
        _totalCapacity = totalCap;
        _occupiedCount = cnt;
        _isLoading = false;
        _hadError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _totalCapacity = 0;
        _occupiedCount = 0;
        _isLoading = false;
        _hadError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 빌드 후에도 가시성/area 변화가 있으면 한 번 더 시도(이미 실행되었으면 내부에서 무시)
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRunAggregate());

    final usageRatio =
    _totalCapacity == 0 ? 0.0 : (_occupiedCount / _totalCapacity).clamp(0.0, 1.0);
    final usagePercent = (usageRatio * 100).toStringAsFixed(1);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_hadError)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.warning_amber, size: 40, color: Colors.redAccent),
                    const SizedBox(height: 12),
                    const Text(
                      '현황 집계 중 오류가 발생했습니다.',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '영역: ${_lastArea ?? '-'}',
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () {
                        _didAggregateRun = false; // 다시 1회만 돌도록
                        _maybeRunAggregate();
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('다시 집계'),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  '📊 현재 주차 현황',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  '총 $_totalCapacity대 중 $_occupiedCount대 주차됨',
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
            ),

          // 잠금 오버레이
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
