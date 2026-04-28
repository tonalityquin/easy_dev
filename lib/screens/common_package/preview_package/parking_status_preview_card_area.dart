import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../features/location/applications/location_state.dart';
import '../../../features/location/domain/models/location_model.dart';
import '../../../shared/plate/application/common/view_doc_rows_store.dart';
import 'parking_grid_3d_preview.dart';

@immutable
class ParkingStatusOverlaySpec {
  final String collection;
  final ParkingSlotStatus status;

  const ParkingStatusOverlaySpec({
    required this.collection,
    required this.status,
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

String _normalizeName(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), ' ');

String _nameKey(String raw) => _normalizeName(raw).toLowerCase();

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

class ParkingStatusPreviewCardArea extends StatefulWidget {
  final String area;
  final List<ParkingStatusOverlaySpec> overlay;

  const ParkingStatusPreviewCardArea({
    super.key,
    required this.area,
    required this.overlay,
  });

  @override
  State<ParkingStatusPreviewCardArea> createState() => _ParkingStatusPreviewCardAreaState();
}

class _ParkingStatusPreviewCardAreaState extends State<ParkingStatusPreviewCardArea> {
  Future<List<LocationModel>>? _prefsFuture;
  String _prefsArea = '';

  @override
  void didUpdateWidget(covariant ParkingStatusPreviewCardArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.area.trim() != widget.area.trim()) {
      _prefsFuture = null;
      _prefsArea = '';
    }
  }

  Future<List<LocationModel>> _loadLocationsFromPrefs(String area) async {
    final a = area.trim();
    if (a.isEmpty) return const <LocationModel>[];
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('cached_locations_$a');
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

  ParkingGridOverlay _buildOverlay(ViewDocRowsStore store, String area) {
    final slotStatusByKey = <String, ParkingSlotStatus>{};
    final groupStatusByKey = <String, ParkingSlotStatus>{};

    void applyRows(List<ViewRowData> rows, ParkingSlotStatus status) {
      for (final r in rows) {
        final seg = _splitLocationSegments(r.location);
        if (seg.length < 2) continue;

        final parentKey = _nameKey(seg[0]);
        final childKey = _nameKey(seg[1]);
        if (parentKey.isEmpty || childKey.isEmpty) continue;

        final base = '$parentKey|$childKey';
        int? no;
        if (seg.length >= 3) {
          no = _parseFirstInt(seg[2]);
        }

        if (no != null) {
          final slotKey = '$base|$no';
          final prev = slotStatusByKey[slotKey] ?? ParkingSlotStatus.empty;
          slotStatusByKey[slotKey] = _mergeStatus(prev, status);
        } else {
          final prev = groupStatusByKey[base] ?? ParkingSlotStatus.empty;
          groupStatusByKey[base] = _mergeStatus(prev, status);
        }
      }
    }

    for (final spec in widget.overlay) {
      final c = spec.collection.trim();
      if (c.isEmpty) continue;
      final rows = store.rows(collection: c, area: area);
      applyRows(rows, spec.status);
    }

    return ParkingGridOverlay(
      slotStatusByKey: slotStatusByKey,
      groupStatusByKey: groupStatusByKey,
    );
  }

  Map<String, TextParkingPreviewMetrics> _buildTextMetrics(
    List<LocationModel> locations,
    ViewDocRowsStore store,
    String area,
  ) {
    final parkingCompletedLocations = <String>[];
    final departureRequestLocations = <String>[];

    for (final spec in widget.overlay) {
      final collection = spec.collection.trim();
      if (collection.isEmpty) continue;
      final rows = store.rows(collection: collection, area: area);
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

  Widget _buildContent(
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
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: ParkingGrid3DPreviewCard(
        locations: locations,
        overlay: overlay,
        textMetricsByLocation: textMetricsByLocation,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.area.trim();
    final store = context.watch<ViewDocRowsStore>();
    final overlay = _buildOverlay(store, a);

    final liveLocations = context.watch<LocationState>().locations;
    final live = List<LocationModel>.of(liveLocations);

    if (live.isNotEmpty) {
      final textMetricsByLocation = _buildTextMetrics(live, store, a);
      return SizedBox.expand(
        child: _buildContent(live, overlay, textMetricsByLocation),
      );
    }

    if (_prefsFuture == null || _prefsArea != a) {
      _prefsArea = a;
      _prefsFuture = _loadLocationsFromPrefs(a);
    }

    return SizedBox.expand(
      child: FutureBuilder<List<LocationModel>>(
        future: _prefsFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
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

          final locs = snap.data ?? const <LocationModel>[];
          final textMetricsByLocation = _buildTextMetrics(locs, store, a);
          return _buildContent(locs, overlay, textMetricsByLocation);
        },
      ),
    );
  }
}