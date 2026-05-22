import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../dashboard/domain/repositories/end_work_report_repository.dart';
import 'statistics_chart_page.dart';

enum _DateMode { single, range }

class Statistics extends StatefulWidget {
  const Statistics({
    super.key,
    this.asBottomSheet = false,
  });

  final bool asBottomSheet;

  static Future<T?> showAsBottomSheet<T>(BuildContext context) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (sheetCtx) {
        final insets = MediaQuery.of(sheetCtx).viewInsets;
        return Padding(
          padding: EdgeInsets.only(bottom: insets.bottom),
          child: const _NinetyTwoPercentBottomSheetFrame(
            child: Statistics(asBottomSheet: true),
          ),
        );
      },
    );
  }

  @override
  State<Statistics> createState() => _StatisticsState();
}

class _StatisticsState extends State<Statistics> {
  static const String _kDivisionPrefsKey = 'division';
  static const String _kCachePrefix = 'end_work_reports_cache_v3:';
  static const String _kLastAreaKey = 'statistics_last_area_v1';
  static const String _kLastModeKey = 'statistics_last_mode_v1';
  static const String _kLastDatesKey = 'statistics_last_dates_v1';
  static const String _kLastRangeKey = 'statistics_last_range_v1';

  final EndWorkReportRepository _reportRepo = EndWorkReportRepository();

  String? _division;
  Object? _loadError;

  bool _refreshLoading = false;
  Object? _refreshError;

  bool _hasLocalCache = false;
  DateTime? _cachedAt;

  final Map<String, Map<String, Map<String, dynamic>>> _cacheByArea = {};
  List<String> _areaOptions = [];

  String? _selectedArea;

  _DateMode _dateMode = _DateMode.single;

  Set<DateTime> _selectedDates = <DateTime>{};

  DateTimeRange? _range;

  final List<Map<String, dynamic>> _savedReports = [];

  final PageController _pageCtrl = PageController(viewportFraction: 0.92);
  int _pageIndex = 0;

  static final DateFormat _fmtDateKeyBase = DateFormat('yyyy-MM-dd');
  String _fmtDateKey(DateTime date) => _fmtDateKeyBase.format(date);

  static final DateFormat _fmtTodayBase = DateFormat('yyyy년 MM월 dd일');
  static final DateFormat _fmtUpdatedBase = DateFormat('yyyy.MM.dd HH:mm');
  static const List<String> _weekdayKor = <String>['월', '화', '수', '목', '금', '토', '일'];

