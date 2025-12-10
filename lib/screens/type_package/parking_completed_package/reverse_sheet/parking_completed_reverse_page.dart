// lib/screens/type_package/parking_completed_package/reverse_sheet/parking_completed_reverse_page.dart
import 'dart:async';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 프로젝트 내부 상태/유틸
import '../../../../states/area/area_state.dart';
import '../../../../states/location/location_state.dart';
import '../../../../utils/snackbar_helper.dart';

// SQLite 기반 리포지토리
import '../table_package/repositories/parking_completed_repository.dart';
import '../table_package/models/parking_completed_record.dart';

/// 역 바텀시트(Top Sheet) 콘텐츠 (SQLite 기반)
/// - 로컬 SQLite 테이블의 parking_completed_records를 created_at 오름차순(오래된 순)으로 조회
/// - 기본: 주차 구역(location) **무관**
/// - 옵션: **특정 주차 구역 제외**
/// - 한 번에 5개씩 페이지네이션(추가 데이터는 메모리에서 페이징)
/// - Firestore 및 원격 DB READ 비용 제어 로직(전역 캐시/쿨다운)은 제거
/// - 단, '업무 마감 동의', '작업 완료' 로컬 표시, 구역 제외 필터,
///   필터/완료 상태 SharedPreferences 저장은 그대로 유지
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
  // 상태
  static const int _pageSize = 5;

  final ParkingCompletedRepository _repository = ParkingCompletedRepository();

  bool _loading = false;
  bool _loadingMore = false;

  /// 전체 결과 (필터 적용 후, SQLite에서 한 번에 읽어온 리스트)
  final List<ParkingCompletedRecord> _allRows = <ParkingCompletedRecord>[];

  /// 화면에 현재 표시 중인 행들(페이지네이션 대상)
  final List<ParkingCompletedRecord> _rows = <ParkingCompletedRecord>[];

  /// 다음에 읽어올 인덱스 (메모리 상에서 페이징)
  int _nextIndex = 0;

  /// 아직 더 로드할 데이터가 있는지 여부
  bool _hasMore = false;

  // 권한 동의(업무 마감 목적 확인) 후에만 데이터를 로드한다
  bool _acknowledged = false;

  // 시트 오픈 시의 area (dispose에서 context 접근 금지)
  late final String _areaAtOpen;

  // 필터 상태(※ 제외만 지원)
  final Set<String> _selectedDisplayNames = <String>{}; // 제외할 표시명 세트(다중 선택)
  // Firestore whereNotIn 제한(최대 10)과 맞추기 위해 동일 제한 유지
  static const int _kWhereNotInLimit = 10;

  // ── '작업 완료' 로컬 상태 (문서 id 기준 → SQLite 전용 key 기준)
  final Set<String> _doneIds = <String>{};
  final Set<String> _overlayOpenIds = <String>{};
  static const Color _doneBg = Color(0xFFE8F5E9); // 연한 초록(완료 표시 유지)
  String get _donePrefsKey => 'rev_top_done_ids_${_areaAtOpen}';

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
    // parent/type 이 실제로는 non-null일 수도 있기 때문에, 로컬 nullable 변수에 담아서 사용
    final String? rawType = type;
    final String? rawParent = parent;

    if ((rawType ?? '').trim() == 'composite' && (rawParent ?? '').trim().isNotEmpty) {
      return '${rawParent!.trim()} - ${name.trim()}';
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

  // ParkingCompletedRecord → 로컬 key (완료 여부 저장용)
  String _keyOfRecord(ParkingCompletedRecord record) {
    // createdAt 이 nullable일 수 있으므로 null-safe 처리
    final DateTime? createdAt = record.createdAt;
    final int millis = createdAt?.millisecondsSinceEpoch ?? 0;

    // location 도 nullable 가능성이 있으므로, 로컬 nullable → non-null 변환
    final String? rawLocation = record.location;
    final String safeLocation = rawLocation ?? '';

    // plate + location + createdAt 조합으로 로컬 고유 키 구성
    return '${record.plateNumber}|$safeLocation|$millis';
  }

  // 현재 필터 기준으로 레코드 필터링
  List<ParkingCompletedRecord> _filterRecordsByExcludedLocations(
      List<ParkingCompletedRecord> all,
      Set<String> excludedDisplayNames,
      ) {
    if (excludedDisplayNames.isEmpty) return all;

    final excludedLeaves = excludedDisplayNames.map(_extractLeaf).toSet();

    return all.where((r) {
      final String? rawLocation = r.location;
      final String loc = (rawLocation ?? '').trim();
      if (loc.isEmpty) return !excludedLeaves.contains(''); // 빈 문자열은 일반적으로 제외 대상 아님
      return !excludedLeaves.contains(loc);
    }).toList();
  }

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
  // SQLite 질의 + 메모리 기반 페이지네이션

  Future<void> _loadFirstPage() async {
    final effectiveCount = _effectiveLocationCount();
    final area = _areaAtOpen;
    debugPrint('[REV-TOP] loadFirstPage() | area=$area');

    if (area.isEmpty) {
      showFailedSnackbar(context, '지역이 선택되지 않았습니다.');
      return;
    }

    // 최소 1개 제외(실제 구역이 2개 이상일 때)
    if (effectiveCount >= 2 && _selectedDisplayNames.isEmpty) {
      showFailedSnackbar(context, '확인하지 않을 주차 구역을 최소 1개 선택해 주세요.');
      return;
    }

    try {
      _setLoading(true);
      debugPrint('[REV-TOP] [QUERY] first page from SQLite START | limit≈500');

      // 기존 테이블 시트와 동일하게 최대 500개 정도만 읽고, 메모리에서 필터/페이징
      final all = await _repository.listAll(limit: 500);

      final filtered = _filterRecordsByExcludedLocations(all, _selectedDisplayNames);

      setState(() {
        _allRows
          ..clear()
          ..addAll(filtered);
        _rows.clear();
        _nextIndex = 0;
      });

      _appendNextPage();

      debugPrint('[REV-TOP] [QUERY] first page DONE | total=${_allRows.length}, page=${_rows.length}, hasMore=$_hasMore');
    } catch (e) {
      showFailedSnackbar(context, '불러오기 실패: $e');
      debugPrint('[REV-TOP] [ERROR] first: $e');
    } finally {
      _setLoading(false);
    }
  }

  void _appendNextPage() {
    if (_nextIndex >= _allRows.length) {
      setState(() => _hasMore = false);
      return;
    }

    final next = _allRows.skip(_nextIndex).take(_pageSize).toList();

    setState(() {
      _rows.addAll(next);
      _nextIndex += next.length;
      _hasMore = _nextIndex < _allRows.length;
    });

    debugPrint('[REV-TOP] [PAGE] append page | appended=${next.length}, '
        'shown=${_rows.length}, total=${_allRows.length}, hasMore=$_hasMore');
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;

    try {
      _setLoadingMore(true);
      _appendNextPage();
    } catch (e) {
      showFailedSnackbar(context, '더보기 실패: $e');
      debugPrint('[REV-TOP] [ERROR] more: $e');
    } finally {
      _setLoadingMore(false);
    }
  }

  // 새로고침: SQLite 기준으로 단순 재조회
  Future<void> _refreshForce() async {
    HapticFeedback.lightImpact();
    debugPrint('[REV-TOP] [REFRESH] force reload from SQLite');
    await _loadFirstPage();
  }

  // 시간 포맷 (SQLite DateTime 기준)
  String _formatTime(DateTime? dt) {
    if (dt == null) return '-';
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$mm';
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 필터 전환

  Future<void> _switchFilterWithSet({required Set<String> displayNames}) async {
    _selectedDisplayNames
      ..clear()
      ..addAll(displayNames.where((e) => e.trim().isNotEmpty));
    await _saveFilter();

    debugPrint('[REV-TOP] [FILTER] switched | excluded=${_selectedDisplayNames.join(", ")}');

    // Firestore 조회 쿨다운/전역 캐시는 제거하고,
    // 단순히 SQLite에서 다시 조회하도록 변경
    setState(() {
      _rows.clear();
      _allRows.clear();
      _nextIndex = 0;
      _hasMore = false;
    });

    await _loadFirstPage();
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
    });
  }

  @override
  void dispose() {
    debugPrint('[REV-TOP] dispose | area=$_areaAtOpen');
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
      ...locations
          .map((l) => _displayOf(name: l.locationName, parent: l.parent, type: l.type))
          .toSet()
          .toList()
        ..sort((a, b) => a.compareTo(b)),
    ];
    final effectiveCount = displayNames.length - 1; // '전체' 제외

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
              const Tooltip(
                message: '제외 목록은 다른 화면의 수동 새로고침으로 캐시에 저장된 구역 기준입니다.',
                child: Icon(Icons.info_outline, size: 20),
              ),
            ],
          ),
        ),

        // 컨트롤 바 2: 데이터 새로고침/더보기
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              // 새로고침
              Expanded(
                child: ElevatedButton.icon(
                  style: _whiteBorderButtonStyle(context),
                  onPressed: (_loading || !_acknowledged)
                      ? null
                      : () async {
                    await _refreshForce();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('새로고침'),
                ),
              ),
              const SizedBox(width: 8),
              // 더보기
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
        if (_rows.isEmpty)
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
        if (_rows.isNotEmpty)
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
            listNotifier.value =
                displayNames.where((e) => e.toLowerCase().contains(query.toLowerCase())).toList();
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
                      child: Text('확인하지 않을 주차 구역 선택',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                            final firstReal =
                            displayNames.firstWhere((e) => e != '전체(구역 무관)', orElse: () => '');
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
                            label: Text(
                              '적용 (${s.isEmpty ? (effectiveCount >= 2 ? "최소 1개" : "제외 없음") : "${s.length}개"})',
                            ),
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
    if (_loading && _rows.isEmpty) {
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

    if (_rows.isEmpty) {
      return const Center(
        child: Text(
          '표시할 데이터가 없습니다.\n[불러오기(5개)]를 눌러 가장 오래된 항목부터 가져옵니다.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      itemCount: _rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final rec = _rows[i];
        final String id = _keyOfRecord(rec);

        final String plate = rec.plateNumber;

        final String? rawLocation = rec.location;
        final String location = rawLocation ?? '';

        final DateTime? createdAt = rec.createdAt;
        final String time = _formatTime(createdAt);

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
