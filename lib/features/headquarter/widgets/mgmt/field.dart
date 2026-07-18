import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../features/commute/domain/repositories/commute_true_false_repository.dart';

class Field extends StatefulWidget {
  const Field({
    super.key,
    this.asBottomSheet = false,
    this.usePromptUi = false,
  });

  final bool asBottomSheet;
  final bool usePromptUi;

  static Future<T?> showAsBottomSheet<T>(
    BuildContext context, {
    bool usePromptUi = false,
  }) {
    Widget buildSheet(BuildContext sheetContext) {
      final insets = MediaQuery.of(sheetContext).viewInsets;
      return Padding(
        padding: EdgeInsets.only(bottom: insets.bottom),
        child: _NinetyTwoPercentBottomSheetFrame(
          child: Field(
            asBottomSheet: true,
            usePromptUi: usePromptUi,
          ),
        ),
      );
    }

    if (usePromptUi) {
      return showPromptOverlayBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: buildSheet,
      );
    }

    final cs = Theme.of(context).colorScheme;
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: cs.scrim.withOpacity(0.45),
      builder: buildSheet,
    );
  }

  @override
  State<Field> createState() => _FieldState();
}

class _FieldState extends State<Field> {
  static const String _kDivisionPrefsKey = 'division';
  static const String _kDocCachePrefix = 'commute_true_false_cache_v1:';

  String? _division;
  Object? _loadError;

  bool _docLoading = false;
  Object? _docError;

  Map<String, Map<String, Object?>> _groupedCache = {};
  List<String> _allAreas = [];

  Set<String> _selectedAreas = {};

  final Set<String> _deletingKeys = <String>{};

  bool _hasLocalCache = false;
  DateTime? _cachedAt;

  final CommuteTrueFalseRepository _commuteRepo = CommuteTrueFalseRepository();

