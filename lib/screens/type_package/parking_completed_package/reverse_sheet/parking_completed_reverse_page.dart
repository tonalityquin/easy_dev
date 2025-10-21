// lib/screens/type_package/parking_completed_package/reverse_sheet/parking_completed_reverse_page.dart
import 'dart:async';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 프로젝트 내부 상태/유틸
import '../../../../enums/plate_type.dart';
import '../../../../states/area/area_state.dart';
import '../../../../states/location/location_state.dart';
import '../../../../utils/snackbar_helper.dart';

/// 역 바텀시트(Top Sheet) 콘텐츠
/// - 기본: 주차 구역(location) **무관**(현재 지역만)
/// - 옵션: **특정 주차 구역 제외**
/// - parking_completed만, request_time 오름차순(오래된 순) 5개씩 페이지네이션
/// - 전역 캐시(정적)로 시트 닫았다가 다시 열어도 READ 0으로 복원
/// - 캐시 키: <area>|ALL  또는  <area>|EX|leaf1,leaf2,...
class ParkingCompletedReversePage extends StatefulWidget {
  const ParkingCompletedReversePage({super.key});

  @override
  State<ParkingCompletedReversePage> createState() => _ParkingCompletedReversePageState();
}

class _ParkingCompletedReversePageState extends State<ParkingCompletedReversePage> {
  // ─────────────────────────────────────────────────────────────────────────────
  // Brand palette (최소 사용)
  static const Color _base = Color(0xFF0D47A1);
  static const Color _dark = Color(0xFF09367D);
  static const Color _light = Color(0xFF5472D3);

  // ─────────────────────────────────────────────────────────────────────────────
  // 전역(앱 세션 내) 캐시
  static final Map<String, _CacheEntry> _globalCacheByKey = {};
  static final Map<String, int> _totalReadsByKey = {}; // 누적 Read
  static final Map<String, int> _pageLoadsByKey = {}; // 페이지 로드 횟수

  static int _readsOf(String key) => _totalReadsByKey[key] ?? 0;
  static int _loadsOf(String key) => _pageLoadsByKey[key] ?? 0;
  static void _incReads(String key, int n) => _totalReadsByKey[key] = _readsOf(key) + n;
  static void _incLoads(String key) => _pageLoadsByKey[key] = _loadsOf(key) + 1;

  // ─────────────────────────────────────────────────────────────────────────────
  // 상태
  static const int _pageSize = 5;
  static const Duration _kRefreshCooldown = Duration(hours: 12); // 12시간 쿨다운

