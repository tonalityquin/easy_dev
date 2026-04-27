import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../features/dev/application/area_state.dart';
import '../../../../features/dev/debug/debug_api_logger.dart';
import '../../../../features/location/applications/location_state.dart';
import '../../../../features/location/domain/models/location_model.dart';
import '../../../../features/plate/application/common/view_doc_rows_store.dart';
import '../../../../features/plate/domain/repositories/plate_repository.dart';
import '../../../common_package/preview_package/parking_grid_3d_preview.dart';

const String _tParking = 'parking';
const String _tParkingStatus = 'parking/status';
const String _tFirestore = 'firestore';
const String _tPrefs = 'prefs';
const String _tUi = 'ui';

String _trimOrEmpty(Object? v) => (v ?? '').toString().trim();

String _normalizeName(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), ' ');

String _nameKey(String raw) => _normalizeName(raw).toLowerCase();

int _statusPriority(ParkingSlotStatus s) {
  switch (s) {
    case ParkingSlotStatus.departureRequest:
      return 3;
    case ParkingSlotStatus.parkingRequest:
      return 2;
    case ParkingSlotStatus.parked:
      return 1;
    case ParkingSlotStatus.empty:
      return 0;
  }
}

ParkingSlotStatus _mergeStatus(ParkingSlotStatus a, ParkingSlotStatus b) {
  return _statusPriority(b) > _statusPriority(a) ? b : a;
}

int? _parseFirstInt(String raw) {
  final m = RegExp(r'(\d+)').firstMatch(raw);
  if (m == null) return null;
  return int.tryParse(m.group(1) ?? '');
}

List<String> _splitLocationSegments(String raw) {
  final v = raw.trim();
  if (v.isEmpty) return const <String>[];
  return v
      .split(' - ')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);
}

class _ViewRow {
  final String plateId;
  final String plateNumber;
  final String location;
  final DateTime? createdAt;

  const _ViewRow({
    required this.plateId,
    required this.plateNumber,
    required this.location,
    required this.createdAt,
  });
}

List<_ViewRow> _rowsFromViewRows(List<ViewRowData> rows) {
  return rows
      .map(
        (e) => _ViewRow(
          plateId: e.plateId,
          plateNumber: e.plateNumber,
          location: e.location,
          createdAt: e.createdAt,
        ),
      )
      .toList(growable: false);
}

ParkingGridOverlay _buildGridOverlayFromViews({
  required List<_ViewRow> parkingCompleted,
  required List<_ViewRow> departureRequests,
}) {
  final slotStatusByKey = <String, ParkingSlotStatus>{};

  final groupStatusByKey = <String, ParkingSlotStatus>{};

  void applyRows(List<_ViewRow> rows, ParkingSlotStatus status) {
    for (final r in rows) {
      final seg = _splitLocationSegments(r.location);
      if (seg.length < 2) continue;

      final parentKey = _nameKey(seg[0]);
      final childKey = parkingOverlayCanonicalChildKey(seg[1]);
      if (parentKey.isEmpty || childKey.isEmpty) continue;

      final groupKey = '$parentKey|$childKey';

      int? no;
      if (seg.length >= 3) {
        no = _parseFirstInt(seg[2]);
      }

      if (no != null) {
        final slotKey = '$groupKey|$no';
        final prev = slotStatusByKey[slotKey] ?? ParkingSlotStatus.empty;
        slotStatusByKey[slotKey] = _mergeStatus(prev, status);
      } else {
        final prev = groupStatusByKey[groupKey] ?? ParkingSlotStatus.empty;
        groupStatusByKey[groupKey] = _mergeStatus(prev, status);
      }
    }
  }

  applyRows(parkingCompleted, ParkingSlotStatus.parked);
  applyRows(departureRequests, ParkingSlotStatus.departureRequest);

  return ParkingGridOverlay(
    slotStatusByKey: slotStatusByKey,
    groupStatusByKey: groupStatusByKey,
  );
}

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
  } catch (_) {}
}

List<Map<String, dynamic>> _decodeCachedLocationsJsonToMaps(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return <Map<String, dynamic>>[];
  final decoded = jsonDecode(trimmed);
  if (decoded is! List)
    throw const FormatException('cached_locations is not a List');
  final out = <Map<String, dynamic>>[];
  for (final item in decoded) {
    if (item is Map) out.add(Map<String, dynamic>.from(item));
  }
  return out;
}