  Future<T?> _showFieldDialog<T>({
    required WidgetBuilder builder,
    bool barrierDismissible = true,
  }) {
    if (widget.usePromptUi) {
      return showPromptOverlayDialog<T>(
        context: context,
        barrierDismissible: barrierDismissible,
        builder: builder,
      );
    }
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: builder,
    );
  }

  Future<T?> _showFieldBottomSheet<T>({
    required WidgetBuilder builder,
  }) {
    if (widget.usePromptUi) {
      return showPromptOverlayBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: builder,
      );
    }
    final cs = Theme.of(context).colorScheme;
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: cs.scrim.withOpacity(0.45),
      builder: builder,
    );
  }

  static final DateFormat _fmtClockInBase = DateFormat('yyyy.MM.dd HH:mm:ss');
  static final DateFormat _fmtTodayBase = DateFormat('yyyy년 MM월 dd일');
  static final DateFormat _fmtUpdatedBase = DateFormat('yyyy.MM.dd HH:mm');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _loadDivisionAndLocalCache());
  }

  String _docCacheKey(String division) => '$_kDocCachePrefix$division';

  DateTime _nowLocal() => DateTime.now().toLocal();

  static const List<String> _weekdayKor = <String>[
    '월',
    '화',
    '수',
    '목',
    '금',
    '토',
    '일'
  ];

  String _weekdayLabel(DateTime dt) {
    final idx = dt.weekday - 1;
    if (idx < 0 || idx >= _weekdayKor.length) return '';
    return _weekdayKor[idx];
  }

  String _todayLabel() {
    final now = _nowLocal();
    return '${_fmtTodayBase.format(now)} (${_weekdayLabel(now)})';
  }

  bool _isSameYmd(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  DateTime? _extractDateTime(Object? v) {
    try {
      final dt = (v as dynamic).toDate();
      if (dt is DateTime) return dt.toLocal();
    } catch (_) {}

    if (v is Map) {
      final seconds = v['seconds'];
      final nanos = v['nanoseconds'] ?? 0;
      if (seconds is int) {
        final ms = (seconds * 1000) + ((nanos is int ? nanos : 0) ~/ 1000000);
        return DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
      }
    }

    return null;
  }

  bool _isTodayValue(Object? v) {
    final dt = _extractDateTime(v);
    if (dt == null) return false;
    return _isSameYmd(dt, _nowLocal());
  }

  String _formatTimestamp(Object? v) {
    final dt = _extractDateTime(v);
    if (dt != null) {
      final base = _fmtClockInBase.format(dt);
      return '$base (${_weekdayLabel(dt)})';
    }
    return v?.toString() ?? '';
  }

  String? _formatCachedAt(DateTime? dt) {
    if (dt == null) return null;
    final base = _fmtUpdatedBase.format(dt);
    return '$base (${_weekdayLabel(dt)})';
  }

  dynamic _jsonify(Object? v) {
    if (v == null) return null;

    try {
      final seconds = (v as dynamic).seconds;
      final nanoseconds = (v as dynamic).nanoseconds;
      if (seconds is int && nanoseconds is int) {
        return <String, dynamic>{
          'seconds': seconds,
          'nanoseconds': nanoseconds,
        };
      }
    } catch (_) {}

    if (v is String || v is num || v is bool) return v;

    if (v is Map) {
      return v.map((k, value) => MapEntry(k.toString(), _jsonify(value)));
    }

    if (v is Iterable) {
      return v.map(_jsonify).toList();
    }

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
        cachedAt: cachedAtMs != null
            ? DateTime.fromMillisecondsSinceEpoch(cachedAtMs).toLocal()
            : null,
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
            await prefs.remove(_docCacheKey(div));
          }
        }
      }

      if (!mounted) return;

      final grouped = local?.grouped ?? <String, Map<String, Object?>>{};
      final areas = grouped.keys.toList()..sort();
      final cleanedSelected =
          _selectedAreas.where((a) => areas.contains(a)).toSet();

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

  Future<void> _loadDocOnce() async {
    final division = (_division ?? '').trim();
    if (division.isEmpty) return;
    if (_docLoading) return;

    setState(() {
      _docLoading = true;
      _docError = null;
    });

    try {
      final normalized = await _commuteRepo.loadGroupedByDivision(division);

      if (!mounted) return;

      if (normalized.isEmpty) {
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

      final areas = normalized.keys.toList()..sort();
      final cleanedSelected =
          _selectedAreas.where((a) => areas.contains(a)).toSet();

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

    final initial = _selectedAreas.toSet();

    final result = await _showFieldBottomSheet<Set<String>>(
      builder: (_) {
        return _AreaPickerSheet(
          allAreas: _allAreas,
          initialSelected: initial,
        );
      },
    );

    if (!mounted) return;
    if (result == null) return;

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
      return;
    }

    final ok = await _showFieldDialog<bool>(
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
                    backgroundColor: cs.error,
                    foregroundColor: cs.onError,
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('삭제'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!ok) return;

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
      await _commuteRepo.deleteWorker(division: division, area: area, worker: worker);

      if (!mounted) return;

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

      if (_groupedCache.isEmpty) {
        await _clearLocalCache(division);
      } else {
        await _saveLocalCache(division: division, grouped: _groupedCache);
      }
    } catch (_) {
    } finally {
      if (!mounted) return;
      setState(() {
        _deletingKeys.remove(key);
      });
    }
  }

  Future<void> _handleRefresh() async {
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
            today: _todayLabel(),
            docLoading: _docLoading,
            docError: _docError,
            lastUpdated: _formatCachedAt(_cachedAt),
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
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          centerTitle: true,
          automaticallyImplyLeading: false,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(
              height: 1,
              thickness: 1,
              color: cs.outlineVariant.withOpacity(0.6),
            ),
          ),
        ),
        body: pageBody,
      );
    }

    return _SheetScaffold(
      title: '근무지 현황',
      onClose: () => Navigator.of(context).maybePop(),
      body: pageBody,
    );
  }

  Widget _buildCachedBody(BuildContext context, String? division) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (division == null) {
      return const Center(child: CircularProgressIndicator());
    }

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

    if (_docLoading) {
      return const Center(child: CircularProgressIndicator());
    }

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

    final visibleAreas = (_selectedAreas.isEmpty)
        ? _allAreas
        : _allAreas.where((a) => _selectedAreas.contains(a)).toList();

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
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 18,
                    decoration: BoxDecoration(
                      color: cs.primary,
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: cs.surfaceVariant,
                      borderRadius: BorderRadius.circular(999),
                      border:
                          Border.all(color: cs.outlineVariant.withOpacity(0.7)),
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
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: cs.surfaceVariant,
                      border: Border(
                        bottom: BorderSide(
                            color: cs.outlineVariant.withOpacity(0.7)),
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
                      final lastClockInText = _formatTimestamp(e.value);
                      final isToday = _isTodayValue(e.value);
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
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          workerName,
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                            fontWeight: FontWeight.w900,
                                            color: isToday
                                                ? cs.onSurface
                                                : cs.error,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: accent.withOpacity(0.10),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                          border: Border.all(
                                            color: accent.withOpacity(0.28),
                                          ),
                                        ),
                                        child: Text(
                                          isToday ? '오늘' : '미일치',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                            fontWeight: FontWeight.w900,
                                            color: accent,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
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
                                          icon:
                                              const Icon(Icons.delete_outline),
                                          color: cs.onSurfaceVariant
                                              .withOpacity(0.8),
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
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
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
                  color: cs.shadow.withOpacity(0.18),
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Material(
                color: cs.surface,
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
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            trailing: IconButton(
              tooltip: '닫기',
              icon: const Icon(Icons.close_rounded),
              onPressed: onClose,
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: cs.outlineVariant.withOpacity(0.6),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

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
          Icon(Icons.info_outline_rounded,
              size: 22, color: cs.onSurfaceVariant),
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
  final String? lastUpdated;
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
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
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
      _tempSelected.clear();
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
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
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
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    _isAll ? '전체 표시' : '${_tempSelected.length}개 선택됨',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
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
                        onPressed: () =>
                            Navigator.pop<Set<String>>(context, _tempSelected),
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
                Divider(
                  height: 1,
                  thickness: 1,
                  color: cs.outlineVariant.withOpacity(0.6),
                ),
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
                      final checked =
                          _isAll ? false : _tempSelected.contains(area);

                      return CheckboxListTile(
                        value: checked,
                        onChanged: (_) => _toggleOne(area),
                        title: Text(
                          area,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '해당 지역만 표시/숨김',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
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

class _LocalDocCache {
  _LocalDocCache({
    required this.grouped,
    required this.cachedAt,
  });

  final Map<String, Map<String, Object?>> grouped;
  final DateTime? cachedAt;
}
