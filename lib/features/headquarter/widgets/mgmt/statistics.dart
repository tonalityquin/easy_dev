import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/models/capability.dart';
import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../../design_system/common_ui/common_ui_side_dock.dart';
import '../../../../design_system/common_ui/common_ui_side_dock_content_dialog.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../dashboard/domain/models/end_work_sector_metrics.dart';
import '../../../dashboard/domain/repositories/end_work_report_repository.dart';
import '../../../selector/application/dev_auth.dart';
import '../../application/area/area_master_cache.dart';
import 'statistics_chart_page.dart';
import 'statistics_deep_log_service.dart';

enum _DateMode { single, range }

enum StatisticsPresentation { page, leftSideDock }

enum _StatisticsDockView { main, areaPicker, multiDatePicker, rangePicker }

class Statistics extends StatefulWidget {
  const Statistics({
    super.key,
    this.presentation = StatisticsPresentation.page,
  });

  final StatisticsPresentation presentation;

  static Future<T?> showAsLeftSideDock<T>(
    BuildContext context, {
    bool useRootNavigator = false,
  }) async {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    debugPrint(
      '[Statistics] side_dock_push_request side=left motion=operations_210_190 translate=-22_to_0 opacity=0.90_to_1 reduceMotion=$reduceMotion',
    );
    try {
      return await showOperationsLeftSideDock<T>(
        context: context,
        barrierLabel: '통계 비교',
        useRootNavigator: useRootNavigator,
        maxWidth: 360,
        widthFactor: 0.92,
        barrierDismissible: true,
        builder: (_) => const Statistics(
          presentation: StatisticsPresentation.leftSideDock,
        ),
      );
    } finally {
      debugPrint('[Statistics] side_dock_closed side=left');
    }
  }

  @override
  State<Statistics> createState() => _StatisticsState();
}

class _StatisticsState extends State<Statistics> {
  static const String _kDivisionPrefsKey = 'division';
  static const String _kMonthCachePrefix = 'statistics_month_cache_v1:';
  static const String _kLastAreaKey = 'statistics_last_area_v1';
  static const String _kLastModeKey = 'statistics_last_mode_v1';
  static const String _kLastDatesKey = 'statistics_last_dates_v1';
  static const String _kLastRangeKey = 'statistics_last_range_v1';

  final EndWorkReportRepository _reportRepo = EndWorkReportRepository();
  final List<String> _debugLines = <String>[];
  final Map<String, Map<String, Map<String, dynamic>>> _cacheByArea =
      <String, Map<String, Map<String, dynamic>>>{};
  final Map<String, DateTime> _monthCachedAt = <String, DateTime>{};
  final Set<String> _loadedMonthKeys = <String>{};
  final List<Map<String, dynamic>> _savedReports = <Map<String, dynamic>>[];

  String? _division;
  Object? _loadError;
  Object? _refreshError;
  String? _selectedArea;
  DateTime? _cachedAt;
  bool _refreshLoading = false;
  bool _developerMode = false;
  bool _queryDirty = false;
  _DateMode _dateMode = _DateMode.single;
  _StatisticsDockView _dockView = _StatisticsDockView.main;
  Set<DateTime> _selectedDates = <DateTime>{};
  DateTimeRange? _range;
  List<String> _areaOptions = <String>[];
  Map<String, bool> _areaSectorEnabled = <String, bool>{};
  int _localCacheHits = 0;
  int _firestoreMonthReadsRequested = 0;
  int _queryCount = 0;
  List<String> _lastQueryMonths = <String>[];

  static final DateFormat _fmtDateKeyBase = DateFormat('yyyy-MM-dd');
  static final DateFormat _fmtUpdatedBase = DateFormat('yyyy.MM.dd HH:mm');

  bool get _useCommonUi =>
      widget.presentation == StatisticsPresentation.leftSideDock;

  String _fmtDateKey(DateTime date) => _fmtDateKeyBase.format(date);

  DateTime _normalizeDate(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  int? _asInt(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) {
      return int.tryParse(value.replaceAll(',', '').trim());
    }
    return null;
  }

  List<String> _asStringList(dynamic value) {
    if (value is! Iterable) return const <String>[];
    final result = <String>[];
    for (final item in value) {
      final text = item?.toString().trim() ?? '';
      if (text.isEmpty || result.contains(text)) continue;
      result.add(text);
    }
    return List<String>.unmodifiable(result);
  }