  DateTime _nowLocal() => DateTime.now().toLocal();
  DateTime _normalizeDate(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  String _weekdayLabel(DateTime dt) {
    final idx = dt.weekday - 1;
    if (idx < 0 || idx >= _weekdayKor.length) return '';
    return _weekdayKor[idx];
  }

  String _todayLabel() {
    final now = _nowLocal();
    return '${_fmtTodayBase.format(now)} (${_weekdayLabel(now)})';
  }

  String? _formatCachedAt(DateTime? dt) {
    if (dt == null) return null;
    final base = _fmtUpdatedBase.format(dt);
    return '$base (${_weekdayLabel(dt)})';
  }

  String _cacheKey(String division) => '$_kCachePrefix$division';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDivisionAndLocalCache());
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
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

  Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  int? _asInt(dynamic v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  void _ensureValidPage(int count) {
    if (count <= 0) return;
    if (_pageIndex <= count - 1) return;

    _pageIndex = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageCtrl.hasClients) _pageCtrl.jumpToPage(0);
    });
  }

  Future<void> _loadDivisionAndLocalCache({bool keepRefreshFlags = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final div = (prefs.getString(_kDivisionPrefsKey) ?? '').trim();

      final lastArea = (prefs.getString(_kLastAreaKey) ?? '').trim();
      final lastMode = (prefs.getString(_kLastModeKey) ?? '').trim();
      final _DateMode restoredMode = (lastMode == 'range') ? _DateMode.range : _DateMode.single;

      final lastDatesRaw = prefs.getStringList(_kLastDatesKey) ?? const <String>[];
      final restoredDates = <DateTime>{};
      for (final s in lastDatesRaw) {
        final dt = DateTime.tryParse(s);
        if (dt == null) continue;
        restoredDates.add(_normalizeDate(dt));
      }

      DateTimeRange? restoredRange;
      final lastRangeRaw = prefs.getStringList(_kLastRangeKey);
      if (lastRangeRaw != null && lastRangeRaw.length == 2) {
        final s = DateTime.tryParse(lastRangeRaw[0]);
        final e = DateTime.tryParse(lastRangeRaw[1]);
        if (s != null && e != null) {
          restoredRange = DateTimeRange(start: _normalizeDate(s), end: _normalizeDate(e));
        }
      }

      final cacheJson = (div.isNotEmpty) ? prefs.getString(_cacheKey(div)) : null;

      _cacheByArea.clear();
      _areaOptions = [];

      DateTime? cachedAt;
      bool hasCache = false;

      if (cacheJson != null && cacheJson.trim().isNotEmpty) {
        final root = jsonDecode(cacheJson);
        if (root is Map) {
          final cachedAtMs = root['cachedAtMs'];
          if (cachedAtMs is int) {
            cachedAt = DateTime.fromMillisecondsSinceEpoch(cachedAtMs).toLocal();
          }

          final areasRaw = root['areas'];
          if (areasRaw is Map) {
            for (final aEntry in areasRaw.entries) {
              final area = aEntry.key.toString();
              final datesRaw = aEntry.value;
              if (datesRaw is! Map) continue;

              final Map<String, Map<String, dynamic>> byDate = {};
              for (final dEntry in datesRaw.entries) {
                final dateStr = dEntry.key.toString();
                final dayMap = _asMap(dEntry.value);
                if (dayMap == null) continue;
                byDate[dateStr] = Map<String, dynamic>.from(dayMap);
              }

              if (byDate.isNotEmpty) {
                _cacheByArea[area] = byDate;
              }
            }
          }

          hasCache = _cacheByArea.isNotEmpty;
        }
      }

      final areas = _cacheByArea.keys.toList()..sort();

      final restoredArea = (lastArea.isNotEmpty && areas.contains(lastArea)) ? lastArea : null;

      if (!mounted) return;
      setState(() {
        _division = div;
        _loadError = null;
        _hasLocalCache = hasCache;
        _cachedAt = cachedAt;
        _areaOptions = areas;
        _selectedArea = restoredArea;
        _dateMode = restoredMode;

        if (restoredMode == _DateMode.single) {
          _selectedDates = restoredDates;
          _range = null;
        } else {
          _selectedDates = <DateTime>{};
          _range = restoredRange;
        }

        if (!keepRefreshFlags) {
          _refreshLoading = false;
          _refreshError = null;
        }

        _pageIndex = 0;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageCtrl.hasClients) _pageCtrl.jumpToPage(0);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _division = '';
        _loadError = e;
        _hasLocalCache = false;
        _cachedAt = null;
        _cacheByArea.clear();
        _areaOptions = [];
        _selectedArea = null;
        _dateMode = _DateMode.single;
        _selectedDates = <DateTime>{};
        _range = null;

        if (!keepRefreshFlags) {
          _refreshLoading = false;
          _refreshError = null;
        }

        _pageIndex = 0;
      });
    }
  }

  Future<void> _saveCacheToPrefs({
    required String division,
    required Map<String, Map<String, Map<String, dynamic>>> data,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final areasJson = <String, dynamic>{};
    for (final areaEntry in data.entries) {
      final datesJson = <String, dynamic>{};
      for (final dateEntry in areaEntry.value.entries) {
        datesJson[dateEntry.key] = _jsonify(dateEntry.value);
      }
      areasJson[areaEntry.key] = datesJson;
    }

    final payload = <String, dynamic>{
      'cachedAtMs': DateTime.now().millisecondsSinceEpoch,
      'areas': areasJson,
    };

    await prefs.setString(_cacheKey(division), jsonEncode(payload));
  }

  Future<void> _saveUiState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastAreaKey, (_selectedArea ?? '').trim());
    await prefs.setString(_kLastModeKey, (_dateMode == _DateMode.range) ? 'range' : 'single');

    final dates = _selectedDates.map(_fmtDateKey).toList()..sort();
    await prefs.setStringList(_kLastDatesKey, dates);

    if (_range == null) {
      await prefs.remove(_kLastRangeKey);
    } else {
      await prefs.setStringList(_kLastRangeKey, <String>[
        _fmtDateKey(_range!.start),
        _fmtDateKey(_range!.end),
      ]);
    }
  }

  Future<void> _handleRefresh() async {
    if (_refreshLoading) return;

    setState(() {
      _refreshLoading = true;
      _refreshError = null;
    });

    try {
      await _loadDivisionAndLocalCache(keepRefreshFlags: true);

      final div = (_division ?? '').trim();

      final rebuilt = await _reportRepo.buildAreaDateCache(division: div);

      if (div.isNotEmpty) {
        await _saveCacheToPrefs(division: div, data: rebuilt);
      }

      final areas = rebuilt.keys.toList()..sort();

      if (!mounted) return;
      setState(() {
        _cacheByArea
          ..clear()
          ..addAll(rebuilt);

        _areaOptions = areas;

        if (_selectedArea != null && !_areaOptions.contains(_selectedArea)) {
          _selectedArea = null;
          _selectedDates = <DateTime>{};
          _range = null;
        }

        _hasLocalCache = rebuilt.isNotEmpty;
        _cachedAt = DateTime.now().toLocal();
        _refreshLoading = false;
        _refreshError = null;
        _pageIndex = 0;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageCtrl.hasClients) _pageCtrl.jumpToPage(0);
      });
    } catch (e, st) {
      dev.log('[STAT] refresh failed', name: 'Statistics', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _refreshLoading = false;
        _refreshError = e;
      });
    }
  }


  List<Map<String, dynamic>> _buildVisibleCards() {
    final area = (_selectedArea ?? '').trim();
    if (area.isEmpty) return [];

    final byDate = _cacheByArea[area];
    if (byDate == null || byDate.isEmpty) return [];

    if (_dateMode == _DateMode.single) {
      if (_selectedDates.isEmpty) return [];

      final datesSorted = _selectedDates.toList()
        ..sort((a, b) => _normalizeDate(a).compareTo(_normalizeDate(b)));

      final list = <Map<String, dynamic>>[];
      for (final dt in datesSorted) {
        final key = _fmtDateKey(_normalizeDate(dt));
        final day = byDate[key];
        if (day == null) continue;
        list.add(day);
      }
      return list;
    }

    if (_range == null) return [];
    final start = _normalizeDate(_range!.start);
    final end = _normalizeDate(_range!.end);

    final list = <Map<String, dynamic>>[];
    for (final entry in byDate.entries) {
      final d = DateTime.tryParse(entry.key);
      if (d == null) continue;

      final dd = _normalizeDate(d);
      if (dd.isBefore(start) || dd.isAfter(end)) continue;
      list.add(entry.value);
    }

    list.sort((a, b) {
      final da = DateTime.tryParse(a['date']?.toString() ?? '');
      final db = DateTime.tryParse(b['date']?.toString() ?? '');
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return _normalizeDate(da).compareTo(_normalizeDate(db));
    });

    return list;
  }

  Future<void> _pickMultiDates() async {
    if (_selectedArea == null) return;

    final first = DateTime(2023, 1, 1);
    final last = DateTime(2100, 12, 31);

    final initMonth = (_selectedDates.isNotEmpty)
        ? (_selectedDates.toList()..sort((a, b) => a.compareTo(b)))
        : <DateTime>[_nowLocal()];
    final initialMonth = _normalizeDate(initMonth.first);

    final picked = await showDialog<Set<DateTime>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return _MultiDatePickerDialog(
          initialSelected: _selectedDates,
          firstDate: first,
          lastDate: last,
          initialMonth: initialMonth,
        );
      },
    );

    if (!mounted) return;
    if (picked == null) return;

    setState(() {
      _selectedDates = picked.map(_normalizeDate).toSet();
      _range = null;
      _pageIndex = 0;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageCtrl.hasClients) _pageCtrl.jumpToPage(0);
    });

    await _saveUiState();
  }

  Future<void> _pickRange() async {
    if (_selectedArea == null) return;

    final first = DateTime(2023, 1, 1);
    final last = DateTime(2100, 12, 31);

    final now = _nowLocal();
    final initialRange = _range ??
        DateTimeRange(
          start: _normalizeDate(now),
          end: _normalizeDate(now),
        );

    final initialMonth = _normalizeDate(initialRange.start);

    final picked = await showDialog<DateTimeRange>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return _RangePickerDialog(
          initialRange: initialRange,
          firstDate: first,
          lastDate: last,
          initialMonth: initialMonth,
        );
      },
    );

    if (!mounted) return;
    if (picked == null) return;

    setState(() {
      _range = DateTimeRange(start: _normalizeDate(picked.start), end: _normalizeDate(picked.end));
      _selectedDates = <DateTime>{};
      _pageIndex = 0;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageCtrl.hasClients) _pageCtrl.jumpToPage(0);
    });

    await _saveUiState();
  }

  void _bulkSaveVisible() {
    final visible = _buildVisibleCards();
    if (visible.isEmpty) return;

    final existing = _savedReports.map((e) => e['date']?.toString()).toSet();

    for (final day in visible) {
      final dateStr = (day['date'] ?? '').toString();
      if (dateStr.isEmpty) continue;
      if (existing.contains(dateStr)) continue;

      final vc = _asMap(day['vehicleCount']);
      final metrics = _asMap(day['metrics']);

      final outCount = _asInt(day['vehicleOutput'] ?? vc?['vehicleOutput'] ?? day['vehicleInput'] ?? vc?['vehicleInput']) ?? 0;
      final lockedFee = _asInt(
        day['totalLockedFee'] ?? vc?['totalLockedFee'] ?? metrics?['snapshot_totalLockedFee'],
      ) ??
          0;

      _savedReports.add({
        'date': dateStr,
        '출차': outCount,
        '정산금': lockedFee,
      });

      existing.add(dateStr);
    }

    setState(() {});
  }

  void _clearSaved() {
    setState(() => _savedReports.clear());
  }

  void _openGraph() {
    final Map<DateTime, Map<String, int>> parsedData = {};
    for (final report in _savedReports) {
      final date = DateTime.tryParse(report['date']?.toString() ?? '');
      if (date == null) continue;

      parsedData[date] = {
        'vehicleOutput': (report['출차'] as int?) ?? 0,
        'totalLockedFee': (report['정산금'] as int?) ?? 0,
      };
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StatisticsChartPage(
          reportDataMap: parsedData,
          division: (_division ?? '').trim(),
          area: (_selectedArea ?? '').trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final division = _division;

    final body = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const _InfoBanner(),
          const SizedBox(height: 12),
          _TopBar(
            today: _todayLabel(),
            refreshLoading: _refreshLoading,
            refreshError: _refreshError,
            lastUpdated: _formatCachedAt(_cachedAt),
            canRefresh: (division != null),
            canBulkSave: _buildVisibleCards().isNotEmpty,
            onRefresh: _handleRefresh,
            onBulkSave: _bulkSaveVisible,
          ),
          const SizedBox(height: 12),
          _buildControls(context),
          const SizedBox(height: 12),
          Expanded(child: _buildCardsArea(context, division)),
        ],
      ),
    );

    if (!widget.asBottomSheet) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('출차 통계'),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
          surfaceTintColor: Colors.white,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: Colors.black.withOpacity(0.06)),
          ),
        ),
        body: body,
      );
    }

    return _SheetScaffold(
      title: '출차 통계',
      onClose: () => Navigator.of(context).maybePop(),
      body: body,
    );
  }

  Widget _buildControls(BuildContext context) {
    final canPickArea = _areaOptions.isNotEmpty;
    final visibleCards = _buildVisibleCards();

    final selectedDateLabel = () {
      if (_dateMode == _DateMode.single) {
        if (_selectedDates.isEmpty) return '날짜를 선택하세요';
        final list = _selectedDates.toList()..sort((a, b) => a.compareTo(b));
        if (list.length == 1) return _fmtDateKey(list.first);
        return '${_fmtDateKey(list.first)} 외 ${list.length - 1}개';
      } else {
        if (_range == null) return '조회 기간을 선택하세요';
        return '${_fmtDateKey(_range!.start)} ~ ${_fmtDateKey(_range!.end)}';
      }
    }();

    final dropdown = DropdownButtonFormField<String>(
      isExpanded: true,
      value: (_selectedArea != null && canPickArea && _areaOptions.contains(_selectedArea)) ? _selectedArea : null,
      hint: Text(
        canPickArea ? '지역을 선택하세요' : '캐시된 지역이 없습니다 (새로고침 필요)',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      selectedItemBuilder: (ctx) {
        return _areaOptions
            .map(
              (a) => Align(
            alignment: Alignment.centerLeft,
            child: Text(
              a,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
            .toList();
      },
      items: _areaOptions
          .map(
            (a) => DropdownMenuItem<String>(
          value: a,
          child: Text(
            a,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      )
          .toList(),
      onChanged: canPickArea
          ? (val) async {
        setState(() {
          _selectedArea = val;
          _selectedDates = <DateTime>{};
          _range = null;
          _pageIndex = 0;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_pageCtrl.hasClients) _pageCtrl.jumpToPage(0);
        });

        await _saveUiState();
      }
          : null,
    );

    final modeToggle = ToggleButtons(
      isSelected: <bool>[
        _dateMode == _DateMode.single,
        _dateMode == _DateMode.range,
      ],
      onPressed: (index) async {
        final next = (index == 0) ? _DateMode.single : _DateMode.range;
        if (next == _dateMode) return;

        setState(() {
          _dateMode = next;
          _selectedDates = <DateTime>{};
          _range = null;
          _pageIndex = 0;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_pageCtrl.hasClients) _pageCtrl.jumpToPage(0);
        });

        await _saveUiState();
      },
      borderRadius: BorderRadius.circular(10),
      constraints: const BoxConstraints(minHeight: 40, minWidth: 66),
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
      color: Colors.black.withOpacity(0.65),
      selectedColor: Colors.white,
      fillColor: Colors.black87,
      borderColor: Colors.black.withOpacity(0.18),
      selectedBorderColor: Colors.black87,
      renderBorder: true,
      children: const [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.event, size: 18),
              SizedBox(width: 6),
              Text('단일'),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.date_range, size: 18),
              SizedBox(width: 6),
              Text('기간'),
            ],
          ),
        ),
      ],
    );

    final pickDateBtn = Tooltip(
      message: (_dateMode == _DateMode.single) ? '날짜(복수) 선택' : '기간 선택',
      child: FilledButton(
        onPressed: (_selectedArea == null)
            ? null
            : () {
          if (_dateMode == _DateMode.single) {
            _pickMultiDates();
          } else {
            _pickRange();
          }
        },
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          minimumSize: const Size(40, 40),
        ),
        child: const Icon(Icons.calendar_today, size: 20),
      ),
    );

    final graphBtn = Tooltip(
      message: '그래프',
      child: FilledButton(
        onPressed: _savedReports.isNotEmpty ? _openGraph : null,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          minimumSize: const Size(40, 40),
        ),
        child: const Icon(Icons.bar_chart, size: 20),
      ),
    );

    final clearBtn = Tooltip(
      message: '보관 초기화',
      child: FilledButton.tonal(
        onPressed: _savedReports.isNotEmpty ? _clearSaved : null,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          minimumSize: const Size(40, 40),
        ),
        child: const Icon(Icons.delete_outline, size: 20),
      ),
    );

    final oneRowControls = Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: modeToggle,
            ),
          ),
        ),
        const SizedBox(width: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              pickDateBtn,
              const SizedBox(width: 6),
              graphBtn,
              const SizedBox(width: 6),
              clearBtn,
            ],
          ),
        ),
      ],
    );

    return Column(
      children: [
        dropdown,
        const SizedBox(height: 10),
        oneRowControls,
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '선택: $selectedDateLabel',
            style: TextStyle(
              color: Colors.black.withOpacity(0.65),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (_selectedArea != null) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '표시 카드: ${visibleCards.length}개',
              style: TextStyle(
                color: Colors.black.withOpacity(0.45),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCardsArea(BuildContext context, String? division) {
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
          ),
        ),
      );
    }

    if (division.trim().isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'SharedPreferences에 division 값이 없습니다.\n'
                'division을 저장한 뒤 다시 시도하세요.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_refreshError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Firestore 갱신 오류: $_refreshError',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_cacheByArea.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _hasLocalCache
                ? '표시할 데이터가 없습니다.'
                : '저장된 데이터(로컬 캐시)가 없습니다.\n'
                '우측 상단 새로고침으로 데이터를 가져오세요.\n\n',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_selectedArea == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            '지역을 선택하세요.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final visible = _buildVisibleCards();
    if (visible.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            '선택 조건에 해당하는 보고 내용이 없습니다.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    _ensureValidPage(visible.length);

    return Stack(
      children: [
        PageView.builder(
          controller: _pageCtrl,
          itemCount: visible.length,
          onPageChanged: (i) => setState(() => _pageIndex = i),
          itemBuilder: (context, i) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: _buildReportCard(visible[i]),
            );
          },
        ),
        Positioned(
          top: 0,
          right: 0,
          child: Container(
            margin: const EdgeInsets.only(top: 6, right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.92),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.black.withOpacity(0.08)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Text(
              '${_pageIndex + 1} / ${visible.length}',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: Colors.black.withOpacity(0.75),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReportCard(Map<String, dynamic> day) {
    final vc = _asMap(day['vehicleCount']);
    final metrics = _asMap(day['metrics']);

    final dateStr = (day['date'] ?? '').toString().trim();
    final createdAt = day['createdAt']?.toString();
    final uploadedBy = day['uploadedBy']?.toString();

    final outCount = _asInt(day['vehicleOutput'] ?? vc?['vehicleOutput'] ?? day['vehicleInput'] ?? vc?['vehicleInput']);
    final lockedFee = _asInt(day['totalLockedFee'] ?? vc?['totalLockedFee'] ?? metrics?['snapshot_totalLockedFee']);

    final outText = outCount?.toString() ?? '정보 없음';
    final feeText = lockedFee?.toString() ?? '정보 없음';

    final alreadySaved = _savedReports.any((r) => r['date']?.toString() == dateStr);

    return Card(
      elevation: 1,
      color: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.black.withOpacity(0.08)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            '📊 통계 결과',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                          ),
                          const Spacer(),
                          if (alreadySaved)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.04),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: Colors.black.withOpacity(0.08)),
                              ),
                              child: Text(
                                '보관됨',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: Colors.black.withOpacity(0.6),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '📅 날짜: ${dateStr.isEmpty ? "-" : dateStr}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.black.withOpacity(0.55)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '🕒 업로드: ${createdAt ?? "-"} / 👤 ${uploadedBy ?? "-"}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.black.withOpacity(0.55)),
                      ),
                      const Divider(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('🚙 출차 차량 수', style: TextStyle(fontSize: 15)),
                          Text(outText, style: const TextStyle(fontWeight: FontWeight.w900)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('🔒 정산 금액', style: TextStyle(fontSize: 15)),
                          Text('₩$feeText', style: const TextStyle(fontWeight: FontWeight.w900)),
                        ],
                      ),
                      const Spacer(),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          onPressed: (dateStr.isEmpty || alreadySaved)
                              ? null
                              : () {
                            final vc2 = _asMap(day['vehicleCount']);
                            final metrics2 = _asMap(day['metrics']);

                            final outC = _asInt(day['vehicleOutput'] ?? vc2?['vehicleOutput'] ?? day['vehicleInput'] ?? vc2?['vehicleInput']) ?? 0;
                            final feeC = _asInt(
                              day['totalLockedFee'] ??
                                  vc2?['totalLockedFee'] ??
                                  metrics2?['snapshot_totalLockedFee'],
                            ) ??
                                0;

                            setState(() {
                              _savedReports.add({
                                'date': dateStr,
                                '출차': outC,
                                '정산금': feeC,
                              });
                            });
                          },
                          child: const Text('보관'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MultiDatePickerDialog extends StatefulWidget {
  const _MultiDatePickerDialog({
    required this.initialSelected,
    required this.firstDate,
    required this.lastDate,
    required this.initialMonth,
  });

  final Set<DateTime> initialSelected;
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime initialMonth;

  @override
  State<_MultiDatePickerDialog> createState() => _MultiDatePickerDialogState();
}

class _MultiDatePickerDialogState extends State<_MultiDatePickerDialog> {
  static final DateFormat _fmtMonth = DateFormat('yyyy년 M월');
  static final DateFormat _fmtChip = DateFormat('MM.dd');
  static const List<String> _wk = <String>['월', '화', '수', '목', '금', '토', '일'];

  late DateTime _month;
  late Set<DateTime> _selected;

  DateTime _normalize(DateTime dt) => DateTime(dt.year, dt.month, dt.day);
  DateTime _monthStart(DateTime dt) => DateTime(dt.year, dt.month, 1);

  int _daysInMonth(DateTime month) {
    final next = (month.month == 12)
        ? DateTime(month.year + 1, 1, 1)
        : DateTime(month.year, month.month + 1, 1);
    return next.subtract(const Duration(days: 1)).day;
  }

  DateTime _addMonths(DateTime monthStart, int delta) => DateTime(monthStart.year, monthStart.month + delta, 1);
  bool _sameMonth(DateTime a, DateTime b) => a.year == b.year && a.month == b.month;

  @override
  void initState() {
    super.initState();
    _month = _monthStart(widget.initialMonth);
    _selected = widget.initialSelected.map(_normalize).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final first = _normalize(widget.firstDate);
    final last = _normalize(widget.lastDate);

    final minMonth = _monthStart(first);
    final maxMonth = _monthStart(last);

    final canPrev = _addMonths(_month, -1).isAfter(minMonth) || _sameMonth(_addMonths(_month, -1), minMonth);
    final canNext = _addMonths(_month, 1).isBefore(maxMonth) || _sameMonth(_addMonths(_month, 1), maxMonth);

    final days = _daysInMonth(_month);
    final firstWeekday = _month.weekday;
    final leadingEmpty = (firstWeekday + 6) % 7;

    const totalCells = 42;
    final maxH = MediaQuery.of(context).size.height * 0.76;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 420, maxHeight: maxH),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.event_available_rounded),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '날짜 선택(복수)',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                  ),
                  TextButton(
                    onPressed: _selected.isEmpty
                        ? null
                        : () => setState(() {
                      _selected.clear();
                    }),
                    child: const Text('전체 해제'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    tooltip: '이전 달',
                    onPressed: canPrev ? () => setState(() => _month = _addMonths(_month, -1)) : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        _fmtMonth.format(_month),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '다음 달',
                    onPressed: canNext ? () => setState(() => _month = _addMonths(_month, 1)) : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: List.generate(7, (i) {
                  return Expanded(
                    child: Center(
                      child: Text(
                        _wk[i],
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Colors.black.withOpacity(0.55),
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                  ),
                  itemCount: totalCells,
                  itemBuilder: (context, index) {
                    final cell = index - leadingEmpty;
                    if (cell < 0 || cell >= days) return const SizedBox.shrink();

                    final dt = DateTime(_month.year, _month.month, cell + 1);
                    final d = _normalize(dt);

                    final disabled = d.isBefore(first) || d.isAfter(last);
                    final selected = _selected.contains(d);

                    return _CalendarDayCell(
                      day: d.day,
                      disabled: disabled,
                      selected: selected,
                      inRange: false,
                      rangeStart: false,
                      rangeEnd: false,
                      onTap: disabled
                          ? null
                          : () {
                        setState(() {
                          if (selected) {
                            _selected.remove(d);
                          } else {
                            _selected.add(d);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '선택 ${_selected.length}개',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Colors.black.withOpacity(0.7),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 40,
                child: _selected.isEmpty
                    ? Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '날짜를 탭해서 선택하세요.',
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.45),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
                    : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: (_selected.toList()..sort((a, b) => a.compareTo(b)))
                        .map(
                          (d) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InputChip(
                          label: Text(_fmtChip.format(d)),
                          onDeleted: () => setState(() => _selected.remove(d)),
                        ),
                      ),
                    )
                        .toList(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      child: const Text('취소'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(_selected),
                      child: const Text('적용'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RangePickerDialog extends StatefulWidget {
  const _RangePickerDialog({
    required this.initialRange,
    required this.firstDate,
    required this.lastDate,
    required this.initialMonth,
  });

  final DateTimeRange initialRange;
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime initialMonth;

  @override
  State<_RangePickerDialog> createState() => _RangePickerDialogState();
}

class _RangePickerDialogState extends State<_RangePickerDialog> {
  static final DateFormat _fmtMonth = DateFormat('yyyy년 M월');
  static final DateFormat _fmtChip = DateFormat('MM.dd');
  static const List<String> _wk = <String>['월', '화', '수', '목', '금', '토', '일'];

  late DateTime _month;
  DateTime? _start;
  DateTime? _end;

  DateTime _normalize(DateTime dt) => DateTime(dt.year, dt.month, dt.day);
  DateTime _monthStart(DateTime dt) => DateTime(dt.year, dt.month, 1);

  int _daysInMonth(DateTime month) {
    final next = (month.month == 12)
        ? DateTime(month.year + 1, 1, 1)
        : DateTime(month.year, month.month + 1, 1);
    return next.subtract(const Duration(days: 1)).day;
  }

  DateTime _addMonths(DateTime monthStart, int delta) => DateTime(monthStart.year, monthStart.month + delta, 1);
  bool _sameMonth(DateTime a, DateTime b) => a.year == b.year && a.month == b.month;

  bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  int _inclusiveDays(DateTime s, DateTime e) {
    final diff = _normalize(e).difference(_normalize(s)).inDays;
    return diff.abs() + 1;
  }

  @override
  void initState() {
    super.initState();
    _month = _monthStart(widget.initialMonth);
    _start = _normalize(widget.initialRange.start);
    _end = _normalize(widget.initialRange.end);
  }

  void _reset() {
    setState(() {
      _start = null;
      _end = null;
    });
  }

  void _tapDay(DateTime d) {
    final dd = _normalize(d);

    if (_start == null || (_start != null && _end != null)) {
      setState(() {
        _start = dd;
        _end = null;
      });
      return;
    }

    if (_start != null && _end == null) {
      if (_isSameDay(dd, _start!)) {
        setState(() {
          _start = null;
          _end = null;
        });
        return;
      }

      if (dd.isBefore(_start!)) {
        setState(() {
          _start = dd;
          _end = null;
        });
      } else {
        setState(() {
          _end = dd;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final first = _normalize(widget.firstDate);
    final last = _normalize(widget.lastDate);

    final minMonth = _monthStart(first);
    final maxMonth = _monthStart(last);

    final canPrev = _addMonths(_month, -1).isAfter(minMonth) || _sameMonth(_addMonths(_month, -1), minMonth);
    final canNext = _addMonths(_month, 1).isBefore(maxMonth) || _sameMonth(_addMonths(_month, 1), maxMonth);

    final days = _daysInMonth(_month);
    final firstWeekday = _month.weekday;
    final leadingEmpty = (firstWeekday + 6) % 7;

    const totalCells = 42;
    final maxH = MediaQuery.of(context).size.height * 0.76;

    final canApply = _start != null;

    final chipLine = () {
      if (_start == null) return '기간을 선택하세요.';
      if (_end == null) return '시작: ${_fmtChip.format(_start!)} (종료일 선택)';
      final daysCount = _inclusiveDays(_start!, _end!);
      return '${_fmtChip.format(_start!)} ~ ${_fmtChip.format(_end!)} ($daysCount일)';
    }();

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 420, maxHeight: maxH),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.date_range_rounded),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '기간 선택',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                  ),
                  TextButton(
                    onPressed: (canApply) ? _reset : null,
                    child: const Text('초기화'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    tooltip: '이전 달',
                    onPressed: canPrev ? () => setState(() => _month = _addMonths(_month, -1)) : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        _fmtMonth.format(_month),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '다음 달',
                    onPressed: canNext ? () => setState(() => _month = _addMonths(_month, 1)) : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: List.generate(7, (i) {
                  return Expanded(
                    child: Center(
                      child: Text(
                        _wk[i],
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Colors.black.withOpacity(0.55),
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                  ),
                  itemCount: totalCells,
                  itemBuilder: (context, index) {
                    final cell = index - leadingEmpty;
                    if (cell < 0 || cell >= days) return const SizedBox.shrink();

                    final dt = DateTime(_month.year, _month.month, cell + 1);
                    final d = _normalize(dt);

                    final disabled = d.isBefore(first) || d.isAfter(last);

                    final hasStart = _start != null;
                    final hasEnd = _end != null;

                    final isStart = hasStart && _isSameDay(d, _start!);
                    final isEnd = hasEnd && _isSameDay(d, _end!);

                    bool inRange = false;
                    if (hasStart && hasEnd) {
                      final s = _start!;
                      final e = _end!;
                      inRange = (d.isAfter(s) && d.isBefore(e)) || isStart || isEnd;
                      if (e.isBefore(s)) {
                        inRange = (d.isAfter(e) && d.isBefore(s)) || isStart || isEnd;
                      }
                    }

                    final selected = isStart || isEnd;

                    return _CalendarDayCell(
                      day: d.day,
                      disabled: disabled,
                      selected: selected,
                      inRange: inRange,
                      rangeStart: isStart,
                      rangeEnd: isEnd,
                      onTap: disabled ? null : () => _tapDay(d),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  chipLine,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Colors.black.withOpacity(0.7),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 40,
                child: (!canApply)
                    ? Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '시작일과 종료일을 탭해서 선택하세요.',
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.45),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
                    : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      InputChip(
                        label: Text('시작 ${_fmtChip.format(_start!)}'),
                        onDeleted: () => setState(() {
                          _start = null;
                          _end = null;
                        }),
                      ),
                      const SizedBox(width: 8),
                      if (_end != null)
                        InputChip(
                          label: Text('종료 ${_fmtChip.format(_end!)}'),
                          onDeleted: () => setState(() {
                            _end = null;
                          }),
                        )
                      else
                        const InputChip(
                          label: Text('종료 미선택'),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      child: const Text('취소'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: canApply
                          ? () {
                        final s = _start!;
                        final e = _end ?? _start!;
                        Navigator.of(context).pop(DateTimeRange(start: s, end: e));
                      }
                          : null,
                      child: const Text('적용'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({
    required this.day,
    required this.disabled,
    required this.selected,
    required this.inRange,
    required this.rangeStart,
    required this.rangeEnd,
    required this.onTap,
  });

  final int day;
  final bool disabled;
  final bool selected;
  final bool inRange;
  final bool rangeStart;
  final bool rangeEnd;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool isStrong = !disabled && (selected || rangeStart || rangeEnd);
    final bool isSoftRange = !disabled && !isStrong && inRange;

    final fg = disabled
        ? Colors.black.withOpacity(0.25)
        : (isStrong ? Colors.white : Colors.black.withOpacity(0.75));

    final bg = disabled
        ? Colors.black.withOpacity(0.02)
        : (isStrong ? Colors.black87 : (isSoftRange ? Colors.black.withOpacity(0.08) : Colors.white));

    final border = disabled
        ? Colors.black.withOpacity(0.06)
        : (isStrong ? Colors.black87 : Colors.black.withOpacity(0.10));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          ),
          alignment: Alignment.center,
          child: Text(
            '$day',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(Icons.info_outline_rounded, size: 22),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '업무 통계 확인 시트입니다.',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.today,
    required this.refreshLoading,
    required this.refreshError,
    required this.lastUpdated,
    required this.canRefresh,
    required this.canBulkSave,
    required this.onRefresh,
    required this.onBulkSave,
  });

  final String today;
  final bool refreshLoading;
  final Object? refreshError;
  final String? lastUpdated;
  final bool canRefresh;
  final bool canBulkSave;
  final VoidCallback onRefresh;
  final VoidCallback onBulkSave;

  @override
  Widget build(BuildContext context) {
    String subLine = '$today입니다.';
    if (refreshLoading) subLine = '데이터 갱신 중...';
    if (refreshError != null) subLine = '갱신 오류';

    final hintLine = (lastUpdated != null) ? '마지막 갱신: $lastUpdated' : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.72),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (hintLine != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    hintLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w700),
                  ),
                ],
              ],
            ),
          ),
          Tooltip(
            message: '새로고침',
            child: FilledButton(
              onPressed: (!canRefresh || refreshLoading) ? null : onRefresh,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                minimumSize: const Size(44, 44),
              ),
              child: refreshLoading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh, size: 20),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: '일괄 보관',
            child: FilledButton(
              onPressed: canBulkSave ? onBulkSave : null,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.black87,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                minimumSize: const Size(44, 44),
              ),
              child: const Icon(Icons.library_add_check_outlined, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

class _NinetyTwoPercentBottomSheetFrame extends StatelessWidget {
  const _NinetyTwoPercentBottomSheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.92,
      widthFactor: 1.0,
      child: SafeArea(
        top: true,
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              boxShadow: [
                BoxShadow(
                  blurRadius: 24,
                  spreadRadius: 8,
                  color: Color(0x33000000),
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Material(
                color: Colors.white,
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
    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.12),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          trailing: IconButton(
            tooltip: '닫기',
            icon: const Icon(Icons.close_rounded),
            onPressed: onClose,
          ),
        ),
        const Divider(height: 1),
        Expanded(child: body),
      ],
    );
  }
}