class TripleParkingStatusPage extends StatefulWidget {
  const TripleParkingStatusPage({super.key});

  @override
  State<TripleParkingStatusPage> createState() =>
      _TripleParkingStatusPageState();
}

class _TripleParkingStatusPageState extends State<TripleParkingStatusPage> {
  static const String _kCachedLocationsPrefix = 'cached_locations_';

  StreamSubscription<List<ViewRowData>>? _pcSub;
  StreamSubscription<List<ViewRowData>>? _drSub;
  Timer? _viewDebounce;
  int _viewListenSeq = 0;

  List<_ViewRow> _latestParkingCompleted = <_ViewRow>[];
  List<_ViewRow> _latestDepartureRequests = <_ViewRow>[];
  bool _pcReady = false;
  bool _drReady = false;

  List<LocationModel> _cachedLocations = <LocationModel>[];
  bool _isLocationsLoading = true;
  bool _hadLocationsError = false;
  String? _lastLocationsArea;

  int _occupiedCount = 0;
  int _departureRequestsCount = 0;
  ParkingGridOverlay _gridOverlay = const ParkingGridOverlay.empty();

  bool _isCountLoading = true;
  bool _hadError = false;
  String? _lastArea;

  int _locationsReqSeq = 0;
  int _countReqSeq = 0;

