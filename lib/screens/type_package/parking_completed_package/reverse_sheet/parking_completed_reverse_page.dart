// lib/screens/type_package/parking_completed_package/reverse_sheet/parking_completed_reverse_page.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

// 프로젝트 내부 상태/유틸
import '../../../../enums/plate_type.dart';
import '../../../../states/area/area_state.dart';
import '../../../../utils/snackbar_helper.dart';

/// 역 바텀시트(Top Sheet) 콘텐츠 (글로벌 조회 버전)
/// - 주차 구역(location) 무관: 현재 지역(area)만 필터하고 location 조건은 걸지 않음
/// - parking_completed만, request_time 오름차순(가장 오래된 것부터) 5개씩
/// - 전역 캐시(정적)로 시트 닫았다가 다시 열어도 READ 0으로 즉시 복원
/// - 비용 디버깅 로그: READ/페이지 로드 수를 영역별로 누적 출력
class ParkingCompletedReversePage extends StatefulWidget {
  const ParkingCompletedReversePage({super.key});

  @override
  State<ParkingCompletedReversePage> createState() => _ParkingCompletedReversePageState();
}

class _ParkingCompletedReversePageState extends State<ParkingCompletedReversePage> {
  // ─────────────────────────────────────────────────────────────────────────────
  // 전역(앱 세션 내) 캐시: area 별로 보존 → 시트 재오픈 시 비용 0으로 복원
  // key: area
  static final Map<String, _CacheEntry> _globalCacheByArea = {};

  // 비용 디버깅용 누적 카운터(영역별)
  static final Map<String, int> _totalReadsByArea = {};   // 누적 Read
  static final Map<String, int> _pageLoadsByArea = {};    // 페이지 로드 횟수

  static int _readsOf(String area) => _totalReadsByArea[area] ?? 0;
  static int _loadsOf(String area) => _pageLoadsByArea[area] ?? 0;
  static void _incReads(String area, int n) => _totalReadsByArea[area] = _readsOf(area) + n;
  static void _incLoads(String area) => _pageLoadsByArea[area] = _loadsOf(area) + 1;

  // ─────────────────────────────────────────────────────────────────────────────
  // 상태
  static const int _pageSize = 5; // 5개씩
  bool _loading = false;
  bool _loadingMore = false;

