import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../operational_cache/application/operational_snapshot_revision_state.dart';
import '../operational_cache/domain/repositories/operational_local_repository.dart';

import '../../app/utils/developer_operation_status_dialog.dart';
import '../../features/location/applications/location_state.dart';
import '../../features/location/applications/parking_parent_order_state.dart';
import '../../features/location/domain/models/location_model.dart';
import '../page/application/common/type_auto_transition_guard.dart';
import '../plate/application/common/view_doc_rows_store.dart';
import '../plate/domain/models/plate_model.dart';
import '../plate/domain/repositories/plate_repository.dart';
import '../preview_package/parking_grid_3d_preview.dart';
import '../preview_package/parking_status_preview_card_area.dart';
import 'real_time_location_board.dart';
import 'real_time_parking_request_shelf.dart';
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
  final bool showParkingRequestShelf;

  const RealTimeStatusPreviewBody({
    super.key,
    required this.controller,
    required this.area,
    required this.screen,
    required this.overlay,
    required this.specs,
    this.showParkingRequestShelf = false,
  });

  @override
  State<RealTimeStatusPreviewBody> createState() =>
      _RealTimeStatusPreviewBodyState();
}

class _RealTimeStatusPreviewBodyState extends State<RealTimeStatusPreviewBody>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  static const String _boardPauseReason = '현황 주차 지도 다이얼로그';
  static const String _dockPauseReason = '현황 상태 처리 사이드 도크';
  static const String _requestTrayPauseReason = '현황 입차 요청 더보기';

  Future<List<LocationModel>>? _localFuture;
  String _localArea = '';
  int _lastOperationalRevision = -1;
  late final AnimationController _snapshotRefreshController;
  bool _openingDetail = false;
  String _lastRenderSignature = '';
  String _lastParkingRequestSignature = '';
  final List<String> _parkingRequestDebugLines = <String>[];
  RealTimeParentFocusRequest? _parentFocusRequest;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _snapshotRefreshController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      value: 1,
    );
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
      _lastOperationalRevision = -1;
      _lastParkingRequestSignature = '';
      _parkingRequestDebugLines.clear();
    }
  }

  @override
  void dispose() {
    widget.controller.unbind(this);
    widget.controller.unbindParentFocus(this);
    _snapshotRefreshController.dispose();
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

  void _beginRequestTrayAutoPause() {
    _autoGuard?.beginBlock(_requestTrayPauseReason);
  }

  void _endRequestTrayAutoPause() {
    _autoGuard?.endBlock(_requestTrayPauseReason);
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

  void _recordParkingRequestDebugLine(String line) {
    final normalized = line.trim();
    if (normalized.isEmpty) return;
    _parkingRequestDebugLines.add(normalized);
    if (_parkingRequestDebugLines.length > 120) {
      _parkingRequestDebugLines.removeRange(
        0,
        _parkingRequestDebugLines.length - 120,
      );
    }
  }

  DateTime? _requestCreatedAt(RealTimeRowVM row) => row.createdAt;

  int _compareParkingRequestRows(RealTimeRowVM a, RealTimeRowVM b) {
    final at = _requestCreatedAt(a);
    final bt = _requestCreatedAt(b);
    if (at != null && bt != null) {
      final timeCompare = bt.compareTo(at);
      if (timeCompare != 0) return timeCompare;
    } else if (at != null) {
      return -1;
    } else if (bt != null) {
      return 1;
    }
    final updatedA = a.updatedAt;
    final updatedB = b.updatedAt;
    if (updatedA != null && updatedB != null) {
      final updatedCompare = updatedB.compareTo(updatedA);
      if (updatedCompare != 0) return updatedCompare;
    } else if (updatedA != null) {
      return -1;
    } else if (updatedB != null) {
      return 1;
    }
    final plateCompare = a.plateNumber.compareTo(b.plateNumber);
    if (plateCompare != 0) return plateCompare;
    return a.plateId.compareTo(b.plateId);
  }

  List<RealTimeRowVM> _buildParkingRequestRows(
    ViewDocRowsStore store,
    String area,
  ) {
    if (!widget.showParkingRequestShelf) return const <RealTimeRowVM>[];
    const collection = 'parking_requests_view';
    final spec = _specForCollection(collection);
    if (spec == null) {
      final line =
          '[RealTimeStatusDotMap] event=parking_request_shelf_blocked reason=spec_missing screen=${widget.screen} collection=$collection area=$area';
      debugPrint(line);
      _recordParkingRequestDebugLine(line);
      return const <RealTimeRowVM>[];
    }
    final rows = store
        .rows(collection: collection, area: area)
        .map(
          (source) => RealTimeRowVM(
            plateId: source.plateId,
            plateNumber: source.plateNumber,
            location: source.location,
            primaryAt: source.primaryAt,
            updatedAt: source.updatedAt,
            createdAt: source.createdAt,
            isSelected: source.isSelected,
            selectedBy: source.selectedBy,
          ),
        )
        .toList(growable: false)
      ..sort(_compareParkingRequestRows);
    final signature = rows
        .map(
          (row) =>
              '${row.plateId}:${row.createdAt?.microsecondsSinceEpoch ?? 0}:${row.updatedAt?.microsecondsSinceEpoch ?? 0}',
        )
        .join('>');
    if (_lastParkingRequestSignature != signature) {
      _lastParkingRequestSignature = signature;
      final line =
          '[RealTimeStatusDotMap] event=parking_request_shelf_rows screen=${widget.screen} area=$area count=${rows.length} collection=$collection sort=createdAt_desc shelfSortLabel=최신→ traySortLabel=최신↓ updatedAtFallback=true source=view_doc_rows_store plateLabel=last4 presentation=list_surface morePresentation=anchored_list_surface relativeTime=tray action=direct_status_side_dock firebaseAdditionalRead=0';
      debugPrint(line);
      _recordParkingRequestDebugLine(line);
    }
    return List<RealTimeRowVM>.unmodifiable(rows);
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
    final repo = context.read<PlateRepository>();
    return repo.getPlate(id);
  }

  String _expectedPlateTypeNameForCollection(String collection) {
    switch (collection.trim()) {
      case 'parking_requests_view':
        return 'parkingRequests';
      case 'parking_completed_view':
        return 'parkingCompleted';
      case 'departure_requests_view':
        return 'departureRequests';
      default:
        return '-';
    }
  }

  Future<void> _openStatusDock(
    RealTimeRowVM row,
    _StatusBoardData data,
  ) async {
    final rowKey = _rowKey(row);
    final spec = data.specByRowKey[rowKey];
    if (spec == null) {
      debugPrint(
        '[RealTimeStatusDotMap] event=status_dock_blocked reason=spec_missing plateId=${row.plateId} plateNumber=${row.plateNumber} location=${row.location}',
      );
      return;
    }
    await _openStatusDockWithSpec(
      row: row,
      spec: spec,
      collection: data.collectionByRowKey[rowKey] ?? spec.collection,
      status: data.statusByRowKey[rowKey],
      source: 'status_child_dialog_slot',
      childDialogClosedBeforeDock: true,
    );
  }

  Future<void> _openParkingRequestDock(
    RealTimeRowVM row,
    String source,
  ) async {
    const collection = 'parking_requests_view';
    final spec = _specForCollection(collection);
    if (spec == null) {
      final line =
          '[RealTimeStatusDotMap] event=status_dock_blocked source=$source reason=parking_request_spec_missing plateId=${row.plateId} plateNumber=${row.plateNumber}';
      debugPrint(line);
      _recordParkingRequestDebugLine(line);
      return;
    }
    final status = row.isSelected
        ? ParkingSlotStatus.departureInProgress
        : ParkingSlotStatus.parkingRequest;
    await _openStatusDockWithSpec(
      row: row,
      spec: spec,
      collection: collection,
      status: status,
      source: source,
      childDialogClosedBeforeDock: false,
    );
  }

  Future<void> _openStatusDockWithSpec({
    required RealTimeRowVM row,
    required RealTimeTabSpec spec,
    required String collection,
    required ParkingSlotStatus? status,
    required String source,
    required bool childDialogClosedBeforeDock,
  }) async {
    if (_openingDetail) {
      debugPrint(
        '[RealTimeStatusDotMap] event=status_dock_blocked reason=already_open source=$source plateId=${row.plateId} plateNumber=${row.plateNumber}',
      );
      return;
    }
    final plateId = row.plateId.trim();
    if (plateId.isEmpty) {
      debugPrint(
        '[RealTimeStatusDotMap] event=status_dock_blocked reason=plate_id_empty source=$source plateNumber=${row.plateNumber}',
      );
      return;
    }

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
        initialMessage: source.startsWith('status_parking_request_')
            ? '현황 입차 요청 Shelf에서 상태 처리 Side Dock 실행을 준비했습니다.'
            : '현황 주차 지도 상태 처리 빠른 실행을 준비했습니다.',
        useCommonUi: true,
        developerModeMessage:
            '개발자 모드 ON: 완료 후 현황 상태 처리 debugPrint 코드를 복사할 수 있습니다.',
        standardModeMessage: '개발자 모드 OFF',
        showDialogImmediately: false,
      );

      if (source.startsWith('status_parking_request_') &&
          _parkingRequestDebugLines.isNotEmpty) {
        final snapshot = _parkingRequestDebugLines.length <= 24
            ? List<String>.of(_parkingRequestDebugLines)
            : _parkingRequestDebugLines
                .sublist(_parkingRequestDebugLines.length - 24);
        trace.log(
          'requestShelfDebugSnapshot=${snapshot.length} sort=createdAt_desc shelfSortLabel=최신→ traySortLabel=최신↓ plateLabel=last4 shelf=list_surface tray=anchored_list_surface trayRow=plate_last4_relative_time dotMapModified=false firebaseAdditionalRead=0',
          progress: .12,
        );
        for (final line in snapshot) {
          trace.log('requestShelfTrace=$line');
        }
      }

      final expectedPlateType =
          _expectedPlateTypeNameForCollection(collection);
      trace.log(
        'source=$source screen=${widget.screen} collection=$collection status=${status?.name ?? '-'} tab=${spec.id} area=${widget.area.trim()} plateId=$plateId plateNumber=${row.plateNumber} location=${row.location} detailCache=disabled expectedPlateType=$expectedPlateType childDialogClosedBeforeDock=$childDialogClosedBeforeDock requestTrayClosedBeforeDock=${source == 'status_parking_request_tray'} autoTransitionPaused=true',
        progress: .28,
      );
      debugPrint(
        '[RealTimeStatusDotMap] event=status_dock_open source=$source screen=${widget.screen} collection=$collection status=${status?.name ?? '-'} tab=${spec.id} area=${widget.area.trim()} plateId=$plateId plateNumber=${row.plateNumber} location=${row.location} detailCache=disabled expectedPlateType=$expectedPlateType childDialogClosedBeforeDock=$childDialogClosedBeforeDock requestTrayClosedBeforeDock=${source == 'status_parking_request_tray'}',
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
          cachedPlate: null,
          loadPlate: () async {
            final startedAt = DateTime.now();
            trace!.log(
              'plateDetailLoad=start source=$source plateId=$plateId collection=$collection expectedPlateType=$expectedPlateType cache=disabled repository=PlateRepository.getPlate',
              progress: .42,
            );
            debugPrint(
              '[RealTimeStatusDotMap] event=plate_detail_load_start source=$source plateId=$plateId collection=$collection expectedPlateType=$expectedPlateType cache=disabled repository=PlateRepository.getPlate',
            );
            try {
              final plate = await _fetchPlateDetail(plateId);
              final elapsedMs =
                  DateTime.now().difference(startedAt).inMilliseconds;
              final actualPlateType = plate?.typeEnum?.name ?? '-';
              final mismatch = plate != null &&
                  expectedPlateType != '-' &&
                  actualPlateType != expectedPlateType;
              trace.log(
                'plateDetailLoad=success source=$source plateId=$plateId found=${plate != null} expectedPlateType=$expectedPlateType actualPlateType=$actualPlateType viewPlateTypeMismatch=$mismatch elapsedMs=$elapsedMs cache=disabled',
                progress: .62,
              );
              debugPrint(
                '[RealTimeStatusDotMap] event=plate_detail_load_success source=$source plateId=$plateId found=${plate != null} collection=$collection expectedPlateType=$expectedPlateType actualPlateType=$actualPlateType viewPlateTypeMismatch=$mismatch elapsedMs=$elapsedMs cache=disabled',
              );
              return plate;
            } catch (error, stackTrace) {
              final elapsedMs =
                  DateTime.now().difference(startedAt).inMilliseconds;
              trace.log(
                'plateDetailLoad=failure source=$source plateId=$plateId expectedPlateType=$expectedPlateType elapsedMs=$elapsedMs cache=disabled error=$error',
                progress: .62,
              );
              debugPrint(
                '[RealTimeStatusDotMap] event=plate_detail_load_failure source=$source plateId=$plateId collection=$collection expectedPlateType=$expectedPlateType elapsedMs=$elapsedMs cache=disabled error=$error stackTrace=$stackTrace',
              );
              rethrow;
            }
          },
        ),
      );
      trace.log(
        'statusDock=closed source=$source childDialogClosedBeforeDock=$childDialogClosedBeforeDock returnStage=parent_overview',
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

  Widget _withParkingRequestShelf({
    required BuildContext context,
    required String area,
    required List<RealTimeRowVM> requestRows,
    required Widget board,
  }) {
    if (!widget.showParkingRequestShelf) return board;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Column(
      children: [
        AnimatedSize(
          alignment: Alignment.topCenter,
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: requestRows.isEmpty
              ? const SizedBox.shrink(
                  key: ValueKey<String>('parking_request_shelf_empty'),
                )
              : RealTimeParkingRequestShelf(
                  key: ValueKey<String>('parking_request_shelf:$area'),
                  rows: requestRows,
                  onDebugLine: _recordParkingRequestDebugLine,
                  onUserActivity: _markUserActivity,
                  onTrayOpen: _beginRequestTrayAutoPause,
                  onTrayClose: _endRequestTrayAutoPause,
                  onRequestTap: (row, source) async {
                    await _openParkingRequestDock(row, source);
                  },
                ),
        ),
        Expanded(child: board),
      ],
    );
  }

  Widget _buildBoard(
    BuildContext context,
    List<LocationModel> locations,
    ViewDocRowsStore store,
    String area,
  ) {
    final requestRows = _buildParkingRequestRows(store, area);
    if (locations.isEmpty) {
      return _withParkingRequestShelf(
        context: context,
        area: area,
        requestRows: requestRows,
        board: const RealTimeExpandedEmpty(
          message: '주차 구역 데이터가 없습니다.',
        ),
      );
    }

    final data = _buildBoardData(store, area);
    final parentOrderState = context.watch<ParkingParentOrderState>();
    final parentComparator = parentOrderState.comparatorForArea(
      area,
      fallback: naturalLocationCompare,
    );
    final groups = buildZoneGroups(
      rows: data.rows,
      meta: locations,
      selected: kRealTimeLocationAll,
      search: '',
      parentComparator: parentComparator,
    );

    if (groups.isEmpty) {
      return _withParkingRequestShelf(
        context: context,
        area: area,
        requestRows: requestRows,
        board: const RealTimeExpandedEmpty(
          message: '표시할 주차 구역이 없습니다.',
        ),
      );
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
    final departureRequested = data.statusByRowKey.values
        .where((status) => status == ParkingSlotStatus.departureRequest)
        .length;
    final departureInProgress = data.statusByRowKey.values
        .where((status) => status == ParkingSlotStatus.departureInProgress)
        .length;
    final parentOrderSignature = groups.map((group) => group.group).join('>');
    final signature =
        '$area|${groups.length}|$parentGridReady|$occupied|${data.rows.length}|$departureRequested|$departureInProgress|${requestRows.length}|$parentOrderSignature';
    if (_lastRenderSignature != signature) {
      _lastRenderSignature = signature;
      debugPrint(
        '[RealTimeStatusDotMap] event=render screen=${widget.screen} area=$area mode=status_spatial parents=${groups.length} parentGridReady=$parentGridReady occupied=$occupied canonicalRows=${data.rows.length} departureRequested=$departureRequested departureInProgress=$departureInProgress parkingRequestShelf=${widget.showParkingRequestShelf} parkingRequestCount=${requestRows.length} parkingRequestSort=createdAt_desc parkingRequestShelfSortLabel=최신→ parkingRequestTraySortLabel=최신↓ parkingRequestPlateLabel=last4 parkingRequestPresentation=list_surface parkingRequestMore=anchored_list_surface parkingRequestTrayRow=plate_last4_relative_time parkingRequestTap=direct_status_side_dock dotMapModified=false parentOrderSource=${parentOrderState.hasCustomOrder(area) ? 'user_persisted' : 'natural_fallback'} parentOrder=$parentOrderSignature source=view_doc_rows_store locationSource=${context.read<LocationState>().locations.isNotEmpty ? 'location_state' : 'sqlite'} interaction=parent_child_dialog_slot parentTap=child_zone parentSlotTap=disabled childPresentation=center_dialog childTransition=source_rect_expand_reverse_collapse childViewport=crop_fit childSlotTap=collapse_then_status_dock childDialogAutoPause=true systemBack=dialog_reverse_to_parent scrim=blur_dim occupiedLabel=plate_last4 departureVisual=statusDepartureRequested departurePulse=outer_halo_940ms_reverse plateTextMotion=static slotHitPolicy=collision_safe_partition statusPriority=departure_in_progress>departure_request>parking_request>parked firebaseAdditionalRead=0',
      );
    }

    final board = KeyedSubtree(
      key: ValueKey<String>('status_dot_map:$area'),
      child: RealTimeLocationBoard(
        groups: groups,
        statusForRow: (row) =>
            data.statusByRowKey[_rowKey(row)] ?? ParkingSlotStatus.parked,
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

    return _withParkingRequestShelf(
      context: context,
      area: area,
      requestRows: requestRows,
      board: board,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final area = widget.area.trim();
    final store = context.watch<ViewDocRowsStore>();
    final liveLocations = context.watch<LocationState>().locations;
    final operationalRevision = context
        .watch<OperationalSnapshotRevisionState>()
        .revisionOf(area);

    if (_lastOperationalRevision < 0) {
      _lastOperationalRevision = operationalRevision;
    } else if (_lastOperationalRevision != operationalRevision) {
      _lastOperationalRevision = operationalRevision;
      _localFuture = null;
      _localArea = '';
      context.read<OperationalSnapshotRevisionState>().reportConsumerRefresh(
            area: area,
            revision: operationalRevision,
            consumer: 'RealTimeStatusPreviewBody:${widget.screen}',
            action: 'sqlite_future_invalidate',
          );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _playSnapshotRefreshAnimation();
      });
    }

    if (liveLocations.isNotEmpty) {
      return _withSnapshotRefreshAnimation(
        SizedBox.expand(
          child: _buildBoard(
            context,
            List<LocationModel>.of(liveLocations),
            store,
            area,
          ),
        ),
      );
    }

    if (_localFuture == null || _localArea != area) {
      _localArea = area;
      _localFuture = _loadLocationsFromLocal(area);
    }

    return _withSnapshotRefreshAnimation(
      SizedBox.expand(
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
      ),
    );
  }
}