  dynamic _jsonify(Object? value) {
    if (value == null) return null;
    try {
      final seconds = (value as dynamic).seconds;
      final nanoseconds = (value as dynamic).nanoseconds;
      if (seconds is int && nanoseconds is int) {
        return <String, dynamic>{
          'seconds': seconds,
          'nanoseconds': nanoseconds,
        };
      }
    } catch (_) {}
    if (value is String || value is num || value is bool) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), _jsonify(item)));
    }
    if (value is Iterable) return value.map(_jsonify).toList();
    return value.toString();
  }

  @override
  void initState() {
    super.initState();
    _developerMode = DevAuth.devModeEnabled.value;
    DevAuth.devModeEnabled.addListener(_handleDeveloperModeChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _recordDebug(
        'initialized presentation=${widget.presentation.name} developerMode=$_developerMode',
      );
      unawaited(_refreshDeveloperMode());
      unawaited(_loadInitialState());
    });
  }

  @override
  void dispose() {
    DevAuth.devModeEnabled.removeListener(_handleDeveloperModeChanged);
    super.dispose();
  }

  void _handleDeveloperModeChanged() {
    final enabled = DevAuth.devModeEnabled.value;
    if (!mounted || enabled == _developerMode) return;
    setState(() => _developerMode = enabled);
    _recordDebug('developer_mode_notifier=$enabled');
  }

  Future<void> _refreshDeveloperMode() async {
    final enabled = await DevAuth.isDevModeEnabled();
    if (!mounted) return;
    _recordDebug('developer_mode=$enabled');
    if (enabled == _developerMode) return;
    setState(() => _developerMode = enabled);
  }

  void _recordDebug(String message) {
    final line = '[Statistics] $message';
    _debugLines.add(line);
    if (_debugLines.length > 180) {
      _debugLines.removeRange(0, _debugLines.length - 180);
    }
    debugPrint(line);
  }

  String _monthKey(DateTime value) =>
      '${value.year}${value.month.toString().padLeft(2, '0')}';

  String _monthCacheKey({
    required String division,
    required String area,
    required String monthKey,
  }) {
    return '$_kMonthCachePrefix$division|$area|$monthKey';
  }

  Set<String> _selectedMonthKeys() {
    if (_dateMode == _DateMode.single) {
      return _selectedDates.map(_monthKey).toSet();
    }
    final range = _range;
    if (range == null) return <String>{};
    final start = _normalizeDate(range.start);
    final end = _normalizeDate(range.end);
    final first = start.isAfter(end) ? end : start;
    final last = start.isAfter(end) ? start : end;
    final result = <String>{};
    var cursor = DateTime(first.year, first.month, 1);
    final stop = DateTime(last.year, last.month, 1);
    while (!cursor.isAfter(stop)) {
      result.add(_monthKey(cursor));
      cursor = cursor.month == 12
          ? DateTime(cursor.year + 1, 1, 1)
          : DateTime(cursor.year, cursor.month + 1, 1);
    }
    return result;
  }

  String _cacheIdentity(String area, String monthKey) => '$area|$monthKey';

  Future<void> _loadInitialState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final division = (prefs.getString(_kDivisionPrefsKey) ?? '').trim();
      final lastArea = (prefs.getString(_kLastAreaKey) ?? '').trim();
      final lastMode = (prefs.getString(_kLastModeKey) ?? '').trim();
      final restoredMode =
          lastMode == 'range' ? _DateMode.range : _DateMode.single;
      final restoredDates = <DateTime>{};
      for (final raw in prefs.getStringList(_kLastDatesKey) ?? const <String>[]) {
        final parsed = DateTime.tryParse(raw);
        if (parsed != null) restoredDates.add(_normalizeDate(parsed));
      }
      DateTimeRange? restoredRange;
      final rangeRaw = prefs.getStringList(_kLastRangeKey);
      if (rangeRaw != null && rangeRaw.length == 2) {
        final start = DateTime.tryParse(rangeRaw[0]);
        final end = DateTime.tryParse(rangeRaw[1]);
        if (start != null && end != null) {
          restoredRange = DateTimeRange(
            start: _normalizeDate(start),
            end: _normalizeDate(end),
          );
        }
      }

      final snapshot = await AreaMasterCache.readSnapshot(division);
      final options = <String>[];
      final sectorEnabled = <String, bool>{};
      if (snapshot != null) {
        for (final item in snapshot.items) {
          final name = item.name.trim();
          if (name.isEmpty || options.contains(name)) continue;
          options.add(name);
          sectorEnabled[name] = item.capabilities.contains(Capability.sector);
        }
      }
      if (lastArea.isNotEmpty && !options.contains(lastArea)) {
        options.add(lastArea);
        sectorEnabled.putIfAbsent(lastArea, () => false);
      }
      options.sort();

      if (!mounted) return;
      setState(() {
        _division = division;
        _loadError = null;
        _areaOptions = options;
        _areaSectorEnabled = sectorEnabled;
        _selectedArea = lastArea.isNotEmpty && options.contains(lastArea)
            ? lastArea
            : null;
        _dateMode = restoredMode;
        _selectedDates = restoredMode == _DateMode.single
            ? restoredDates
            : <DateTime>{};
        _range = restoredMode == _DateMode.range ? restoredRange : null;
      });

      await _ensureLocalMonthsForSelection();
      if (!mounted) return;
      final hasConditions =
          (_selectedArea ?? '').trim().isNotEmpty && _selectedMonthKeys().isNotEmpty;
      if (hasConditions && _buildVisibleCards().isEmpty) {
        unawaited(_handleQuery());
      }
      _recordDebug(
        'initial division=$division areas=${options.length} selectedArea=${_selectedArea ?? '-'} mode=${_dateMode.name} months=${_selectedMonthKeys().join(',')} localMonths=${_loadedMonthKeys.length}',
      );
    } catch (error, stackTrace) {
      dev.log(
        '[STAT] initial load failed',
        name: 'Statistics',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _division = '';
        _loadError = error;
      });
      _recordDebug('initial_error=$error');
    }
  }

  Future<void> _saveUiState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastAreaKey, (_selectedArea ?? '').trim());
    await prefs.setString(
      _kLastModeKey,
      _dateMode == _DateMode.range ? 'range' : 'single',
    );
    final dates = _selectedDates.map(_fmtDateKey).toList()..sort();
    await prefs.setStringList(_kLastDatesKey, dates);
    final range = _range;
    if (range == null) {
      await prefs.remove(_kLastRangeKey);
    } else {
      await prefs.setStringList(
        _kLastRangeKey,
        <String>[_fmtDateKey(range.start), _fmtDateKey(range.end)],
      );
    }
  }

  Future<void> _ensureLocalMonthsForSelection() async {
    final division = (_division ?? '').trim();
    final area = (_selectedArea ?? '').trim();
    final months = _selectedMonthKeys().toList()..sort();
    if (division.isEmpty || area.isEmpty || months.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final byDate = _cacheByArea.putIfAbsent(
      area,
      () => <String, Map<String, dynamic>>{},
    );
    var latest = _cachedAt;
    for (final monthKey in months) {
      final identity = _cacheIdentity(area, monthKey);
      if (_loadedMonthKeys.contains(identity)) continue;
      final raw = prefs.getString(
        _monthCacheKey(
          division: division,
          area: area,
          monthKey: monthKey,
        ),
      );
      if (raw == null || raw.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        final cachedAtMs = decoded['cachedAtMs'];
        DateTime? cachedAt;
        if (cachedAtMs is int) {
          cachedAt = DateTime.fromMillisecondsSinceEpoch(cachedAtMs).toLocal();
          _monthCachedAt[identity] = cachedAt;
          if (latest == null || cachedAt.isAfter(latest)) latest = cachedAt;
        }
        final days = decoded['days'];
        if (days is Map) {
          for (final entry in days.entries) {
            final day = _asMap(entry.value);
            if (day == null) continue;
            byDate[entry.key.toString()] = Map<String, dynamic>.from(day);
          }
        }
        _loadedMonthKeys.add(identity);
        _localCacheHits++;
        _recordDebug(
          'month_cache_hit area=$area month=$monthKey days=${days is Map ? days.length : 0}',
        );
      } catch (error) {
        _recordDebug('month_cache_decode_failed area=$area month=$monthKey error=$error');
      }
    }
    if (mounted && latest != _cachedAt) {
      setState(() => _cachedAt = latest);
    }
  }

  Future<void> _saveMonthCache({
    required String division,
    required String area,
    required String monthKey,
    required Map<String, Map<String, dynamic>> areaDays,
    required DateTime cachedAt,
  }) async {
    final days = <String, dynamic>{};
    for (final entry in areaDays.entries) {
      final parsed = DateTime.tryParse(entry.key);
      if (parsed == null || _monthKey(parsed) != monthKey) continue;
      days[entry.key] = _jsonify(entry.value);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _monthCacheKey(
        division: division,
        area: area,
        monthKey: monthKey,
      ),
      jsonEncode(<String, dynamic>{
        'cachedAtMs': cachedAt.millisecondsSinceEpoch,
        'days': days,
      }),
    );
  }

  Future<void> _handleQuery({bool forceRemote = false}) async {
    if (_refreshLoading) return;
    final division = (_division ?? '').trim();
    final area = (_selectedArea ?? '').trim();
    final months = _selectedMonthKeys().toList()..sort();
    if (division.isEmpty || area.isEmpty || months.isEmpty) {
      setState(() => _queryDirty = true);
      _recordDebug(
        'query_aborted division=$division area=$area months=${months.length}',
      );
      return;
    }

    await _ensureLocalMonthsForSelection();
    final requested = forceRemote
        ? months
        : months
            .where(
              (month) => !_loadedMonthKeys.contains(_cacheIdentity(area, month)),
            )
            .toList();
    _queryCount++;
    _lastQueryMonths = List<String>.of(months);
    if (requested.isEmpty) {
      if (!mounted) return;
      setState(() {
        _queryDirty = false;
        _refreshError = null;
      });
      _recordDebug(
        'query_cache_only area=$area months=${months.join(',')} localHits=$_localCacheHits',
      );
      return;
    }

    setState(() {
      _refreshLoading = true;
      _refreshError = null;
    });
    _firestoreMonthReadsRequested += requested.length;
    _recordDebug(
      'query_remote_start area=$area months=${requested.join(',')} firestoreMonthReads=${requested.length} force=$forceRemote',
    );

    try {
      final fetched = await _reportRepo.loadAreaMonths(
        division: division,
        area: area,
        monthKeys: requested,
      );
      final target = _cacheByArea.putIfAbsent(
        area,
        () => <String, Map<String, dynamic>>{},
      );
      for (final month in requested) {
        target.removeWhere((date, _) {
          final parsed = DateTime.tryParse(date);
          return parsed != null && _monthKey(parsed) == month;
        });
      }
      target.addAll(fetched);
      final now = DateTime.now().toLocal();
      for (final month in requested) {
        final identity = _cacheIdentity(area, month);
        _loadedMonthKeys.add(identity);
        _monthCachedAt[identity] = now;
        await _saveMonthCache(
          division: division,
          area: area,
          monthKey: month,
          areaDays: target,
          cachedAt: now,
        );
      }
      if (!mounted) return;
      setState(() {
        _cachedAt = now;
        _refreshLoading = false;
        _refreshError = null;
        _queryDirty = false;
      });
      _recordDebug(
        'query_remote_complete area=$area months=${requested.join(',')} days=${fetched.length} visible=${_buildVisibleCards().length}',
      );
    } catch (error, stackTrace) {
      dev.log(
        '[STAT] direct month query failed',
        name: 'Statistics',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _refreshLoading = false;
        _refreshError = error;
      });
      _recordDebug('query_remote_failed area=$area error=$error');
    }
  }

  bool _isStatisticsEligibleDay(Map<String, dynamic> day) {
    if (day['_statisticsEligible'] != true) return false;
    return _asStringList(day['_historyLogsUrls']).isNotEmpty;
  }

  EndWorkSectorMetrics? _sectorMetricsFromDay(Map<String, dynamic> day) {
    final metrics = _asMap(day['metrics']);
    final sector = EndWorkSectorMetrics.fromDynamic(metrics?['sector']);
    if (sector == null || !sector.enabled) return null;
    return sector;
  }

  List<Map<String, dynamic>> _buildVisibleCards() {
    final area = (_selectedArea ?? '').trim();
    if (area.isEmpty) return <Map<String, dynamic>>[];
    final byDate = _cacheByArea[area];
    if (byDate == null || byDate.isEmpty) return <Map<String, dynamic>>[];
    if (_dateMode == _DateMode.single) {
      final dates = _selectedDates.toList()..sort();
      return <Map<String, dynamic>>[
        for (final date in dates)
          if (byDate[_fmtDateKey(date)] != null &&
              _isStatisticsEligibleDay(byDate[_fmtDateKey(date)]!))
            byDate[_fmtDateKey(date)]!,
      ];
    }
    final range = _range;
    if (range == null) return <Map<String, dynamic>>[];
    final start = _normalizeDate(range.start);
    final end = _normalizeDate(range.end);
    final first = start.isAfter(end) ? end : start;
    final last = start.isAfter(end) ? start : end;
    final result = <Map<String, dynamic>>[];
    for (final entry in byDate.entries) {
      final parsed = DateTime.tryParse(entry.key);
      if (parsed == null) continue;
      final date = _normalizeDate(parsed);
      if (date.isBefore(first) || date.isAfter(last)) continue;
      if (!_isStatisticsEligibleDay(entry.value)) continue;
      result.add(entry.value);
    }
    result.sort((a, b) {
      final da = DateTime.tryParse(a['date']?.toString() ?? '');
      final db = DateTime.tryParse(b['date']?.toString() ?? '');
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });
    return result;
  }

  Future<T?> _showStatisticsDialog<T>({
    required WidgetBuilder builder,
    bool barrierDismissible = true,
  }) {
    if (_useCommonUi) {
      return showCommonOverlayDialog<T>(
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

  Future<void> _pickMultiDates() async {
    if (_selectedArea == null) return;
    if (_useCommonUi) {
      HapticFeedback.selectionClick();
      setState(() => _dockView = _StatisticsDockView.multiDatePicker);
      _recordDebug('date_picker_open mode=individual presentation=dock');
      return;
    }
    final initial = _selectedDates.isEmpty
        ? DateTime.now()
        : (_selectedDates.toList()..sort()).first;
    final picked = await _showStatisticsDialog<Set<DateTime>>(
      barrierDismissible: false,
      builder: (_) => _MultiDatePickerDialog(
        initialSelected: _selectedDates,
        firstDate: DateTime(2023, 1, 1),
        lastDate: DateTime(2100, 12, 31),
        initialMonth: _normalizeDate(initial),
      ),
    );
    if (!mounted || picked == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selectedDates = picked.map(_normalizeDate).toSet();
      _range = null;
      _queryDirty = true;
    });
    await _saveUiState();
    await _ensureLocalMonthsForSelection();
    _recordDebug('dates_changed mode=individual count=${_selectedDates.length}');
  }

  Future<void> _pickRange() async {
    if (_selectedArea == null) return;
    if (_useCommonUi) {
      HapticFeedback.selectionClick();
      setState(() => _dockView = _StatisticsDockView.rangePicker);
      _recordDebug('date_picker_open mode=range presentation=dock');
      return;
    }
    final now = _normalizeDate(DateTime.now());
    final picked = await _showStatisticsDialog<DateTimeRange>(
      barrierDismissible: false,
      builder: (_) => _RangePickerDialog(
        initialRange: _range ?? DateTimeRange(start: now, end: now),
        firstDate: DateTime(2023, 1, 1),
        lastDate: DateTime(2100, 12, 31),
        initialMonth: _normalizeDate((_range ?? DateTimeRange(start: now, end: now)).start),
      ),
    );
    if (!mounted || picked == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _range = DateTimeRange(
        start: _normalizeDate(picked.start),
        end: _normalizeDate(picked.end),
      );
      _selectedDates = <DateTime>{};
      _queryDirty = true;
    });
    await _saveUiState();
    await _ensureLocalMonthsForSelection();
    _recordDebug(
      'dates_changed mode=range start=${_fmtDateKey(_range!.start)} end=${_fmtDateKey(_range!.end)}',
    );
  }

  void _applyDockMultiDates(Set<DateTime> picked) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedDates = picked.map(_normalizeDate).toSet();
      _range = null;
      _queryDirty = true;
      _dockView = _StatisticsDockView.main;
    });
    unawaited(_saveUiState());
    unawaited(_ensureLocalMonthsForSelection());
    _recordDebug('date_picker_apply mode=individual count=${_selectedDates.length}');
  }

  void _applyDockRange(DateTimeRange picked) {
    HapticFeedback.selectionClick();
    setState(() {
      _range = DateTimeRange(
        start: _normalizeDate(picked.start),
        end: _normalizeDate(picked.end),
      );
      _selectedDates = <DateTime>{};
      _queryDirty = true;
      _dockView = _StatisticsDockView.main;
    });
    unawaited(_saveUiState());
    unawaited(_ensureLocalMonthsForSelection());
    _recordDebug(
      'date_picker_apply mode=range start=${_fmtDateKey(_range!.start)} end=${_fmtDateKey(_range!.end)}',
    );
  }

  void _closeDockPicker() {
    HapticFeedback.selectionClick();
    setState(() => _dockView = _StatisticsDockView.main);
    _recordDebug('date_picker_cancel');
  }

  void _selectArea(String area) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedArea = area;
      _selectedDates = <DateTime>{};
      _range = null;
      _savedReports.clear();
      _queryDirty = true;
      _dockView = _StatisticsDockView.main;
    });
    unawaited(_saveUiState());
    _recordDebug('area_selected area=$area');
  }

  void _setDateMode(_DateMode mode) {
    if (_dateMode == mode) return;
    HapticFeedback.selectionClick();
    setState(() {
      _dateMode = mode;
      _selectedDates = <DateTime>{};
      _range = null;
      _savedReports.clear();
      _queryDirty = true;
    });
    unawaited(_saveUiState());
    _recordDebug('date_mode=${mode.name}');
  }

  Map<String, dynamic> _comparisonPayload(Map<String, dynamic> day) {
    final vc = _asMap(day['vehicleCount']);
    final metrics = _asMap(day['metrics']);
    final sector = _sectorMetricsFromDay(day);
    return <String, dynamic>{
      'date': (day['date'] ?? '').toString(),
      '출차': _asInt(
            day['vehicleOutput'] ??
                vc?['vehicleOutput'] ??
                day['vehicleInput'] ??
                vc?['vehicleInput'],
          ) ??
          0,
      '정산금': _asInt(
            day['totalLockedFee'] ??
                vc?['totalLockedFee'] ??
                metrics?['snapshot_totalLockedFee'],
          ) ??
          0,
      'historyEntryCount': _asInt(day['_historyEntryCount']) ?? 1,
      'historyDetailedEntryCount':
          _asInt(day['_historyDetailedEntryCount']) ?? 0,
      'historyExcludedEntryCount':
          _asInt(day['_historyExcludedEntryCount']) ?? 0,
      'historyFirstEntryCount': _asInt(day['_historyFirstEntryCount']) ?? 0,
      'historyUnverifiedDetailedEntryCount':
          _asInt(day['_historyUnverifiedDetailedEntryCount']) ?? 0,
      'historyLegacyDetailedEntryCount':
          _asInt(day['_historyLegacyDetailedEntryCount']) ?? 0,
      'historyAggregationMode':
          day['_historyAggregationMode']?.toString() ?? 'unknown',
      'historyLogsUrls': _asStringList(day['_historyLogsUrls']),
      'historyAggregated': day['_historyAggregated'] == true,
      'historySectorEntryCount':
          _asInt(day['_historySectorEntryCount']) ?? (sector == null ? 0 : 1),
      if (sector != null) 'sector': sector.toMap(),
    };
  }

  bool _isCompared(String date) =>
      _savedReports.any((item) => item['date']?.toString() == date);

  void _toggleComparison(Map<String, dynamic> day) {
    final date = (day['date'] ?? '').toString().trim();
    if (date.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      final index = _savedReports.indexWhere(
        (item) => item['date']?.toString() == date,
      );
      if (index >= 0) {
        _savedReports.removeAt(index);
      } else {
        _savedReports.add(_comparisonPayload(day));
      }
    });
    _recordDebug('comparison_toggle date=$date selected=${_isCompared(date)} count=${_savedReports.length}');
  }

  void _bulkCompareVisible() {
    final visible = _buildVisibleCards();
    if (visible.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      for (final day in visible) {
        final date = (day['date'] ?? '').toString().trim();
        if (date.isEmpty || _isCompared(date)) continue;
        _savedReports.add(_comparisonPayload(day));
      }
    });
    _recordDebug('comparison_add_all visible=${visible.length} selected=${_savedReports.length}');
  }

  void _clearCompared() {
    HapticFeedback.lightImpact();
    setState(() => _savedReports.clear());
    _recordDebug('comparison_clear');
  }

  void _openGraph() {
    final parsedData = <DateTime, Map<String, dynamic>>{};
    for (final report in _savedReports) {
      final date = DateTime.tryParse(report['date']?.toString() ?? '');
      if (date == null) continue;
      final sector = EndWorkSectorMetrics.fromDynamic(report['sector']);
      parsedData[date] = <String, dynamic>{
        'vehicleOutput': (report['출차'] as int?) ?? 0,
        'totalLockedFee': (report['정산금'] as int?) ?? 0,
        'historyEntryCount': _asInt(report['historyEntryCount']) ?? 1,
        'historyDetailedEntryCount':
            _asInt(report['historyDetailedEntryCount']) ?? 0,
        'historyExcludedEntryCount':
            _asInt(report['historyExcludedEntryCount']) ?? 0,
        'historyFirstEntryCount': _asInt(report['historyFirstEntryCount']) ?? 0,
        'historyUnverifiedDetailedEntryCount':
            _asInt(report['historyUnverifiedDetailedEntryCount']) ?? 0,
        'historyLegacyDetailedEntryCount':
            _asInt(report['historyLegacyDetailedEntryCount']) ?? 0,
        'historyAggregationMode':
            report['historyAggregationMode']?.toString() ?? 'unknown',
        'historyLogsUrls': _asStringList(report['historyLogsUrls']),
        'historyAggregated': report['historyAggregated'] == true,
        'historySectorEntryCount':
            _asInt(report['historySectorEntryCount']) ?? (sector == null ? 0 : 1),
        if (sector != null) 'sector': sector.toMap(),
      };
    }
    if (parsedData.isEmpty) return;
    final page = StatisticsChartPage(
      reportDataMap: parsedData,
      division: (_division ?? '').trim(),
      area: (_selectedArea ?? '').trim(),
      useCommonUi: true,
      availableAreas: List<String>.unmodifiable(_areaOptions),
      areaSectorEnabled: Map<String, bool>.unmodifiable(_areaSectorEnabled),
    );
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _recordDebug(
      'analytics_dock_open selected=${parsedData.length} area=${_selectedArea ?? '-'} width=max1000 factor=.96 reduceMotion=$reduceMotion',
    );
    unawaited(
      showOperationsLeftSideDock<void>(
        context: context,
        barrierLabel: '출차·정산 분석',
        useRootNavigator: false,
        maxWidth: 1000,
        widthFactor: 0.96,
        barrierDismissible: true,
        scrimOpacity: 0,
        builder: (_) => page,
      ).whenComplete(() {
        _recordDebug('analytics_dock_closed');
      }),
    );
  }

  Future<void> _showDeveloperStatus() async {
    if (!_developerMode || !mounted) return;
    final months = _selectedMonthKeys().toList()..sort();
    final visible = _buildVisibleCards();
    final media = MediaQuery.maybeOf(context);
    _recordDebug(
      'developer_status_open presentation=${widget.presentation.name} area=${_selectedArea ?? '-'} months=${months.join(',')} visible=${visible.length} compared=${_savedReports.length} localHits=$_localCacheHits firestoreMonthReads=$_firestoreMonthReadsRequested deepCache=${StatisticsDeepLogService.memoryCacheSize} deepHits=${StatisticsDeepLogService.cacheHits} deepDownloads=${StatisticsDeepLogService.gcsDownloads} deepBytes=${StatisticsDeepLogService.gcsDownloadedBytes} loading=$_refreshLoading error=${_refreshError != null} reduceMotion=${media?.disableAnimations ?? false}',
    );
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '통계 비교 상태',
      initialMessage: '통계 비교와 데이터 비용 상태를 수집하고 있습니다.',
      useCommonUi: true,
      developerModeMessage: '개발자 모드 ON: debugPrint 코드를 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF',
    );
    if (!trace.developerMode) return;
    trace.log(
      'presentation=${widget.presentation.name}, division=${_division ?? '-'}, area=${_selectedArea ?? '-'}, mode=${_dateMode.name}, months=${months.join(',')}, queryDirty=$_queryDirty',
      progress: .16,
    );
    trace.log(
      'visibleDays=${visible.length}, comparedDays=${_savedReports.length}, loadedMonthKeys=${_loadedMonthKeys.length}, localCacheHits=$_localCacheHits, queryCount=$_queryCount, firestoreMonthReadsRequested=$_firestoreMonthReadsRequested, lastQueryMonths=${_lastQueryMonths.join(',')}',
      progress: .32,
    );
    trace.log(
      'refreshLoading=$_refreshLoading, refreshError=${_refreshError ?? '-'}, cachedAt=${_cachedAt?.toIso8601String() ?? '-'}, areaOptions=${_areaOptions.length}, sectorEnabled=${_areaSectorEnabled[_selectedArea] == true}',
      progress: .44,
    );
    trace.log(
      'deepMemoryCache=${StatisticsDeepLogService.memoryCacheSize}, deepCacheHits=${StatisticsDeepLogService.cacheHits}, deepGcsDownloads=${StatisticsDeepLogService.gcsDownloads}, deepGcsBytes=${StatisticsDeepLogService.gcsDownloadedBytes}, reduceMotion=${media?.disableAnimations ?? false}',
      progress: .56,
    );
    final snapshot = List<String>.of(_debugLines);
    if (snapshot.isEmpty) {
      trace.log('기록된 통계 비교 로그가 없습니다.', progress: .9);
    } else {
      for (var i = 0; i < snapshot.length; i++) {
        trace.log(
          snapshot[i],
          progress: .56 + ((i + 1) / snapshot.length) * .38,
        );
      }
    }
    await trace.succeed('통계 비교 상태 수집이 완료되었습니다.');
  }

  String _conditionLabel() {
    if (_dateMode == _DateMode.single) {
      if (_selectedDates.isEmpty) return '날짜를 선택해 주세요';
      final dates = _selectedDates.toList()..sort();
      if (dates.length == 1) return _fmtDateKey(dates.first);
      return '${_fmtDateKey(dates.first)} 외 ${dates.length - 1}일';
    }
    if (_range == null) return '기간을 선택해 주세요';
    return '${_fmtDateKey(_range!.start)} ~ ${_fmtDateKey(_range!.end)}';
  }

  String _dockSubtitle() {
    final area = (_selectedArea ?? '').trim();
    if (area.isEmpty) return '지역과 날짜를 선택해 주세요';
    return '$area · ${_conditionLabel()}';
  }

  String _syncLabel() {
    if (_refreshLoading) return '데이터 불러오는 중';
    final cachedAt = _cachedAt;
    if (cachedAt == null) return '동기화 기록 없음';
    return '마지막 동기화 ${_fmtUpdatedBase.format(cachedAt)}';
  }

  Widget _buildDockHeader(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final subtitle = _dockSubtitle();
    return CommonAnimatedReveal(
      offset: const Offset(-0.025, 0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 0, 8),
        child: Row(
          children: [
            Icon(Icons.stacked_line_chart_rounded, color: tokens.accent, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _developerMode ? _showDeveloperStatus : null,
                onLongPress: _developerMode ? _showDeveloperStatus : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '통계 비교',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      AnimatedSwitcher(
                        duration: reduceMotion
                            ? Duration.zero
                            : CommonUiMotion.selection,
                        switchInCurve: CommonUiMotion.enter,
                        switchOutCurve: CommonUiMotion.exit,
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(-0.025, 0),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          );
                        },
                        child: Text(
                          subtitle,
                          key: ValueKey<String>(subtitle),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(
                            color: tokens.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_developerMode)
              IconButton(
                tooltip: '개발 상태',
                onPressed: _showDeveloperStatus,
                icon: Icon(
                  Icons.terminal_rounded,
                  color: tokens.iconSecondary,
                  size: 20,
                ),
              ),
            PopupMenuButton<String>(
              tooltip: '통계 비교 메뉴',
              icon: Icon(Icons.more_vert_rounded, color: tokens.iconSecondary),
              onSelected: (value) {
                switch (value) {
                  case 'all':
                    _bulkCompareVisible();
                    break;
                  case 'clear':
                    _clearCompared();
                    break;
                  case 'refresh':
                    unawaited(_handleQuery(forceRemote: true));
                    break;
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem<String>(
                  value: 'all',
                  enabled: _buildVisibleCards().isNotEmpty,
                  child: const Text('전체 비교에 추가'),
                ),
                PopupMenuItem<String>(
                  value: 'clear',
                  enabled: _savedReports.isNotEmpty,
                  child: const Text('비교 목록 비우기'),
                ),
                const PopupMenuItem<String>(
                  value: 'refresh',
                  child: Text('선택 범위 최신화'),
                ),
              ],
            ),
            IconButton(
              tooltip: '통계 비교 닫기',
              onPressed: () {
                HapticFeedback.lightImpact();
                _recordDebug('side_dock_close source=header');
                Navigator.of(context).maybePop();
              },
              icon: Icon(Icons.close_rounded, color: tokens.iconPrimary, size: 22),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentSwitcher(BuildContext context) {
    final now = _normalizeDate(DateTime.now());
    Widget child;
    String activeKey;
    switch (_dockView) {
      case _StatisticsDockView.areaPicker:
        activeKey = 'statistics_area_picker';
        child = _buildAreaPicker(context);
        break;
      case _StatisticsDockView.multiDatePicker:
        activeKey = 'statistics_multi_date_picker';
        final initial = _selectedDates.isEmpty
            ? now
            : (_selectedDates.toList()..sort()).first;
        child = _MultiDatePickerDialog(
          initialSelected: _selectedDates,
          firstDate: DateTime(2023, 1, 1),
          lastDate: DateTime(2100, 12, 31),
          initialMonth: initial,
          embedded: true,
          onApply: _applyDockMultiDates,
          onCancel: _closeDockPicker,
        );
        break;
      case _StatisticsDockView.rangePicker:
        activeKey = 'statistics_range_picker';
        final range = _range ?? DateTimeRange(start: now, end: now);
        child = _RangePickerDialog(
          initialRange: range,
          firstDate: DateTime(2023, 1, 1),
          lastDate: DateTime(2100, 12, 31),
          initialMonth: range.start,
          embedded: true,
          onApply: _applyDockRange,
          onCancel: _closeDockPicker,
        );
        break;
      case _StatisticsDockView.main:
        activeKey = 'statistics_main';
        child = _buildMainContent(context);
        break;
    }
    return CommonSideDockContentCropSwitcher(
      activeKey: activeKey,
      originAlignment: Alignment.centerLeft,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 180),
      child: child,
    );
  }

  Widget _buildAreaPicker(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 4, 4, 8),
          child: Row(
            children: [
              IconButton(
                tooltip: '통계 비교로 돌아가기',
                onPressed: () {
                  HapticFeedback.selectionClick();
                  setState(() => _dockView = _StatisticsDockView.main);
                },
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '지역 선택',
                      style: text.titleMedium?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${_areaOptions.length}개 지역',
                      style: text.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: tokens.borderSubtle),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: _areaOptions.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: tokens.borderSubtle),
            itemBuilder: (context, index) {
              final area = _areaOptions[index];
              final selected = area == _selectedArea;
              return CommonAnimatedReveal(
                delay: Duration(milliseconds: index * 24),
                offset: const Offset(0.02, 0),
                child: ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: Text(
                    area,
                    style: text.bodyMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: _areaSectorEnabled[area] == true
                      ? Text(
                          '방문 구역 통계 지원',
                          style: text.bodySmall?.copyWith(
                            color: tokens.textSecondary,
                          ),
                        )
                      : null,
                  trailing: selected
                      ? Icon(Icons.check_rounded, color: tokens.accent)
                      : Icon(Icons.chevron_right_rounded, color: tokens.iconSecondary),
                  onTap: () => _selectArea(area),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMainContent(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final visible = _buildVisibleCards();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              CommonAnimatedReveal(
                child: _buildConditionSection(context),
              ),
              Divider(height: 1, color: tokens.borderSubtle),
              CommonAnimatedReveal(
                delay: const Duration(milliseconds: 30),
                child: _buildSyncSection(context),
              ),
              Divider(height: 1, color: tokens.borderSubtle),
              CommonAnimatedReveal(
                delay: const Duration(milliseconds: 55),
                child: _buildResultsSection(context, visible),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: tokens.borderSubtle),
        CommonAnimatedReveal(
          delay: const Duration(milliseconds: 80),
          child: _buildFooter(context),
        ),
      ],
    );
  }

  Widget _buildConditionSection(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final area = (_selectedArea ?? '').trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              '조회 조건',
              style: text.labelLarge?.copyWith(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 6),
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            title: Text(
              '지역',
              style: text.bodySmall?.copyWith(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              area.isEmpty ? '지역을 선택해 주세요' : area,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodyMedium?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            trailing: TextButton(
              onPressed: _areaOptions.isEmpty
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      setState(() => _dockView = _StatisticsDockView.areaPicker);
                    },
              child: const Text('변경'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: area.isEmpty
                        ? null
                        : () => _setDateMode(_DateMode.single),
                    icon: Icon(
                      _dateMode == _DateMode.single
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      size: 17,
                    ),
                    label: const Text('개별 날짜'),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: area.isEmpty
                        ? null
                        : () => _setDateMode(_DateMode.range),
                    icon: Icon(
                      _dateMode == _DateMode.range
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      size: 17,
                    ),
                    label: const Text('기간'),
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            title: Text(
              _dateMode == _DateMode.single ? '날짜' : '기간',
              style: text.bodySmall?.copyWith(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              _conditionLabel(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.bodyMedium?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            trailing: TextButton(
              onPressed: area.isEmpty
                  ? null
                  : _dateMode == _DateMode.single
                      ? _pickMultiDates
                      : _pickRange,
              child: const Text('변경'),
            ),
          ),
          AnimatedSwitcher(
            duration: MediaQuery.maybeOf(context)?.disableAnimations == true
                ? Duration.zero
                : CommonUiMotion.selection,
            child: _queryDirty && _selectedMonthKeys().isNotEmpty
                ? Padding(
                    key: const ValueKey<String>('dirty_query'),
                    padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '조건이 변경되었습니다.',
                            style: text.bodySmall?.copyWith(
                              color: tokens.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        FilledButton(
                          onPressed: _refreshLoading ? null : _handleQuery,
                          child: const Text('조회'),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey<String>('clean_query')),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncSection(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration:
                      reduceMotion ? Duration.zero : CommonUiMotion.component,
                  child: Text(
                    _syncLabel(),
                    key: ValueKey<String>(_syncLabel()),
                    style: text.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: '선택 범위 최신화',
                onPressed: _refreshLoading || _selectedMonthKeys().isEmpty
                    ? null
                    : () => _handleQuery(forceRemote: true),
                icon: AnimatedSwitcher(
                  duration:
                      reduceMotion ? Duration.zero : CommonUiMotion.component,
                  child: _refreshLoading
                      ? const SizedBox(
                          key: ValueKey<String>('loading'),
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          Icons.refresh_rounded,
                          key: const ValueKey<String>('refresh'),
                          color: tokens.iconSecondary,
                        ),
                ),
              ),
            ],
          ),
          if (_refreshError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline_rounded, color: tokens.warning, size: 17),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      '최신화하지 못했습니다. 저장된 데이터를 계속 표시합니다.',
                      style: text.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _refreshLoading
                        ? null
                        : () => _handleQuery(forceRemote: true),
                    child: const Text('다시 시도'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResultsSection(
    BuildContext context,
    List<Map<String, dynamic>> visible,
  ) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    if (_loadError != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          '통계 설정을 불러오지 못했습니다.',
          style: text.bodyMedium?.copyWith(color: tokens.textSecondary),
        ),
      );
    }
    if ((_selectedArea ?? '').trim().isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          '지역을 선택하면 통계 조회 범위를 정할 수 있습니다.',
          style: text.bodyMedium?.copyWith(color: tokens.textSecondary),
        ),
      );
    }
    if (_selectedMonthKeys().isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          '비교할 날짜 또는 기간을 선택해 주세요.',
          style: text.bodyMedium?.copyWith(color: tokens.textSecondary),
        ),
      );
    }
    if (visible.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          _refreshLoading
              ? '선택 범위의 검증된 업무종료 통계를 불러오고 있습니다.'
              : '선택 범위에 검증된 상세 업무종료 통계가 없습니다.',
          style: text.bodyMedium?.copyWith(color: tokens.textSecondary),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '조회 결과 ${visible.length}일',
                  style: text.labelLarge?.copyWith(
                    color: tokens.textSecondary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(
                onPressed: _bulkCompareVisible,
                child: const Text('전체 비교에 추가'),
              ),
            ],
          ),
        ),
        for (var index = 0; index < visible.length; index++) ...[
          CommonAnimatedReveal(
            delay: Duration(milliseconds: index * 28),
            child: _buildResultRow(context, visible[index]),
          ),
          if (index != visible.length - 1)
            Divider(height: 1, color: tokens.borderSubtle),
        ],
      ],
    );
  }

  Widget _buildResultRow(BuildContext context, Map<String, dynamic> day) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final vc = _asMap(day['vehicleCount']);
    final metrics = _asMap(day['metrics']);
    final date = (day['date'] ?? '').toString().trim();
    final output = _asInt(
          day['vehicleOutput'] ??
              vc?['vehicleOutput'] ??
              day['vehicleInput'] ??
              vc?['vehicleInput'],
        ) ??
        0;
    final fee = _asInt(
          day['totalLockedFee'] ??
              vc?['totalLockedFee'] ??
              metrics?['snapshot_totalLockedFee'],
        ) ??
        0;
    final compared = _isCompared(date);
    final sector = _sectorMetricsFromDay(day);
    final showSector = _areaSectorEnabled[(_selectedArea ?? '').trim()] == true &&
        sector != null;
    final currency = NumberFormat('#,###');
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      date,
                      style: text.bodyMedium?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '출차 $output대 · 정산 ₩${currency.format(fee)}',
                      style: text.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (showSector) ...[
                      const SizedBox(height: 8),
                      _StatisticsSectorMetricsFlat(metrics: sector),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: compared ? '비교에서 제외' : '비교에 추가',
                onPressed: () => _toggleComparison(day),
                icon: AnimatedSwitcher(
                  duration:
                      reduceMotion ? Duration.zero : const Duration(milliseconds: 150),
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: animation,
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: Icon(
                    compared ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                    key: ValueKey<bool>(compared),
                    color: compared ? tokens.accent : tokens.iconSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration:
                  reduceMotion ? Duration.zero : CommonUiMotion.selection,
              child: Text(
                _savedReports.isEmpty
                    ? '비교할 날짜를 선택하세요'
                    : '비교 ${_savedReports.length}일',
                key: ValueKey<int>(_savedReports.length),
                style: text.bodySmall?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: _savedReports.isEmpty ? null : _openGraph,
            icon: const Icon(Icons.stacked_line_chart_rounded, size: 18),
            label: const Text('그래프 보기'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final content = _buildContentSwitcher(context);
    if (widget.presentation == StatisticsPresentation.page) {
      return Scaffold(
        backgroundColor: tokens.canvas,
        appBar: AppBar(
          backgroundColor: tokens.canvas,
          surfaceTintColor: tokens.transparent,
          elevation: 0,
          foregroundColor: tokens.textPrimary,
          title: const Text(
            '통계 비교',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: [
            if (_developerMode)
              IconButton(
                tooltip: '개발 상태',
                onPressed: _showDeveloperStatus,
                icon: const Icon(Icons.terminal_rounded),
              ),
          ],
        ),
        body: content,
      );
    }
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildDockHeader(context),
          Divider(height: 1, color: tokens.borderSubtle),
          Expanded(child: content),
        ],
      ),
    );
  }
}

class _StatisticsSectorMetricsFlat extends StatelessWidget {
  const _StatisticsSectorMetricsFlat({required this.metrics});

  final EndWorkSectorMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final currency = NumberFormat('#,###');
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedSize(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
      curve: CommonUiMotion.enter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '방문 구역 ${metrics.sectorCount}개 · 지정 ${metrics.assignedVehicleCount}대 · ₩${currency.format(metrics.assignedLockedFee)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          for (final item in metrics.items.take(3))
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: _StatisticsSectorMetricLine(
                label: item.sectorName,
                vehicleCount: item.vehicleCount,
                lockedFee: item.totalLockedFee,
              ),
            ),
          if (metrics.unassignedVehicleCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: _StatisticsSectorMetricLine(
                label: '미지정',
                vehicleCount: metrics.unassignedVehicleCount,
                lockedFee: metrics.unassignedLockedFee,
              ),
            ),
        ],
      ),
    );
  }
}

class _StatisticsSectorMetricLine extends StatelessWidget {
  const _StatisticsSectorMetricLine({
    required this.label,
    required this.vehicleCount,
    required this.lockedFee,
  });

  final String label;
  final int vehicleCount;
  final num lockedFee;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final currency = NumberFormat('#,###');
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        Text(
          '$vehicleCount대 · ₩${currency.format(lockedFee)}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}

class _MultiDatePickerDialog extends StatefulWidget {
  const _MultiDatePickerDialog({
    required this.initialSelected,
    required this.firstDate,
    required this.lastDate,
    required this.initialMonth,
    this.embedded = false,
    this.onApply,
    this.onCancel,
  });

  final Set<DateTime> initialSelected;
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime initialMonth;
  final bool embedded;
  final ValueChanged<Set<DateTime>>? onApply;
  final VoidCallback? onCancel;

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
    final tokens = CommonUiTheme.of(context);
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

    final content = Padding(
      padding: EdgeInsets.fromLTRB(
        widget.embedded ? 8 : 16,
        widget.embedded ? 4 : 14,
        widget.embedded ? 8 : 16,
        12,
      ),
      child: Column(
        children: [
              Row(
                children: [
                  if (widget.embedded)
                    IconButton(
                      tooltip: '통계 비교로 돌아가기',
                      onPressed: widget.onCancel,
                      icon: const Icon(Icons.arrow_back_rounded),
                    )
                  else ...[
                    const Icon(Icons.event_available_rounded),
                    const SizedBox(width: 8),
                  ],
                  const Expanded(
                    child: Text(
                      '개별 날짜 선택',
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
                          color: tokens.textSecondary,
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
                    color: tokens.textPrimary,
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
                      color: tokens.textDisabled,
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
                      onPressed: widget.embedded
                          ? widget.onCancel
                          : () => Navigator.of(context).pop(null),
                      child: const Text('취소'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: widget.embedded
                          ? () => widget.onApply?.call(Set<DateTime>.of(_selected))
                          : () => Navigator.of(context).pop(_selected),
                      child: const Text('적용'),
                    ),
                  ),
                ],
              ),
        ],
      ),
    );
    if (widget.embedded) return content;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 420, maxHeight: maxH),
        child: content,
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
    this.embedded = false,
    this.onApply,
    this.onCancel,
  });

  final DateTimeRange initialRange;
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime initialMonth;
  final bool embedded;
  final ValueChanged<DateTimeRange>? onApply;
  final VoidCallback? onCancel;

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
    final tokens = CommonUiTheme.of(context);
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

    final content = Padding(
      padding: EdgeInsets.fromLTRB(
        widget.embedded ? 8 : 16,
        widget.embedded ? 4 : 14,
        widget.embedded ? 8 : 16,
        12,
      ),
      child: Column(
        children: [
              Row(
                children: [
                  if (widget.embedded)
                    IconButton(
                      tooltip: '통계 비교로 돌아가기',
                      onPressed: widget.onCancel,
                      icon: const Icon(Icons.arrow_back_rounded),
                    )
                  else ...[
                    const Icon(Icons.date_range_rounded),
                    const SizedBox(width: 8),
                  ],
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
                          color: tokens.textSecondary,
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
                    color: tokens.textPrimary,
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
                      color: tokens.textDisabled,
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
                      onPressed: widget.embedded
                          ? widget.onCancel
                          : () => Navigator.of(context).pop(null),
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
                        final result = DateTimeRange(start: s, end: e);
                        if (widget.embedded) {
                          widget.onApply?.call(result);
                        } else {
                          Navigator.of(context).pop(result);
                        }
                      }
                          : null,
                      child: const Text('적용'),
                    ),
                  ),
                ],
              ),
        ],
      ),
    );
    if (widget.embedded) return content;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 420, maxHeight: maxH),
        child: content,
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
    final tokens = CommonUiTheme.of(context);
    final bool isStrong = !disabled && (selected || rangeStart || rangeEnd);
    final bool isSoftRange = !disabled && !isStrong && inRange;

    final fg = disabled
        ? tokens.textDisabled
        : isStrong
            ? tokens.onAccent
            : tokens.textPrimary;

    final bg = disabled
        ? tokens.surfaceDisabled
        : isStrong
            ? tokens.accent
            : isSoftRange
                ? tokens.surfaceSelected
                : tokens.surface;

    final border = disabled
        ? tokens.borderSubtle
        : isStrong
            ? tokens.accentPressed
            : tokens.borderSubtle;

    return Material(
      color: tokens.transparent,
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

