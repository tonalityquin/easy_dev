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
  static const String _kStatusParkingCompleted = 'parkingCompleted';

  int _occupiedCount = 0;
  int _totalCapacity = 0;

  bool _isLoading = true;
  bool _hadError = false;

  bool _didAggregateRun = false;
  String? _lastArea;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRunAggregate());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRunAggregate());
  }

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

    final area = ((row?['currentArea'] as String?) ?? (row?['selectedArea'] as String?) ?? '').trim();
    return area;
  }

  Future<void> _maybeRunAggregate() async {
    if (!mounted) return;

    final route = ModalRoute.of(context);
    final isVisible = route == null ? true : (route.isCurrent || route.isActive);
    if (!isVisible) return;

    final area = await _loadCurrentArea();

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

      final capRes = await db.rawQuery(
        '''
        SELECT COALESCE(SUM(capacity), 0) AS cap
          FROM ${OfflineAuthDb.tableLocations}
         WHERE area = ?
        ''',
        [area],
      );
      final totalCap = ((capRes.isNotEmpty ? capRes.first['cap'] : 0) as int?) ?? 0;

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRunAggregate());

    final usageRatio = _totalCapacity == 0 ? 0.0 : (_occupiedCount / _totalCapacity).clamp(0.0, 1.0);
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
                        _didAggregateRun = false;
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
                const _AutoCyclingReminderCards(),
                const SizedBox(height: 12),
              ],
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

class _AutoCyclingReminderCards extends StatefulWidget {
  const _AutoCyclingReminderCards();

  @override
  State<_AutoCyclingReminderCards> createState() => _AutoCyclingReminderCardsState();
}

class _AutoCyclingReminderCardsState extends State<_AutoCyclingReminderCards> {
  static const Duration cycleInterval = Duration(seconds: 2);
  static const Duration animDuration = Duration(milliseconds: 400);
  static const Curve animCurve = Curves.easeInOut;

  final PageController _pageController = PageController();
  Timer? _timer;
  int _currentIndex = 0;

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
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 170,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.center,
            child: FractionallySizedBox(
              widthFactor: 0.98, // 좌우 여백 약간
              child: PageView.builder(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => _currentIndex = i,
                itemCount: _cards.length,
                itemBuilder: (context, index) {
                  final c = _cards[index];
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
