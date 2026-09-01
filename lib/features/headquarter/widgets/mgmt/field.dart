import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../app/utils/snackbar_helper.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_side_dock.dart';
import '../../../../design_system/common_ui/common_ui_side_dock_content_dialog.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../account/data/services/user_read_service.dart';
import '../../../commute/domain/repositories/commute_true_false_repository.dart';
import '../../../selector/application/dev_auth.dart';
import '../../../../shared/plate/application/common/area_plate_status_counter.dart';
import '../../../../shared/plate/domain/repositories/plate_repository.dart';
import '../../application/area/area_master_cache.dart';

enum FieldPresentation {
  page,
  leftSideDock,
}

class Field extends StatefulWidget {
  const Field({
    super.key,
    this.presentation = FieldPresentation.page,
  });

  final FieldPresentation presentation;

  static Future<T?> showAsLeftSideDock<T>(
    BuildContext context, {
    bool useRootNavigator = false,
  }) async {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    debugPrint(
      '[Field] side_dock_push_request side=left motion=operations_210_190 translate=-22_to_0 opacity=0.90_to_1 reduceMotion=$reduceMotion',
    );
    try {
      return await showOperationsLeftSideDock<T>(
        context: context,
        barrierLabel: '근무지 현황',
        useRootNavigator: useRootNavigator,
        maxWidth: 360,
        widthFactor: 0.92,
        barrierDismissible: true,
        builder: (_) => const Field(
          presentation: FieldPresentation.leftSideDock,
        ),
      );
    } finally {
      debugPrint('[Field] side_dock_closed side=left');
    }
  }

  @override
  State<Field> createState() => _FieldState();
}

class _FieldState extends State<Field> {
  static const String _kDivisionPrefsKey = 'division';
  static const String _kRosterCachePrefix = 'field_active_roster_cache_v1:';
  static const String _kCommuteCachePrefix = 'field_commute_cache_v2:';
  static const String _kPlateCachePrefix = 'field_plate_count_cache_v1:';
  static const Duration _rosterTtl = Duration(hours: 1);
  static const double _compactTouchTarget = 44;
  static const double _regularTouchTarget = 46;

  static final DateFormat _fmtUpdatedCompact = DateFormat('MM.dd HH:mm');
  static final DateFormat _fmtClockTime = DateFormat('HH:mm');
  static final DateFormat _fmtLastCompact = DateFormat('MM.dd HH:mm');

  final CommuteTrueFalseRepository _commuteRepo = CommuteTrueFalseRepository();
  final UserReadService _userReadService = UserReadService();
  final List<String> _debugLines = <String>[];

  String? _division;
  Object? _loadError;
  Object? _rosterError;
  Object? _commuteError;
  Object? _plateError;
  bool _rosterLoading = false;
  bool _commuteLoading = false;
  bool _plateLoading = false;
  bool _hasRosterCache = false;
  bool _hasCommuteCache = false;
  bool _hasPlateCache = false;
  bool _rosterRemoteLoaded = false;
  bool _commuteRemoteLoaded = false;
  bool _plateRemoteLoaded = false;
  bool _developerMode = false;
  bool _showAreaFilter = false;
  DateTime? _rosterCachedAt;
  DateTime? _commuteCachedAt;
  Map<String, DateTime> _plateCachedAtByArea = <String, DateTime>{};
  Map<String, List<_RosterWorker>> _workersByArea =
  <String, List<_RosterWorker>>{};
  Map<String, Map<String, Object?>> _commuteByArea =
  <String, Map<String, Object?>>{};
  Map<String, AreaPlateStatusCount> _plateCountsByArea =
  <String, AreaPlateStatusCount>{};
  Map<String, String> _plateErrorsByArea = <String, String>{};
  List<String> _allAreas = <String>[];
  Set<String> _selectedAreas = <String>{};
  final Set<String> _expandedPresentAreas = <String>{};