  bool _syncScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncForCurrentArea(refreshLocationsSource: false);
    });
  }

  @override
  void dispose() {
    _viewDebounce?.cancel();
    _pcSub?.cancel();
    _drSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final currentArea = context.read<AreaState>().currentArea.trim();
    final bool areaChanged =
        (_lastLocationsArea != null && _lastLocationsArea != currentArea) ||
            (_lastArea != null && _lastArea != currentArea);

    if (!areaChanged) return;
    if (_syncScheduled) return;

    _syncScheduled = true;
    Future.microtask(() {
      _syncScheduled = false;
      if (!mounted) return;
      _syncForCurrentArea(refreshLocationsSource: false);
    });
  }

  Future<void> _syncForCurrentArea({
    required bool refreshLocationsSource,
  }) async {
    final area = context.read<AreaState>().currentArea.trim();
    _lastLocationsArea = area;
    _lastArea = area;

    await Future.wait(<Future<void>>[
      _runLoadLocationsFromPrefs(forceRefresh: refreshLocationsSource),
      _runAggregateCount(forceRefresh: false),
    ]);
  }

  Future<void> _runLoadLocationsFromPrefs({required bool forceRefresh}) async {
    if (!mounted) return;

    final int seq = ++_locationsReqSeq;

    final area = context.read<AreaState>().currentArea.trim();
    final division = context.read<AreaState>().currentDivision.trim();

    final requestedArea = area;
    _lastLocationsArea = requestedArea;

    setState(() {
      _isLocationsLoading = true;
      _hadLocationsError = false;
    });

    if (forceRefresh) {
      try {
        final locState = context.read<LocationState>();
        await locState.manualLocationRefresh();
      } catch (e) {
        await _logApiError(
          tag: 'TripleParkingStatusPage._runLoadLocationsFromPrefs',
          message:
              'forceRefresh: LocationState.manualLocationRefresh 실패 → prefs 로드로 fallback',
          error: e,
          extra: <String, dynamic>{
            'division': division,
            'area': requestedArea,
            'forceRefresh': forceRefresh,
          },
          tags: const <String>[_tParking, _tParkingStatus, _tUi],
        );
      }
    }

    bool shouldDropResult() {
      if (!mounted) return true;
      if (seq != _locationsReqSeq) return true;
      final nowArea = context.read<AreaState>().currentArea.trim();
      if (nowArea != requestedArea) return true;
      return false;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_kCachedLocationsPrefix$requestedArea';
      final raw = (prefs.getString(key) ?? '').trim();

      if (raw.isEmpty) {
        if (shouldDropResult()) return;
        setState(() {
          _cachedLocations = <LocationModel>[];
          _isLocationsLoading = false;
          _hadLocationsError = false;
        });
        return;
      }

      final List<Map<String, dynamic>> maps =
          await compute(_decodeCachedLocationsJsonToMaps, raw);

      if (shouldDropResult()) return;

      final next = <LocationModel>[];
      for (final m in maps) {
        next.add(LocationModel.fromCacheMap(m));
      }

      setState(() {
        _cachedLocations = next;
        _isLocationsLoading = false;
        _hadLocationsError = false;
      });
    } catch (e) {
      await _logApiError(
        tag: 'TripleParkingStatusPage._runLoadLocationsFromPrefs',
        message: 'SharedPreferences에서 cached_locations 로드/파싱 실패',
        error: e,
        extra: <String, dynamic>{
          'division': division,
          'area': requestedArea,
          'cacheKey': '$_kCachedLocationsPrefix$requestedArea',
          'forceRefresh': forceRefresh,
        },
        tags: const <String>[_tParking, _tParkingStatus, _tPrefs],
      );

      if (shouldDropResult()) return;
      setState(() {
        _cachedLocations = <LocationModel>[];
        _isLocationsLoading = false;
        _hadLocationsError = true;
      });
    }
  }

  Future<void> _runAggregateCount({required bool forceRefresh}) async {
    if (!mounted) return;

    final int seq = ++_countReqSeq;

    final area = context.read<AreaState>().currentArea.trim();
    final division = context.read<AreaState>().currentDivision.trim();
    final repo = context.read<PlateRepository>();

    final requestedArea = area;
    _lastArea = requestedArea;

    setState(() {
      _isCountLoading = true;
      _hadError = false;
    });

    await _pcSub?.cancel();
    await _drSub?.cancel();
    _pcSub = null;
    _drSub = null;
    _viewDebounce?.cancel();
    _viewDebounce = null;

    _latestParkingCompleted = <_ViewRow>[];
    _latestDepartureRequests = <_ViewRow>[];
    _pcReady = false;
    _drReady = false;

    final int myListenSeq = ++_viewListenSeq;
    if (requestedArea.isEmpty) {
      debugPrint('[TripleParkingStatusPage] empty area, skip subscribe');
      if (!mounted) return;
      setState(() {
        _occupiedCount = 0;
        _departureRequestsCount = 0;
        _gridOverlay = const ParkingGridOverlay.empty();
        _isCountLoading = false;
        _hadError = false;
      });
      return;
    }

    debugPrint(
        '[TripleParkingStatusPage] subscribe parking_completed_view/$requestedArea + departure_requests_view/$requestedArea (seq=$myListenSeq, forceRefresh=$forceRefresh)');

    bool shouldDropResult() {
      if (!mounted) return true;
      if (seq != _countReqSeq) return true;
      final nowArea = context.read<AreaState>().currentArea.trim();
      if (nowArea != requestedArea) return true;
      if (myListenSeq != _viewListenSeq) return true;
      return false;
    }

    void scheduleRecompute() {
      _viewDebounce?.cancel();
      _viewDebounce = Timer(const Duration(milliseconds: 120), () {
        if (shouldDropResult()) return;
        final overlay = _buildGridOverlayFromViews(
          parkingCompleted: _latestParkingCompleted,
          departureRequests: _latestDepartureRequests,
        );
        final pcCount = _latestParkingCompleted.length;
        final drCount = _latestDepartureRequests.length;
        final ready = _pcReady && _drReady;
        setState(() {
          _occupiedCount = pcCount;
          _departureRequestsCount = drCount;
          _gridOverlay = overlay;
          _isCountLoading = !ready;
          _hadError = false;
        });
      });
    }

    Future<void> fail(Object e, String which) async {
      debugPrint(
          '[TripleParkingStatusPage] watch error $which/$requestedArea: $e');
      await _logApiError(
        tag: 'TripleParkingStatusPage._runAggregateCount',
        message: '$which watchViewRows 실패',
        error: e,
        extra: <String, dynamic>{
          'division': division,
          'area': requestedArea,
          'forceRefresh': forceRefresh,
          'which': which,
        },
        tags: const <String>[_tParking, _tParkingStatus, _tFirestore, _tUi],
      );
      if (shouldDropResult()) return;
      setState(() {
        _occupiedCount = 0;
        _departureRequestsCount = 0;
        _gridOverlay = const ParkingGridOverlay.empty();
        _isCountLoading = false;
        _hadError = true;
      });
    }

    _pcSub = repo
        .watchViewRows(
      collection: 'parking_completed_view',
      area: requestedArea,
      primaryAtField: 'parkingCompletedAt',
    )
        .listen(
      (rowData) {
        if (shouldDropResult()) return;
        final rows = _rowsFromViewRows(rowData);
        try {
          context.read<ViewDocRowsStore>().setRows(
                collection: 'parking_completed_view',
                area: requestedArea,
                rows: rowData,
                source: 'TripleParkingStatusPage',
              );
        } catch (e) {
          debugPrint('[TripleParkingStatusPage] store setRows(pc) failed: $e');
        }
        _latestParkingCompleted = rows;
        _pcReady = true;
        debugPrint(
            '[TripleParkingStatusPage] watch parking_completed_view/$requestedArea items=${rows.length}');
        scheduleRecompute();
      },
      onError: (e) => fail(e, 'parking_completed_view'),
    );

    _drSub = repo
        .watchViewRows(
      collection: 'departure_requests_view',
      area: requestedArea,
      primaryAtField: 'departureRequestedAt',
    )
        .listen(
      (rowData) {
        if (shouldDropResult()) return;
        final rows = _rowsFromViewRows(rowData);
        try {
          context.read<ViewDocRowsStore>().setRows(
                collection: 'departure_requests_view',
                area: requestedArea,
                rows: rowData,
                source: 'TripleParkingStatusPage',
              );
        } catch (e) {
          debugPrint('[TripleParkingStatusPage] store setRows(dep) failed: $e');
        }
        _latestDepartureRequests = rows;
        _drReady = true;
        debugPrint(
            '[TripleParkingStatusPage] watch departure_requests_view/$requestedArea items=${rows.length}');
        scheduleRecompute();
      },
      onError: (e) => fail(e, 'departure_requests_view'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentArea =
        context.select<AreaState, String>((s) => s.currentArea.trim());
    final cs = Theme.of(context).colorScheme;

    if (_isLocationsLoading || _isCountLoading) {
      return Scaffold(
          body: Center(child: CircularProgressIndicator(color: cs.primary)));
    }

    int totalCapacity = 0;
    for (final l in _cachedLocations) {
      final type = _trimOrEmpty(l.type);
      if (type == 'composite_parent') continue;
      totalCapacity += l.capacity;
    }

    final occupiedCount = _occupiedCount;
    final textMetricsByLocation = buildTextParkingPreviewMetricsByLocations(
      locations: _cachedLocations,
      parkingCompletedLocations: _latestParkingCompleted.map((e) => e.location),
      departureRequestLocations:
          _latestDepartureRequests.map((e) => e.location),
    );
    final totalOccupied = occupiedCount + _departureRequestsCount;
    final double usageRatio =
        totalCapacity == 0 ? 0 : totalOccupied / totalCapacity;
    final String usagePercent = (usageRatio * 100).toStringAsFixed(1);

    if (_hadLocationsError) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_amber, size: 40, color: cs.error),
                const SizedBox(height: 12),
                Text(
                  '주차 구역(레이아웃) 캐시 로드 중 오류가 발생했습니다.',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text('영역: $currentArea',
                    style: TextStyle(color: cs.onSurfaceVariant)),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () =>
                      _runLoadLocationsFromPrefs(forceRefresh: true),
                  icon: const Icon(Icons.refresh),
                  label: const Text('원본 갱신 후 캐시 다시 로드'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_hadError) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_amber, size: 40, color: cs.error),
                const SizedBox(height: 12),
                Text(
                  '현황(view) 데이터 로드 중 오류가 발생했습니다.',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text('영역: $currentArea',
                    style: TextStyle(color: cs.onSurfaceVariant)),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => _runAggregateCount(forceRefresh: true),
                  icon: const Icon(Icons.refresh),
                  label: const Text('다시 갱신'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            '📊 현재 총 주차 현황',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: cs.onSurface),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            '총 $totalCapacity대 중 $totalOccupied대 점유',
            style: TextStyle(fontSize: 16, color: cs.onSurface),
            textAlign: TextAlign.center,
          ),
          Text(
            '주차 $occupiedCount대 · 출차 요청 $_departureRequestsCount대',
            style: TextStyle(
                fontSize: 13,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: usageRatio,
            backgroundColor: cs.outlineVariant.withOpacity(0.6),
            valueColor: AlwaysStoppedAnimation<Color>(
                usageRatio >= 0.8 ? cs.error : cs.primary),
            minHeight: 8,
          ),
          const SizedBox(height: 12),
          Text(
            '$usagePercent% 사용 중',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w600, color: cs.onSurface),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          ParkingGrid3DPreviewCard(
            locations: _cachedLocations,
            overlay: _gridOverlay,
            textMetricsByLocation: textMetricsByLocation,
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
