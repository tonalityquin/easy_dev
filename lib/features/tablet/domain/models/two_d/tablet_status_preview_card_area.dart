import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../../shared/plate/application/common/view_doc_rows_store.dart';
import '../../../../../shared/plate/domain/repositories/plate_repository.dart';
import '../../../../location/applications/location_state.dart';
import '../../../../location/domain/models/location_model.dart';
import 'tablet_grid_2d_preview.dart';

@immutable
class ParkingStatusOverlaySpec {
  final String collection;
  final ParkingSlotStatus status;

  const ParkingStatusOverlaySpec({
    required this.collection,
    required this.status,
  });
}

@immutable
class _LiveViewRow {
  final String location;

  const _LiveViewRow({
    required this.location,
  });
}

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

String _normalizeText(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), ' ');

String _normalizeLocationValue(Object? raw) =>
    (raw ?? '').toString().trim().replaceAll(RegExp(r'\s+'), ' ');

String _nameKey(String raw) => _normalizeText(raw).toLowerCase();

int? _parseFirstInt(String raw) {
  final match = RegExp(r'(\d+)').firstMatch(raw);
  if (match == null) return null;
  return int.tryParse(match.group(1) ?? '');
}

List<String> _splitLocationSegments(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return const <String>[];
  return value
      .split(' - ')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);
}

String _primaryAtFieldForCollection(String collection) {
  switch (collection.trim()) {
    case 'parking_completed_view':
      return 'parkingCompletedAt';
    case 'departure_requests_view':
      return 'departureRequestedAt';
    case 'parking_requests_view':
      return 'requestTime';
    default:
      return 'updatedAt';
  }
}

class ParkingStatusPreviewCardArea extends StatefulWidget {
  final String area;
  final List<ParkingStatusOverlaySpec> overlay;

  const ParkingStatusPreviewCardArea({
    super.key,
    required this.area,
    required this.overlay,
  });

  @override
  State<ParkingStatusPreviewCardArea> createState() =>
      _ParkingStatusPreviewCardAreaState();
}

