import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Field extends StatefulWidget {
  const Field({
    super.key,
    this.asBottomSheet = false,
  });

  /// true면 AppBar 없는 **전체 화면 바텀시트 UI**로 렌더링
  final bool asBottomSheet;

  /// 전체 화면 바텀시트(92%)로 열기
  static Future<T?> showAsBottomSheet<T>(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: cs.scrim.withOpacity(0.45), // ✅ 브랜드 테마 scrim 사용
      builder: (sheetCtx) {
        final insets = MediaQuery.of(sheetCtx).viewInsets;
        return Padding(
          padding: EdgeInsets.only(bottom: insets.bottom),
          child: const _NinetyTwoPercentBottomSheetFrame(
            child: Field(asBottomSheet: true),
          ),
        );
      },
    );
  }

  @override
  State<Field> createState() => _FieldState();
}

class _FieldState extends State<Field> {
  static const String _kDivisionPrefsKey = 'division';

  // ✅ division별 문서 캐시 저장 키(prefix)
  static const String _kDocCachePrefix = 'commute_true_false_cache_v1:';

  String? _division;
  Object? _loadError;

  // ✅ 새로고침(서버 fetch) 중 표시
  bool _docLoading = false;
  Object? _docError;

  /// area -> workerName -> Timestamp/값
  Map<String, Map<String, Object?>> _groupedCache = {};
  List<String> _allAreas = [];

  /// ✅ 선택된 지역(빈 Set이면 "전체 표시")
  Set<String> _selectedAreas = {};

  /// ✅ 삭제 진행 중 표시용
  final Set<String> _deletingKeys = <String>{};

  /// ✅ 로컬 캐시 존재 여부/시각 (UI용)
  bool _hasLocalCache = false;
  DateTime? _cachedAt;

