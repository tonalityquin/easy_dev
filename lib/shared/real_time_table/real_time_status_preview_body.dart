import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../operational_cache/domain/repositories/operational_local_repository.dart';

import '../../app/utils/developer_operation_status_dialog.dart';
import '../../features/location/applications/location_state.dart';
import '../../features/location/domain/models/location_model.dart';
import '../page/application/common/type_auto_transition_guard.dart';
import '../plate/application/common/view_doc_rows_store.dart';
import '../plate/domain/models/plate_model.dart';
import '../plate/domain/repositories/plate_repository.dart';
import '../preview_package/parking_grid_3d_preview.dart';
import '../preview_package/parking_status_preview_card_area.dart';
import 'real_time_location_board.dart';
import 'real_time_tab_controller.dart';
import 'real_time_table_components.dart';
import 'real_time_table_row_vm.dart';
import 'real_time_table_spec.dart';
import 'real_time_table_zone.dart';

class _StatusRowCandidate {
  const _StatusRowCandidate({
    required this.row,
    required this.spec,
    required this.status,
    required this.priority,
    required this.collection,
  });

  final RealTimeRowVM row;
  final RealTimeTabSpec spec;
  final ParkingSlotStatus status;
  final int priority;
  final String collection;
}

class _StatusBoardData {
  const _StatusBoardData({
    required this.rows,
    required this.specByRowKey,
    required this.statusByRowKey,
    required this.collectionByRowKey,
  });

  final List<RealTimeRowVM> rows;
  final Map<String, RealTimeTabSpec> specByRowKey;
  final Map<String, ParkingSlotStatus> statusByRowKey;
  final Map<String, String> collectionByRowKey;
}

class RealTimeStatusPreviewBody extends StatefulWidget {
  final RealTimeTabController controller;
  final String area;
  final String screen;
  final List<ParkingStatusOverlaySpec> overlay;
  final List<RealTimeTabSpec> specs;

  const RealTimeStatusPreviewBody({
    super.key,
    required this.controller,
    required this.area,
    required this.screen,
    required this.overlay,
    required this.specs,
  });

  @override
  State<RealTimeStatusPreviewBody> createState() =>
      _RealTimeStatusPreviewBodyState();
}

