import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// ✅ Sheets API
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:shared_preferences/shared_preferences.dart';

// ✅ Header와 동일한 인증 세션(프로젝트 경로에 맞게 유지/조정)
import '../../../../utils/google_auth_session.dart';

import '../../../../states/location/location_state.dart';
import '../../../../states/area/area_state.dart';

// import '../../../../utils/usage_reporter.dart';;

import '../../../common_package/memo_package/dash_memo.dart';
import 'double_parking_reminder_contents.dart';

// ✅ API 디버그(통합 에러 로그) 로거
import 'package:easydev/screens/hubs_mode/dev_package/debug_package/debug_api_logger.dart';

// ─────────────────────────────────────────────────────────────
// ✅ API 디버그 로직: 표준 태그 / 로깅 헬퍼 (file-scope)
// ─────────────────────────────────────────────────────────────
const String _tParking = 'parking';
const String _tParkingStatus = 'parking/status';
const String _tParkingNotice = 'parking/notice';
const String _tFirestore = 'firestore';
const String _tFirestoreAgg = 'firestore/aggregate';
const String _tSheets = 'sheets';
const String _tPrefs = 'prefs';
const String _tUi = 'ui';

Future<void> _logApiError({
  required String tag,
  required String message,
  required Object error,
  Map<String, dynamic>? extra,
  List<String>? tags,
}) async {
  try {
    await DebugApiLogger().log(
      <String, dynamic>{
        'tag': tag,
        'message': message,
        'error': error.toString(),
        if (extra != null) 'extra': extra,
      },
      level: 'error',
      tags: tags,
    );
  } catch (_) {
    // 로깅 실패는 UX에 영향 없도록 무시
  }
}

class DoubleParkingStatusPage extends StatefulWidget {
  const DoubleParkingStatusPage({super.key});

  @override
  State<DoubleParkingStatusPage> createState() => _DoubleParkingStatusPageState();
}

class _DoubleParkingStatusPageState extends State<DoubleParkingStatusPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  int _occupiedCount = 0; // 영역 전체의 주차 완료 총합
  bool _isCountLoading = true; // 총합 집계 로딩 상태

  // 🔒 UI 표시 시점에만 1회 집계하도록 제어
  bool _didCountRun = false;

  // Area 변경 감지용
  String? _lastArea;

  // 에러 상태 플래그
  bool _hadError = false;

  // ✅ 상단 공지(관리자 공지) 상태
  String _noticeMessage = '';
  bool _isNoticeLoading = true;
  bool _didNoticeRun = false;
  String? _lastNoticeArea;

  @override
  void initState() {
    super.initState();
    // 첫 프레임 이후에 라우트 가시성 확인 → 표시 중일 때만 집계/공지 호출
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeRunCount();
      _maybeRunNotice();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 라우트 바인딩이 늦게 잡히는 경우를 대비해 한 번 더 시도
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeRunCount();
      _maybeRunNotice();
    });
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

  void _maybeRunNotice() {
    if (_didNoticeRun) return;
    // 현재 라우트가 실제로 화면에 표시될 때만 실행
    final route = ModalRoute.of(context);
    final isVisible = route == null ? true : (route.isCurrent || route.isActive);
    if (!isVisible) return;
    _didNoticeRun = true;
    _runNoticeFetch(forceRefresh: false);
  }

  Future<void> _runAggregateCount() async {
    if (!mounted) return;

    final area = context.read<AreaState>().currentArea.trim();
    final division = context.read<AreaState>().currentDivision.trim();
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
      // ✅ DebugApiLogger 로깅
      await _logApiError(
        tag: 'DoubleParkingStatusPage._runAggregateCount',
        message: 'Firestore aggregate count 실패(parking_completed)',
        error: e,
        extra: <String, dynamic>{
          'division': division,
          'area': area,
          'collection': 'plates',
          'type': 'parking_completed',
        },
        tags: const <String>[_tParking, _tParkingStatus, _tFirestore, _tFirestoreAgg],
      );

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

  Future<void> _runNoticeFetch({required bool forceRefresh}) async {
    if (!mounted) return;

    final area = context.read<AreaState>().currentArea.trim();
    final division = context.read<AreaState>().currentDivision.trim();
    _lastNoticeArea = area;

    setState(() {
      _isNoticeLoading = true;
    });

    try {
      final result = await DoubleParkingNoticeService.fetchNoticeMessage(
        area: area,
        forceRefresh: forceRefresh,
      );

      if (!mounted) return;
      setState(() {
        _noticeMessage = result;
        _isNoticeLoading = false;
      });
    } catch (e) {
      await _logApiError(
        tag: 'DoubleParkingStatusPage._runNoticeFetch',
        message: '공지 로드(fetchNoticeMessage) 실패',
        error: e,
        extra: <String, dynamic>{
          'division': division,
          'area': area,
          'forceRefresh': forceRefresh,
        },
        tags: const <String>[_tParking, _tParkingNotice, _tSheets, _tUi],
      );

      if (!mounted) return;
      setState(() {
        _noticeMessage = '';
        _isNoticeLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeRunCount();
      _maybeRunNotice();
    });

    final currentArea = context.select<AreaState, String>((s) => s.currentArea.trim());
    if (_lastArea != null && _lastArea != currentArea) {
      _didCountRun = false;
      _lastArea = currentArea;
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRunCount());
    }

    if (_lastNoticeArea != null && _lastNoticeArea != currentArea) {
      _didNoticeRun = false;
      _lastNoticeArea = currentArea;
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRunNotice());
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: Consumer<LocationState>(
        builder: (context, locationState, _) {
          if (locationState.isLoading || _isCountLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final totalCapacity =
          locationState.locations.fold<int>(0, (sum, l) => sum + l.capacity);
          final occupiedCount = _occupiedCount;

          final double usageRatio = totalCapacity == 0 ? 0 : occupiedCount / totalCapacity;
          final String usagePercent = (usageRatio * 100).toStringAsFixed(1);

          if (_hadError) {
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
                        _didCountRun = false;
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
              _DoubleParkingNoticeBar(
                isLoading: _isNoticeLoading,
                message: _noticeMessage,
                onRefresh: () {
                  _didNoticeRun = false;
                  _runNoticeFetch(forceRefresh: true);
                },
              ),
              if (_noticeMessage.trim().isNotEmpty || _isNoticeLoading)
                const SizedBox(height: 12),

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

              _AutoCyclingReminderCards(area: currentArea),

              const SizedBox(height: 12),

              const _AutoCyclingMemoCards(),

              const SizedBox(height: 12),
            ],
          );
        },
      ),
    );
  }
}