class _ParkingStatusPreviewCardAreaState
    extends State<ParkingStatusPreviewCardArea> {
  final Map<String, StreamSubscription<List<ViewRowData>>> _subscriptions =
      <String, StreamSubscription<List<ViewRowData>>>{};

  final Map<String, List<_LiveViewRow>> _rowsByCollection =
      <String, List<_LiveViewRow>>{};

  Future<List<LocationModel>>? _prefsFuture;
  String _prefsArea = '';

  String _boundArea = '';
  String _boundOverlaySignature = '';

  @override
  void initState() {
    super.initState();
    _bindSubscriptionsIfNeeded();
  }

  @override
  void didUpdateWidget(covariant ParkingStatusPreviewCardArea oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.area.trim() != widget.area.trim()) {
      _prefsFuture = null;
      _prefsArea = '';
    }

    _bindSubscriptionsIfNeeded();
  }

  @override
  void dispose() {
    _cancelAllSubscriptions();
    super.dispose();
  }

  String _overlaySignature() {
    return widget.overlay
        .map((e) => '${e.collection.trim()}::${e.status.name}')
        .join('|');
  }

  void _cancelAllSubscriptions() {
    for (final sub in _subscriptions.values) {
      sub.cancel();
    }
    _subscriptions.clear();
  }

  List<_LiveViewRow> _rowsFromViewRows(List<ViewRowData> rows) {
    final out = <_LiveViewRow>[];
    final seen = <String>{};

    for (final row in rows) {
      final location = _normalizeLocationValue(row.location);
      if (location.isEmpty) continue;
      if (!seen.add(location)) continue;
      out.add(_LiveViewRow(location: location));
    }

    return out;
  }

  void _bindSubscriptionsIfNeeded() {
    final area = widget.area.trim();
    final signature = _overlaySignature();

    final sameBinding = _boundArea == area &&
        _boundOverlaySignature == signature &&
        _subscriptions.isNotEmpty;

    if (sameBinding) return;

    _cancelAllSubscriptions();
    _rowsByCollection.clear();

    _boundArea = area;
    _boundOverlaySignature = signature;

    if (area.isEmpty) {
      if (mounted) {
        setState(() {});
      }
      return;
    }

    final repo = context.read<PlateRepository>();

    for (final spec in widget.overlay) {
      final collection = spec.collection.trim();
      if (collection.isEmpty) continue;

      _subscriptions[collection] = repo
          .watchViewRows(
            collection: collection,
            area: area,
            primaryAtField: _primaryAtFieldForCollection(collection),
          )
          .listen(
        (rows) {
          if (!mounted) return;
          setState(() {
            _rowsByCollection[collection] = _rowsFromViewRows(rows);
          });
        },
        onError: (error) {
          debugPrint(
            'ParkingStatusPreviewCardArea subscribe error [$collection/$area]: $error',
          );
          if (!mounted) return;
          setState(() {
            _rowsByCollection[collection] = const <_LiveViewRow>[];
          });
        },
      );
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<List<LocationModel>> _loadLocationsFromPrefs(String area) async {
    final resolvedArea = area.trim();
    if (resolvedArea.isEmpty) return const <LocationModel>[];

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('cached_locations_$resolvedArea');
    if (raw == null || raw.trim().isEmpty) return const <LocationModel>[];

    final decoded = json.decode(raw);
    if (decoded is! List) return const <LocationModel>[];

    final out = <LocationModel>[];
    for (final item in decoded) {
      if (item is Map) {
        out.add(LocationModel.fromCacheMap(Map<String, dynamic>.from(item)));
      }
    }
    return out;
  }

  List<_LiveViewRow> _rowsForCollection(String collection) {
    return _rowsByCollection[collection.trim()] ?? const <_LiveViewRow>[];
  }

  ParkingGridOverlay _buildOverlay() {
    final slotStatusByKey = <String, ParkingSlotStatus>{};
    final groupStatusByKey = <String, ParkingSlotStatus>{};

    void applyRows(List<_LiveViewRow> rows, ParkingSlotStatus status) {
      for (final row in rows) {
        final segments = _splitLocationSegments(row.location);
        if (segments.length < 2) continue;

        final parentKey = _nameKey(segments[0]);
        final childKey = parkingOverlayCanonicalChildKey(segments[1]);

        if (parentKey.isEmpty || childKey.isEmpty) continue;

        final baseKey = '$parentKey|$childKey';

        int? slotNo;
        if (segments.length >= 3) {
          slotNo = _parseFirstInt(segments[2]);
        }

        if (slotNo != null) {
          final slotKey = '$baseKey|$slotNo';
          final prev = slotStatusByKey[slotKey] ?? ParkingSlotStatus.empty;
          slotStatusByKey[slotKey] = _mergeStatus(prev, status);
        } else {
          final prev = groupStatusByKey[baseKey] ?? ParkingSlotStatus.empty;
          groupStatusByKey[baseKey] = _mergeStatus(prev, status);
        }
      }
    }

    for (final spec in widget.overlay) {
      final collection = spec.collection.trim();
      if (collection.isEmpty) continue;
      applyRows(_rowsForCollection(collection), spec.status);
    }

    return ParkingGridOverlay(
      slotStatusByKey: slotStatusByKey,
      groupStatusByKey: groupStatusByKey,
    );
  }

  Map<String, TextParkingPreviewMetrics> _buildTextMetrics(
    List<LocationModel> locations,
  ) {
    final parkingCompletedLocations = <String>[];
    final departureRequestLocations = <String>[];

    for (final spec in widget.overlay) {
      final collection = spec.collection.trim();
      if (collection.isEmpty) continue;

      final rows = _rowsForCollection(collection);

      switch (spec.status) {
        case ParkingSlotStatus.parked:
          parkingCompletedLocations.addAll(rows.map((e) => e.location));
          break;
        case ParkingSlotStatus.departureRequest:
          departureRequestLocations.addAll(rows.map((e) => e.location));
          break;
        case ParkingSlotStatus.empty:
        case ParkingSlotStatus.parkingRequest:
          break;
      }
    }

    return buildTextParkingPreviewMetricsByLocations(
      locations: locations,
      parkingCompletedLocations: parkingCompletedLocations,
      departureRequestLocations: departureRequestLocations,
    );
  }

  Widget _buildPreview(
    List<LocationModel> locations,
    ParkingGridOverlay overlay,
    Map<String, TextParkingPreviewMetrics> textMetricsByLocation,
  ) {
    final cs = Theme.of(context).colorScheme;

    if (locations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Text(
            '주차구역 메타가 없습니다.\n설정에서 주차구역 새로고침 후 다시 시도하세요.',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: TabletGrid2dPreview(
        locations: locations,
        overlay: overlay,
        textMetricsByLocation: textMetricsByLocation,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resolvedArea = widget.area.trim();
    final overlay = _buildOverlay();

    final liveLocations = List<LocationModel>.of(
      context.watch<LocationState>().locations,
    );

    if (liveLocations.isNotEmpty) {
      final textMetricsByLocation = _buildTextMetrics(liveLocations);
      return SizedBox.expand(
        child: _buildPreview(liveLocations, overlay, textMetricsByLocation),
      );
    }

    if (_prefsFuture == null || _prefsArea != resolvedArea) {
      _prefsArea = resolvedArea;
      _prefsFuture = _loadLocationsFromPrefs(resolvedArea);
    }

    return SizedBox.expand(
      child: FutureBuilder<List<LocationModel>>(
        future: _prefsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            final cs = Theme.of(context).colorScheme;
            return Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                ),
              ),
            );
          }

          final locations = snapshot.data ?? const <LocationModel>[];
          final textMetricsByLocation = _buildTextMetrics(locations);

          return _buildPreview(
            locations,
            overlay,
            textMetricsByLocation,
          );
        },
      ),
    );
  }
}
