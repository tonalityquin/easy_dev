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

ParkingGridOverlay _buildGridOverlayFromParkingCompleted({
  required List<_ViewRow> parkingCompleted,
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
  if (decoded is! List) throw const FormatException('cached_locations is not a List');
  final out = <Map<String, dynamic>>[];
  for (final item in decoded) {
    if (item is Map) out.add(Map<String, dynamic>.from(item));
  }
  return out;
}

class DoubleParkingStatusPage extends StatefulWidget {
  const DoubleParkingStatusPage({super.key});

  @override
  State<DoubleParkingStatusPage> createState() => _DoubleParkingStatusPageState();
}

class _DoubleParkingStatusPageState extends State<DoubleParkingStatusPage> {
  static const String _kCachedLocationsPrefix = 'cached_locations_';

  StreamSubscription<List<ViewRowData>>? _pcSub;
  Timer? _pcDebounce;
  int _pcListenSeq = 0;

  List<LocationModel> _cachedLocations = <LocationModel>[];
  List<_ViewRow> _latestParkingCompleted = <_ViewRow>[];
  bool _isLocationsLoading = true;
  bool _hadLocationsError = false;
  String? _lastLocationsArea;

  int _occupiedCount = 0;
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
    _pcDebounce?.cancel();
    _pcSub?.cancel();
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
          tag: 'DoubleParkingStatusPage._runLoadLocationsFromPrefs',
          message: 'forceRefresh: LocationState.manualLocationRefresh 실패 → prefs 로드로 fallback',
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
        tag: 'DoubleParkingStatusPage._runLoadLocationsFromPrefs',
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

    bool shouldDropResult() {
      if (!mounted) return true;
      if (seq != _countReqSeq) return true;
      final nowArea = context.read<AreaState>().currentArea.trim();
      if (nowArea != requestedArea) return true;
      return false;
    }

    await _pcSub?.cancel();
    _pcSub = null;
    _pcDebounce?.cancel();
    _pcDebounce = null;
    _latestParkingCompleted = <_ViewRow>[];

    final int myListenSeq = ++_pcListenSeq;
    if (requestedArea.isEmpty) {
      debugPrint('[DoubleParkingStatusPage] empty area, skip subscribe');
      if (!mounted) return;
      setState(() {
        _latestParkingCompleted = <_ViewRow>[];
        _occupiedCount = 0;
        _gridOverlay = const ParkingGridOverlay.empty();
        _isCountLoading = false;
        _hadError = false;
      });
      return;
    }

    debugPrint(
      '[DoubleParkingStatusPage] subscribe parking_completed_view/$requestedArea (seq=$myListenSeq, forceRefresh=$forceRefresh)',
    );

    _pcSub = repo
        .watchViewRows(
          collection: 'parking_completed_view',
          area: requestedArea,
          primaryAtField: 'parkingCompletedAt',
        )
        .listen(
          (rowData) {
            if (shouldDropResult()) return;
            if (myListenSeq != _pcListenSeq) return;

            final rows = _rowsFromViewRows(rowData);
            try {
              context.read<ViewDocRowsStore>().setRows(
                    collection: 'parking_completed_view',
                    area: requestedArea,
                    rows: rowData,
                    source: 'DoubleParkingStatusPage',
                  );
            } catch (e) {
              debugPrint('[DoubleParkingStatusPage] store setRows failed: $e');
            }

            debugPrint(
              '[DoubleParkingStatusPage] watch parking_completed_view/$requestedArea items=${rows.length}',
            );

            _pcDebounce?.cancel();
            _pcDebounce = Timer(const Duration(milliseconds: 120), () {
              if (shouldDropResult()) return;
              if (myListenSeq != _pcListenSeq) return;
              final overlay =
                  _buildGridOverlayFromParkingCompleted(parkingCompleted: rows);
              setState(() {
                _latestParkingCompleted = rows;
                _occupiedCount = rows.length;
                _gridOverlay = overlay;
                _isCountLoading = false;
                _hadError = false;
              });
            });
          },
          onError: (e) async {
            debugPrint(
              '[DoubleParkingStatusPage] watch error parking_completed_view/$requestedArea: $e',
            );
            await _logApiError(
              tag: 'DoubleParkingStatusPage._runAggregateCount',
              message: 'parking_completed_view watchViewRows 실패',
              error: e,
              extra: <String, dynamic>{
                'division': division,
                'area': requestedArea,
                'forceRefresh': forceRefresh,
              },
              tags: const <String>[_tParking, _tParkingStatus, _tFirestore, _tUi],
            );
            if (shouldDropResult()) return;
            if (myListenSeq != _pcListenSeq) return;
            setState(() {
              _latestParkingCompleted = <_ViewRow>[];
              _occupiedCount = 0;
              _gridOverlay = const ParkingGridOverlay.empty();
              _isCountLoading = false;
              _hadError = true;
            });
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    final currentArea = context.select<AreaState, String>((s) => s.currentArea.trim());
    final cs = Theme.of(context).colorScheme;

    if (_isLocationsLoading || _isCountLoading) {
      return Scaffold(body: Center(child: CircularProgressIndicator(color: cs.primary)));
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
    );
    final double usageRatio = totalCapacity == 0 ? 0 : occupiedCount / totalCapacity;
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
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text('영역: $currentArea', style: TextStyle(color: cs.onSurfaceVariant)),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => _runLoadLocationsFromPrefs(forceRefresh: true),
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
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text('영역: $currentArea', style: TextStyle(color: cs.onSurfaceVariant)),
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
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.onSurface),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            '총 $totalCapacity대 중 $occupiedCount대 주차됨',
            style: TextStyle(fontSize: 16, color: cs.onSurface),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: usageRatio,
            backgroundColor: cs.outlineVariant.withOpacity(0.6),
            valueColor: AlwaysStoppedAnimation<Color>(usageRatio >= 0.8 ? cs.error : cs.primary),
            minHeight: 8,
          ),
          const SizedBox(height: 12),
          Text(
            '$usagePercent% 사용 중',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: cs.onSurface),
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