/// ✅ 상단 알림바(관리자 공지)
class _DoubleParkingNoticeBar extends StatelessWidget {
  final bool isLoading;
  final String message;
  final VoidCallback onRefresh;

  const _DoubleParkingNoticeBar({
    required this.isLoading,
    required this.message,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final text = message.trim();
    if (!isLoading && text.isEmpty) {
      return const SizedBox.shrink();
    }

    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black.withOpacity(0.08)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: isLoading
                  ? const Text(
                '공지 불러오는 중...',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              )
                  : Text(
                text,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: onRefresh,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.refresh, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ✅ Google Sheets API 기반 공지 서비스 (Double)
class DoubleParkingNoticeService {
  DoubleParkingNoticeService._();

  static const String kNoticeSpreadsheetIdKey = 'notice_spreadsheet_id_v1';
  static const String kNoticeSheetName = 'noti';
  static const String kNoticeRange = '$kNoticeSheetName!A1:A50';

  static const Duration cacheTtl = Duration(minutes: 10);

  static Future<sheets.SheetsApi> _sheetsApi() async {
    try {
      final client = await GoogleAuthSession.instance.safeClient();
      return sheets.SheetsApi(client);
    } catch (e) {
      await _logApiError(
        tag: 'DoubleParkingNoticeService._sheetsApi',
        message: 'GoogleAuthSession.safeClient 또는 SheetsApi 생성 실패',
        error: e,
        tags: const <String>[_tParking, _tParkingNotice, _tSheets],
      );
      rethrow;
    }
  }

  static Future<String> _loadSpreadsheetId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getString(kNoticeSpreadsheetIdKey) ?? '').trim();
    } catch (e) {
      await _logApiError(
        tag: 'DoubleParkingNoticeService._loadSpreadsheetId',
        message: 'SharedPreferences에서 SpreadsheetId 로드 실패',
        error: e,
        tags: const <String>[_tParking, _tParkingNotice, _tPrefs],
      );
      return '';
    }
  }

  static Future<String> fetchNoticeMessage({
    required String area,
    required bool forceRefresh,
  }) async {
    final trimmedArea = area.trim();
    final prefs = await SharedPreferences.getInstance();

    final cacheKey = 'double_parking_notice_cache_v2_${trimmedArea.isEmpty ? 'empty' : trimmedArea}';
    final cacheAtKey = 'double_parking_notice_cache_at_v2_${trimmedArea.isEmpty ? 'empty' : trimmedArea}';
    final cacheSidKey = 'double_parking_notice_cache_sid_v2_${trimmedArea.isEmpty ? 'empty' : trimmedArea}';

    final nowMs = DateTime.now().millisecondsSinceEpoch;

    final spreadsheetId = await _loadSpreadsheetId();

    if (spreadsheetId.isEmpty) {
      final fallback = (prefs.getString(cacheKey) ?? '').trim();

      if (fallback.isEmpty) {
        await _logApiError(
          tag: 'DoubleParkingNoticeService.fetchNoticeMessage',
          message: 'SpreadsheetId 미설정(공지 불가) — 캐시도 없음',
          error: StateError('spreadsheet_id_empty'),
          extra: <String, dynamic>{'area': trimmedArea},
          tags: const <String>[_tParking, _tParkingNotice, _tPrefs],
        );
      }

      return fallback;
    }

    if (!forceRefresh) {
      final cached = (prefs.getString(cacheKey) ?? '').trim();
      final cachedAt = prefs.getInt(cacheAtKey) ?? 0;
      final cachedSid = (prefs.getString(cacheSidKey) ?? '').trim();

      final isFresh = cachedAt > 0 && (nowMs - cachedAt) <= cacheTtl.inMilliseconds;
      final isSameSid = cachedSid == spreadsheetId;

      if (cached.isNotEmpty && isFresh && isSameSid) {
        return cached;
      }
    }

    try {
      final api = await _sheetsApi();

      final resp = await api.spreadsheets.values
          .get(spreadsheetId, kNoticeRange)
          .timeout(const Duration(seconds: 6));

      final values = resp.values ?? const <List<Object?>>[];

      final lines = <String>[];
      for (final row in values) {
        final rowStrings = row.map((c) => (c ?? '').toString().trim()).toList();
        final joined = rowStrings.where((s) => s.isNotEmpty).join(' ');
        if (joined.isNotEmpty) lines.add(joined);
      }

      final msg = lines.join('\n').trim();

      if (msg.isNotEmpty) {
        await prefs.setString(cacheKey, msg);
        await prefs.setInt(cacheAtKey, nowMs);
        await prefs.setString(cacheSidKey, spreadsheetId);
        return msg;
      }

      final fallback = (prefs.getString(cacheKey) ?? '').trim();
      if (fallback.isNotEmpty) return fallback;

      await _logApiError(
        tag: 'DoubleParkingNoticeService.fetchNoticeMessage',
        message: '공지 시트가 비어있고 캐시도 없음',
        error: StateError('notice_empty'),
        extra: <String, dynamic>{
          'area': trimmedArea,
          'spreadsheetIdLen': spreadsheetId.length,
          'range': kNoticeRange,
        },
        tags: const <String>[_tParking, _tParkingNotice, _tSheets],
      );

      return '';
    } catch (e) {
      await _logApiError(
        tag: 'DoubleParkingNoticeService.fetchNoticeMessage',
        message: 'Sheets 공지 로드 실패 → 캐시 fallback',
        error: e,
        extra: <String, dynamic>{
          'area': trimmedArea,
          'spreadsheetIdLen': spreadsheetId.length,
          'range': kNoticeRange,
          'forceRefresh': forceRefresh,
        },
        tags: const <String>[_tParking, _tParkingNotice, _tSheets],
      );

      final fallback = (prefs.getString(cacheKey) ?? '').trim();
      return fallback;
    }
  }
}

/// 하단에 표시되는 자동 순환 카드 뷰
class _AutoCyclingReminderCards extends StatefulWidget {
  final String area;

