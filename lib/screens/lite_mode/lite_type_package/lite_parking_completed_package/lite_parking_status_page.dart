import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../states/location/location_state.dart';
import '../../../../states/area/area_state.dart';

// import '../../../../utils/usage_reporter.dart';;

// ⬇️ 지역별 리마인더 콘텐츠 파일 import
import '../lite_common_widgets/dashboard_bottom_sheet/memo/lite_dash_memo.dart';
import 'lite_parking_reminder_contents.dart';

class LiteParkingStatusPage extends StatefulWidget {
  final bool isLocked;

  const LiteParkingStatusPage({super.key, required this.isLocked});

  @override
  State<LiteParkingStatusPage> createState() => _LiteParkingStatusPageState();
}

class _LiteParkingStatusPageState extends State<LiteParkingStatusPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  int _occupiedCount = 0; // 영역 전체의 주차 완료 총합
  bool _isCountLoading = true; // 총합 집계 로딩 상태

  // 🔒 UI 표시 시점에만 1회 집계하도록 제어
  bool _didCountRun = false;

  // Area 변경 감지용
  String? _lastArea;

  // 에러 상태 플래그
  bool _hadError = false;

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
    _lastArea = area; // 최신 area 기억

    setState(() {
      _isCountLoading = true;
      _hadError = false;
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
          n: 1, // ← 고정(집계 1회당 read 1회)
          source: 'parkingStatus.count.query(parking_completed).aggregate',
        );*/
      } catch (_) {
        // 계측 실패는 UX에 영향 없음
      }

      if (!mounted) return;
      setState(() {
        _occupiedCount = cnt;
        _isCountLoading = false;
        _hadError = false;
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
        _hadError = true; // 에러 플래그 ON
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 빌드 후에도 가시성 변화가 있으면 한 번 더 시도(이미 실행되었으면 무시됨)
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRunCount());

    // Area 변경 감지 → 재집계 트리거
    final currentArea = context.select<AreaState, String>((s) => s.currentArea.trim());
    if (_lastArea != null && _lastArea != currentArea) {
      // 같은 위젯 인스턴스지만 area가 바뀐 경우에 한해 다시 1회 돌리도록 플래그를 내리고 트리거
      _didCountRun = false;
      _lastArea = currentArea;
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRunCount());
    }

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

              // capacity 합계는 로컬 state로 계산 (요청: 유지)
              final totalCapacity = locationState.locations.fold<int>(0, (sum, l) => sum + l.capacity);
              final occupiedCount = _occupiedCount;

              final double usageRatio = totalCapacity == 0 ? 0 : occupiedCount / totalCapacity;
              final String usagePercent = (usageRatio * 100).toStringAsFixed(1);

              if (_hadError) {
                // 에러 UI: 간단한 재시도 버튼 제공
                return Center(
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
                          '영역: $currentArea',
                          style: const TextStyle(color: Colors.black54),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () {
                            _didCountRun = false; // 다시 1회만 돌도록
                            _runAggregateCount();
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('다시 집계'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              // ------ 상단 영역: "디자인/텍스트 수정 금지" 요청 반영 ------
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
                  // ------ 상단 영역 끝 (수정 없음) ------

                  const SizedBox(height: 24),

                  // ⬇️ 지역별 문구가 들어가는 자동 순환 카드
                  _AutoCyclingReminderCards(area: currentArea),

                  const SizedBox(height: 12),

                  // ⬇️ DashMemo 메모 자동 순환 카드 (1.5초 주기)
                  const _AutoCyclingMemoCards(),

                  const SizedBox(height: 12),
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

/// 하단에 표시되는 자동 순환 카드 뷰
/// - 한 번에 한 카드만 표시
/// - [cycleInterval]마다 자동으로 다음 카드로 애니메이션
/// - 마지막까지 읽으면 다시 첫 카드로 순환
class _AutoCyclingReminderCards extends StatefulWidget {
  final String area;

  const _AutoCyclingReminderCards({
    required this.area,
  });

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

  @override
  void initState() {
    super.initState();
    _startAutoCycle();
  }

  @override
  void didUpdateWidget(covariant _AutoCyclingReminderCards oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 지역이 바뀌면 인덱스/페이지/타이머를 리셋
    if (oldWidget.area.trim() != widget.area.trim()) {
      _currentIndex = 0;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
      _startAutoCycle();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startAutoCycle() {
    _timer?.cancel();
    final total = parkingRemindersForArea(widget.area).length;
    if (total <= 1) return; // 카드가 1장 이하이면 순환 불필요
    _timer = Timer.periodic(cycleInterval, (_) {
      if (!mounted) return;
      final cards = parkingRemindersForArea(widget.area);
      if (cards.length <= 1) return;
      final next = (_currentIndex + 1) % cards.length;
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
    final cards = parkingRemindersForArea(widget.area);

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
                physics: const NeverScrollableScrollPhysics(),
                // 스와이프 대신 자동 전환
                onPageChanged: (i) => _currentIndex = i,
                itemCount: cards.length,
                itemBuilder: (context, index) {
                  final c = cards[index];
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

          // 하단 점 인디케이터 - 중앙 정렬
          Positioned(
            bottom: 6,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(cards.length, (i) {
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

// ⬇️ DashMemo 메모를 1.5초 주기로 넘기는 자동 순환 카드
class _AutoCyclingMemoCards extends StatefulWidget {
  const _AutoCyclingMemoCards();

  @override
  State<_AutoCyclingMemoCards> createState() => _AutoCyclingMemoCardsState();
}

class _AutoCyclingMemoCardsState extends State<_AutoCyclingMemoCards> {
  // ✔ 1.5초 주기로 전환
  static const Duration cycleInterval = Duration(milliseconds: 1500);
  static const Duration animDuration = Duration(milliseconds: 300);
  static const Curve animCurve = Curves.easeInOut;

  final PageController _pageController = PageController();
  Timer? _timer;
  int _currentIndex = 0;

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
    _timer = Timer.periodic(cycleInterval, (_) {
      if (!mounted) return;
      final list = LiteDashMemo.notes.value;
      if (list.length <= 1) return; // 0/1개면 넘기지 않음
      final next = (_currentIndex + 1) % list.length;
      _animateToPage(next);
    });
  }

  void _animateToPage(int index) {
    _currentIndex = index;
    if (!mounted) return;
    // itemCount가 줄어든 경우를 대비해 안전 처리
    final total = LiteDashMemo.notes.value.length;
    if (total == 0) return;
    if (_currentIndex >= total) _currentIndex = 0;

    _pageController.animateToPage(
      _currentIndex,
      duration: animDuration,
      curve: animCurve,
    );
    setState(() {}); // 인디케이터 확장 대비
  }

  // "YYYY-MM-DD HH:mm | 내용" → (time, text) 파싱
  (String, String) _parseLine(String line) {
    final split = line.indexOf('|');
    if (split < 0) return ('', line.trim());
    final time = line.substring(0, split).trim();
    final text = line.substring(split + 1).trim();
    return (time, text);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 170,
      child: ValueListenableBuilder<List<String>>(
        valueListenable: LiteDashMemo.notes,
        builder: (context, list, _) {
          // 페이지 수가 바뀌면 현재 인덱스 보정
          if (list.isNotEmpty && _currentIndex >= list.length) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _currentIndex = 0;
              _pageController.jumpToPage(0);
              setState(() {});
            });
          }

          final itemCount = list.isEmpty ? 1 : list.length;

          return Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: Alignment.center,
                child: FractionallySizedBox(
                  widthFactor: 0.98,
                  child: PageView.builder(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: (i) => _currentIndex = i,
                    itemCount: itemCount,
                    itemBuilder: (context, index) {
                      if (list.isEmpty) {
                        // 저장된 메모가 없을 때 표시 (간단한 안내 카드)
                        return Center(
                          child: Card(
                            color: Colors.white,
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.notes_rounded, size: 18),
                                      SizedBox(width: 8),
                                      Text(
                                        '메모',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 12),
                                  Text(
                                    '저장된 메모가 없습니다.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }

                      final (time, text) = _parseLine(list[index]);
                      return Center(
                        child: Card(
                          color: Colors.white,
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(Icons.notes_rounded, size: 18),
                                    SizedBox(width: 8),
                                    Text(
                                      '메모',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                if (text.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Text(
                                      text,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontSize: 14),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                if (time.isNotEmpty)
                                  Text(
                                    time,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 12, color: Colors.black54),
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

              // 하단 점 인디케이터(메모 개수 기준)
              Positioned(
                bottom: 6,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(list.isEmpty ? 1 : list.length, (i) {
                    final active = i == _currentIndex && list.isNotEmpty;
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
          );
        },
      ),
    );
  }
}