  // 로드된 리스트(보이는 만큼만)
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];
  QueryDocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _hasMore = false;

  // ✅ 권한 동의(업무 마감 목적 확인) 후에만 데이터를 로드한다
  bool _acknowledged = false;

  // ✅ dispose에서 Provider.of를 쓰지 않기 위해, 시트가 열릴 때의 area를 저장
  late final String _areaAtOpen;

  void _setLoading(bool v) => setState(() => _loading = v);
  void _setLoadingMore(bool v) => setState(() => _loadingMore = v);

  // ─────────────────────────────────────────────────────────────────────────────
  // 공통 버튼 스타일: HomeWorkButtonWidget 스타일을 재현
  ButtonStyle _whiteBorderButtonStyle(BuildContext context) {
    return ElevatedButton.styleFrom(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      minimumSize: const Size(0, 55),
      padding: EdgeInsets.zero,
      elevation: 0,
      side: const BorderSide(color: Colors.grey, width: 1.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.1),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 질의

  // 첫 페이지 로드: 전역 캐시 우선, 없으면 READ 1~5
  Future<void> _loadFirstPage() async {
    final area = _areaAtOpen;
    debugPrint('[REV-TOP] loadFirstPage() called | area=$area');

    if (area.isEmpty) {
      showFailedSnackbar(context, '지역이 선택되지 않았습니다.');
      return;
    }

    // 1) 전역 캐시 히트 → READ 0로 즉시 복원
    final hit = _globalCacheByArea[area];
    if (hit != null) {
      setState(() {
        _docs
          ..clear()
          ..addAll(hit.docs);
        _lastDoc = hit.last;
        _hasMore = hit.hasMore;
      });
      debugPrint('[REV-TOP] [CACHE] HIT → READ 0 | area=$area | '
          'totalReads=${_readsOf(area)}, pageLoads=${_loadsOf(area)}, '
          'docs=${_docs.length}, hasMore=$_hasMore');
      return;
    }

    // 2) 캐시 미스 → 첫 페이지 네트워크 1회 (최대 5 read)
    try {
      _setLoading(true);
      debugPrint('[REV-TOP] [QUERY] first page START | area=$area | limit=$_pageSize (expected billed up to ≤$_pageSize reads)');

      final q = FirebaseFirestore.instance
          .collection('plates')
          .where('type', isEqualTo: PlateType.parkingCompleted.firestoreValue)
          .where('area', isEqualTo: area) // 지역만 필터, location 조건 없음
          .orderBy('request_time', descending: false) // 오래된 순
          .limit(_pageSize);

      final snap = await q.get(); // 반환 문서 수만큼 READ
      final docs = snap.docs;

      setState(() {
        _docs
          ..clear()
          ..addAll(docs);
        _lastDoc = docs.isNotEmpty ? docs.last : null;
        _hasMore = docs.length >= _pageSize;
      });

      _incReads(area, docs.length);
      _incLoads(area);
      _saveCache(area);

      debugPrint('[REV-TOP] [COST] READ +${docs.length} (first) | area=$area | '
          'totalReads=${_readsOf(area)}, pageLoads=${_loadsOf(area)}, '
          'docsInCache=${_docs.length}, hasMore=$_hasMore');
    } catch (e) {
      showFailedSnackbar(context, '불러오기 실패: $e');
    } finally {
      _setLoading(false);
    }
  }

  // 다음 5개
  Future<void> _loadMore() async {
    final area = _areaAtOpen;
    if (area.isEmpty || !_hasMore || _lastDoc == null) return;

    try {
      _setLoadingMore(true);

      final q = FirebaseFirestore.instance
          .collection('plates')
          .where('type', isEqualTo: PlateType.parkingCompleted.firestoreValue)
          .where('area', isEqualTo: area)
          .orderBy('request_time', descending: false) // 오래된 순
          .startAfterDocument(_lastDoc!)
          .limit(_pageSize);

      final snap = await q.get(); // 최대 5 read
      final docs = snap.docs;

      setState(() {
        _docs.addAll(docs);
        _lastDoc = docs.isNotEmpty ? docs.last : _lastDoc;
        _hasMore = docs.length >= _pageSize;
      });

      _incReads(area, docs.length);
      _incLoads(area);
      _saveCache(area);

      debugPrint('[REV-TOP] [COST] READ +${docs.length} (more) | area=$area | '
          'totalReads=${_readsOf(area)}, pageLoads=${_loadsOf(area)}, '
          'docsInCache=${_docs.length}, hasMore=$_hasMore');
    } catch (e) {
      showFailedSnackbar(context, '더보기 실패: $e');
    } finally {
      _setLoadingMore(false);
    }
  }

  // 캐시 저장(시트 닫아도 유지)
  void _saveCache(String area) {
    _globalCacheByArea[area] = _CacheEntry(
      docs: List.of(_docs),
      last: _lastDoc,
      hasMore: _hasMore,
    );
  }

  // 캐시 비우고 처음부터 다시(사용자가 갱신 원할 때만)
  Future<void> _refreshForce() async {
    final area = _areaAtOpen;
    if (area.isEmpty) return;

    debugPrint('[REV-TOP] [CACHE] CLEAR by user | area=$area | '
        'prevTotalReads=${_readsOf(area)}, prevPageLoads=${_loadsOf(area)}');

    _globalCacheByArea.remove(area);
    setState(() {
      _docs.clear();
      _lastDoc = null;
      _hasMore = false;
    });
    await _loadFirstPage();
  }

  // 시간 포맷
  String _formatTime(dynamic ts) {
    if (ts is Timestamp) {
      final dt = ts.toDate();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '-';
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 생명주기

  @override
  void initState() {
    super.initState();
    // ✅ dispose에서 context를 쓰지 않기 위해 여기서 한 번만 읽어 보관
    _areaAtOpen = context.read<AreaState>().currentArea.trim();

    // ⚠️ 동의 전에는 데이터를 불러오지 않는다(READ 0)
    // scheduleMicrotask(_loadFirstPage); // 제거
  }

  @override
  void dispose() {
    // ❗ dispose에서는 Provider/BuildContext 조상 탐색 금지
    //    저장해둔 _areaAtOpen으로만 로그 출력
    debugPrint('[REV-TOP] dispose | area=$_areaAtOpen | '
        'totalReads=${_readsOf(_areaAtOpen)}, pageLoads=${_loadsOf(_areaAtOpen)}');
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // UI

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 헤더
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '입차 완료 - 가장 오래된 순으로 5개씩 (구역 무관)',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).maybePop(),
                tooltip: '닫기',
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // 컨트롤 바 (지역명 줄 없음)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: _whiteBorderButtonStyle(context),
                  onPressed: (_loading || !_acknowledged) ? null : () async {
                    HapticFeedback.lightImpact();
                    await _refreshForce();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('새로고침'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: _whiteBorderButtonStyle(context),
                  onPressed: (_loadingMore || !_hasMore || !_acknowledged) ? null : () async {
                    HapticFeedback.lightImpact();
                    await _loadMore();
                  },
                  icon: _loadingMore
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                    ),
                  )
                      : const Icon(Icons.expand_more),
                  label: Text(_hasMore ? '더보기(5)' : '모두 표시됨'),
                ),
              ),
            ],
          ),
        ),

        // 본문 + 경고 오버레이
        Expanded(
          child: Stack(
            children: [
              // 실제 목록
              _buildList(theme),

              // 동의 전 오버레이(콘텐츠 전부 덮기)
              if (!_acknowledged)
                Positioned.fill(
                  child: Container(
                    color: Colors.white, // 완전히 덮음
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.info_outline, size: 36),
                            const SizedBox(height: 12),
                            const Text(
                              '본 페이지는 업무 마감을 위해 남은 입차 완료의 차량 대수를 확인하는 공간입니다.\n'
                                  '업무 마감을 위한 사용 목적인 경우 아래의 \'동의합니다\' 버튼을 누르세요.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 16, height: 1.5),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                style: _whiteBorderButtonStyle(context),
                                onPressed: () async {
                                  HapticFeedback.lightImpact();
                                  setState(() => _acknowledged = true);
                                  await _loadFirstPage(); // 동의 후에만 최초 조회
                                },
                                icon: const Icon(Icons.check_circle_outline),
                                label: const Text('동의합니다'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // 하단(첫 진입에 아무것도 없을 때 불러오기 버튼) — 동의 전에는 비활성
        if (_docs.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: _whiteBorderButtonStyle(context),
                onPressed: (_loading || !_acknowledged) ? null : () async {
                  HapticFeedback.lightImpact();
                  await _loadFirstPage();
                },
                icon: _loading
                    ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                    ))
                    : const Icon(Icons.download),
                label: const Text('불러오기(5개)'),
              ),
            ),
          ),
        if (_docs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: _whiteBorderButtonStyle(context),
                onPressed: (_loadingMore || !_hasMore || !_acknowledged) ? null : () async {
                  HapticFeedback.lightImpact();
                  await _loadMore();
                },
                icon: _loadingMore
                    ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                    ))
                    : const Icon(Icons.expand_more),
                label: Text(_hasMore ? '더보기(5)' : '모두 표시됨'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildList(ThemeData theme) {
    if (_loading && _docs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_docs.isEmpty) {
      return const Center(
        child: Text(
          '표시할 데이터가 없습니다.\n[불러오기(5개)]를 눌러 가장 오래된 항목부터 가져옵니다.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      itemCount: _docs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final data = _docs[i].data();
        final plate = (data['plate_number'] ?? '').toString();
        final time = _formatTime(data['request_time']);
        final car = (data['car_model'] ?? '').toString();
        final color = (data['color'] ?? '').toString();
        final location = (data['location'] ?? '').toString();

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceVariant.withOpacity(.25),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.directions_car, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 번호판
                    Text(plate, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    // 부가정보
                    Text(
                      [
                        if (car.isNotEmpty) car,
                        if (color.isNotEmpty) color,
                        if (location.isNotEmpty) 'loc:$location',
                      ].join(' • '),
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 시간(오래된 순)
              Text(time, style: theme.textTheme.bodySmall),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 캐시 엔트리(전역)
class _CacheEntry {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final QueryDocumentSnapshot<Map<String, dynamic>>? last;
  final bool hasMore;

  _CacheEntry({
    required this.docs,
    required this.last,
    required this.hasMore,
  });
}