  bool _loading = false;
  bool _loadingMore = false;

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];
  QueryDocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _hasMore = false;

  // 권한 동의(업무 마감 목적 확인) 후에만 데이터를 로드한다
  bool _acknowledged = false;

  // 시트 오픈 시의 area (dispose에서 context 접근 금지)
  late final String _areaAtOpen;

  // 필터 상태(※ 제외만 지원)
  final Set<String> _selectedDisplayNames = <String>{}; // 제외할 표시명 세트(다중 선택)
  // Firestore whereNotIn 제한(최대 10)
  static const int _kWhereNotInLimit = 10;

  // ── '작업 완료' 로컬 상태 (문서 id 기준)
  final Set<String> _doneIds = <String>{};
  final Set<String> _overlayOpenIds = <String>{};
  static const Color _doneBg = Color(0xFFE8F5E9); // 연한 초록(완료 표시 유지)
  String get _donePrefsKey => 'rev_top_done_ids_${_areaAtOpen}';

  // ── 새로고침 쿨다운(UI는 지역 단위로 표기/적용)
  Duration _refreshRemain = Duration.zero;
  Timer? _cooldownTimer;

  // ─────────────────────────────────────────────────────────────────────────────
  void _setLoading(bool v) => setState(() => _loading = v);
  void _setLoadingMore(bool v) => setState(() => _loadingMore = v);

  // 표시명 → 질의용 leaf locationName
  String _extractLeaf(String displayName) {
    const sep = ' - ';
    final trimmed = displayName.trim();
    if (trimmed.contains(sep)) {
      final parts = trimmed.split(sep);
      return parts.sublist(1).join(sep).trim();
    }
    return trimmed;
  }

  // LocationModel → 표시명
  String _displayOf({
    required String name,
    required String? parent,
    required String? type,
  }) {
    if ((type ?? '').trim() == 'composite' && (parent ?? '').trim().isNotEmpty) {
      return '${parent!.trim()} - ${name.trim()}';
    }
    return name.trim();
  }

  // 현재 지역의 “실제 구역 개수”(전체(구역 무관) 제외)
  int _effectiveLocationCount() {
    final locationState = context.read<LocationState>();
    final set = locationState.locations
        .map((l) => _displayOf(name: l.locationName, parent: l.parent, type: l.type))
        .toSet();
    return set.length;
  }

  // 캐시 키
  String _cacheKeyFor({Set<String>? displayNames}) {
    final names = displayNames ?? _selectedDisplayNames;
    if (names.isEmpty) return '${_areaAtOpen}|ALL';
    final sortedLeaves = names.map(_extractLeaf).toList()..sort();
    return '${_areaAtOpen}|EX|${sortedLeaves.join(',')}';
  }

  String _cacheKey() => _cacheKeyFor();

  // ─────────────────────────────────────────────────────────────────────────────
  // SharedPreferences (필터/완료 상태 저장/복원)
  Future<void> _loadSavedFilter() async {
    final prefs = await SharedPreferences.getInstance();

    // 제외 목록(표시명들)
    final list = prefs.getStringList('rev_top_selected_locations_${_areaAtOpen}') ?? const <String>[];
    _selectedDisplayNames
      ..clear()
      ..addAll(list.where((e) => e.trim().isNotEmpty));

    // 구버전 호환(단일 선택 문자열)
    final legacy = prefs.getString('rev_top_selected_location_${_areaAtOpen}');
    if (legacy != null && legacy.trim().isNotEmpty && _selectedDisplayNames.isEmpty) {
      _selectedDisplayNames.add(legacy.trim());
    }

    setState(() {}); // UI 갱신
  }

  Future<void> _saveFilter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('rev_top_selected_locations_${_areaAtOpen}', _selectedDisplayNames.toList());
  }

  Future<void> _loadDoneForArea() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_donePrefsKey) ?? const <String>[];
    setState(() {
      _doneIds
        ..clear()
        ..addAll(list);
    });
    debugPrint('[REV-TOP][DONE] loaded ${_doneIds.length} items for area=$_areaAtOpen');
  }

  Future<void> _saveDoneForArea() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_donePrefsKey, _doneIds.toList());
    debugPrint('[REV-TOP][DONE] saved ${_doneIds.length} items for area=$_areaAtOpen');
  }

  // ── 새로고침 스로틀링(지역 단위)
  String get _refreshAreaPrefsKey => 'rev_top_last_refresh_area_${_areaAtOpen}';

  Future<Duration> _remainingRefreshCooldownArea() async {
    final prefs = await SharedPreferences.getInstance();
    final lastMs = prefs.getInt(_refreshAreaPrefsKey);
    if (lastMs == null) return Duration.zero;
    final last = DateTime.fromMillisecondsSinceEpoch(lastMs);
    final now = DateTime.now();
    final remain = _kRefreshCooldown - now.difference(last);
    return remain.isNegative ? Duration.zero : remain;
  }

  Future<void> _markRefreshedNowArea() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_refreshAreaPrefsKey, DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> _updateRefreshCooldownLabel() async {
    final remain = await _remainingRefreshCooldownArea(); // 지역 단위
    if (!mounted) return;
    setState(() => _refreshRemain = remain);

    _cooldownTimer?.cancel();
    if (remain > Duration.zero) {
      _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
        final r = await _remainingRefreshCooldownArea();
        if (!mounted) {
          t.cancel();
          return;
        }
        setState(() => _refreshRemain = r);
        if (r == Duration.zero) t.cancel();
      });
    }
  }

  String _formatRemain(Duration d) {
    final totalSeconds = d.inSeconds;
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) return '${h}시간 ${m}분';
    if (m > 0) return '${m}분 ${s}초';
    return '${s}초';
  }

  // ─────────────────────────────────────────────────────────────────────────────
  void _toggleOverlay(String id, {bool? open}) {
    setState(() {
      if (open == true) {
        _overlayOpenIds.add(id);
      } else if (open == false) {
        _overlayOpenIds.remove(id);
      } else {
        if (_overlayOpenIds.contains(id)) {
          _overlayOpenIds.remove(id);
        } else {
          _overlayOpenIds.add(id);
        }
      }
    });
  }

  Future<void> _markDone(String id) async {
    HapticFeedback.lightImpact();
    setState(() {
      _doneIds.add(id);
      _overlayOpenIds.remove(id);
    });
    await _saveDoneForArea();
    debugPrint('[REV-TOP][DONE] marked as done → $id');
  }

  Future<void> _unmarkDone(String id) async {
    HapticFeedback.lightImpact();
    setState(() {
      _doneIds.remove(id);
      _overlayOpenIds.remove(id);
    });
    await _saveDoneForArea();
    debugPrint('[REV-TOP][DONE] unmarked (cancel) → $id');
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 캐시 하이드레이션(READ 0)
  void _applyCache(String key) {
    final hit = _globalCacheByKey[key];
    if (hit == null) return;
    setState(() {
      _docs
        ..clear()
        ..addAll(hit.docs);
      _lastDoc = hit.last;
      _hasMore = hit.hasMore;
    });
    debugPrint('[REV-TOP] [CACHE] APPLY → READ 0 | key=$key | '
        'totalReads=${_readsOf(key)}, pageLoads=${_loadsOf(key)}, '
        'docs=${_docs.length}, hasMore=$_hasMore');
  }

  // ALL 캐시로부터 현재 필터 결과의 1페이지를 파생(READ 0)
  bool _applyDerivedFromAllCache() {
    final allKey = '${_areaAtOpen}|ALL';
    final allCache = _globalCacheByKey[allKey];
    if (allCache == null) return false;

    final leaves = _selectedDisplayNames.map(_extractLeaf).toSet();
    bool matches(Map<String, dynamic> data) {
      final loc = (data['location'] ?? '').toString();
      if (leaves.isEmpty) return true; // ALL
      // 제외만 지원
      return !leaves.contains(loc);
    }

    final filtered = allCache.docs.where((d) => matches(d.data())).toList();

    // 파생 1페이지
    final page = filtered.take(_pageSize).toList();
    final hasMoreFromAll = allCache.hasMore || filtered.length > _pageSize; // 더 있을 가능성

    setState(() {
      _docs
        ..clear()
        ..addAll(page);
      _lastDoc = page.isNotEmpty ? page.last : null;
      _hasMore = hasMoreFromAll;
    });

    // 파생된 결과도 캐시에 저장(READ 0)
    final derivedKey = _cacheKey();
    _globalCacheByKey[derivedKey] = _CacheEntry(
      docs: List.of(_docs),
      last: _lastDoc,
      hasMore: _hasMore,
    );

    debugPrint('[REV-TOP] [CACHE] DERIVE from ALL → READ 0 | from=$allKey → to=$derivedKey | '
        'docs=${_docs.length}, hasMore=$_hasMore');
    return true;
  }

  // 필터 전환: 캐시→파생→쿨다운 시 네트워크 차단→쿨다운 끝나면 허용
  Future<void> _switchFilterWithSet({required Set<String> displayNames}) async {
    _selectedDisplayNames
      ..clear()
      ..addAll(displayNames.where((e) => e.trim().isNotEmpty));
    await _saveFilter();

    await _updateRefreshCooldownLabel(); // 지역 단위 라벨 갱신

    final newKey = _cacheKey();

    if (_globalCacheByKey.containsKey(newKey)) {
      _applyCache(newKey); // READ 0
      return;
    }

    if (_applyDerivedFromAllCache()) {
      return;
    }

    final remain = await _remainingRefreshCooldownArea();
    if (remain > Duration.zero) {
      showFailedSnackbar(context, '쿨다운 중에는 새로운 제외 설정으로 서버 조회가 제한됩니다. 남은 시간: ${_formatRemain(remain)}');
      debugPrint('[REV-TOP] [THROTTLE] filter-switch blocked (area) | remain=${remain.inMinutes}m');
      return;
    }

    setState(() {
      _docs.clear();
      _lastDoc = null;
      _hasMore = false;
    });
    await _loadFirstPage();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 질의

  Future<void> _loadFirstPage() async {
    final area = _areaAtOpen;
    final key = _cacheKey();
    debugPrint('[REV-TOP] loadFirstPage() | key=$key');

    if (area.isEmpty) {
      showFailedSnackbar(context, '지역이 선택되지 않았습니다.');
      return;
    }

    // 최소 1개 제외(실제 구역이 2개 이상일 때)
    final effectiveCount = _effectiveLocationCount();
    if (effectiveCount >= 2 && _selectedDisplayNames.isEmpty) {
      showFailedSnackbar(context, '확인하지 않을 주차 구역을 최소 1개 선택해 주세요.');
      return;
    }

    final hit = _globalCacheByKey[key];
    if (hit != null) {
      _applyCache(key);
      return;
    }

    try {
      _setLoading(true);
      debugPrint('[REV-TOP] [QUERY] first page START | key=$key | limit=$_pageSize');

      final leaves = _selectedDisplayNames.map(_extractLeaf).toList();

      Query<Map<String, dynamic>> q = FirebaseFirestore.instance
          .collection('plates')
          .where('type', isEqualTo: PlateType.parkingCompleted.firestoreValue)
          .where('area', isEqualTo: area);

      if (effectiveCount >= 2 && leaves.isNotEmpty) {
        if (leaves.length <= _kWhereNotInLimit) {
          q = q.where('location', whereNotIn: leaves);
        } else {
          showFailedSnackbar(context, '제외 모드는 최대 $_kWhereNotInLimit개까지 선택할 수 있습니다.');
          return;
        }
      }

      q = q.orderBy('request_time', descending: false).limit(_pageSize);

      final snap = await q.get();
      final docs = snap.docs;

      setState(() {
        _docs
          ..clear()
          ..addAll(docs);
        _lastDoc = docs.isNotEmpty ? docs.last : null;
        _hasMore = docs.length >= _pageSize;
      });

      _incReads(key, docs.length);
      _incLoads(key);
      _saveCache(key);

      debugPrint('[REV-TOP] [COST] READ +${docs.length} (first) | key=$key | '
          'totalReads=${_readsOf(key)}, pageLoads=${_loadsOf(key)}, '
          'docsInCache=${_docs.length}, hasMore=$_hasMore');
    } catch (e) {
      showFailedSnackbar(context, '불러오기 실패: $e');
      debugPrint('[REV-TOP] [ERROR] first: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _loadMore() async {
    final area = _areaAtOpen;
    final key = _cacheKey();
    if (area.isEmpty || !_hasMore || _lastDoc == null) return;

    try {
      _setLoadingMore(true);

      final leaves = _selectedDisplayNames.map(_extractLeaf).toList();
      final effectiveCount = _effectiveLocationCount();

      Query<Map<String, dynamic>> q = FirebaseFirestore.instance
          .collection('plates')
          .where('type', isEqualTo: PlateType.parkingCompleted.firestoreValue)
          .where('area', isEqualTo: area);

      if (effectiveCount >= 2 && leaves.isNotEmpty) {
        q = q.where('location', whereNotIn: leaves);
      }

      final lastTs = _lastDoc!.data()['request_time'];
      if (lastTs == null) {
        debugPrint('[REV-TOP] [WARN] lastDoc.request_time == null → 더보기 중단');
        _setLoadingMore(false);
        return;
      }

      q = q.orderBy('request_time', descending: false).startAfter([lastTs]).limit(_pageSize);

      final snap = await q.get();
      final docs = snap.docs;

      setState(() {
        _docs.addAll(docs);
        _lastDoc = docs.isNotEmpty ? docs.last : _lastDoc;
        _hasMore = docs.length >= _pageSize;
      });

      _incReads(key, docs.length);
      _incLoads(key);
      _saveCache(key);

      debugPrint('[REV-TOP] [COST] READ +${docs.length} (more) | key=$key | '
          'totalReads=${_readsOf(key)}, pageLoads=${_loadsOf(key)}, '
          'docsInCache=${_docs.length}, hasMore=$_hasMore');
    } catch (e) {
      showFailedSnackbar(context, '더보기 실패: $e');
      debugPrint('[REV-TOP] [ERROR] more: $e');
    } finally {
      _setLoadingMore(false);
    }
  }

  void _saveCache(String key) {
    _globalCacheByKey[key] = _CacheEntry(
      docs: List.of(_docs),
      last: _lastDoc,
      hasMore: _hasMore,
    );
  }

  // 현재 지역의 쿨다운을 적용하여 캐시만 비우고 처음부터
  Future<void> _refreshForce() async {
    final remain = await _remainingRefreshCooldownArea(); // 지역 단위 검사
    if (remain > Duration.zero) {
      final msg = '새로고침은 12시간에 1회만 가능합니다. 남은 시간: ${_formatRemain(remain)}';
      showFailedSnackbar(context, msg);
      debugPrint('[REV-TOP] [THROTTLE] refresh denied (area) | remain=${remain.inMinutes}m');
      await _updateRefreshCooldownLabel();
      return;
    }

    await _markRefreshedNowArea();
    await _updateRefreshCooldownLabel();

    final key = _cacheKey();
    debugPrint('[REV-TOP] [CACHE] CLEAR by user | key=$key | '
        'prevTotalReads=${_readsOf(key)}, prevPageLoads=${_loadsOf(key)}');

    _globalCacheByKey.remove(key);
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
    _areaAtOpen = context.read<AreaState>().currentArea.trim();
    scheduleMicrotask(() async {
      await _loadSavedFilter();
      await _loadDoneForArea();
      await _updateRefreshCooldownLabel(); // 초기 라벨/상태 계산(지역 단위)
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    final key = _cacheKey();
    debugPrint('[REV-TOP] dispose | key=$key | '
        'totalReads=${_readsOf(key)}, pageLoads=${_loadsOf(key)}');
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // UI

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 구역 목록은 LocationState의 캐시(SharedPreferences)에서만 읽는다.
    final locationState = context.watch<LocationState>();
    final locations = locationState.locations;

    // 표시명 목록
    final List<String> displayNames = [
      '전체(구역 무관)',
      ...locations.map((l) => _displayOf(name: l.locationName, parent: l.parent, type: l.type)).toSet().toList()
        ..sort((a, b) => a.compareTo(b)),
    ];
    final effectiveCount = displayNames.length - 1; // '전체' 제외

    final bool inCooldown = _refreshRemain > Duration.zero;

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
                  '입차 완료 - 오래된 순 (${_selectedDisplayNames.isEmpty ? (effectiveCount >= 2 ? "제외 미설정" : "구역 1개") : "제외 선택"})',
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

        // 컨트롤 바 1: 제외 구역 선택(바텀시트)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: _whiteBorderButtonStyle(context),
                  onPressed: (!_acknowledged || _loading || _loadingMore)
                      ? null
                      : () async {
                    HapticFeedback.selectionClick();
                    await _openLocationPickerBottomSheet(context, displayNames);
                  },
                  icon: const Icon(Icons.tune),
                  label: const Text('확인하지 않을 주차 구역'),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: '제외 목록은 다른 화면의 수동 새로고침으로 캐시에 저장된 구역 기준입니다.',
                child: const Icon(Icons.info_outline, size: 20),
              ),
            ],
          ),
        ),

        // 컨트롤 바 2: 데이터 새로고침/더보기
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              // 새로고침/업무 종료
              Expanded(
                child: ElevatedButton.icon(
                  style: _whiteBorderButtonStyle(context),
                  onPressed: (_loading || !_acknowledged || inCooldown)
                      ? null
                      : () async {
                    HapticFeedback.lightImpact();
                    await _refreshForce();
                  },
                  icon: const Icon(Icons.refresh),
                  label: Text(inCooldown ? '업무 종료' : '새로고침'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: _whiteBorderButtonStyle(context),
                  onPressed: (_loadingMore || !_hasMore || !_acknowledged)
                      ? null
                      : () async {
                    HapticFeedback.lightImpact();
                    await _loadMore();
                  },
                  icon: _loadingMore
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(_base), // brand color
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
              _buildList(theme),
              if (!_acknowledged)
                Positioned.fill(
                  child: Container(
                    color: Colors.white,
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
                              '본 페이지는 업무 마감을 위해 남은 입차 완료 차량을 확인하는 공간입니다.\n'
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
                                  await _loadFirstPage();
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

        // 하단(첫 진입에 아무것도 없을 때 불러오기 버튼)
        if (_docs.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: _whiteBorderButtonStyle(context),
                onPressed: (_loading || !_acknowledged)
                    ? null
                    : () async {
                  HapticFeedback.lightImpact();
                  await _loadFirstPage();
                },
                icon: _loading
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(_base), // brand color
                  ),
                )
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
                onPressed: (_loadingMore || !_hasMore || !_acknowledged)
                    ? null
                    : () async {
                  HapticFeedback.lightImpact();
                  await _loadMore();
                },
                icon: _loadingMore
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(_base), // brand color
                  ),
                )
                    : const Icon(Icons.expand_more),
                label: Text(_hasMore ? '더보기(5)' : '모두 표시됨'),
              ),
            ),
          ),
      ],
    );
  }

  // 하단 바텀시트: 주차 구역 **제외** 다중 선택(최소 1개 강제, 단 구역이 1개면 제외 미적용)
  Future<void> _openLocationPickerBottomSheet(BuildContext context, List<String> displayNames) async {
    final effectiveCount = displayNames.length - 1; // '전체(구역 무관)' 제외

    final result = await showModalBottomSheet<_FilterResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final controller = TextEditingController();
        final ValueNotifier<List<String>> listNotifier = ValueNotifier<List<String>>(displayNames);
        final ValueNotifier<Set<String>> selectedN = ValueNotifier<Set<String>>(Set.of(_selectedDisplayNames));

        void applyFilter(String q) {
          final query = q.trim();
          if (query.isEmpty) {
            listNotifier.value = List<String>.from(displayNames);
          } else {
            listNotifier.value = displayNames.where((e) => e.toLowerCase().contains(query.toLowerCase())).toList();
          }
        }

        void toggleSelect(String name) {
          if (name == '전체(구역 무관)') {
            if (effectiveCount >= 2) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('최소 1개 이상 제외해야 합니다.')),
              );
              return;
            }
            selectedN.value = <String>{};
            return;
          }
          final set = Set<String>.from(selectedN.value);
          if (set.contains(name)) {
            if (effectiveCount >= 2 && set.length == 1) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('최소 1개 이상 제외해야 합니다.')),
              );
              return;
            }
            set.remove(name);
          } else {
            final nextCount = set.length + 1;
            if (nextCount > _kWhereNotInLimit) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text('제외 모드는 최대 $_kWhereNotInLimit개까지 선택 가능합니다.')),
              );
              return;
            }
            set.add(name);
          }
          selectedN.value = set;
        }

        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(ctx).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),

              // 헤더
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('확인하지 않을 주차 구역 선택', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // 검색
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  controller: controller,
                  onChanged: applyFilter,
                  decoration: InputDecoration(
                    hintText: '구역명 검색',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    isDense: true,
                  ),
                ),
              ),

              // 리스트
              Flexible(
                child: ValueListenableBuilder<List<String>>(
                  valueListenable: listNotifier,
                  builder: (context, items, _) {
                    return ValueListenableBuilder<Set<String>>(
                      valueListenable: selectedN,
                      builder: (context, selectedSet, __) {
                        return ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final name = items[i];
                            final isAll = name == '전체(구역 무관)';
                            final selected = isAll ? selectedSet.isEmpty : selectedSet.contains(name);
                            return ListTile(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              tileColor: selected ? _light.withOpacity(.12) : null, // brand tint (최소 사용)
                              leading: Icon(isAll ? Icons.all_inclusive : Icons.place_outlined),
                              title: Text(name, overflow: TextOverflow.ellipsis),
                              trailing: selected ? const Icon(Icons.check, size: 20) : null,
                              onTap: () => toggleSelect(name),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),

              // 하단 액션
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          controller.clear();
                          applyFilter('');
                          if (effectiveCount >= 2) {
                            final firstReal = displayNames.firstWhere((e) => e != '전체(구역 무관)', orElse: () => '');
                            selectedN.value = firstReal.isEmpty ? <String>{} : <String>{firstReal};
                          } else {
                            selectedN.value = <String>{};
                          }
                        },
                        icon: const Icon(Icons.restore),
                        label: const Text('초기화'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          side: BorderSide(color: _light), // brand outline
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ValueListenableBuilder<Set<String>>(
                        valueListenable: selectedN,
                        builder: (_, s, __) {
                          final disabled = (effectiveCount >= 2 && s.isEmpty);
                          return ElevatedButton.icon(
                            onPressed: disabled
                                ? null
                                : () {
                              final resolved = (effectiveCount >= 2) ? s : <String>{};
                              Navigator.of(ctx).pop(_FilterResult(selected: resolved));
                            },
                            icon: const Icon(Icons.check),
                            label: Text('적용 (${s.isEmpty ? (effectiveCount >= 2 ? "최소 1개" : "제외 없음") : "${s.length}개"})'),
                            style: _whiteBorderButtonStyle(context),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );

    if (result == null) return;

    await _switchFilterWithSet(displayNames: result.selected);
  }

  ButtonStyle _whiteBorderButtonStyle(BuildContext context) {
    // 최소한의 브랜드 컬러만 적용: 테두리/_fg/disabled
    return ElevatedButton.styleFrom(
      backgroundColor: Colors.white,
      foregroundColor: _dark, // 글자/아이콘
      disabledBackgroundColor: _light.withOpacity(.08),
      disabledForegroundColor: _dark.withOpacity(.45),
      minimumSize: const Size(0, 55),
      padding: EdgeInsets.zero,
      elevation: 0,
      side: BorderSide(color: _light, width: 1.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.1),
    );
  }

  Widget _buildList(ThemeData theme) {
    if (_loading && _docs.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation<Color>(_base), // brand color
          ),
        ),
      );
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
        final snap = _docs[i];
        final id = snap.id;
        final data = snap.data();
        final plate = (data['plate_number'] ?? '').toString();
        final time = _formatTime(data['request_time']);
        final car = (data['car_model'] ?? '').toString();
        final color = (data['color'] ?? '').toString();
        final location = (data['location'] ?? '').toString();

        final bool isDone = _doneIds.contains(id);
        final bool overlayOpen = _overlayOpenIds.contains(id);

        return GestureDetector(
          onTap: () {
            if (isDone) {
              _unmarkDone(id);
            } else {
              _toggleOverlay(id);
            }
          },
          onLongPress: () {
            if (isDone) {
              _unmarkDone(id);
            } else {
              _toggleOverlay(id);
            }
          },
          child: Stack(
            children: [
              // 카드(완료면 연초록 배경 유지)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDone ? _doneBg : theme.colorScheme.surfaceVariant.withOpacity(.25),
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
                          Text(
                            plate,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
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
                    Text(time, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),

              // 반투명 오버레이 + '작업 완료' (미완료 + 오버레이 열린 경우에만)
              if (!isDone && overlayOpen)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Align(
                      alignment: Alignment.center,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _toggleOverlay(id, open: false),
                              icon: const Icon(Icons.close),
                              label: const Text('닫기'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 44),
                                side: BorderSide(color: _light), // brand outline
                              ),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              onPressed: () => _markDone(id),
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text('작업 완료'),
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size(0, 44),
                                backgroundColor: _base, // brand primary (버튼만 적용)
                                foregroundColor: Colors.white,
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
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 보조 타입/위젯

class _FilterResult {
  final Set<String> selected;
  _FilterResult({required this.selected});
}

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