  @override
  void initState() {
    super.initState();
    _developerMode = DevAuth.devModeEnabled.value;
    DevAuth.devModeEnabled.addListener(_handleDeveloperModeChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recordDebug(
        'initialized presentation=${widget.presentation.name} developerMode=$_developerMode',
      );
      unawaited(_refreshDeveloperMode());
      unawaited(_bootstrap());
    });
  }

  @override
  void dispose() {
    DevAuth.devModeEnabled.removeListener(_handleDeveloperModeChanged);
    super.dispose();
  }

  void _handleDeveloperModeChanged() {
    final enabled = DevAuth.devModeEnabled.value;
    if (!mounted || _developerMode == enabled) return;
    setState(() => _developerMode = enabled);
    _recordDebug('developer_mode_notifier=$enabled');
  }

  void _recordDebug(String message) {
    final line = '[Field] $message';
    _debugLines.add(line);
    if (_debugLines.length > 120) {
      _debugLines.removeRange(0, _debugLines.length - 120);
    }
    debugPrint(line);
  }

  Future<void> _refreshDeveloperMode() async {
    final enabled = await DevAuth.isDevModeEnabled();
    if (!mounted) return;
    _recordDebug('developer_mode=$enabled');
    if (_developerMode == enabled) return;
    setState(() => _developerMode = enabled);
  }

  Future<void> _showDeveloperStatus() async {
    if (!_developerMode || !mounted) return;
    final visibleAreas = _visibleAreas();
    final activeCount = _activeCountForAreas(visibleAreas);
    final presentCount = _presentCountForAreas(visibleAreas);
    final absentCount = activeCount - presentCount;
    final rosterAge = _cacheAge(_rosterCachedAt);
    final commuteAge = _cacheAge(_commuteCachedAt);
    final plateAge = _cacheAge(_plateCachedAt);
    final parkingCount = _parkingCountForAreas(visibleAreas);
    final departureCount = _departureCountForAreas(visibleAreas);
    final media = MediaQuery.maybeOf(context);
    final viewport = media?.size;
    final surface = context.size;
    final effectiveWidth = surface?.width ?? viewport?.width;
    final effectiveHeight = surface?.height ?? viewport?.height;
    final compactLayout = effectiveWidth != null && effectiveHeight != null
        ? effectiveWidth <= 390 || effectiveHeight <= 700
        : false;
    _recordDebug(
      'developer_status_open presentation=${widget.presentation.name} filter=$_showAreaFilter areas=${_allAreas.length} visibleAreas=${visibleAreas.length} active=$activeCount present=$presentCount absent=$absentCount parking=$parkingCount departure=$departureCount plateErrors=${_plateErrorsByArea.length} expandedPresentAreas=${_expandedPresentAreas.length} rosterLoading=$_rosterLoading commuteLoading=$_commuteLoading plateLoading=$_plateLoading compact=$compactLayout surface=${effectiveWidth?.toStringAsFixed(0) ?? '-'}x${effectiveHeight?.toStringAsFixed(0) ?? '-'} reduceMotion=${media?.disableAnimations ?? false}',
    );
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '근무지 현황 상태',
      initialMessage: '근무지 현황 상태를 수집하고 있습니다.',
      useCommonUi: true,
      developerModeMessage: '개발자 모드 ON: debugPrint 코드를 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF',
    );
    if (!trace.developerMode) return;
    trace.log(
      'presentation=${widget.presentation.name}, filter=$_showAreaFilter, divisionSet=${(_division ?? '').trim().isNotEmpty}, areas=${_allAreas.length}, visibleAreas=${visibleAreas.length}, selectedAreas=${_selectedAreas.length}, expandedPresentAreas=${_expandedPresentAreas.length}, active=$activeCount, present=$presentCount, absent=$absentCount',
      progress: 0.18,
    );
    trace.log(
      'rosterCache=$_hasRosterCache, rosterRemote=$_rosterRemoteLoaded, rosterAge=${rosterAge?.inSeconds ?? -1}s, rosterLoading=$_rosterLoading, rosterError=${_rosterError != null}',
      progress: 0.30,
    );
    trace.log(
      'commuteCache=$_hasCommuteCache, commuteRemote=$_commuteRemoteLoaded, commuteAge=${commuteAge?.inSeconds ?? -1}s, commuteLoading=$_commuteLoading, commuteError=${_commuteError != null}',
      progress: 0.40,
    );
    trace.log(
      'plateCache=$_hasPlateCache, plateRemote=$_plateRemoteLoaded, plateAge=${plateAge?.inSeconds ?? -1}s, plateLoading=$_plateLoading, plateError=${_plateError != null}, plateAreaErrors=${_plateErrorsByArea.length}, parking=$parkingCount, departure=$departureCount',
      progress: 0.48,
    );
    for (final area in visibleAreas) {
      final count = _plateCountsByArea[area];
      final error = _plateErrorsByArea[area];
      final cachedAt = _plateCachedAtByArea[area];
      final cachedAge = _cacheAge(cachedAt);
      trace.log(
        'plateArea=$area, parking=${count?.parkingCompleted ?? -1}, departure=${count?.departureCompleted ?? -1}, cachedAt=${cachedAt?.toIso8601String() ?? '-'}, cacheAge=${cachedAge?.inSeconds ?? -1}s, error=${error ?? '-'}',
        progress: 0.50,
      );
    }
    trace.log(
      'rosterTtl=${_rosterTtl.inMinutes}m, reduceMotion=${media?.disableAnimations ?? false}, compactLayout=$compactLayout, surface=${effectiveWidth?.toStringAsFixed(0) ?? '-'}x${effectiveHeight?.toStringAsFixed(0) ?? '-'}, touchTarget=${compactLayout ? _compactTouchTarget : _regularTouchTarget}, expandedPresentAreas=${_expandedPresentAreas.join(',')}',
      progress: 0.56,
    );
    final snapshot = List<String>.of(_debugLines);
    if (snapshot.isEmpty) {
      trace.log('기록된 근무지 현황 로그가 없습니다.', progress: 0.86);
    } else {
      for (var i = 0; i < snapshot.length; i++) {
        trace.log(
          snapshot[i],
          progress: 0.56 + ((i + 1) / snapshot.length) * 0.36,
        );
      }
    }
    await trace.succeed('근무지 현황 상태 수집이 완료되었습니다.');
  }

  Future<void> _bootstrap() async {
    _recordDebug('bootstrap_start');
    await _loadDivisionAndCaches();
    if (!mounted) return;
    final division = (_division ?? '').trim();
    if (division.isEmpty || _loadError != null) {
      _recordDebug(
        'bootstrap_stop divisionSet=${division.isNotEmpty} loadError=${_loadError != null}',
      );
      return;
    }

    final commuteFuture = _refreshCommute(reason: 'auto');
    if (_isRosterFresh()) {
      _recordDebug(
        'roster_refresh_skip reason=auto source=cache ageSeconds=${_cacheAge(_rosterCachedAt)?.inSeconds ?? -1}',
      );
      await Future.wait<void>(<Future<void>>[
        commuteFuture,
        _refreshPlateCounts(reason: 'auto', areas: _allAreas),
      ]);
    } else {
      await _refreshRoster(reason: 'auto');
      await Future.wait<void>(<Future<void>>[
        commuteFuture,
        _refreshPlateCounts(reason: 'auto', areas: _allAreas),
      ]);
    }
    _recordDebug('bootstrap_complete');
  }

  String _rosterCacheKey(String division) => '$_kRosterCachePrefix$division';

  String _commuteCacheKey(String division) => '$_kCommuteCachePrefix$division';

  String _plateCacheKey(String division) => '$_kPlateCachePrefix$division';

  DateTime _nowLocal() => DateTime.now().toLocal();

  Duration? _cacheAge(DateTime? value) {
    if (value == null) return null;
    final age = _nowLocal().difference(value);
    return age.isNegative ? Duration.zero : age;
  }

  bool _isRosterFresh() {
    if (!_hasRosterCache || _rosterCachedAt == null) return false;
    final age = _cacheAge(_rosterCachedAt);
    return age != null && age <= _rosterTtl;
  }

  bool _isSameYmd(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  DateTime? _extractDateTime(Object? value) {
    try {
      final dt = (value as dynamic).toDate();
      if (dt is DateTime) return dt.toLocal();
    } catch (_) {}

    if (value is Map) {
      final seconds = value['seconds'];
      final nanos = value['nanoseconds'] ?? 0;
      if (seconds is int) {
        final milliseconds =
            (seconds * 1000) + ((nanos is int ? nanos : 0) ~/ 1000000);
        return DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
      }
    }

    return null;
  }

  bool _isTodayValue(Object? value) {
    final dt = _extractDateTime(value);
    return dt != null && _isSameYmd(dt, _nowLocal());
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
      return value.map(
            (key, item) => MapEntry(key.toString(), _jsonify(item)),
      );
    }

    if (value is Iterable) {
      return value.map(_jsonify).toList();
    }

    return value.toString();
  }

  Map<String, Map<String, Object?>> _decodeCommuteGrouped(dynamic raw) {
    final grouped = <String, Map<String, Object?>>{};
    if (raw is! Map) return grouped;
    for (final areaEntry in raw.entries) {
      final area = areaEntry.key.toString().trim();
      final workersRaw = areaEntry.value;
      if (area.isEmpty || workersRaw is! Map) continue;
      final workers = <String, Object?>{};
      for (final workerEntry in workersRaw.entries) {
        final name = workerEntry.key.toString().trim();
        if (name.isEmpty) continue;
        workers[name] = workerEntry.value;
      }
      grouped[area] = workers;
    }
    return grouped;
  }

  _CommuteCache? _decodeCommuteCache(String raw) {
    try {
      final root = jsonDecode(raw);
      if (root is! Map) return null;
      final cachedAtRaw = root['cachedAtMs'];
      final cachedAtMs = cachedAtRaw is num ? cachedAtRaw.toInt() : null;
      return _CommuteCache(
        grouped: _decodeCommuteGrouped(root['grouped']),
        cachedAt: cachedAtMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(cachedAtMs).toLocal(),
      );
    } catch (_) {
      return null;
    }
  }

  _RosterCache? _decodeRosterCache(String raw) {
    try {
      final root = jsonDecode(raw);
      if (root is! Map) return null;
      final cachedAtRaw = root['cachedAtMs'];
      final cachedAtMs = cachedAtRaw is num ? cachedAtRaw.toInt() : null;
      final areasRaw = root['areas'];
      if (areasRaw is! Map) return null;
      final workersByArea = <String, List<_RosterWorker>>{};
      for (final areaEntry in areasRaw.entries) {
        final area = areaEntry.key.toString().trim();
        if (area.isEmpty) continue;
        final workersRaw = areaEntry.value;
        final workers = <_RosterWorker>[];
        if (workersRaw is List) {
          for (final item in workersRaw) {
            if (item is! Map) continue;
            final id = (item['id'] ?? '').toString().trim();
            final name = (item['name'] ?? '').toString().trim();
            if (name.isEmpty) continue;
            workers.add(_RosterWorker(id: id, name: name, area: area));
          }
        }
        workers.sort((a, b) => a.name.compareTo(b.name));
        workersByArea[area] = workers;
      }
      return _RosterCache(
        workersByArea: workersByArea,
        cachedAt: cachedAtMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(cachedAtMs).toLocal(),
      );
    } catch (_) {
      return null;
    }
  }

  _PlateCache? _decodePlateCache(String raw) {
    try {
      final root = jsonDecode(raw);
      if (root is! Map) return null;
      final legacyCachedAtRaw = root['cachedAtMs'];
      final legacyCachedAtMs =
          legacyCachedAtRaw is num ? legacyCachedAtRaw.toInt() : null;
      final countsRaw = root['counts'];
      if (countsRaw is! Map) return null;
      final counts = <String, AreaPlateStatusCount>{};
      final cachedAtByArea = <String, DateTime>{};
      for (final entry in countsRaw.entries) {
        final area = entry.key.toString().trim();
        if (area.isEmpty) continue;
        final count = AreaPlateStatusCount.fromJson(area, entry.value);
        if (count == null) continue;
        counts[area] = count;
        final rawEntry = entry.value;
        final entryCachedAtRaw =
            rawEntry is Map ? rawEntry['cachedAtMs'] : null;
        final entryCachedAtMs = entryCachedAtRaw is num
            ? entryCachedAtRaw.toInt()
            : legacyCachedAtMs;
        if (entryCachedAtMs != null) {
          cachedAtByArea[area] =
              DateTime.fromMillisecondsSinceEpoch(entryCachedAtMs).toLocal();
        }
      }
      return _PlateCache(
        counts: counts,
        cachedAtByArea: cachedAtByArea,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCommuteCache({
    required String division,
    required Map<String, Map<String, Object?>> grouped,
    required DateTime cachedAt,
  }) async {
    final groupedJson = <String, dynamic>{};
    for (final areaEntry in grouped.entries) {
      final workersJson = <String, dynamic>{};
      for (final workerEntry in areaEntry.value.entries) {
        workersJson[workerEntry.key] = _jsonify(workerEntry.value);
      }
      groupedJson[areaEntry.key] = workersJson;
    }
    final payload = <String, dynamic>{
      'cachedAtMs': cachedAt.millisecondsSinceEpoch,
      'grouped': groupedJson,
    };
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_commuteCacheKey(division), jsonEncode(payload));
  }

  Future<void> _saveRosterCache({
    required String division,
    required Map<String, List<_RosterWorker>> workersByArea,
    required DateTime cachedAt,
  }) async {
    final areas = <String, dynamic>{};
    for (final areaEntry in workersByArea.entries) {
      areas[areaEntry.key] = areaEntry.value
          .map(
            (worker) =>
        <String, String>{
          'id': worker.id,
          'name': worker.name,
        },
      )
          .toList(growable: false);
    }
    final payload = <String, dynamic>{
      'cachedAtMs': cachedAt.millisecondsSinceEpoch,
      'areas': areas,
    };
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_rosterCacheKey(division), jsonEncode(payload));
  }

  Future<void> _savePlateCache({
    required String division,
    required Map<String, AreaPlateStatusCount> counts,
    required Map<String, DateTime> cachedAtByArea,
  }) async {
    DateTime? oldestCachedAt;
    for (final area in counts.keys) {
      final value = cachedAtByArea[area];
      if (value == null) continue;
      if (oldestCachedAt == null || value.isBefore(oldestCachedAt)) {
        oldestCachedAt = value;
      }
    }
    final payload = <String, dynamic>{
      if (oldestCachedAt != null)
        'cachedAtMs': oldestCachedAt.millisecondsSinceEpoch,
      'counts': <String, dynamic>{
        for (final entry in counts.entries)
          entry.key: <String, dynamic>{
            ...entry.value.toJson(),
            if (cachedAtByArea[entry.key] != null)
              'cachedAtMs':
                  cachedAtByArea[entry.key]!.millisecondsSinceEpoch,
          },
      },
    };
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_plateCacheKey(division), jsonEncode(payload));
  }

  Future<void> _loadDivisionAndCaches() async {
    _recordDebug('cache_load_start');
    try {
      final prefs = await SharedPreferences.getInstance();
      final division = (prefs.getString(_kDivisionPrefsKey) ?? '').trim();
      _RosterCache? roster;
      _CommuteCache? commute;
      _PlateCache? plate;

      if (division.isNotEmpty) {
        final rosterRaw = prefs.getString(_rosterCacheKey(division));
        if (rosterRaw != null && rosterRaw
            .trim()
            .isNotEmpty) {
          roster = _decodeRosterCache(rosterRaw);
          if (roster == null) {
            await prefs.remove(_rosterCacheKey(division));
            _recordDebug('roster_cache_invalid_removed');
          }
        }

        final commuteRaw = prefs.getString(_commuteCacheKey(division));
        if (commuteRaw != null && commuteRaw
            .trim()
            .isNotEmpty) {
          commute = _decodeCommuteCache(commuteRaw);
          if (commute == null) {
            await prefs.remove(_commuteCacheKey(division));
            _recordDebug('commute_cache_invalid_removed');
          }
        }

        final plateRaw = prefs.getString(_plateCacheKey(division));
        if (plateRaw != null && plateRaw
            .trim()
            .isNotEmpty) {
          plate = _decodePlateCache(plateRaw);
          if (plate == null) {
            await prefs.remove(_plateCacheKey(division));
            _recordDebug('plate_cache_invalid_removed');
          }
        }
      }

      if (!mounted) return;
      final rosterMap = roster?.workersByArea ??
          <String, List<_RosterWorker>>{};
      final areas = rosterMap.keys.toList()
        ..sort();
      final selected = _selectedAreas.where(areas.contains).toSet();
      setState(() {
        _division = division;
        _loadError = null;
        _rosterError = null;
        _commuteError = null;
        _plateError = null;
        _workersByArea = rosterMap;
        _commuteByArea =
            commute?.grouped ?? <String, Map<String, Object?>>{};
        _plateCountsByArea =
            plate?.counts ?? <String, AreaPlateStatusCount>{};
        _plateCachedAtByArea =
            plate?.cachedAtByArea ?? <String, DateTime>{};
        _plateErrorsByArea = <String, String>{};
        _allAreas = areas;
        _selectedAreas = selected;
        _expandedPresentAreas.removeWhere((area) => !areas.contains(area));
        _hasRosterCache = roster != null;
        _hasCommuteCache = commute != null;
        _hasPlateCache = plate != null && plate.counts.isNotEmpty;
        _rosterRemoteLoaded = false;
        _commuteRemoteLoaded = false;
        _plateRemoteLoaded = false;
        _rosterCachedAt = roster?.cachedAt;
        _commuteCachedAt = commute?.cachedAt;
      });
      _recordDebug(
        'cache_load_complete divisionSet=${division.isNotEmpty} areas=${areas
            .length} active=${_activeCount(rosterMap)} rosterCache=${roster !=
            null} commuteCache=${commute != null} plateCache=${plate != null} rosterAgeSeconds=${_cacheAge(
            roster?.cachedAt)?.inSeconds ?? -1} commuteAgeSeconds=${_cacheAge(
            commute?.cachedAt)?.inSeconds ?? -1} plateAgeSeconds=${_cacheAge(
            plate?.oldestCachedAt)?.inSeconds ?? -1}',
      );
    } catch (error, stackTrace) {
      _recordDebug(
        'cache_load_failure error=$error\nStackTrace:\n$stackTrace',
      );
      if (!mounted) return;
      setState(() {
        _division = '';
        _loadError = error;
        _rosterError = null;
        _commuteError = null;
        _plateError = null;
        _workersByArea = <String, List<_RosterWorker>>{};
        _commuteByArea = <String, Map<String, Object?>>{};
        _plateCountsByArea = <String, AreaPlateStatusCount>{};
        _plateCachedAtByArea = <String, DateTime>{};
        _plateErrorsByArea = <String, String>{};
        _allAreas = <String>[];
        _selectedAreas = <String>{};
        _expandedPresentAreas.clear();
        _hasRosterCache = false;
        _hasCommuteCache = false;
        _hasPlateCache = false;
        _rosterRemoteLoaded = false;
        _commuteRemoteLoaded = false;
        _plateRemoteLoaded = false;
        _rosterCachedAt = null;
        _commuteCachedAt = null;
      });
    }
  }

  int _activeCount(Map<String, List<_RosterWorker>> source) {
    return source.values.fold<int>(0, (sum, workers) => sum + workers.length);
  }

  Future<void> _refreshRoster({required String reason}) async {
    final division = (_division ?? '').trim();
    if (division.isEmpty || _rosterLoading) return;
    _recordDebug('roster_refresh_start reason=$reason division=$division');
    setState(() {
      _rosterLoading = true;
      _rosterError = null;
    });

    try {
      final areaSnapshot = await AreaMasterCache.readSnapshot(division);
      if (areaSnapshot == null) {
        _recordDebug('area_master_cache_missing division=$division');
        throw StateError('저장된 지역 마스터가 없습니다.');
      }
      final areas = areaSnapshot.items
          .map((item) => item.name.trim())
          .where((name) => name.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      _recordDebug('area_master_cache_read_complete areas=${areas.length}');

      final futures = areas.map((area) async {
        _recordDebug('active_users_load_start area=$area');
        final users = await _userReadService
            .refreshActiveUsersByDivisionAreaFromShow(division, area);
        final workers = users
            .map(
              (user) =>
              _RosterWorker(
                id: user.id,
                name: user.name.trim(),
                area: area,
              ),
        )
            .where((worker) => worker.name.isNotEmpty)
            .toList(growable: false)
          ..sort((a, b) => a.name.compareTo(b.name));
        _recordDebug(
          'active_users_load_complete area=$area count=${workers.length}',
        );
        return MapEntry<String, List<_RosterWorker>>(area, workers);
      }).toList(growable: false);

      final entries = await Future.wait(futures);
      final nextRoster = <String, List<_RosterWorker>>{
        for (final entry in entries) entry.key: entry.value,
      };
      final duplicateCount = _duplicateNameCount(nextRoster);
      if (duplicateCount > 0) {
        _recordDebug('roster_duplicate_names count=$duplicateCount');
      }
      final now = _nowLocal();
      await _saveRosterCache(
        division: division,
        workersByArea: nextRoster,
        cachedAt: now,
      );
      if (!mounted) return;
      final selected = _selectedAreas.where(areas.contains).toSet();
      setState(() {
        _workersByArea = nextRoster;
        _allAreas = areas;
        _selectedAreas = selected;
        _plateCountsByArea = <String, AreaPlateStatusCount>{
          for (final entry in _plateCountsByArea.entries)
            if (areas.contains(entry.key)) entry.key: entry.value,
        };
        _plateErrorsByArea.removeWhere((area, _) => !areas.contains(area));
        _expandedPresentAreas.removeWhere((area) => !areas.contains(area));
        _rosterLoading = false;
        _rosterError = null;
        _hasRosterCache = true;
        _rosterRemoteLoaded = true;
        _rosterCachedAt = now;
      });
      _recordDebug(
        'roster_refresh_complete reason=$reason areas=${areas
            .length} active=${_activeCount(
            nextRoster)} duplicateNames=$duplicateCount',
      );
    } catch (error, stackTrace) {
      _recordDebug(
        'roster_refresh_failure reason=$reason error=$error\nStackTrace:\n$stackTrace',
      );
      if (!mounted) return;
      setState(() {
        _rosterLoading = false;
        _rosterError = error;
      });
      if (reason == 'manual' && !_hasRosterCache) {
        showFailedSnackbar(
          context,
          '활성 직원 명단을 불러오지 못했습니다.',
          useCommonUi: true,
        );
      }
    }
  }

  int _duplicateNameCount(Map<String, List<_RosterWorker>> source) {
    var duplicates = 0;
    for (final workers in source.values) {
      final seen = <String>{};
      for (final worker in workers) {
        if (!seen.add(worker.name)) duplicates++;
      }
    }
    return duplicates;
  }

  Future<void> _refreshCommute({required String reason}) async {
    final division = (_division ?? '').trim();
    if (division.isEmpty || _commuteLoading) return;
    _recordDebug('commute_refresh_start reason=$reason division=$division');
    setState(() {
      _commuteLoading = true;
      _commuteError = null;
    });

    try {
      final grouped = await _commuteRepo.loadGroupedByDivision(division);
      final now = _nowLocal();
      await _saveCommuteCache(
        division: division,
        grouped: grouped,
        cachedAt: now,
      );
      if (!mounted) return;
      setState(() {
        _commuteByArea = grouped;
        _commuteLoading = false;
        _commuteError = null;
        _hasCommuteCache = true;
        _commuteRemoteLoaded = true;
        _commuteCachedAt = now;
      });
      final active = _activeCount(_workersByArea);
      final present = _presentCountForAreas(_allAreas);
      _recordDebug(
        'commute_refresh_complete reason=$reason commuteAreas=${grouped
            .length} active=$active present=$present absent=${active -
            present}',
      );
    } catch (error, stackTrace) {
      _recordDebug(
        'commute_refresh_failure reason=$reason error=$error\nStackTrace:\n$stackTrace',
      );
      if (!mounted) return;
      setState(() {
        _commuteLoading = false;
        _commuteError = error;
      });
      if (reason == 'manual') {
        showFailedSnackbar(
          context,
          '최신 출근 현황을 불러오지 못했습니다. 기존 데이터는 유지됩니다.',
          useCommonUi: true,
        );
      }
    }
  }

  Future<void> _refreshPlateCounts({
    required String reason,
    required Iterable<String> areas,
  }) async {
    final division = (_division ?? '').trim();
    final targets = areas
        .map((area) => area.trim())
        .where((area) => area.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort();
    if (division.isEmpty || targets.isEmpty || _plateLoading) {
      _recordDebug(
        'plate_refresh_skip reason=$reason divisionSet=${division.isNotEmpty} areas=${targets.length} loading=$_plateLoading',
      );
      return;
    }

    final counter = AreaPlateStatusCounter(context.read<PlateRepository>());
    _recordDebug(
      'plate_refresh_start reason=$reason division=$division areas=${targets.length}',
    );
    if (mounted) {
      setState(() {
        _plateLoading = true;
        _plateError = null;
        _plateErrorsByArea = <String, String>{};
      });
    }

    try {
      final result = await counter.countAreas(targets);
      final nextCounts = <String, AreaPlateStatusCount>{
        for (final area in targets)
          if (_plateCountsByArea[area] != null) area: _plateCountsByArea[area]!,
      };
      final nextCachedAtByArea = <String, DateTime>{
        for (final area in targets)
          if (_plateCachedAtByArea[area] != null)
            area: _plateCachedAtByArea[area]!,
      };
      nextCounts.addAll(result.counts);
      final now = _nowLocal();
      for (final area in result.counts.keys) {
        nextCachedAtByArea[area] = now;
      }

      if (!mounted) return;
      setState(() {
        _plateCountsByArea = nextCounts;
        _plateCachedAtByArea = nextCachedAtByArea;
        _plateErrorsByArea = result.errors;
        _plateLoading = false;
        _plateError = null;
        _hasPlateCache = nextCounts.isNotEmpty;
        _plateRemoteLoaded = result.counts.isNotEmpty;
      });

      if (nextCounts.isNotEmpty) {
        try {
          await _savePlateCache(
            division: division,
            counts: nextCounts,
            cachedAtByArea: nextCachedAtByArea,
          );
          _recordDebug(
            'plate_cache_save_complete reason=$reason areas=${nextCounts.length} refreshed=${result.counts.length} preserved=${result.errors.length}',
          );
        } catch (error, stackTrace) {
          _recordDebug(
            'plate_cache_save_failure reason=$reason error=$error\nStackTrace:\n$stackTrace',
          );
        }
      }

      for (final entry in result.counts.entries) {
        _recordDebug(
          'plate_area_complete reason=$reason area=${entry.key} parking=${entry.value.parkingCompleted} departure=${entry.value.departureCompleted} cachedAt=${nextCachedAtByArea[entry.key]?.toIso8601String() ?? '-'}',
        );
      }
      for (final entry in result.errors.entries) {
        _recordDebug(
          'plate_area_failure reason=$reason area=${entry.key} preservedCachedAt=${nextCachedAtByArea[entry.key]?.toIso8601String() ?? '-'} error=${entry.value}',
        );
      }
      _recordDebug(
        'plate_refresh_complete reason=$reason success=${result.counts.length} errors=${result.errors.length} cached=${nextCounts.length}',
      );
    } catch (error, stackTrace) {
      _recordDebug(
        'plate_refresh_failure reason=$reason error=$error\nStackTrace:\n$stackTrace',
      );
      if (!mounted) return;
      setState(() {
        _plateLoading = false;
        _plateError = error;
      });
      if (reason == 'manual' && !_hasPlateCache) {
        showFailedSnackbar(
          context,
          '차량 현황을 불러오지 못했습니다.',
          useCommonUi: true,
        );
      }
    }
  }

  Future<void> _handleRefresh() async {
    if (_commuteLoading || _rosterLoading || _plateLoading) return;
    final commuteFuture = _refreshCommute(reason: 'manual');
    if (!_isRosterFresh()) {
      await _refreshRoster(reason: 'manual');
    } else {
      _recordDebug(
        'roster_refresh_skip reason=manual source=cache ageSeconds=${_cacheAge(_rosterCachedAt)?.inSeconds ?? -1}',
      );
    }
    await Future.wait<void>(<Future<void>>[
      commuteFuture,
      _refreshPlateCounts(reason: 'manual', areas: _allAreas),
    ]);
  }

  Future<void> _retryAll() async {
    if (_commuteLoading || _rosterLoading || _plateLoading) return;
    final commuteFuture = _refreshCommute(reason: 'manual');
    await _refreshRoster(reason: 'manual');
    await Future.wait<void>(<Future<void>>[
      commuteFuture,
      _refreshPlateCounts(reason: 'manual', areas: _allAreas),
    ]);
  }

  void _openAreaPicker() {
    if (_allAreas.isEmpty || _showAreaFilter) return;
    HapticFeedback.selectionClick();
    _recordDebug(
      'filter_open areas=${_allAreas.length} selected=${_selectedAreas.length}',
    );
    setState(() => _showAreaFilter = true);
  }

  void _closeAreaPicker({String source = 'back'}) {
    if (!_showAreaFilter) return;
    HapticFeedback.lightImpact();
    _recordDebug('filter_close source=$source');
    setState(() => _showAreaFilter = false);
  }

  void _applyAreaPicker(Set<String> result) {
    final normalized = result.length == _allAreas.length
        ? <String>{}
        : result.where(_allAreas.contains).toSet();
    HapticFeedback.selectionClick();
    setState(() {
      _selectedAreas = normalized;
      _showAreaFilter = false;
    });
    _recordDebug(
      'filter_apply selected=${normalized.isEmpty ? _allAreas.length : normalized.length} all=${normalized.isEmpty}',
    );
  }

  List<String> _visibleAreas() {
    if (_selectedAreas.isEmpty) return List<String>.of(_allAreas);
    return _allAreas.where(_selectedAreas.contains).toList(growable: false);
  }

  Object? _commuteValueFor(_RosterWorker worker) {
    return _commuteByArea[worker.area]?[worker.name];
  }

  bool _isPresent(_RosterWorker worker) {
    return _isTodayValue(_commuteValueFor(worker));
  }

  int _activeCountForAreas(Iterable<String> areas) {
    var count = 0;
    for (final area in areas) {
      count += _workersByArea[area]?.length ?? 0;
    }
    return count;
  }

  int _presentCountForAreas(Iterable<String> areas) {
    var count = 0;
    for (final area in areas) {
      final workers = _workersByArea[area] ?? const <_RosterWorker>[];
      for (final worker in workers) {
        if (_isPresent(worker)) count++;
      }
    }
    return count;
  }

  int _parkingCountForAreas(Iterable<String> areas) {
    var count = 0;
    for (final area in areas) {
      count += _plateCountsByArea[area]?.parkingCompleted ?? 0;
    }
    return count;
  }

  int _departureCountForAreas(Iterable<String> areas) {
    var count = 0;
    for (final area in areas) {
      count += _plateCountsByArea[area]?.departureCompleted ?? 0;
    }
    return count;
  }

  DateTime? get _plateCachedAt {
    final visibleAreas = _visibleAreas();
    DateTime? oldest;
    for (final area in visibleAreas) {
      final value = _plateCachedAtByArea[area];
      if (value == null) continue;
      if (oldest == null || value.isBefore(oldest)) {
        oldest = value;
      }
    }
    return oldest;
  }

  bool get _hasUsableRoster => _hasRosterCache || _rosterRemoteLoaded;

  bool get _hasUsableCommute => _hasCommuteCache || _commuteRemoteLoaded;

  String _bodyStateKey(String? division) {
    if (division == null) return 'division-loading';
    if (_loadError != null) return 'division-error';
    if (division
        .trim()
        .isEmpty) return 'division-empty';
    if (!_hasUsableRoster && _rosterLoading) return 'roster-loading';
    if (!_hasUsableRoster && _rosterError != null) return 'roster-error';
    if (!_hasUsableRoster) return 'roster-pending';
    if (!_hasUsableCommute && _commuteLoading) return 'commute-loading';
    if (!_hasUsableCommute && _commuteError != null) return 'commute-error';
    if (!_hasUsableCommute) return 'commute-pending';
    if (_allAreas.isEmpty) return 'area-empty';
    return 'data';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.presentation == FieldPresentation.leftSideDock) {
      return PopScope(
        canPop: !_showAreaFilter,
        onPopInvoked: (didPop) {
          if (!didPop && _showAreaFilter) {
            _closeAreaPicker(source: 'system_back');
          }
        },
        child: _buildLeftSideDock(context),
      );
    }

    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    return CommonUiScope(
      child: PopScope(
        canPop: !_showAreaFilter,
        onPopInvoked: (didPop) {
          if (!didPop && _showAreaFilter) {
            _closeAreaPicker(source: 'system_back');
          }
        },
        child: Scaffold(
          backgroundColor: tokens.canvas,
          appBar: AppBar(
            title: Text(
              '근무지 현황',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            centerTitle: true,
            actions: [
              if (_developerMode)
                IconButton(
                  tooltip: '개발 상태',
                  onPressed: _showDeveloperStatus,
                  icon: const Icon(Icons.terminal_rounded),
                ),
            ],
          ),
          body: _buildContentSwitcher(context),
        ),
      ),
    );
  }

  Widget _buildLeftSideDock(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFlatDockHeader(context),
        Divider(height: 1, color: tokens.borderSubtle),
        Expanded(child: _buildContentSwitcher(context)),
      ],
    );
  }

  String _dockSubtitle() {
    final division = (_division ?? '').trim();
    if (division.isEmpty) return '사업부 확인 중';
    if (_allAreas.isEmpty) return '$division · 지역 확인 중';
    final visibleCount = _selectedAreas.isEmpty
        ? _allAreas.length
        : _selectedAreas.where(_allAreas.contains).length;
    final areaLabel = visibleCount == _allAreas.length
        ? '전체 ${_allAreas.length}개 지역'
        : '${_allAreas.length}개 중 $visibleCount개 지역';
    return '$division · $areaLabel';
  }

  Widget _buildFlatDockHeader(BuildContext context) {
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
            Icon(
              Icons.map_rounded,
              color: tokens.accent,
              size: 24,
            ),
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
                        '근무지 현황',
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
                          final offset = Tween<Offset>(
                            begin: const Offset(-0.025, 0),
                            end: Offset.zero,
                          ).animate(animation);
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: offset,
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
            IconButton(
              tooltip: '근무지 현황 닫기',
              onPressed: () {
                HapticFeedback.lightImpact();
                _recordDebug('side_dock_close source=header');
                Navigator.of(context).maybePop();
              },
              icon: Icon(
                Icons.close_rounded,
                color: tokens.iconPrimary,
                size: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentSwitcher(BuildContext context) {
    final counts = <String, int>{
      for (final area in _allAreas) area: _workersByArea[area]?.length ?? 0,
    };
    return CommonSideDockContentCropSwitcher(
      activeKey: _showAreaFilter ? 'field_area_filter' : 'field_status',
      originAlignment: Alignment.centerLeft,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 180),
      child: _showAreaFilter
          ? _AreaFilterView(
              allAreas: _allAreas,
              areaCounts: counts,
              initialSelected: _selectedAreas,
              onCancel: () => _closeAreaPicker(source: 'filter_back'),
              onApply: _applyAreaPicker,
              onDebug: _recordDebug,
            )
          : _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final division = _division;
    return LayoutBuilder(
      builder: (context, constraints) {
        final media = MediaQuery.of(context);
        final compact = constraints.maxWidth <= 390 || media.size.height <= 700;
        final horizontal = compact ? 2.0 : 4.0;
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontal),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CommonAnimatedReveal(
                offset: const Offset(-0.02, 0),
                child: _buildOverviewRow(context, compact: compact),
              ),
              Divider(height: 1, color: CommonUiTheme.of(context).borderSubtle),
              CommonAnimatedReveal(
                delay: const Duration(milliseconds: 55),
                offset: const Offset(-0.02, 0),
                child: _buildSyncRow(context, compact: compact),
              ),
              Divider(height: 1, color: CommonUiTheme.of(context).borderSubtle),
              Expanded(
                child: AnimatedSwitcher(
                  duration:
                      reduceMotion ? Duration.zero : CommonUiMotion.component,
                  switchInCurve: CommonUiMotion.enter,
                  switchOutCurve: CommonUiMotion.exit,
                  transitionBuilder: (child, animation) {
                    if (reduceMotion) return child;
                    final offset = Tween<Offset>(
                      begin: const Offset(-0.025, 0),
                      end: Offset.zero,
                    ).animate(animation);
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(position: offset, child: child),
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey<String>(_bodyStateKey(division)),
                    child: _buildBody(context, division, compact: compact),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOverviewRow(
    BuildContext context, {
    required bool compact,
  }) {
    final tokens = CommonUiTheme.of(context);
    final visibleAreas = _visibleAreas();
    final activeCount = _activeCountForAreas(visibleAreas);
    final presentCount =
        _hasUsableCommute ? _presentCountForAreas(visibleAreas) : 0;
    final absentCount = _hasUsableCommute ? activeCount - presentCount : 0;

    return Semantics(
      label: '활성 $activeCount명, 출근 $presentCount명, 미출근 $absentCount명',
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 4 : 6,
          vertical: compact ? 10 : 12,
        ),
        child: Row(
          children: [
            Expanded(
              child: _FlatMetric(
                label: '활성',
                value: activeCount,
                foreground: tokens.accent,
              ),
            ),
            Expanded(
              child: _FlatMetric(
                label: '출근',
                value: presentCount,
                foreground: tokens.success,
              ),
            ),
            Expanded(
              child: _FlatMetric(
                label: '미출근',
                value: absentCount,
                foreground: tokens.warning,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _syncStamp(DateTime? value) {
    if (value == null) return '--';
    final now = _nowLocal();
    if (_isSameYmd(value, now)) {
      return _fmtClockTime.format(value);
    }
    return _fmtUpdatedCompact.format(value);
  }

  String _compactUpdatedLabel() {
    return '출근 ${_syncStamp(_commuteCachedAt)} · 차량 ${_syncStamp(_plateCachedAt)}';
  }

  String _compactSyncLabel(_SyncStatus status) {
    if (_rosterLoading || _commuteLoading || _plateLoading) return '갱신 중';
    if (_rosterError != null ||
        _commuteError != null ||
        _plateError != null ||
        _plateErrorsByArea.isNotEmpty) {
      return '일부 실패';
    }
    if (_commuteRemoteLoaded && _plateRemoteLoaded) return '최신';
    if (_hasCommuteCache && _hasRosterCache && _hasPlateCache) {
      return '저장 데이터';
    }
    return status.label;
  }

  Widget _buildSyncRow(
    BuildContext context, {
    required bool compact,
  }) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final status = _syncStatus(tokens);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final displayLabel = compact ? _compactSyncLabel(status) : status.label;
    final refreshing = _commuteLoading || _rosterLoading || _plateLoading;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 4 : 6,
        compact ? 7 : 9,
        0,
        compact ? 7 : 9,
      ),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.88, end: 1).animate(animation),
                  child: child,
                ),
              );
            },
            child: refreshing
                ? SizedBox(
                    key: const ValueKey<String>('field_sync_loading'),
                    width: compact ? 16 : 18,
                    height: compact ? 16 : 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: status.foreground,
                    ),
                  )
                : Icon(
                    status.icon,
                    key: ValueKey<String>(
                      '${status.label}_${status.icon.codePoint}',
                    ),
                    size: compact ? 16 : 18,
                    color: status.foreground,
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration:
                      reduceMotion ? Duration.zero : CommonUiMotion.selection,
                  child: Text(
                    displayLabel,
                    key: ValueKey<String>(displayLabel),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelMedium?.copyWith(
                      color: status.foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 1),
                AnimatedSwitcher(
                  duration:
                      reduceMotion ? Duration.zero : CommonUiMotion.selection,
                  child: Text(
                    _compactUpdatedLabel(),
                    key: ValueKey<String>(
                      '${_syncStamp(_commuteCachedAt)}_${_syncStamp(_plateCachedAt)}',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '지역 필터',
            onPressed: _allAreas.isEmpty ? null : _openAreaPicker,
            icon: AnimatedSwitcher(
              duration:
                  reduceMotion ? Duration.zero : CommonUiMotion.selection,
              child: Icon(
                _selectedAreas.isEmpty
                    ? Icons.filter_alt_outlined
                    : Icons.filter_alt_rounded,
                key: ValueKey<bool>(_selectedAreas.isNotEmpty),
                color: _selectedAreas.isEmpty
                    ? tokens.iconSecondary
                    : tokens.accent,
                size: compact ? 19 : 20,
              ),
            ),
          ),
          IconButton(
            tooltip: '근무지 현황 새로고침',
            onPressed: refreshing
                ? null
                : () {
                    HapticFeedback.lightImpact();
                    _recordDebug('manual_refresh_tap');
                    unawaited(_handleRefresh());
                  },
            icon: AnimatedSwitcher(
              duration:
                  reduceMotion ? Duration.zero : CommonUiMotion.selection,
              child: refreshing
                  ? SizedBox(
                      key: const ValueKey<String>('field_refresh_loading'),
                      width: compact ? 18 : 20,
                      height: compact ? 18 : 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: tokens.info,
                      ),
                    )
                  : Icon(
                      Icons.refresh_rounded,
                      key: const ValueKey<String>('field_refresh_idle'),
                      color: tokens.iconPrimary,
                      size: compact ? 20 : 21,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  _SyncStatus _syncStatus(CommonUiTokens tokens) {
    if (_rosterLoading && _commuteLoading && _plateLoading) {
      return _SyncStatus(
        label: '근무지 현황 동기화 중',
        icon: Icons.sync_rounded,
        foreground: tokens.info,
      );
    }
    if (_rosterLoading) {
      return _SyncStatus(
        label: '활성 직원 명단 동기화 중',
        icon: Icons.groups_rounded,
        foreground: tokens.info,
      );
    }
    if (_commuteLoading && _plateLoading) {
      return _SyncStatus(
        label: '출근·차량 현황 갱신 중',
        icon: Icons.sync_rounded,
        foreground: tokens.info,
      );
    }
    if (_commuteLoading) {
      return _SyncStatus(
        label: '출근 현황 갱신 중',
        icon: Icons.sync_rounded,
        foreground: tokens.info,
      );
    }
    if (_plateLoading) {
      return _SyncStatus(
        label: '차량 현황 갱신 중',
        icon: Icons.directions_car_filled_rounded,
        foreground: tokens.info,
      );
    }
    if (_rosterError != null ||
        _commuteError != null ||
        _plateError != null ||
        _plateErrorsByArea.isNotEmpty) {
      final usable = _hasUsableRoster &&
          _hasUsableCommute &&
          (_hasPlateCache || _plateRemoteLoaded);
      return _SyncStatus(
        label: usable ? '일부 최신화 실패 · 기존 데이터 유지' : '데이터 최신화 실패',
        icon: Icons.error_outline_rounded,
        foreground: tokens.danger,
      );
    }
    if (_commuteRemoteLoaded && _plateRemoteLoaded) {
      return _SyncStatus(
        label: _isRosterFresh() ? '최신 근무지 현황' : '현황 최신 · 직원 명단 캐시',
        icon: Icons.cloud_done_rounded,
        foreground: tokens.success,
      );
    }
    if (_commuteRemoteLoaded && _hasPlateCache) {
      return _SyncStatus(
        label: '출근 최신 · 차량 저장 데이터',
        icon: Icons.cloud_done_rounded,
        foreground: tokens.success,
      );
    }
    if (_hasCommuteCache && _hasRosterCache && _hasPlateCache) {
      return _SyncStatus(
        label: '저장된 근무지 현황 표시',
        icon: Icons.storage_rounded,
        foreground: tokens.warning,
      );
    }
    if (_commuteRemoteLoaded) {
      return _SyncStatus(
        label: '출근 현황 최신 · 차량 확인 대기',
        icon: Icons.schedule_rounded,
        foreground: tokens.warning,
      );
    }
    return _SyncStatus(
      label: '데이터 확인 대기',
      icon: Icons.schedule_rounded,
      foreground: tokens.textSecondary,
    );
  }

  Widget _buildBody(
    BuildContext context,
    String? division, {
    required bool compact,
  }) {
    if (division == null) {
      return const _StatePanel(
        icon: Icons.apartment_rounded,
        title: '사업부 정보를 확인하고 있습니다.',
        loading: true,
      );
    }

    if (_loadError != null) {
      return _StatePanel(
        icon: Icons.error_outline_rounded,
        title: '사업부 정보를 불러오지 못했습니다.',
        message: '다시 시도해 주세요.',
        actionLabel: '다시 시도',
        onAction: _bootstrap,
        tone: _StateTone.danger,
      );
    }

    if (division.trim().isEmpty) {
      return const _StatePanel(
        icon: Icons.domain_disabled_rounded,
        title: '사업부 정보가 없습니다.',
        message: '사업부를 선택하거나 저장한 뒤 다시 확인해 주세요.',
        tone: _StateTone.info,
      );
    }

    if (!_hasUsableRoster) {
      if (_rosterLoading) {
        return const _StatePanel(
          icon: Icons.groups_rounded,
          title: '활성 직원 명단을 불러오고 있습니다.',
          loading: true,
        );
      }
      if (_rosterError != null) {
        return _StatePanel(
          icon: Icons.cloud_off_rounded,
          title: '활성 직원 명단을 불러오지 못했습니다.',
          message: '네트워크 상태를 확인한 후 다시 시도해 주세요.',
          actionLabel: '다시 시도',
          onAction: _retryAll,
          tone: _StateTone.danger,
        );
      }
      return const _StatePanel(
        icon: Icons.storage_rounded,
        title: '저장된 직원 명단이 없습니다.',
        message: '활성 직원 명단을 확인하고 있습니다.',
        loading: true,
      );
    }

    if (!_hasUsableCommute) {
      if (_commuteLoading) {
        return const _StatePanel(
          icon: Icons.cloud_sync_rounded,
          title: '오늘 출근 현황을 불러오고 있습니다.',
          loading: true,
        );
      }
      if (_commuteError != null) {
        return _StatePanel(
          icon: Icons.cloud_off_rounded,
          title: '출근 현황을 불러오지 못했습니다.',
          message: '출근 여부를 정확히 표시하려면 다시 시도해 주세요.',
          actionLabel: '다시 시도',
          onAction: _handleRefresh,
          tone: _StateTone.danger,
        );
      }
      return const _StatePanel(
        icon: Icons.storage_rounded,
        title: '저장된 출근 현황이 없습니다.',
        message: '최신 출근 현황을 확인하고 있습니다.',
        loading: true,
      );
    }

    if (_allAreas.isEmpty) {
      return const _StatePanel(
        icon: Icons.location_off_rounded,
        title: '등록된 지역이 없습니다.',
        message: '현재 사업부에 등록된 지역을 확인해 주세요.',
        tone: _StateTone.info,
      );
    }

    final visibleAreas = _visibleAreas();
    if (visibleAreas.isEmpty) {
      return _StatePanel(
        icon: Icons.filter_alt_off_rounded,
        title: '선택한 지역이 없습니다.',
        message: '전체 지역을 다시 표시할 수 있습니다.',
        actionLabel: '전체 보기',
        onAction: () {
          setState(() => _selectedAreas = <String>{});
          _recordDebug('filter_reset');
        },
        tone: _StateTone.info,
      );
    }

    return ListView.separated(
      padding: EdgeInsets.only(
        top: compact ? 8 : 10,
        bottom: compact ? 16 : 20,
      ),
      itemCount: visibleAreas.length,
      separatorBuilder: (_, __) => Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? 7 : 9),
        child: Divider(
          height: 1,
          thickness: 1,
          color: CommonUiTheme.of(context).borderSubtle,
        ),
      ),
      itemBuilder: (context, index) {
        final area = visibleAreas[index];
        final workers = _workersByArea[area] ?? const <_RosterWorker>[];
        final delayIndex = index > 6 ? 6 : index;
        return CommonAnimatedReveal(
          key: ValueKey<String>('field_area_$area'),
          delay: Duration(milliseconds: (compact ? 26 : 32) * delayIndex),
          offset: const Offset(-0.025, 0),
          child: _buildAreaSection(
            context,
            area,
            workers,
            compact: compact,
          ),
        );
      },
    );
  }

  void _togglePresentGroup(String area, int presentCount, int absentCount) {
    final expanded = !_expandedPresentAreas.contains(area);
    setState(() {
      if (expanded) {
        _expandedPresentAreas.add(area);
      } else {
        _expandedPresentAreas.remove(area);
      }
    });
    HapticFeedback.selectionClick();
    _recordDebug(
      'present_group_toggle area=$area expanded=$expanded present=$presentCount absent=$absentCount',
    );
  }

  Widget _buildAreaSection(
    BuildContext context,
    String area,
    List<_RosterWorker> sourceWorkers, {
    required bool compact,
  }) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final workers = List<_RosterWorker>.of(sourceWorkers)
      ..sort((a, b) {
        final aPresent = _isPresent(a);
        final bPresent = _isPresent(b);
        if (aPresent != bPresent) return aPresent ? 1 : -1;
        return a.name.compareTo(b.name);
      });
    final absentWorkers = workers
        .where((worker) => !_isPresent(worker))
        .toList(growable: false);
    final presentWorkers = workers.where(_isPresent).toList(growable: false);
    final present = presentWorkers.length;
    final absent = absentWorkers.length;
    final expanded = _expandedPresentAreas.contains(area) && present > 0;
    final summary = compact
        ? absent > 0
            ? '${workers.length}명 · 미출근 $absent'
            : '${workers.length}명 · 전원 출근'
        : '${workers.length}명 · 출근 $present · 미출근 $absent';
    final summaryColor = absent > 0 ? tokens.warning : tokens.success;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 4 : 6,
            compact ? 4 : 6,
            compact ? 4 : 6,
            compact ? 8 : 10,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  area,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              AnimatedSwitcher(
                duration:
                    reduceMotion ? Duration.zero : CommonUiMotion.selection,
                transitionBuilder: (child, animation) {
                  final offset = Tween<Offset>(
                    begin: const Offset(0.03, 0),
                    end: Offset.zero,
                  ).animate(animation);
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(position: offset, child: child),
                  );
                },
                child: Text(
                  summary,
                  key: ValueKey<String>('$area-$summary'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelSmall?.copyWith(
                    color: summaryColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: tokens.borderSubtle),
        _buildAreaVehicleStatus(
          context,
          area: area,
          compact: compact,
        ),
        Divider(height: 1, color: tokens.borderSubtle),
        if (workers.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 10,
              vertical: compact ? 12 : 14,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.person_off_outlined,
                  size: 18,
                  color: tokens.iconSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '현재 활성 직원이 없습니다.',
                    style: text.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          )
        else ...[
          if (absentWorkers.isNotEmpty)
            _buildWorkerList(
              context,
              absentWorkers,
              compact: compact,
              animationPrefix: 'absent',
            ),
          if (presentWorkers.isNotEmpty) ...[
            if (absentWorkers.isNotEmpty)
              Divider(height: 1, color: tokens.borderSubtle),
            _buildPresentDisclosure(
              context,
              area: area,
              presentCount: present,
              absentCount: absent,
              expanded: expanded,
              compact: compact,
            ),
            AnimatedSize(
              duration: reduceMotion ? Duration.zero : CommonUiMotion.layout,
              curve: CommonUiMotion.standard,
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration:
                    reduceMotion ? Duration.zero : CommonUiMotion.selection,
                switchInCurve: CommonUiMotion.standard,
                switchOutCurve: CommonUiMotion.standard,
                transitionBuilder: (child, animation) {
                  final offset = Tween<Offset>(
                    begin: const Offset(-0.025, 0),
                    end: Offset.zero,
                  ).animate(animation);
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(position: offset, child: child),
                  );
                },
                child: expanded
                    ? Column(
                        key: ValueKey<String>('present_open_$area'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Divider(height: 1, color: tokens.borderSubtle),
                          _buildWorkerList(
                            context,
                            presentWorkers,
                            compact: compact,
                            animationPrefix: 'present',
                          ),
                        ],
                      )
                    : SizedBox(
                        key: ValueKey<String>('present_closed_$area'),
                      ),
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildAreaVehicleStatus(
    BuildContext context, {
    required String area,
    required bool compact,
  }) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final count = _plateCountsByArea[area];
    final error = _plateErrorsByArea[area];
    final hasCount = count != null;
    final loadingWithoutValue = _plateLoading && !hasCount;
    final statusColor = error != null
        ? tokens.danger
        : _plateLoading
            ? tokens.info
            : hasCount
                ? tokens.success
                : tokens.textSecondary;
    final stateKey = loadingWithoutValue
        ? 'loading'
        : error != null && !hasCount
            ? 'error'
            : hasCount
                ? 'count_${count.parkingCompleted}_${count.departureCompleted}_${error != null}'
                : 'empty';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 10,
            vertical: compact ? 7 : 8,
          ),
          child: Row(
            children: [
              Icon(
                Icons.directions_car_filled_rounded,
                size: compact ? 16 : 18,
                color: tokens.iconSecondary,
              ),
              SizedBox(width: compact ? 7 : 8),
              Expanded(
                child: Text(
                  '차량 현황',
                  style: text.labelMedium?.copyWith(
                    color: tokens.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration:
                    reduceMotion ? Duration.zero : CommonUiMotion.selection,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.88, end: 1).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: _plateLoading
                    ? SizedBox(
                        key: const ValueKey<String>('plate_loading'),
                        width: compact ? 16 : 18,
                        height: compact ? 16 : 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: statusColor,
                        ),
                      )
                    : Icon(
                        error != null
                            ? Icons.error_outline_rounded
                            : hasCount
                                ? Icons.cloud_done_rounded
                                : Icons.schedule_rounded,
                        key: ValueKey<String>('plate_status_$stateKey'),
                        size: compact ? 16 : 18,
                        color: statusColor,
                      ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: tokens.borderSubtle),
        AnimatedSwitcher(
          duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
          switchInCurve: CommonUiMotion.enter,
          switchOutCurve: CommonUiMotion.exit,
          transitionBuilder: (child, animation) {
            if (reduceMotion) return child;
            final offset = Tween<Offset>(
              begin: const Offset(-0.025, 0),
              end: Offset.zero,
            ).animate(animation);
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(position: offset, child: child),
            );
          },
          child: Column(
            key: ValueKey<String>('vehicle_${area}_$stateKey'),
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildVehicleRow(
                context,
                icon: Icons.local_parking_rounded,
                label: '입차 완료',
                value: count?.parkingCompleted,
                foreground: tokens.info,
                loading: loadingWithoutValue,
                compact: compact,
              ),
              Divider(height: 1, color: tokens.borderSubtle),
              _buildVehicleRow(
                context,
                icon: Icons.exit_to_app_rounded,
                label: '출차 완료',
                value: count?.departureCompleted,
                foreground: tokens.accent,
                loading: loadingWithoutValue,
                compact: compact,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVehicleRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required int? value,
    required Color foreground,
    required bool loading,
    required bool compact,
  }) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion ? Duration.zero : CommonUiMotion.component;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 9 : 10,
      ),
      child: Row(
        children: [
          Icon(icon, size: compact ? 18 : 19, color: foreground),
          SizedBox(width: compact ? 9 : 10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: duration,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.92, end: 1).animate(animation),
                  child: child,
                ),
              );
            },
            child: loading
                ? SizedBox(
                    key: ValueKey<String>('vehicle_row_loading_$label'),
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: foreground,
                    ),
                  )
                : value == null
                    ? Text(
                        '--',
                        key: ValueKey<String>('vehicle_row_empty_$label'),
                        style: text.labelLarge?.copyWith(
                          color: tokens.textSecondary,
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    : TweenAnimationBuilder<double>(
                        key: ValueKey<String>('vehicle_row_${label}_$value'),
                        tween: Tween<double>(begin: 0, end: value.toDouble()),
                        duration: duration,
                        curve: CommonUiMotion.standard,
                        builder: (context, animatedValue, _) {
                          return Text(
                            '${animatedValue.round()}',
                            style: text.labelLarge?.copyWith(
                              color: foreground,
                              fontWeight: FontWeight.w800,
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkerList(
    BuildContext context,
    List<_RosterWorker> workers, {
    required bool compact,
    required String animationPrefix,
  }) {
    final tokens = CommonUiTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(workers.length, (index) {
        final worker = workers[index];
        final delayIndex = index > 5 ? 5 : index;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (index > 0) Divider(height: 1, color: tokens.borderSubtle),
            CommonAnimatedReveal(
              key: ValueKey<String>(
                'field_${animationPrefix}_${worker.area}_${worker.id}_${worker.name}',
              ),
              delay: Duration(
                milliseconds: delayIndex * (compact ? 16 : 20),
              ),
              offset: const Offset(-0.018, 0),
              child: _buildWorkerRow(
                context,
                worker,
                compact: compact,
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildPresentDisclosure(
    BuildContext context, {
    required String area,
    required int presentCount,
    required int absentCount,
    required bool expanded,
    required bool compact,
  }) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion ? Duration.zero : CommonUiMotion.selection;

    return Semantics(
      button: true,
      value: expanded ? '펼침' : '접힘',
      label: expanded
          ? '$area 출근 완료 $presentCount명 숨기기'
          : '$area 출근 완료 $presentCount명 보기',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _togglePresentGroup(area, presentCount, absentCount),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: compact ? _compactTouchTarget : _regularTouchTarget,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 8 : 10,
                vertical: compact ? 8 : 9,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.check_rounded,
                    size: compact ? 18 : 19,
                    color: tokens.success,
                  ),
                  SizedBox(width: compact ? 9 : 10),
                  Expanded(
                    child: Text(
                      '출근 완료 $presentCount명',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: tokens.success,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: duration,
                    child: Text(
                      expanded ? '숨기기' : '보기',
                      key: ValueKey<bool>(expanded),
                      style: text.labelSmall?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  SizedBox(width: compact ? 3 : 4),
                  AnimatedRotation(
                    duration: duration,
                    curve: CommonUiMotion.standard,
                    turns: expanded ? 0.5 : 0,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: compact ? 20 : 22,
                      color: tokens.iconSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatWorkerDetail(Object? value) {
    final dt = _extractDateTime(value);
    if (dt == null) return '출근 기록 없음';
    final now = _nowLocal();
    final sameDay =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    return sameDay
        ? '${_fmtClockTime.format(dt)} 출근'
        : '마지막 출근 ${_fmtLastCompact.format(dt)}';
  }

  Widget _buildWorkerRow(
    BuildContext context,
    _RosterWorker worker, {
    required bool compact,
  }) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final value = _commuteValueFor(worker);
    final present = _isTodayValue(value);
    final statusLabel = present
        ? compact
            ? '출근'
            : '오늘 출근'
        : compact
            ? '미출근'
            : '오늘 미출근';
    final statusColor = present ? tokens.success : tokens.warning;
    final statusIcon = present
        ? Icons.check_circle_outline_rounded
        : Icons.pending_actions_rounded;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final detail = _formatWorkerDetail(value);

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 9 : 10,
      ),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.9, end: 1).animate(animation),
                  child: child,
                ),
              );
            },
            child: Icon(
              statusIcon,
              key: ValueKey<bool>(present),
              size: compact ? 20 : 21,
              color: statusColor,
            ),
          ),
          SizedBox(width: compact ? 9 : 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  worker.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                AnimatedSwitcher(
                  duration:
                      reduceMotion ? Duration.zero : CommonUiMotion.selection,
                  child: Text(
                    detail,
                    key: ValueKey<String>('${worker.id}-$detail'),
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
          SizedBox(width: compact ? 8 : 10),
          AnimatedSwitcher(
            duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
            transitionBuilder: (child, animation) {
              final offset = Tween<Offset>(
                begin: const Offset(0.04, 0),
                end: Offset.zero,
              ).animate(animation);
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: offset, child: child),
              );
            },
            child: Text(
              statusLabel,
              key: ValueKey<String>('${worker.id}_$statusLabel'),
              style: text.labelSmall?.copyWith(
                color: statusColor,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FlatMetric extends StatelessWidget {
  const _FlatMetric({
    required this.label,
    required this.value,
    required this.foreground,
  });

  final String label;
  final int value;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.labelSmall?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 5),
        AnimatedSwitcher(
          duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.92, end: 1).animate(animation),
                child: child,
              ),
            );
          },
          child: Text(
            '$value',
            key: ValueKey<int>(value),
            style: text.titleSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

enum _StateTone {
  neutral,
  info,
  danger,
}

class _StatePanel extends StatelessWidget {
  const _StatePanel({
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.loading = false,
    this.tone = _StateTone.neutral,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool loading;
  final _StateTone tone;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    Color foreground = tokens.iconSecondary;
    if (tone == _StateTone.info) {
      foreground = tokens.info;
    } else if (tone == _StateTone.danger) {
      foreground = tokens.danger;
    }

    return Center(
      child: CommonAnimatedReveal(
        offset: const Offset(-0.02, 0),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              loading
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: foreground,
                      ),
                    )
                  : Icon(icon, color: foreground, size: 28),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: text.bodyLarge?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: 7),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                    height: 1.45,
                  ),
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AreaFilterView extends StatefulWidget {
  const _AreaFilterView({
    required this.allAreas,
    required this.areaCounts,
    required this.initialSelected,
    required this.onCancel,
    required this.onApply,
    required this.onDebug,
  });

  final List<String> allAreas;
  final Map<String, int> areaCounts;
  final Set<String> initialSelected;
  final VoidCallback onCancel;
  final ValueChanged<Set<String>> onApply;
  final ValueChanged<String> onDebug;

  @override
  State<_AreaFilterView> createState() => _AreaFilterViewState();
}

class _AreaFilterViewState extends State<_AreaFilterView> {
  late Set<String> _tempSelected;

  @override
  void initState() {
    super.initState();
    _tempSelected = widget.initialSelected.isEmpty
        ? widget.allAreas.toSet()
        : widget.initialSelected.where(widget.allAreas.contains).toSet();
    if (_tempSelected.isEmpty && widget.allAreas.isNotEmpty) {
      _tempSelected = widget.allAreas.toSet();
    }
    widget.onDebug(
      'filter_view_enter selected=${_tempSelected.length} areas=${widget.allAreas.length}',
    );
  }

  bool get _isAll => _tempSelected.length == widget.allAreas.length;

  void _selectAll() {
    HapticFeedback.selectionClick();
    setState(() => _tempSelected = widget.allAreas.toSet());
    widget.onDebug('filter_select_all areas=${widget.allAreas.length}');
  }

  void _toggleOne(String area) {
    HapticFeedback.selectionClick();
    var changed = false;
    setState(() {
      if (_tempSelected.contains(area)) {
        if (_tempSelected.length > 1) {
          _tempSelected.remove(area);
          changed = true;
        }
      } else {
        _tempSelected.add(area);
        changed = true;
      }
    });
    widget.onDebug(
      'filter_toggle area=$area changed=$changed selected=${_tempSelected.contains(area)} total=${_tempSelected.length}',
    );
  }

  void _apply() {
    widget.onDebug(
      'filter_apply_request selected=${_tempSelected.length} all=$_isAll',
    );
    widget.onApply(_tempSelected.toSet());
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final size = MediaQuery.of(context).size;
    final compact = size.width <= 390 || size.height <= 700;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final selectionLabel = _isAll
        ? '전체 ${widget.allAreas.length}개 지역'
        : '${widget.allAreas.length}개 중 ${_tempSelected.length}개 선택';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CommonAnimatedReveal(
          offset: const Offset(-0.025, 0),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              0,
              compact ? 4 : 6,
              0,
              compact ? 6 : 8,
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: '근무지 현황으로 돌아가기',
                  onPressed: widget.onCancel,
                  icon: Icon(
                    Icons.arrow_back_rounded,
                    color: tokens.iconPrimary,
                    size: compact ? 21 : 22,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '지역 필터',
                        style: text.titleSmall?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      AnimatedSwitcher(
                        duration: reduceMotion
                            ? Duration.zero
                            : CommonUiMotion.selection,
                        child: Text(
                          selectionLabel,
                          key: ValueKey<String>(selectionLabel),
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
                TextButton(
                  onPressed: _selectAll,
                  child: Text(
                    '전체',
                    style: TextStyle(
                      color: _isAll ? tokens.accent : tokens.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _apply,
                  child: Text(
                    '적용',
                    style: TextStyle(
                      color: tokens.accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Divider(height: 1, color: tokens.borderSubtle),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.only(bottom: compact ? 12 : 16),
            itemCount: widget.allAreas.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: tokens.borderSubtle),
            itemBuilder: (_, index) {
              final area = widget.allAreas[index];
              final checked = _tempSelected.contains(area);
              final count = widget.areaCounts[area] ?? 0;
              return CommonAnimatedReveal(
                delay: Duration(milliseconds: (index > 6 ? 6 : index) * 18),
                offset: const Offset(-0.02, 0),
                child: CheckboxListTile(
                  value: checked,
                  onChanged: (_) => _toggleOne(area),
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: tokens.accent,
                  checkColor: tokens.onAccent,
                  dense: compact,
                  visualDensity:
                      compact ? VisualDensity.compact : VisualDensity.standard,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: compact ? 4 : 6,
                  ),
                  title: Text(
                    area,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  secondary: AnimatedSwitcher(
                    duration: reduceMotion
                        ? Duration.zero
                        : CommonUiMotion.selection,
                    child: Text(
                      '$count명',
                      key: ValueKey<String>('$area-$count'),
                      style: text.labelMedium?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RosterWorker {
  const _RosterWorker({
    required this.id,
    required this.name,
    required this.area,
  });

  final String id;
  final String name;
  final String area;
}

class _RosterCache {
  const _RosterCache({
    required this.workersByArea,
    required this.cachedAt,
  });

  final Map<String, List<_RosterWorker>> workersByArea;
  final DateTime? cachedAt;
}

class _CommuteCache {
  const _CommuteCache({
    required this.grouped,
    required this.cachedAt,
  });

  final Map<String, Map<String, Object?>> grouped;
  final DateTime? cachedAt;
}

class _PlateCache {
  const _PlateCache({
    required this.counts,
    required this.cachedAtByArea,
  });

  final Map<String, AreaPlateStatusCount> counts;
  final Map<String, DateTime> cachedAtByArea;

  DateTime? get oldestCachedAt {
    DateTime? oldest;
    for (final area in counts.keys) {
      final value = cachedAtByArea[area];
      if (value == null) continue;
      if (oldest == null || value.isBefore(oldest)) {
        oldest = value;
      }
    }
    return oldest;
  }
}


class _SyncStatus {
  const _SyncStatus({
    required this.label,
    required this.icon,
    required this.foreground,
  });

  final String label;
  final IconData icon;
  final Color foreground;
}
