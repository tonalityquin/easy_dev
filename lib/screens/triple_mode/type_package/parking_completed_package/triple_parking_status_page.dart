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

import '../../../common_package/memo_package/dash_memo.dart';
import '../../../hubs_mode/dev_package/debug_package/debug_api_logger.dart';

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

class TripleParkingStatusPage extends StatefulWidget {
  const TripleParkingStatusPage({super.key});

  @override
  State<TripleParkingStatusPage> createState() => _TripleParkingStatusPageState();
}

class _TripleParkingStatusPageState extends State<TripleParkingStatusPage> {
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeRunCount();
      _maybeRunNotice();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeRunCount();
      _maybeRunNotice();
    });
  }

  void _maybeRunCount() {
    if (_didCountRun) return;
    final route = ModalRoute.of(context);
    final isVisible = route == null ? true : (route.isCurrent || route.isActive);
    if (!isVisible) return;
    _didCountRun = true;
    _runAggregateCount();
  }

  void _maybeRunNotice() {
    if (_didNoticeRun) return;
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
    _lastArea = area;

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

      if (!mounted) return;
      setState(() {
        _occupiedCount = cnt;
        _isCountLoading = false;
        _hadError = false;
      });
    } catch (e) {
      await _logApiError(
        tag: 'TripleParkingStatusPage._runAggregateCount',
        message: 'Firestore aggregate count 실패(parking_completed)',
        error: e,
        extra: <String, dynamic>{
          'division': division,
          'area': area,
          'collection': 'plates',
          'type': 'parking_completed',
        },
        tags: const <String>[
          _tParking,
          _tParkingStatus,
          _tFirestore,
          _tFirestoreAgg,
        ],
      );

      if (!mounted) return;
      setState(() {
        _occupiedCount = 0;
        _isCountLoading = false;
        _hadError = true;
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
      final result = await TripleParkingNoticeService.fetchNoticeMessage(
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
        tag: 'TripleParkingStatusPage._runNoticeFetch',
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

    final currentArea =
    context.select<AreaState, String>((s) => s.currentArea.trim());

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
      // ✅ 전역 ThemeData(scaffoldBackgroundColor) 사용
      body: Consumer<LocationState>(
        builder: (context, locationState, _) {
          final cs = Theme.of(context).colorScheme;

          if (locationState.isLoading || _isCountLoading) {
            return Center(
              child: CircularProgressIndicator(color: cs.primary),
            );
          }

          final totalCapacity =
          locationState.locations.fold<int>(0, (sum, l) => sum + l.capacity);
          final occupiedCount = _occupiedCount;

          final double usageRatio =
          totalCapacity == 0 ? 0 : occupiedCount / totalCapacity;
          final String usagePercent = (usageRatio * 100).toStringAsFixed(1);

          if (_hadError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber, size: 40, color: cs.error),
                    const SizedBox(height: 12),
                    Text(
                      '현황 집계 중 오류가 발생했습니다.',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '영역: $currentArea',
                      style: TextStyle(color: cs.onSurfaceVariant),
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
              _TripleParkingNoticeBar(
                isLoading: _isNoticeLoading,
                message: _noticeMessage,
                onRefresh: () {
                  _didNoticeRun = false;
                  _runNoticeFetch(forceRefresh: true);
                },
              ),
              if (_noticeMessage.trim().isNotEmpty || _isNoticeLoading)
                const SizedBox(height: 12),

              // ✅ (변경) const 제거 + color 명시
              Text(
                '📊 현재 노말 주차 현황',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 12),

              // ✅ (변경) color 명시
              Text(
                '총 $totalCapacity대 중 $occupiedCount대 주차됨',
                style: TextStyle(fontSize: 16, color: cs.onSurface),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: usageRatio,
                backgroundColor: cs.outlineVariant.withOpacity(0.6),
                valueColor: AlwaysStoppedAnimation<Color>(
                  usageRatio >= 0.8 ? cs.error : cs.primary,
                ),
                minHeight: 8,
              ),
              const SizedBox(height: 12),

              // ✅ (변경) color 명시
              Text(
                '$usagePercent% 사용 중',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
                textAlign: TextAlign.center,
              ),

              // ------ 상단 영역 끝 ------
              const SizedBox(height: 24),
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

/// ✅ 상단 알림바(관리자 공지) - 브랜드(ColorScheme) 기반
class _TripleParkingNoticeBar extends StatelessWidget {
  final bool isLoading;
  final String message;
  final VoidCallback onRefresh;

  const _TripleParkingNoticeBar({
    required this.isLoading,
    required this.message,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

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
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: isLoading
                  ? Text(
                '공지 불러오는 중...',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              )
                  : Text(
                text,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: onRefresh,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.refresh, size: 18, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ✅ Google Sheets API 기반 공지 서비스 (Triple)
class TripleParkingNoticeService {
  TripleParkingNoticeService._();

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
        tag: 'TripleParkingNoticeService._sheetsApi',
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
        tag: 'TripleParkingNoticeService._loadSpreadsheetId',
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

    final cacheKey =
        'triple_parking_notice_cache_v2_${trimmedArea.isEmpty ? 'empty' : trimmedArea}';
    final cacheAtKey =
        'triple_parking_notice_cache_at_v2_${trimmedArea.isEmpty ? 'empty' : trimmedArea}';
    final cacheSidKey =
        'triple_parking_notice_cache_sid_v2_${trimmedArea.isEmpty ? 'empty' : trimmedArea}';

    final nowMs = DateTime.now().millisecondsSinceEpoch;

    final spreadsheetId = await _loadSpreadsheetId();

    if (spreadsheetId.isEmpty) {
      final fallback = (prefs.getString(cacheKey) ?? '').trim();

      if (fallback.isEmpty) {
        await _logApiError(
          tag: 'TripleParkingNoticeService.fetchNoticeMessage',
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

      final isFresh =
          cachedAt > 0 && (nowMs - cachedAt) <= cacheTtl.inMilliseconds;
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
        tag: 'TripleParkingNoticeService.fetchNoticeMessage',
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
        tag: 'TripleParkingNoticeService.fetchNoticeMessage',
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
    final cs = Theme.of(context).colorScheme;

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
                            color: cs.surface,
                            surfaceTintColor: Colors.transparent,
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: cs.outlineVariant.withOpacity(0.55),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 16,
                                horizontal: 16,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.notes_rounded,
                                        size: 18,
                                        color: cs.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '메모',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: cs.onSurface,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    '저장된 메모가 없습니다.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: cs.onSurfaceVariant,
                                    ),
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
                          color: cs.surface,
                          surfaceTintColor: Colors.transparent,
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: cs.outlineVariant.withOpacity(0.55),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 16,
                              horizontal: 16,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.notes_rounded,
                                      size: 18,
                                      color: cs.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '메모',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: cs.onSurface,
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
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: cs.onSurface,
                                      ),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                if (time.isNotEmpty)
                                  Text(
                                    time,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: cs.onSurfaceVariant,
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
                  children: List.generate(list.isEmpty ? 1 : list.length, (i) {
                    final active = i == _currentIndex && list.isNotEmpty;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: active ? 10 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: active
                            ? cs.onSurface
                            : cs.onSurfaceVariant.withOpacity(0.35),
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
