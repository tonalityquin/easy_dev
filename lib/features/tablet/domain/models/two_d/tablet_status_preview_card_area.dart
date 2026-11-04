import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../app/utils/dev_firebase_debug_dialog.dart';
import '../../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../../shared/operational_cache/domain/repositories/operational_local_repository.dart';
import '../../../../../shared/parking_spatial/parking_spatial_geometry.dart';
import '../../../../../shared/plate/application/common/view_doc_rows_store.dart';
import '../../../../../shared/plate/domain/repositories/plate_repository.dart';
import '../../../../location/applications/location_state.dart';
import '../../../../location/domain/models/grid_rect.dart';
import '../../../../location/domain/models/location_model.dart';
import '../../../applications/tablet_debug_trace.dart';
import '../../../pages/widgets/tablet_common_components.dart';
import 'tablet_grid_2d_preview.dart';
import 'tablet_parking_guidance_map_surface.dart';

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
  final bool isSelected;

  const _LiveViewRow({
    required this.location,
    required this.isSelected,
  });
}

@immutable
class _GuidanceMarkerCandidate {
  final TabletParkingGuidanceMarker marker;
  final int priority;

  const _GuidanceMarkerCandidate({
    required this.marker,
    required this.priority,
  });
}

int _statusPriority(ParkingSlotStatus status) {
  switch (status) {
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

bool _isCompositeParent(String? type) {
  final value = (type ?? '').trim().toLowerCase();
  return value == 'composite_parent' ||
      value.replaceAll(RegExp(r'[_\-\s]'), '') == 'compositeparent';
}

bool _isCompositeChild(String? type) {
  final value = (type ?? '').trim().toLowerCase();
  if (value == 'composite_child' || value == 'composite') return true;
  final packed = value.replaceAll(RegExp(r'[_\-\s]'), '');
  return packed == 'compositechild' || packed == 'composite';
}

bool _matchesArea(String expected, String actual) {
  final a = expected.trim();
  final b = actual.trim();
  if (a.isEmpty || b.isEmpty) return true;
  return a == b;
}

Set<String> _parentAliases(LocationModel parent) {
  final aliases = <String>{};
  void add(String value) {
    final key = _nameKey(value);
    if (key.isNotEmpty) aliases.add(key);
  }

  add(parent.id);
  add(parent.locationName);
  return aliases;
}

class ParkingStatusPreviewCardArea extends StatefulWidget {
  final String area;
  final List<ParkingStatusOverlaySpec> overlay;
  final bool cleanPresentation;

  const ParkingStatusPreviewCardArea({
    super.key,
    required this.area,
    required this.overlay,
    this.cleanPresentation = false,
  });

  @override
  State<ParkingStatusPreviewCardArea> createState() =>
      _ParkingStatusPreviewCardAreaState();
}

class _ParkingStatusPreviewCardAreaState
    extends State<ParkingStatusPreviewCardArea>
    with SingleTickerProviderStateMixin {
  final Map<String, StreamSubscription<List<ViewRowData>>> _subscriptions =
      <String, StreamSubscription<List<ViewRowData>>>{};
  final Map<String, List<_LiveViewRow>> _rowsByCollection =
      <String, List<_LiveViewRow>>{};

  Future<List<LocationModel>>? _localFuture;
  String _localArea = '';
  String _boundArea = '';
  String _boundOverlaySignature = '';
  int _parentIndex = 0;
  int _navigationDirection = 1;
  bool? _reduceMotion;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 940),
      value: 1,
    );
    _bindSubscriptionsIfNeeded();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;
    if (reduceMotion) {
      _pulseController.stop();
      _pulseController.value = 1;
    } else {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant ParkingStatusPreviewCardArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.area.trim() != widget.area.trim()) {
      _localFuture = null;
      _localArea = '';
      _parentIndex = 0;
    }
    _bindSubscriptionsIfNeeded();
  }

  @override
  void dispose() {
    _cancelAllSubscriptions();
    _pulseController.dispose();
    super.dispose();
  }

  String _overlaySignature() {
    return widget.overlay
        .map((e) => '${e.collection.trim()}::${e.status.name}')
        .join('|');
  }

  void _cancelAllSubscriptions() {
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }
    _subscriptions.clear();
  }

  List<_LiveViewRow> _rowsFromViewRows(List<ViewRowData> rows) {
    final out = <_LiveViewRow>[];
    final seen = <String>{};
    for (final row in rows) {
      final location = _normalizeLocationValue(row.location);
      if (location.isEmpty) continue;
      final identity = '${row.plateId}|$location';
      if (!seen.add(identity)) continue;
      out.add(
        _LiveViewRow(
          location: location,
          isSelected: row.isSelected,
        ),
      );
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
    TabletDebugTrace.record(
      'TabletParkingGuide',
      'subscription_binding_changed',
      <String, Object?>{
        'area': area,
        'overlay': signature,
      },
    );

    if (area.isEmpty) {
      if (mounted) setState(() {});
      return;
    }

    final repository = context.read<PlateRepository>();
    for (final spec in widget.overlay) {
      final collection = spec.collection.trim();
      if (collection.isEmpty) continue;
      _subscriptions[collection] = repository
          .watchViewRows(
            collection: collection,
            area: area,
            primaryAtField: _primaryAtFieldForCollection(collection),
          )
          .listen(
        (rows) {
          if (!mounted) return;
          final resolved = _rowsFromViewRows(rows);
          TabletDebugTrace.record(
            'TabletParkingGuide',
            'view_rows_received',
            <String, Object?>{
              'collection': collection,
              'area': area,
              'rows': resolved.length,
              'status': spec.status.name,
            },
          );
          setState(() {
            _rowsByCollection[collection] = resolved;
          });
        },
        onError: (error, stackTrace) {
          TabletDebugTrace.record(
            'TabletParkingGuide',
            'view_rows_failed',
            <String, Object?>{
              'collection': collection,
              'area': area,
              'error': error,
            },
          );
          unawaited(
            DevFirebaseDebugDialog.show(
              context: context,
              operation: 'tablet.parking_guide.watchViewRows',
              error: error,
              stackTrace: stackTrace,
              details: <String, Object?>{
                'collection': collection,
                'area': area,
                'primaryAtField': _primaryAtFieldForCollection(collection),
                'overlayStatus': spec.status.name,
                'widget': 'ParkingStatusPreviewCardArea',
                'plateNumberVisible': false,
              },
              useCommonUi: true,
            ),
          );
          if (!mounted) return;
          setState(() {
            _rowsByCollection[collection] = const <_LiveViewRow>[];
          });
        },
      );
    }

    if (mounted) setState(() {});
  }

  Future<List<LocationModel>> _loadLocationsFromLocal(String area) async {
    final resolvedArea = area.trim();
    if (resolvedArea.isEmpty) return const <LocationModel>[];
    final locations = await context
        .read<OperationalLocalRepository>()
        .readLocations(resolvedArea);
    TabletDebugTrace.record(
      'TabletParkingGuide',
      'sqlite_locations_loaded',
      <String, Object?>{
        'area': resolvedArea,
        'count': locations.length,
      },
    );
    return locations;
  }

  List<_LiveViewRow> _rowsForCollection(String collection) {
    return _rowsByCollection[collection.trim()] ?? const <_LiveViewRow>[];
  }

  List<LocationModel> _parents(List<LocationModel> locations) {
    final area = widget.area.trim();
    final parents = locations
        .where(
          (location) =>
              _matchesArea(area, location.area) &&
              _isCompositeParent(location.type) &&
              location.parkingGrid != null,
        )
        .toList(growable: false);
    parents.sort((a, b) => a.locationName.compareTo(b.locationName));
    return parents;
  }

  List<LocationModel> _childrenForParent(
    LocationModel parent,
    List<LocationModel> locations,
  ) {
    final aliases = _parentAliases(parent);
    final area = widget.area.trim();
    final children = locations.where((location) {
      if (!_matchesArea(area, location.area)) return false;
      if (!_isCompositeChild(location.type)) return false;
      final refs = <String>{
        _nameKey(location.parent ?? ''),
        _nameKey(location.parentId ?? ''),
      }..removeWhere((value) => value.isEmpty);
      return refs.any(aliases.contains);
    }).toList(growable: false);
    children.sort((a, b) => a.locationName.compareTo(b.locationName));
    return children;
  }

  List<TabletParkingGuidanceMarker> _markersForParent(
    LocationModel parent,
    List<LocationModel> children,
  ) {
    final grid = parent.parkingGrid;
    if (grid == null) return const <TabletParkingGuidanceMarker>[];
    final aliases = _parentAliases(parent);
    final byRect = <String, _GuidanceMarkerCandidate>{};

    for (final spec in widget.overlay) {
      final collection = spec.collection.trim();
      if (collection.isEmpty) continue;
      for (final row in _rowsForCollection(collection)) {
        final segments = _splitLocationSegments(row.location);
        if (segments.length < 2) continue;
        if (!aliases.contains(_nameKey(segments.first))) continue;
        final childKey = parkingOverlayCanonicalChildKey(segments[1]);
        if (childKey.isEmpty) continue;

        LocationModel? child;
        for (final candidate in children) {
          final candidateKey =
              parkingOverlayCanonicalChildKey(candidate.locationName);
          if (candidateKey == childKey) {
            child = candidate;
            break;
          }
          if (candidate.isTowerChild &&
              childKey == kParkingOverlayTowerChildKey) {
            child = candidate;
            break;
          }
        }
        if (child == null) continue;

        final slotNo = segments.length >= 3
            ? _parseFirstInt(segments.sublist(2).join(' - '))
            : null;
        GridRect? rect;
        var exact = false;
        if (slotNo != null) {
          for (final slot in child.childSlots) {
            if (slot.no != slotNo) continue;
            rect = GridRect(
              r0: slot.r0,
              c0: slot.c0,
              r1: slot.r1,
              c1: slot.c1,
            ).normalized();
            exact = true;
            break;
          }
        }
        rect ??= resolveParkingSpatialChildRect(child, grid);
        if (rect == null) continue;

        final marker = TabletParkingGuidanceMarker(
          rect: rect,
          exact: exact,
          attention: spec.status == ParkingSlotStatus.departureRequest,
          selected: row.isSelected,
        );
        final priority = _statusPriority(spec.status);
        final key = rect.toKey();
        final previous = byRect[key];
        if (previous == null ||
            priority > previous.priority ||
            (marker.selected && !previous.marker.selected)) {
          byRect[key] = _GuidanceMarkerCandidate(
            marker: marker,
            priority: priority,
          );
        }
      }
    }

    return byRect.values
        .map((candidate) => candidate.marker)
        .toList(growable: false);
  }

  void _moveParent(int delta, int count) {
    if (count <= 1) return;
    final next = (_parentIndex + delta) % count;
    final resolved = next < 0 ? next + count : next;
    if (resolved == _parentIndex) return;
    setState(() {
      _navigationDirection = delta >= 0 ? 1 : -1;
      _parentIndex = resolved;
    });
    TabletDebugTrace.record(
      'TabletParkingGuide',
      'parent_changed',
      <String, Object?>{
        'index': resolved,
        'count': count,
      },
    );
  }

  Widget _buildParkingGuidanceMap(List<LocationModel> locations) {
    final parents = _parents(locations);
    if (parents.isEmpty) {
      return const TabletCommonEmptyState(
        title: '주차장 지도를 표시할 수 없습니다',
        message: '현재 지역에 구조형 주차 구역이 없습니다.',
        icon: Icons.local_parking_rounded,
      );
    }

    if (_parentIndex >= parents.length) {
      _parentIndex = math.max(0, parents.length - 1);
    }
    final parent = parents[_parentIndex];
    final grid = parent.parkingGrid!;
    final children = _childrenForParent(parent, locations);
    final markers = _markersForParent(parent, children);
    final tokens = CommonUiTheme.of(context);

    TabletDebugTrace.record(
      'TabletParkingGuide',
      'guidance_map_resolved',
      <String, Object?>{
        'area': widget.area.trim(),
        'parent': parent.locationName,
        'parkingAreas': grid.parkingAreas.length,
        'occupiedMarkers': markers.length,
        'plateNumberVisible': false,
        'parentBoundarySolid': true,
      },
    );

    return Column(
      children: <Widget>[
        SizedBox(
          height: 52,
          child: Row(
            children: <Widget>[
              IconButton(
                onPressed: parents.length > 1
                    ? () => _moveParent(-1, parents.length)
                    : null,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: tabletCommonDuration(
                    context,
                    CommonUiMotion.selection,
                  ),
                  child: Text(
                    parent.locationName,
                    key: ValueKey<String>(parent.id),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ),
              IconButton(
                onPressed: parents.length > 1
                    ? () => _moveParent(1, parents.length)
                    : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ),
        Divider(height: 1, thickness: 1, color: tokens.borderSubtle),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragEnd: parents.length <= 1
                ? null
                : (details) {
                    final velocity = details.primaryVelocity ?? 0;
                    if (velocity.abs() < 220) return;
                    _moveParent(velocity < 0 ? 1 : -1, parents.length);
                  },
            child: AnimatedSwitcher(
              duration: tabletCommonDuration(
                context,
                CommonUiMotion.layout,
              ),
              switchInCurve: CommonUiMotion.enter,
              switchOutCurve: CommonUiMotion.exit,
              transitionBuilder: (child, animation) {
                final curved = CurvedAnimation(
                  parent: animation,
                  curve: CommonUiMotion.enter,
                  reverseCurve: CommonUiMotion.exit,
                );
                return FadeTransition(
                  opacity: curved,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: Offset(0.06 * _navigationDirection, 0),
                      end: Offset.zero,
                    ).animate(curved),
                    child: child,
                  ),
                );
              },
              child: TabletParkingGuidanceMapSurface(
                key: ValueKey<String>('parking-guide-${parent.id}'),
                grid: grid,
                markers: markers,
                pulseAnimation: _pulseController,
                framed: true,
                padding: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreview(List<LocationModel> locations) {
    if (locations.isEmpty) {
      return const TabletCommonEmptyState(
        title: '주차 구역 정보가 없습니다',
        message: '현재 지역의 주차 구역 데이터를 확인할 수 없습니다.',
        icon: Icons.local_parking_rounded,
      );
    }
    return CommonAnimatedReveal(
      child: _buildParkingGuidanceMap(locations),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resolvedArea = widget.area.trim();
    final liveLocations = List<LocationModel>.of(
      context.watch<LocationState>().locations,
    );

    if (liveLocations.isNotEmpty) {
      return SizedBox.expand(child: _buildPreview(liveLocations));
    }

    if (_localFuture == null || _localArea != resolvedArea) {
      _localArea = resolvedArea;
      _localFuture = _loadLocationsFromLocal(resolvedArea);
    }

    return SizedBox.expand(
      child: FutureBuilder<List<LocationModel>>(
        future: _localFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const TabletCommonLoadingState(
              label: '주차 구역 불러오는 중',
            );
          }
          final locations = snapshot.data ?? const <LocationModel>[];
          return _buildPreview(locations);
        },
      ),
    );
  }
}
