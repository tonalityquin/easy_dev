import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../operational_cache/application/operational_snapshot_revision_state.dart';
import '../operational_cache/domain/repositories/operational_local_repository.dart';

import '../../features/location/applications/location_state.dart';
import '../../features/location/domain/models/location_model.dart';
import '../plate/application/common/view_doc_rows_store.dart';
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
    case ParkingSlotStatus.departureInProgress:
      return 4;
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

class _ParkingStatusPreviewCardAreaState extends State<ParkingStatusPreviewCardArea>
    with SingleTickerProviderStateMixin {
  Future<List<LocationModel>>? _localFuture;
  String _localArea = '';
  int _lastOperationalRevision = -1;
  late final AnimationController _snapshotRefreshController;

  @override
  void initState() {
    super.initState();
    _snapshotRefreshController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      value: 1,
    );
  }

  @override
  void didUpdateWidget(covariant ParkingStatusPreviewCardArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.area.trim() != widget.area.trim()) {
      _localFuture = null;
      _localArea = '';
      _lastOperationalRevision = -1;
    }
  }

  @override
  void dispose() {
    _snapshotRefreshController.dispose();
    super.dispose();
  }

  Future<List<LocationModel>> _loadLocationsFromLocal(String area) async {
    final a = area.trim();
    if (a.isEmpty) return const <LocationModel>[];
    return context.read<OperationalLocalRepository>().readLocations(a);
  }

  void _playSnapshotRefreshAnimation() {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _snapshotRefreshController.value = 1;
      return;
    }
    _snapshotRefreshController.forward(from: 0);
  }

  Widget _withSnapshotRefreshAnimation(Widget child) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return child;
    return AnimatedBuilder(
      animation: _snapshotRefreshController,
      child: child,
      builder: (context, animatedChild) {
        final value = Curves.easeOutCubic.transform(
          _snapshotRefreshController.value,
        );
        return Opacity(
          opacity: 0.94 + (0.06 * value),
          child: Transform.translate(
            offset: Offset(0, 6 * (1 - value)),
            child: animatedChild,
          ),
        );
      },
    );
  }

  ParkingGridOverlay _buildOverlay(ViewDocRowsStore store, String area) {
    final slotStatusByKey = <String, ParkingSlotStatus>{};
    final groupStatusByKey = <String, ParkingSlotStatus>{};

    void applyRows(List<ViewRowData> rows, ParkingSlotStatus status) {
      for (final r in rows) {
        final effectiveStatus =
            (status == ParkingSlotStatus.departureRequest ||
                    status == ParkingSlotStatus.parkingRequest) &&
                r.isSelected
                ? ParkingSlotStatus.departureInProgress
                : status;
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
          slotStatusByKey[slotKey] = _mergeStatus(prev, effectiveStatus);
        } else {
          final prev = groupStatusByKey[base] ?? ParkingSlotStatus.empty;
          groupStatusByKey[base] = _mergeStatus(prev, effectiveStatus);
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
    final departureInProgressLocations = <String>[];

    for (final spec in widget.overlay) {
      final collection = spec.collection.trim();
      if (collection.isEmpty) continue;
      final rows = store.rows(collection: collection, area: area);
      switch (spec.status) {
        case ParkingSlotStatus.parked:
          parkingCompletedLocations.addAll(rows.map((e) => e.location));
          break;
        case ParkingSlotStatus.departureRequest:
          departureRequestLocations.addAll(
            rows.where((e) => !e.isSelected).map((e) => e.location),
          );
          departureInProgressLocations.addAll(
            rows.where((e) => e.isSelected).map((e) => e.location),
          );
          break;
        case ParkingSlotStatus.departureInProgress:
          departureInProgressLocations.addAll(rows.map((e) => e.location));
          break;
        case ParkingSlotStatus.parkingRequest:
          departureInProgressLocations.addAll(
            rows.where((e) => e.isSelected).map((e) => e.location),
          );
          break;
        case ParkingSlotStatus.empty:
          break;
      }
    }

    return buildTextParkingPreviewMetricsByLocations(
      locations: locations,
      parkingCompletedLocations: parkingCompletedLocations,
      departureRequestLocations: departureRequestLocations,
      departureInProgressLocations: departureInProgressLocations,
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
    final operationalRevision = context
        .watch<OperationalSnapshotRevisionState>()
        .revisionOf(a);

    if (_lastOperationalRevision < 0) {
      _lastOperationalRevision = operationalRevision;
    } else if (_lastOperationalRevision != operationalRevision) {
      _lastOperationalRevision = operationalRevision;
      _localFuture = null;
      _localArea = '';
      context.read<OperationalSnapshotRevisionState>().reportConsumerRefresh(
            area: a,
            revision: operationalRevision,
            consumer: 'ParkingStatusPreviewCardArea',
            action: 'sqlite_future_invalidate',
          );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _playSnapshotRefreshAnimation();
      });
    }

    final liveLocations = context.watch<LocationState>().locations;
    final live = List<LocationModel>.of(liveLocations);

    if (live.isNotEmpty) {
      final textMetricsByLocation = _buildTextMetrics(live, store, a);
      return _withSnapshotRefreshAnimation(
        SizedBox.expand(
          child: _buildContent(live, overlay, textMetricsByLocation),
        ),
      );
    }

    if (_localFuture == null || _localArea != a) {
      _localArea = a;
      _localFuture = _loadLocationsFromLocal(a);
    }

    return _withSnapshotRefreshAnimation(
      SizedBox.expand(
        child: FutureBuilder<List<LocationModel>>(
          future: _localFuture,
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
      ),
    );
  }
}