  // ✅ 날짜/시간 포맷 (요일은 intl이 아니라 직접 붙임)
  static final DateFormat _fmtClockInBase = DateFormat('yyyy.MM.dd HH:mm:ss');
  static final DateFormat _fmtTodayBase = DateFormat('yyyy년 MM월 dd일');
  static final DateFormat _fmtUpdatedBase = DateFormat('yyyy.MM.dd HH:mm');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDivisionAndLocalCache());
  }

  String _docCacheKey(String division) => '$_kDocCachePrefix$division';

  DateTime _nowLocal() => DateTime.now().toLocal();

  static const List<String> _weekdayKor = <String>['월', '화', '수', '목', '금', '토', '일'];

  String _weekdayLabel(DateTime dt) {
    final idx = dt.weekday - 1; // 1..7
    if (idx < 0 || idx >= _weekdayKor.length) return '';
    return _weekdayKor[idx];
  }

  /// ✅ 오늘 라벨: "yyyy년 MM월 dd일 (요일)"
  String _todayLabel() {
    final now = _nowLocal();
    return '${_fmtTodayBase.format(now)} (${_weekdayLabel(now)})';
  }

  bool _isSameYmd(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  DateTime? _extractDateTime(Object? v) {
    if (v is Timestamp) return v.toDate().toLocal();

    // 방어: Map 형태(캐시 복원 시)
    if (v is Map) {
      final seconds = v['seconds'];
      final nanos = v['nanoseconds'] ?? 0;
      if (seconds is int) {
        final ts = Timestamp(seconds, (nanos is int) ? nanos : 0);
        return ts.toDate().toLocal();
      }
    }

    return null;
  }

  bool _isTodayValue(Object? v) {
    final dt = _extractDateTime(v);
    if (dt == null) return false;
    return _isSameYmd(dt, _nowLocal());
  }

  /// ✅ Timestamp → yyyy.MM.dd HH:mm:ss (요일) (로컬 타임존 기준)
  String _formatTimestamp(Object? v) {
    final dt = _extractDateTime(v);
    if (dt != null) {
      final base = _fmtClockInBase.format(dt);
      return '$base (${_weekdayLabel(dt)})';
    }
    return v?.toString() ?? '';
  }

  /// ✅ cachedAt → yyyy.MM.dd HH:mm (요일)
  String? _formatCachedAt(DateTime? dt) {
    if (dt == null) return null;
    final base = _fmtUpdatedBase.format(dt);
    return '$base (${_weekdayLabel(dt)})';
  }

  /// 안전한 Map 캐스팅
  Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  /// ✅ 문서 데이터를 "area별로 묶어서" 정규화
  ///
  /// 지원 케이스:
  /// 1) 중첩 구조: { "<area>": { "<worker>": Timestamp, ... }, ... }
  /// 2) 플랫 키:  { "<area>.<worker>": Timestamp, ... }
  Map<String, Map<String, Object?>> _normalizeByArea(Map<String, dynamic> raw) {
    final Map<String, Map<String, Object?>> grouped = {};

    void put(String area, String worker, Object? value) {
      final a = area.trim();
      final w = worker.trim();
      if (a.isEmpty || w.isEmpty) return;
      grouped.putIfAbsent(a, () => {});
      grouped[a]![w] = value;
    }

    for (final entry in raw.entries) {
      final key = entry.key.toString();
      final value = entry.value;

      // 1) area -> Map(worker -> value)
      final maybeMap = _asMap(value);
      if (maybeMap != null) {
        for (final w in maybeMap.entries) {
          put(key, w.key.toString(), w.value);
        }
        continue;
      }

      // 2) "area.worker" -> Timestamp
      final dot = key.indexOf('.');
      if (dot > 0 && dot < key.length - 1) {
        final area = key.substring(0, dot);
        final worker = key.substring(dot + 1);
        put(area, worker, value);
        continue;
      }

      // 3) 예외 구조
      put('(기타)', key, value);
    }

    return grouped;
  }

  /// ---------------------------
  /// 로컬 캐시(영속) 직렬화/역직렬화
  /// ---------------------------
  dynamic _jsonify(Object? v) {
    if (v == null) return null;

    if (v is Timestamp) {
      return <String, dynamic>{
        'seconds': v.seconds,
        'nanoseconds': v.nanoseconds,
      };
    }

    if (v is String || v is num || v is bool) return v;

    if (v is Map) {
      return v.map((k, value) => MapEntry(k.toString(), _jsonify(value)));
    }

    if (v is Iterable) {
      return v.map(_jsonify).toList();
    }

    // 알 수 없는 타입은 문자열로
    return v.toString();
  }

  Map<String, Map<String, Object?>> _decodeGrouped(dynamic groupedRaw) {
    final Map<String, Map<String, Object?>> grouped = {};

    if (groupedRaw is! Map) return grouped;

    for (final entry in groupedRaw.entries) {
      final area = entry.key.toString();
      final workersRaw = entry.value;

      if (workersRaw is! Map) continue;

      final Map<String, Object?> workers = {};
      for (final w in workersRaw.entries) {
        workers[w.key.toString()] = w.value;
      }

      grouped[area] = workers;
    }

    return grouped;
  }

  _LocalDocCache? _tryDecodeLocalCache(String jsonStr) {
    try {
      final root = jsonDecode(jsonStr);
      if (root is! Map) return null;

      final cachedAtMsRaw = root['cachedAtMs'];
      final cachedAtMs = (cachedAtMsRaw is int) ? cachedAtMsRaw : null;

      final groupedRaw = root['grouped'];
      final grouped = _decodeGrouped(groupedRaw);

      return _LocalDocCache(
        grouped: grouped,
        cachedAt: cachedAtMs != null ? DateTime.fromMillisecondsSinceEpoch(cachedAtMs).toLocal() : null,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveLocalCache({
    required String division,
    required Map<String, Map<String, Object?>> grouped,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    if (grouped.isEmpty) {
      await prefs.remove(_docCacheKey(division));
      return;
    }

    final groupedJson = <String, dynamic>{};
    for (final areaEntry in grouped.entries) {
      final workersJson = <String, dynamic>{};
      for (final wEntry in areaEntry.value.entries) {
        workersJson[wEntry.key] = _jsonify(wEntry.value);
      }
      groupedJson[areaEntry.key] = workersJson;
    }

    final payload = <String, dynamic>{
      'cachedAtMs': DateTime.now().millisecondsSinceEpoch,
      'grouped': groupedJson,
    };

    await prefs.setString(_docCacheKey(division), jsonEncode(payload));
  }

  Future<void> _clearLocalCache(String division) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_docCacheKey(division));
  }

  /// ----------------------------------
  /// 오픈 시: division + 로컬 캐시만 로드
  /// (Firestore get 금지)
  /// ----------------------------------
  Future<void> _loadDivisionAndLocalCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final div = (prefs.getString(_kDivisionPrefsKey) ?? '').trim();

      _LocalDocCache? local;
      if (div.isNotEmpty) {
        final jsonStr = prefs.getString(_docCacheKey(div));
        if (jsonStr != null && jsonStr.trim().isNotEmpty) {
          local = _tryDecodeLocalCache(jsonStr);
          if (local == null) {
            // 캐시가 깨졌다면 제거
            await prefs.remove(_docCacheKey(div));
          }
        }
      }

      if (!mounted) return;

      final grouped = local?.grouped ?? <String, Map<String, Object?>>{};
      final areas = grouped.keys.toList()..sort();
      final cleanedSelected = _selectedAreas.where((a) => areas.contains(a)).toSet();

      setState(() {
        _division = div;
        _loadError = null;

        _docLoading = false;
        _docError = null;

        _groupedCache = grouped;
        _allAreas = areas;
        _selectedAreas = cleanedSelected;

        _hasLocalCache = local != null && grouped.isNotEmpty;
        _cachedAt = local?.cachedAt;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _division = '';
        _loadError = e;

        _docLoading = false;
        _docError = null;

        _groupedCache = {};
        _allAreas = [];
        _selectedAreas = {};

        _hasLocalCache = false;
        _cachedAt = null;
      });
    }
  }

  /// ----------------------------------
  /// 새로고침 시에만: 서버(Firestore) get 수행
  /// ----------------------------------
  Future<void> _loadDocOnce() async {
    final division = (_division ?? '').trim();
    if (division.isEmpty) return;
    if (_docLoading) return;

    setState(() {
      _docLoading = true;
      _docError = null;
    });

    try {
      final doc = await FirebaseFirestore.instance.collection('commute_true_false').doc(division).get();

      if (!mounted) return;

      if (!doc.exists) {
        await _clearLocalCache(division);

        setState(() {
          _groupedCache = {};
          _allAreas = [];
          _selectedAreas = {};
          _docLoading = false;
          _docError = null;

          _hasLocalCache = false;
          _cachedAt = null;
        });
        return;
      }

      final raw = doc.data();
      final normalized = _normalizeByArea(raw ?? {});
      final areas = normalized.keys.toList()..sort();

      // ✅ 선택된 지역이 더 이상 없으면 제거
      final cleanedSelected = _selectedAreas.where((a) => areas.contains(a)).toSet();

      // ✅ 로컬 캐시 저장(영속)
      await _saveLocalCache(division: division, grouped: normalized);

      if (!mounted) return;

      setState(() {
        _groupedCache = normalized;
        _allAreas = areas;
        _selectedAreas = cleanedSelected;
        _docLoading = false;
        _docError = null;

        _hasLocalCache = normalized.isNotEmpty;
        _cachedAt = DateTime.now().toLocal();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _docLoading = false;
        _docError = e;
      });
    }
  }

  Future<void> _openAreaPicker() async {
    if (_allAreas.isEmpty) return;

    // 임시 선택값: 빈 Set이면 전체
    final initial = _selectedAreas.toSet();

    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Theme.of(context).colorScheme.scrim.withOpacity(0.45), // ✅ 테마 scrim
      builder: (_) {
        return _AreaPickerSheet(
          allAreas: _allAreas,
          initialSelected: initial,
        );
      },
    );

    if (!mounted) return;
    if (result == null) return;

    // ✅ "전체" 의미: 빈 Set
    setState(() {
      _selectedAreas = result;
    });
  }

  String _delKey(String area, String worker) => '$area|$worker';

  Future<void> _confirmDeleteWorker({
    required String area,
    required String worker,
  }) async {
    final division = (_division ?? '').trim();
    if (division.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('division 값이 없어 삭제할 수 없습니다.')),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;

        return AlertDialog(
          title: const Text('직원 삭제'),
          content: Text(
            '퇴사 등으로 인해 아래 직원을 목록에서 삭제합니다.\n\n'
                '지역: $area\n'
                '이름: $worker\n\n'
                '삭제 후에는 되돌릴 수 없습니다.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: cs.error, // ✅ 테마 error
                foregroundColor: cs.onError, // ✅ 테마 onError
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('삭제'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    await _deleteWorker(area: area, worker: worker);
  }

  Future<void> _deleteWorker({
    required String area,
    required String worker,
  }) async {
    final division = (_division ?? '').trim();
    if (division.isEmpty) return;

    final key = _delKey(area, worker);
    if (_deletingKeys.contains(key)) return;

    setState(() {
      _deletingKeys.add(key);
    });

    try {
      final docRef = FirebaseFirestore.instance.collection('commute_true_false').doc(division);

      // ✅ 두 구조 모두 커버:
      // 1) 중첩: { area: { worker: ... } }  -> FieldPath([area, worker])
      // 2) 플랫:  { "area.worker": ... }     -> FieldPath(["area.worker"])
      await docRef.update(<Object, Object?>{
        FieldPath(<String>[area, worker]): FieldValue.delete(),
        FieldPath(<String>['$area.$worker']): FieldValue.delete(),
      });

      if (!mounted) return;

      // ✅ 네트워크 재조회 없이 화면 캐시에서 제거 + 로컬 캐시도 저장
      setState(() {
        final areaMap = _groupedCache[area];
        if (areaMap != null) {
          areaMap.remove(worker);

          if (areaMap.isEmpty) {
            _groupedCache.remove(area);
            _allAreas = _groupedCache.keys.toList()..sort();
            _selectedAreas.remove(area);
          }
        }

        _hasLocalCache = _groupedCache.isNotEmpty;
        if (_groupedCache.isEmpty) _cachedAt = null;
      });

      // ✅ 영속 캐시 반영
      if (_groupedCache.isEmpty) {
        await _clearLocalCache(division);
      } else {
        await _saveLocalCache(division: division, grouped: _groupedCache);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('삭제 완료: $worker')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('삭제 실패: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _deletingKeys.remove(key);
      });
    }
  }

  Future<void> _handleRefresh() async {
    // ✅ 새로고침 동작:
    // 1) (혹시 division이 바뀌었을 수 있으니) division+로컬 캐시 재로드
    // 2) 서버 get 수행 (이때만)
    await _loadDivisionAndLocalCache();
    await _loadDocOnce();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final division = _division;

    final Widget pageBody = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const _InfoBanner(),
          const SizedBox(height: 12),
          _AreaFilterBar(
            today: _todayLabel(), // ✅ 요일 포함
            docLoading: _docLoading,
            docError: _docError,
            lastUpdated: _formatCachedAt(_cachedAt), // ✅ 요일 포함(필요 시 UI 확장용)
            onPickAreas: _openAreaPicker,
            onRefresh: _handleRefresh,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _buildCachedBody(context, division),
          ),
        ],
      ),
    );

    // ===== 페이지 모드 =====
    if (!widget.asBottomSheet) {
      return Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          backgroundColor: cs.surface,
          elevation: 0,
          foregroundColor: cs.onSurface,
          surfaceTintColor: Colors.transparent,
          title: Text(
            '근무지 현황',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          centerTitle: true,
          automaticallyImplyLeading: false,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(height: 1, thickness: 1, color: cs.outlineVariant.withOpacity(0.6)),
          ),
        ),
        body: pageBody,
      );
    }

    // ===== 바텀시트 모드 =====
    return _SheetScaffold(
      title: '근무지 현황',
      onClose: () => Navigator.of(context).maybePop(),
      body: pageBody,
    );
  }

  Widget _buildCachedBody(BuildContext context, String? division) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // 1) prefs 로딩 중
    if (division == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // 2) prefs 로딩 에러
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'division 로드 실패: $_loadError',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface),
          ),
        ),
      );
    }

    // 3) division 값 없음
    if (division.trim().isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'SharedPreferences에 division 값이 없습니다.\n'
                'division을 저장한 뒤 다시 시도하세요.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface),
          ),
        ),
      );
    }

    // 4) 서버 새로고침 로딩 중
    if (_docLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // 5) 서버 새로고침 에러
    if (_docError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Firestore 문서 로드 오류: $_docError',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface),
          ),
        ),
      );
    }

    // 6) 표시 데이터 없음(= 로컬 캐시 없음/비었음)
    if (_groupedCache.isEmpty) {
      final msg = _hasLocalCache
          ? '표시할 데이터가 없습니다.'
          : '저장된 데이터(로컬 캐시)가 없습니다.\n'
          '새로고침을 눌러 데이터를 가져오세요.\n\n'
          'collection: commute_true_false\n'
          'docId: ${division.trim()}';

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            msg,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface),
          ),
        ),
      );
    }

    // ✅ 필터 적용: 선택 없으면 전체, 선택 있으면 해당 area만
    final visibleAreas =
    (_selectedAreas.isEmpty) ? _allAreas : _allAreas.where((a) => _selectedAreas.contains(a)).toList();

    if (visibleAreas.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '선택된 지역에 표시할 데이터가 없습니다.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
      itemCount: visibleAreas.length,
      separatorBuilder: (context, index) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Divider(
          height: 1,
          thickness: 1,
          color: cs.outlineVariant.withOpacity(0.6),
        ),
      ),
      itemBuilder: (context, index) {
        final area = visibleAreas[index];
        final workers = _groupedCache[area] ?? {};

        // ✅ worker 항목을 "최근 출근" 기준으로 내림차순 정렬
        final entries = workers.entries.toList();
        entries.sort((a, b) {
          final adt = _extractDateTime(a.value);
          final bdt = _extractDateTime(b.value);

          if (adt == null && bdt == null) return a.key.compareTo(b.key);
          if (adt == null) return 1;
          if (bdt == null) return -1;
          return bdt.compareTo(adt);
        });

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ✅ 대제목: 지역명 (브랜드 테마 기반)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 18,
                    decoration: BoxDecoration(
                      color: cs.primary, // ✅ 브랜드 primary
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      area,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                        color: cs.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: cs.surfaceVariant, // ✅ 중립 배경(테마)
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: cs.outlineVariant.withOpacity(0.7)),
                    ),
                    child: Text(
                      '${entries.length}명',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ✅ 카드: 지역별 사용자 목록 (테마 surface/outlineVariant)
            Card(
              elevation: 0,
              color: cs.surface,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: cs.outlineVariant.withOpacity(0.7)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  // 상단 헤더 (테마 surfaceVariant)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: cs.surfaceVariant,
                      border: Border(
                        bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.7)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.location_on_rounded,
                          size: 18,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '최근 출근 목록',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 목록
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      thickness: 1,
                      color: cs.outlineVariant.withOpacity(0.6),
                    ),
                    itemBuilder: (context, i) {
                      final e = entries[i];
                      final workerName = e.key;
                      final lastClockInText = _formatTimestamp(e.value); // ✅ 요일 포함
                      final isToday = _isTodayValue(e.value);

                      // ✅ 오늘=브랜드 primary, 미일치=테마 error
                      final accent = isToday ? cs.primary : cs.error;

                      final delKey = _delKey(area, workerName);
                      final deleting = _deletingKeys.contains(delKey);

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 좌측 아이콘
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: accent.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: accent.withOpacity(0.28),
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.badge_rounded,
                                size: 18,
                                color: accent,
                              ),
                            ),
                            const SizedBox(width: 12),

                            // 본문
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        // ✅ 사용자 UI: "지역.이름"이 아니라 이름만 표시
                                        child: Text(
                                          workerName,
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            fontWeight: FontWeight.w900,
                                            color: isToday ? cs.onSurface : cs.error,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),

                                      // 오늘 여부 배지
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: accent.withOpacity(0.10),
                                          borderRadius: BorderRadius.circular(999),
                                          border: Border.all(
                                            color: accent.withOpacity(0.28),
                                          ),
                                        ),
                                        child: Text(
                                          isToday ? '오늘' : '미일치',
                                          style: theme.textTheme.labelSmall?.copyWith(
                                            fontWeight: FontWeight.w900,
                                            color: accent,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),

                                      // ✅ 삭제 버튼 (퇴사자 등)
                                      if (deleting)
                                        SizedBox(
                                          width: 34,
                                          height: 28,
                                          child: Center(
                                            child: SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: cs.primary,
                                              ),
                                            ),
                                          ),
                                        )
                                      else
                                        IconButton(
                                          tooltip: '직원 삭제',
                                          icon: const Icon(Icons.delete_outline),
                                          color: cs.onSurfaceVariant.withOpacity(0.8),
                                          onPressed: () => _confirmDeleteWorker(
                                            area: area,
                                            worker: workerName,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: accent.withOpacity(0.06),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: accent.withOpacity(0.20),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.schedule_rounded,
                                          size: 16,
                                          color: accent,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            lastClockInText,
                                            style: theme.textTheme.bodyMedium?.copyWith(
                                              fontWeight: FontWeight.w900,
                                              color: accent,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// ===== “92% 전체 화면” 바텀시트 프레임 =====
class _NinetyTwoPercentBottomSheetFrame extends StatelessWidget {
  const _NinetyTwoPercentBottomSheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return FractionallySizedBox(
      heightFactor: 1,
      widthFactor: 1.0,
      child: SafeArea(
        top: true,
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  blurRadius: 24,
                  spreadRadius: 8,
                  color: cs.shadow.withOpacity(0.18), // ✅ 테마 shadow
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Material(
                color: cs.surface, // ✅ 테마 surface
                surfaceTintColor: Colors.transparent,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ===== 바텀시트용 스캐폴드(핸들+타이틀+닫기) =====
class _SheetScaffold extends StatelessWidget {
  const _SheetScaffold({
    required this.title,
    required this.onClose,
    required this.body,
  });

  final String title;
  final VoidCallback onClose;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      color: cs.surface,
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withOpacity(0.35),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            title: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            trailing: IconButton(
              tooltip: '닫기',
              icon: const Icon(Icons.close_rounded),
              onPressed: onClose,
            ),
          ),
          Divider(height: 1, thickness: 1, color: cs.outlineVariant.withOpacity(0.6)),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// ===== 상단 안내 배너 =====
class _InfoBanner extends StatelessWidget {
  const _InfoBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.7)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 22, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '가장 마지막에 출근한 날짜를 출력합니다.',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.25,
                color: cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ===== 상단 필터 바 =====
/// 요구사항: 표시 필드에는 오늘 날짜(년/월/일 + 요일)만 출력
class _AreaFilterBar extends StatelessWidget {
  const _AreaFilterBar({
    required this.today,
    required this.docLoading,
    required this.docError,
    required this.onPickAreas,
    required this.onRefresh,
    this.lastUpdated,
  });

  final String today;
  final bool docLoading;
  final Object? docError;
  final String? lastUpdated; // 필요 시 UI 확장용
  final VoidCallback onPickAreas;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    String subLine = '$today입니다.';
    if (docLoading) subLine = '문서 로딩 중...';
    if (docError != null) subLine = '문서 로드 오류';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.7)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  subLine,
                  style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '지역 선택',
            onPressed: onPickAreas,
            icon: Icon(Icons.filter_alt_rounded, color: cs.primary),
          ),
          IconButton(
            tooltip: '새로고침',
            onPressed: onRefresh,
            icon: Icon(Icons.refresh, color: cs.primary),
          ),
        ],
      ),
    );
  }
}

/// ===== 지역 선택 시트(멀티 셀렉트) =====
class _AreaPickerSheet extends StatefulWidget {
  const _AreaPickerSheet({
    required this.allAreas,
    required this.initialSelected,
  });

  final List<String> allAreas;
  final Set<String> initialSelected;

  @override
  State<_AreaPickerSheet> createState() => _AreaPickerSheetState();
}

class _AreaPickerSheetState extends State<_AreaPickerSheet> {
  late Set<String> _tempSelected;

  @override
  void initState() {
    super.initState();
    _tempSelected = widget.initialSelected.toSet();
  }

  bool get _isAll => _tempSelected.isEmpty;

  void _toggleAll() {
    setState(() {
      _tempSelected.clear(); // ✅ 빈 Set = 전체
    });
  }

  void _toggleOne(String area) {
    setState(() {
      if (_tempSelected.isEmpty) {
        _tempSelected = {area};
        return;
      }

      if (_tempSelected.contains(area)) {
        _tempSelected.remove(area);
        if (_tempSelected.isEmpty) {
          _tempSelected.clear();
        }
      } else {
        _tempSelected.add(area);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SafeArea(
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        builder: (_, controller) {
          return Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border.all(color: cs.outlineVariant.withOpacity(.7)),
              boxShadow: [
                BoxShadow(
                  color: cs.shadow.withOpacity(.14),
                  blurRadius: 20,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withOpacity(.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  title: Text(
                    '지역 선택',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    _isAll ? '전체 표시' : '${_tempSelected.length}개 선택됨',
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: _toggleAll,
                        child: const Text('전체'),
                      ),
                      const SizedBox(width: 4),
                      FilledButton(
                        onPressed: () => Navigator.pop<Set<String>>(context, _tempSelected),
                        child: const Text('적용'),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: '닫기',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, thickness: 1, color: cs.outlineVariant.withOpacity(0.6)),
                Expanded(
                  child: ListView.separated(
                    controller: controller,
                    itemCount: widget.allAreas.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      thickness: 1,
                      color: cs.outlineVariant.withOpacity(0.6),
                    ),
                    itemBuilder: (_, i) {
                      final area = widget.allAreas[i];
                      final checked = _isAll ? false : _tempSelected.contains(area);

                      return CheckboxListTile(
                        value: checked,
                        onChanged: (_) => _toggleOne(area),
                        title: Text(
                          area,
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '해당 지역만 표시/숨김',
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// ===== 로컬 캐시 디코딩용 모델 =====
class _LocalDocCache {
  _LocalDocCache({
    required this.grouped,
    required this.cachedAt,
  });

  final Map<String, Map<String, Object?>> grouped;
  final DateTime? cachedAt;
}