class _RealTimeStatusPreviewBodyState extends State<RealTimeStatusPreviewBody>
    with AutomaticKeepAliveClientMixin {
  static const String _boardPauseReason = '현황 DOT MAP 다이얼로그';
  static const String _dockPauseReason = '현황 상태 처리 사이드 도크';

  Future<List<LocationModel>>? _localFuture;
  String _localArea = '';
  final Map<String, PlateModel> _plateDetailCache = <String, PlateModel>{};
  final Map<String, Future<PlateModel?>> _plateDetailInflight =
      <String, Future<PlateModel?>>{};
  bool _openingDetail = false;
  String _lastRenderSignature = '';
  RealTimeParentFocusRequest? _parentFocusRequest;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.controller.bind(this, _refreshFromUser);
    widget.controller.bindParentFocus(this, _onParentFocusRequest);
  }

  @override
  void didUpdateWidget(covariant RealTimeStatusPreviewBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.unbind(this);
      oldWidget.controller.unbindParentFocus(this);
      widget.controller.bind(this, _refreshFromUser);
      widget.controller.bindParentFocus(this, _onParentFocusRequest);
    }
    if (oldWidget.area.trim() != widget.area.trim()) {
      _localFuture = null;
      _localArea = '';
      _plateDetailCache.clear();
      _plateDetailInflight.clear();
    }
  }

  @override
  void dispose() {
    widget.controller.unbind(this);
    widget.controller.unbindParentFocus(this);
    super.dispose();
  }

  void _onParentFocusRequest(RealTimeParentFocusRequest request) {
    if (!mounted) return;
    debugPrint(
      '[RealTimeStatusDotMap] event=parent_focus_request_received screen=${widget.screen} serial=${request.serial} parent=${request.parent}',
    );
    setState(() => _parentFocusRequest = request);
  }

  TypeAutoTransitionGuard? get _autoGuard {
    try {
      return context.read<TypeAutoTransitionGuard>();
    } catch (_) {
      return null;
    }
  }

  void _markUserActivity() {
    _autoGuard?.markActivity('status_dot_map');
  }

  void _beginBoardAutoPause() {
    _autoGuard?.beginBlock(_boardPauseReason);
  }

  void _endBoardAutoPause() {
    _autoGuard?.endBlock(_boardPauseReason);
  }

  void _beginDockAutoPause() {
    _autoGuard?.beginBlock(_dockPauseReason);
  }

  void _endDockAutoPause() {
    _autoGuard?.endBlock(_dockPauseReason);
  }

  Future<void> _refreshFromUser() async {
    if (!mounted) return;
    debugPrint(
      '[RealTimeStatusDotMap] event=user_refresh screen=${widget.screen} area=${widget.area.trim()} source=view_doc_rows_store firebaseAdditionalRead=0',
    );
    setState(() {});
  }

  Future<List<LocationModel>> _loadLocationsFromLocal(String area) async {
    final normalizedArea = area.trim();
    if (normalizedArea.isEmpty) return const <LocationModel>[];
    return context.read<OperationalLocalRepository>().readLocations(normalizedArea);
  }

  RealTimeTabSpec? _specForCollection(String collection) {
    final normalized = collection.trim();
    for (final spec in widget.specs) {
      if (spec.collection.trim() == normalized) return spec;
    }
    return null;
  }

  ParkingSlotStatus _effectiveStatus(
    ParkingStatusOverlaySpec overlay,
    ViewRowData row,
  ) {
    final status = overlay.status;
    if ((status == ParkingSlotStatus.departureRequest ||
            status == ParkingSlotStatus.parkingRequest) &&
        row.isSelected) {
      return ParkingSlotStatus.departureInProgress;
    }
    return status;
  }

  int _statusPriority(ParkingSlotStatus status) {
    switch (status) {
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

  String _slotIdentity(ViewRowData row) {
    final parent = parentFromRowLocation(row.location).trim().toLowerCase();
    final child = childFromRowLocation(row.location).trim().toLowerCase();
    final slot = slotNumberFromRowLocation(row.location);
    if (parent.isNotEmpty && child.isNotEmpty && slot != null) {
      return '$parent|$child|$slot';
    }
    final id = row.plateId.trim();
    if (id.isNotEmpty) return 'plate:$id';
    return 'fallback:${row.plateNumber.trim()}|${row.location.trim()}';
  }

  String _rowKey(RealTimeRowVM row) {
    return '${row.plateId.trim()}\u0001${row.plateNumber.trim()}\u0001${row.location.trim()}';
  }

  _StatusBoardData _buildBoardData(ViewDocRowsStore store, String area) {
    final canonical = <String, _StatusRowCandidate>{};

    for (final overlay in widget.overlay) {
      final collection = overlay.collection.trim();
      if (collection.isEmpty) continue;
      final spec = _specForCollection(collection);
      if (spec == null) {
        debugPrint(
          '[RealTimeStatusDotMap] event=overlay_spec_missing screen=${widget.screen} collection=$collection action=skip',
        );
        continue;
      }
      final sourceRows = store.rows(collection: collection, area: area);
      for (final source in sourceRows) {
        final effectiveStatus = _effectiveStatus(overlay, source);
        final priority = _statusPriority(effectiveStatus);
        final row = RealTimeRowVM(
          plateId: source.plateId,
          plateNumber: source.plateNumber,
          location: source.location,
          primaryAt: source.primaryAt,
          updatedAt: source.updatedAt,
          createdAt: source.createdAt,
          isSelected: source.isSelected,
          selectedBy: source.selectedBy,
        );
        final key = _slotIdentity(source);
        final previous = canonical[key];
        if (previous != null && previous.priority >= priority) continue;
        canonical[key] = _StatusRowCandidate(
          row: row,
          spec: spec,
          status: effectiveStatus,
          priority: priority,
          collection: collection,
        );
      }
    }

    final candidates = canonical.values.toList(growable: false)
      ..sort((a, b) => compareRowsByLocationSlot(a.row, b.row));
    final rows = <RealTimeRowVM>[];
    final specByRowKey = <String, RealTimeTabSpec>{};
    final statusByRowKey = <String, ParkingSlotStatus>{};
    final collectionByRowKey = <String, String>{};

    for (final candidate in candidates) {
      rows.add(candidate.row);
      final key = _rowKey(candidate.row);
      specByRowKey[key] = candidate.spec;
      statusByRowKey[key] = candidate.status;
      collectionByRowKey[key] = candidate.collection;
    }

    return _StatusBoardData(
      rows: List<RealTimeRowVM>.unmodifiable(rows),
      specByRowKey: Map<String, RealTimeTabSpec>.unmodifiable(specByRowKey),
      statusByRowKey: Map<String, ParkingSlotStatus>.unmodifiable(statusByRowKey),
      collectionByRowKey: Map<String, String>.unmodifiable(collectionByRowKey),
    );
  }

  Future<PlateModel?> _fetchPlateDetail(String plateId) async {
    final id = plateId.trim();
    if (id.isEmpty) return null;

    final cached = _plateDetailCache[id];
    if (cached != null) return cached;

    final inflight = _plateDetailInflight[id];
    if (inflight != null) return inflight;

    final repo = context.read<PlateRepository>();
    final future = () async {
      try {
        final plate = await repo.getPlate(id);
        if (plate != null) {
          _plateDetailCache[id] = plate;
        }
        return plate;
      } finally {
        _plateDetailInflight.remove(id);
      }
    }();

    _plateDetailInflight[id] = future;
    return future;
  }

  Future<void> _openStatusDock(
    RealTimeRowVM row,
    _StatusBoardData data,
  ) async {
    if (_openingDetail) return;
    final rowKey = _rowKey(row);
    final spec = data.specByRowKey[rowKey];
    if (spec == null) {
      debugPrint(
        '[RealTimeStatusDotMap] event=status_dock_blocked reason=spec_missing plateId=${row.plateId} plateNumber=${row.plateNumber} location=${row.location}',
      );
      return;
    }

    final plateId = row.plateId.trim();
    if (plateId.isEmpty) return;

    _openingDetail = true;
    _markUserActivity();
    _beginDockAutoPause();
    DeveloperOperationTrace? trace;
    BuildContext? rootContext;

    try {
      final dockContext = Navigator.of(context, rootNavigator: true).context;
      rootContext = dockContext;
      trace = await DeveloperOperationTrace.start(
        context: context,
        title: '현황 상태 빠른 실행',
        initialMessage: '현황 DOT MAP 상태 처리 빠른 실행을 준비했습니다.',
        useCommonUi: true,
        developerModeMessage:
            '개발자 모드 ON: 완료 후 현황 DOT MAP debugPrint 코드를 복사할 수 있습니다.',
        standardModeMessage: '개발자 모드 OFF',
        showDialogImmediately: false,
      );

      final cachedPlate = _plateDetailCache[plateId];
      final collection = data.collectionByRowKey[rowKey] ?? spec.collection;
      final status = data.statusByRowKey[rowKey];
      trace.log(
        'source=status_child_dialog_slot screen=${widget.screen} collection=$collection status=${status?.name ?? '-'} tab=${spec.id} area=${widget.area.trim()} plateId=$plateId plateNumber=${row.plateNumber} location=${row.location} cached=${cachedPlate != null} childDialogClosedBeforeDock=true autoTransitionPaused=true',
        progress: .28,
      );
      debugPrint(
        '[RealTimeStatusDotMap] event=status_dock_open source=status_child_dialog_slot screen=${widget.screen} collection=$collection status=${status?.name ?? '-'} tab=${spec.id} area=${widget.area.trim()} plateId=$plateId plateNumber=${row.plateNumber} location=${row.location} cached=${cachedPlate != null} childDialogClosedBeforeDock=true',
      );

      if (!mounted || !dockContext.mounted) return;
      await spec.openStatusDock(
        dockContext,
        RealTimePlateDetailRequest(
          plateId: plateId,
          plateNumber: row.plateNumber,
          area: widget.area.trim(),
          location: row.location,
          statusTitle: '${spec.label} 상태 처리',
          cachedPlate: cachedPlate,
          loadPlate: () => _fetchPlateDetail(plateId),
        ),
      );
      trace.log(
        'statusDock=closed source=status_child_dialog_slot childDialogClosedBeforeDock=true returnStage=parent_overview',
        progress: .9,
      );
      await trace.succeed('현황 상태 처리 빠른 실행이 종료되었습니다.');
    } catch (error, stackTrace) {
      if (trace != null) {
        await trace.fail(
          '현황 상태 처리 빠른 실행 중 오류가 발생했습니다.',
          error: error,
          stackTrace: stackTrace,
        );
      }
      rethrow;
    } finally {
      if (trace != null &&
          trace.developerMode &&
          rootContext != null &&
          rootContext.mounted) {
        await trace.showStatusDialog(rootContext);
      }
      _endDockAutoPause();
      _markUserActivity();
      _openingDetail = false;
    }
  }

  void _onParentPageChanged(String parent, int index, int count) {
    widget.controller.reportActiveParent(parent);
    _markUserActivity();
    debugPrint(
      '[RealTimeStatusDotMap] event=parent_page_changed screen=${widget.screen} parent=$parent index=$index count=$count interaction=parent_child_dialog_slot childPresentation=center_dialog childTransition=source_rect_expand_reverse_collapse childViewport=crop_fit childSlotTap=collapse_then_status_dock firebaseAdditionalRead=0',
    );
  }

  Widget _buildBoard(
    BuildContext context,
    List<LocationModel> locations,
    ViewDocRowsStore store,
    String area,
  ) {
    if (locations.isEmpty) {
      return const RealTimeExpandedEmpty(message: '주차 구역 데이터가 없습니다.');
    }

    final data = _buildBoardData(store, area);
    final groups = buildZoneGroups(
      rows: data.rows,
      meta: locations,
      selected: kRealTimeLocationAll,
      search: '',
    );

    if (groups.isEmpty) {
      return const RealTimeExpandedEmpty(message: '표시할 주차 구역이 없습니다.');
    }

    if (widget.controller.activeParent.trim().isEmpty) {
      widget.controller.reportActiveParent(groups.first.group);
    }

    final parentGridReady = groups
        .where((group) => group.parentSource?.parkingGrid != null)
        .length;
    final occupied = groups.fold<int>(
      0,
      (sum, group) => sum + group.totalCurrent,
    );
    final signature =
        '$area|${groups.length}|$parentGridReady|$occupied|${data.rows.length}';
    if (_lastRenderSignature != signature) {
      _lastRenderSignature = signature;
      debugPrint(
        '[RealTimeStatusDotMap] event=render screen=${widget.screen} area=$area mode=status_spatial parents=${groups.length} parentGridReady=$parentGridReady occupied=$occupied canonicalRows=${data.rows.length} source=view_doc_rows_store locationSource=${context.read<LocationState>().locations.isNotEmpty ? 'location_state' : 'sqlite'} interaction=parent_child_dialog_slot parentTap=child_zone parentSlotTap=disabled childPresentation=center_dialog childTransition=source_rect_expand_reverse_collapse childViewport=crop_fit childSlotTap=collapse_then_status_dock childDialogAutoPause=true systemBack=dialog_reverse_to_parent scrim=blur_dim occupiedLabel=plate_last4 slotHitPolicy=collision_safe_partition statusPriority=departure_in_progress>departure_request>parking_request>parked firebaseAdditionalRead=0',
      );
    }

    return KeyedSubtree(
      key: ValueKey<String>('status_dot_map:$area'),
      child: RealTimeLocationBoard(
        groups: groups,
        onPlateTap: (row) {
          unawaited(_openStatusDock(row, data));
        },
        onParentPageChanged: _onParentPageChanged,
        onUserActivity: _markUserActivity,
        onAutoPauseStart: _beginBoardAutoPause,
        onAutoPauseEnd: _endBoardAutoPause,
        externalDebugLines: widget.controller.debugLinesSnapshot,
        parentFocusRequest: _parentFocusRequest,
        onParentFocusApplied: (request, index) {
          widget.controller.reportActiveParent(request.parent);
          if (mounted && _parentFocusRequest?.serial == request.serial) {
            setState(() => _parentFocusRequest = null);
          }
          debugPrint(
            '[RealTimeStatusDotMap] event=parent_focus_applied screen=${widget.screen} serial=${request.serial} parent=${request.parent} index=$index count=${groups.length}',
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final area = widget.area.trim();
    final store = context.watch<ViewDocRowsStore>();
    final liveLocations = context.watch<LocationState>().locations;

    if (liveLocations.isNotEmpty) {
      return SizedBox.expand(
        child: _buildBoard(
          context,
          List<LocationModel>.of(liveLocations),
          store,
          area,
        ),
      );
    }

    if (_localFuture == null || _localArea != area) {
      _localArea = area;
      _localFuture = _loadLocationsFromLocal(area);
    }

    return SizedBox.expand(
      child: FutureBuilder<List<LocationModel>>(
        future: _localFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const RealTimeExpandedLoading();
          }
          final locations = snapshot.data ?? const <LocationModel>[];
          return _buildBoard(context, locations, store, area);
        },
      ),
    );
  }
}