  const _AutoCyclingReminderCards({
    required this.area,
  });

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

  @override
  void initState() {
    super.initState();
    _startAutoCycle();
  }

  @override
  void didUpdateWidget(covariant _AutoCyclingReminderCards oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    if (total <= 1) return;
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
    try {
      _pageController.animateToPage(
        index,
        duration: animDuration,
        curve: animCurve,
      );
      setState(() {});
    } catch (e) {
      _logApiError(
        tag: '_AutoCyclingReminderCards._animateToPage',
        message: '안내 카드 페이지 전환 실패',
        error: e,
        extra: <String, dynamic>{'index': index, 'area': widget.area},
        tags: const <String>[_tParking, _tUi],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cards = parkingRemindersForArea(widget.area);

    return SizedBox(
      height: 170,
      child: Stack(
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
                itemCount: cards.length,
                itemBuilder: (context, index) {
                  final c = cards[index];
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
      final list = DashMemo.notes.value;
      if (list.length <= 1) return;
      final next = (_currentIndex + 1) % list.length;
      _animateToPage(next);
    });
  }

  void _animateToPage(int index) {
    _currentIndex = index;
    if (!mounted) return;

    final total = DashMemo.notes.value.length;
    if (total == 0) return;
    if (_currentIndex >= total) _currentIndex = 0;

    try {
      _pageController.animateToPage(
        _currentIndex,
        duration: animDuration,
        curve: animCurve,
      );
      setState(() {});
    } catch (e) {
      _logApiError(
        tag: '_AutoCyclingMemoCards._animateToPage',
        message: '메모 카드 페이지 전환 실패',
        error: e,
        extra: <String, dynamic>{'index': _currentIndex, 'total': total},
        tags: const <String>[_tParking, _tUi],
      );
    }
  }

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
        valueListenable: DashMemo.notes,
        builder: (context, list, _) {
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
