// lib/screens/type_pages/offline_parking_completed_package/widgets/offline_parking_status_page.dart
//
// 리팩터링 요약
// - Firestore/Provider(LocationState, AreaState) 제거
// - SQLite(offline_auth_db/offline_auth_service)만 사용해 집계
//   · 총 수용 대수: offline_locations.capacity 합계(area 기준)
//   · 주차 완료 대수: offline_plates.status_type='parkingCompleted' AND area=?
// - 화면 가시성일 때 1회 집계 + area 변경 감지 시 재집계
//
import 'dart:async';

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

    if (row == null) {
      final r2 = await db.query(
        OfflineAuthDb.tableAccounts,
        columns: const ['currentArea', 'selectedArea'],
        where: 'isSelected = 1',
        limit: 1,
      );
      if (r2.isNotEmpty) row = r2.first;
    }

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

                const SizedBox(height: 24),

                // ⬇️ 하단 자동 순환 카드: 한 화면에 한 장, 2초마다 전환
                const _AutoCyclingReminderCards(),

                const SizedBox(height: 12),
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

/// 하단에 표시되는 자동 순환 카드 뷰
/// - 한 번에 한 카드만 표시
/// - [cycleInterval]마다 자동으로 다음 카드로 애니메이션
/// - 마지막까지 읽으면 다시 첫 카드로 순환
class _AutoCyclingReminderCards extends StatefulWidget {
  const _AutoCyclingReminderCards();

  @override
  State<_AutoCyclingReminderCards> createState() => _AutoCyclingReminderCardsState();
}

class _AutoCyclingReminderCardsState extends State<_AutoCyclingReminderCards> {
  // ✔ 2초 주기로 전환
  static const Duration cycleInterval = Duration(seconds: 2);
  static const Duration animDuration = Duration(milliseconds: 400);
  static const Curve animCurve = Curves.easeInOut;

  final PageController _pageController = PageController();
  Timer? _timer;
  int _currentIndex = 0;

  // 중앙 정렬 카드 컨텐츠 (업무 리마인더)
  static const List<_ReminderContent> _cards = [
    _ReminderContent(
      title: '사내 공지란',
      lines: [
        '• 공지 1',
        '• 공지 2',
      ],
    ),
    _ReminderContent(
      title: '사내 공지란 2',
      lines: [
        '• 공지 3',
        '• 공지 4',
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _startAutoCycle();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startAutoCycle() {
    _timer?.cancel();
    if (_cards.length <= 1) return; // 카드가 1장 이하이면 순환 불필요
    _timer = Timer.periodic(cycleInterval, (_) {
      if (!mounted) return;
      final next = (_currentIndex + 1) % _cards.length;
      _animateToPage(next);
    });
  }

  void _animateToPage(int index) {
    _currentIndex = index;
    if (!mounted) return;
    _pageController.animateToPage(
      index,
      duration: animDuration,
      curve: animCurve,
    );
    setState(() {}); // 현재 인덱스 반영(인디케이터 등 확장 시 대비)
  }

  @override
  Widget build(BuildContext context) {
    // ListView 안에 들어가므로 높이를 고정해 주어야 함
    return SizedBox(
      height: 170,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 가운데 정렬로 한 카드씩만 보이게
          Align(
            alignment: Alignment.center,
            child: FractionallySizedBox(
              widthFactor: 0.98, // 좌우 여백 약간
              child: PageView.builder(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(), // 스와이프 대신 자동 전환
                onPageChanged: (i) => _currentIndex = i,
                itemCount: _cards.length,
                itemBuilder: (context, index) {
                  final c = _cards[index];
                  return Center(
                    child: Card(
                      color: Colors.white, // 카드 배경 하얀색
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center, // 중앙 정렬
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.fact_check, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  c.title,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ...c.lines.map(
                                  (t) => Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(
                                  t,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // (선택) 하단 점 인디케이터 - 중앙 정렬
          Positioned(
            bottom: 6,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(_cards.length, (i) {
                final active = i == _currentIndex;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 10 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: active ? Colors.black87 : Colors.black26,
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReminderContent {
  final String title;
  final List<String> lines;
  const _ReminderContent({required this.title, required this.lines});
}
