import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/utils/developer_operation_status_dialog.dart';
import '../../../features/location/applications/location_state.dart';
import '../../../features/location/domain/models/grid_rect.dart';
import '../../../features/location/domain/models/location_model.dart';
import '../../../features/location/domain/models/parking_grid_model.dart';
import '../domain/models/plate_model.dart';
import '../../../design_system/common_ui/common_ui_components.dart';
import '../../../design_system/common_ui/common_ui_side_dock.dart';
import '../../../design_system/common_ui/common_ui_side_dock_frame.dart';
import '../../../design_system/common_ui/common_ui_side_rail.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../parking_dot_map/parking_status_dot_map_surface.dart';

Future<DeveloperOperationTrace> traceParkingStatusSectorSummary({
  required BuildContext context,
  required String mode,
  required String statusTitle,
  required String plateNumber,
  required String area,
  required String sectorId,
  required String sectorName,
}) async {
  final normalizedSectorId = sectorId.trim();
  final normalizedSectorName = sectorName.trim();
  final displaySector = normalizedSectorName.isEmpty ? '—' : normalizedSectorName;

  final trace = await DeveloperOperationTrace.start(
    context: context,
    title: '$statusTitle · $plateNumber',
    initialMessage: '$statusTitle 세션을 준비하고 있습니다.',
    developerModeMessage: '개발자 모드 ON: 상태 처리 전체 로그를 누적하고 복사할 수 있습니다.',
    standardModeMessage: '개발자 모드 OFF: 상태 처리 로그를 콘솔에 기록합니다.',
    useCommonUi: true,
    showDialogImmediately: false,
  );
  trace.log(
    'mode=$mode status=$statusTitle plate=$plateNumber area=$area',
    progress: .06,
  );
  trace.log(
    'sectorId=${normalizedSectorId.isEmpty ? "—" : normalizedSectorId} '
    'sectorName=$displaySector source=PlateModel',
    progress: .1,
  );
  trace.log(
    'presentation=right_side_dock direction=right_to_left motion=spring_slide_staggered_reveal '
    'presentationFirebaseRead=false presentationFirebaseWrite=false sessionTrace=enabled',
    progress: .14,
  );
  trace.log(
    'status_information_architecture=deduplicated summary=plate_status_sector management=left_rail railDesign=common_operations railMetricsSource=CommonSideRailMetrics management_distribution=visible_actions_equal_fill location=dot_map_and_path billing=compact_single_row memo=conditional footer=status_change_only',
    progress: .16,
  );
  return trace;
}

class _ParkingStatusTraceScope extends InheritedWidget {
  const _ParkingStatusTraceScope({
    required this.trace,
    required super.child,
  });

  final DeveloperOperationTrace trace;

  static DeveloperOperationTrace? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_ParkingStatusTraceScope>()
        ?.trace;
  }

  @override
  bool updateShouldNotify(_ParkingStatusTraceScope oldWidget) {
    return !identical(trace, oldWidget.trace);
  }
}

DeveloperOperationTrace? parkingStatusTraceOf(BuildContext context) {
  return _ParkingStatusTraceScope.maybeOf(context);
}

void parkingStatusTraceLog(
  BuildContext context,
  String message, {
  double? progress,
}) {
  final trace = parkingStatusTraceOf(context);
  if (trace != null) {
    trace.log(message, progress: progress);
    return;
  }
  debugPrint(message);
}

String parkingStatusHeaderSubtitle({
  required String statusTitle,
  String? sectorId,
  String? sectorName,
}) {
  final title = statusTitle.trim();
  final sector = (sectorName ?? '').trim();
  if (sector.isEmpty) return title;
  return '$title · $sector';
}

enum _ParkingStatusLocationPrecision {
  exact,
  region,
  unavailable,
}

class _ParkingStatusLocationResolution {
  const _ParkingStatusLocationResolution({
    required this.precision,
    required this.parentName,
    required this.childName,
    required this.reason,
    this.grid,
    this.targetRect,
    this.slotNo,
  });

  final _ParkingStatusLocationPrecision precision;
  final String parentName;
  final String childName;
  final String reason;
  final ParkingGridModel? grid;
  final GridRect? targetRect;
  final int? slotNo;

  String get debugPrecision {
    if (precision == _ParkingStatusLocationPrecision.exact) return 'exact';
    if (precision == _ParkingStatusLocationPrecision.region) return 'region';
    return 'unavailable';
  }

}

class _ParkingStatusLocationSnapshot {
  const _ParkingStatusLocationSnapshot({
    required this.locations,
    required this.source,
  });

  final List<LocationModel> locations;
  final String source;
}

class ParkingStatusVehicleLocationCard extends StatefulWidget {
  const ParkingStatusVehicleLocationCard({
    super.key,
    required this.plate,
    required this.area,
    this.attention = 0,
    this.expandToFill = false,
  });

  final PlateModel plate;
  final String area;
  final double attention;
  final bool expandToFill;

  @override
  State<ParkingStatusVehicleLocationCard> createState() =>
      _ParkingStatusVehicleLocationCardState();
}

class _ParkingStatusVehicleLocationCardState
    extends State<ParkingStatusVehicleLocationCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _markerController;
  Future<_ParkingStatusLocationResolution>? _future;
  String _signature = '';

  @override
  void initState() {
    super.initState();
    _markerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
    );
    _scheduleResolution();
  }

  @override
  void didUpdateWidget(covariant ParkingStatusVehicleLocationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleResolution();
  }

  @override
  void dispose() {
    _markerController.dispose();
    super.dispose();
  }

  String get _resolvedArea {
    final plateArea = widget.plate.area.trim();
    return plateArea.isNotEmpty ? plateArea : widget.area.trim();
  }

  void _scheduleResolution() {
    final signature = '${_resolvedArea}|${widget.plate.location.trim()}';
    if (_future != null && signature == _signature) return;
    _signature = signature;
    _markerController.reset();
    _future = _resolve();
  }

  Future<_ParkingStatusLocationSnapshot> _loadLocations(String area) async {
    final key = area.trim();
    if (key.isEmpty) {
      return const _ParkingStatusLocationSnapshot(
        locations: <LocationModel>[],
        source: 'none',
      );
    }
    try {
      final memoryLocations = context.read<LocationState>().locations;
      final matchingMemory = memoryLocations.where((item) {
        final itemArea = item.area.trim();
        return itemArea.isEmpty || itemArea == key;
      }).toList(growable: false);
      if (matchingMemory.isNotEmpty) {
        return _ParkingStatusLocationSnapshot(
          locations: List<LocationModel>.unmodifiable(matchingMemory),
          source: 'memory',
        );
      }
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('cached_locations_$key');
      if (raw == null || raw.trim().isEmpty) {
        return const _ParkingStatusLocationSnapshot(
          locations: <LocationModel>[],
          source: 'local_cache_empty',
        );
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const _ParkingStatusLocationSnapshot(
          locations: <LocationModel>[],
          source: 'local_cache_invalid',
        );
      }
      final out = <LocationModel>[];
      for (final item in decoded) {
        if (item is Map) {
          out.add(
            LocationModel.fromCacheMap(
              Map<String, dynamic>.from(item),
            ),
          );
        }
      }
      return _ParkingStatusLocationSnapshot(
        locations: List<LocationModel>.unmodifiable(out),
        source: 'local_cache',
      );
    } catch (error) {
      parkingStatusTraceLog(
        context,
        'vehicle_location_cache=error target=${widget.plate.plateNumber} error=$error',
      );
      return const _ParkingStatusLocationSnapshot(
        locations: <LocationModel>[],
        source: 'local_cache_error',
      );
    }
  }

  Future<_ParkingStatusLocationResolution> _resolve() async {
    final area = _resolvedArea;
    final snapshot = await _loadLocations(area);
    final resolution = _resolveParkingStatusLocation(
      locations: snapshot.locations,
      area: area,
      location: widget.plate.location,
    );
    if (mounted) {
      final billingState = resolveParkingCompletedBillingState(
        billingType: widget.plate.billingType,
        isLocked: widget.plate.isLockedFee == true,
      );
      parkingStatusTraceLog(
        context,
        'vehicle_location_map=render style=dot parent=${resolution.parentName.isEmpty ? "none" : resolution.parentName} '
        'child=${resolution.childName.isEmpty ? "none" : resolution.childName} '
        'precision=${resolution.debugPrecision} slot=${resolution.slotNo ?? 0} reason=${resolution.reason} '
        'sector=${(widget.plate.sectorName ?? '').trim().isEmpty ? "none" : (widget.plate.sectorName ?? '').trim()} '
        'billing_state=${parkingCompletedBillingStateDebugName(billingState)} source=${snapshot.source} '
        'firebaseRead=false firebaseWrite=false listener=false',
      );
      parkingStatusTraceLog(
        context,
        'vehicle_location_metadata=compact sector_scope=summary_header sector_chip=removed '
        'location_row=${resolution.grid == null ? "embedded" : "visible"} '
        'billing_summary=single_row billing_detail=${billingState == ParkingCompletedBillingState.settled ? "visible" : "hidden"} '
        'memo=${(widget.plate.customStatus ?? '').trim().isEmpty ? "hidden" : "visible"} '
        'dot_map=${resolution.grid == null ? "unavailable" : "preserved"}',
      );
      if (resolution.targetRect != null) {
        _markerController.forward(from: 0);
      }
    }
    return resolution;
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

    return _ParkingStatusReveal(
      order: 1,
      offsetY: 6,
      child: FutureBuilder<_ParkingStatusLocationResolution>(
        future: _future,
        builder: (context, snapshot) {
          final resolution = snapshot.data;
          final content = resolution == null
              ? _ParkingStatusLocationLoading(
                  key: const ValueKey<String>('location-loading'),
                  tokens: tokens,
                  expandToFill: widget.expandToFill,
                  showBillingDetail: resolveParkingCompletedBillingState(
                        billingType: widget.plate.billingType,
                        isLocked: widget.plate.isLockedFee == true,
                      ) ==
                      ParkingCompletedBillingState.settled,
                  showMemo:
                      (widget.plate.customStatus ?? '').trim().isNotEmpty,
                )
              : _ParkingStatusLocationContent(
                  key: ValueKey<String>(
                    '${resolution.parentName}|${resolution.grid?.rows ?? 0}|${resolution.grid?.cols ?? 0}|${resolution.grid == null ? resolution.reason : "map"}',
                  ),
                  resolution: resolution,
                  plate: widget.plate,
                  attention: widget.attention,
                  markerAnimation: _markerController,
                  reduceMotion: reduceMotion,
                  tokens: tokens,
                  textTheme: textTheme,
                  expandToFill: widget.expandToFill,
                );

          final switcher = AnimatedSwitcher(
            duration:
                reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            layoutBuilder: widget.expandToFill
                ? (currentChild, previousChildren) {
                    return Stack(
                      fit: StackFit.expand,
                      alignment: Alignment.center,
                      children: [
                        ...previousChildren,
                        if (currentChild != null) currentChild,
                      ],
                    );
                  }
                : AnimatedSwitcher.defaultLayoutBuilder,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, .025),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
                  child: child,
                ),
              );
            },
            child: content,
          );
          if (!widget.expandToFill) return switcher;
          return SizedBox.expand(child: switcher);
        },
      ),
    );
  }
}

class _ParkingStatusLocationLoading extends StatelessWidget {
  const _ParkingStatusLocationLoading({
    super.key,
    required this.tokens,
    required this.expandToFill,
    required this.showBillingDetail,
    required this.showMemo,
  });

  final CommonUiTokens tokens;
  final bool expandToFill;
  final bool showBillingDetail;
  final bool showMemo;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final metrics = ParkingStatusAdaptiveLayout.maybeOf(context);
    final variant = metrics?.variant ?? ParkingStatusPrimaryVariant.normal;
    final compact = variant != ParkingStatusPrimaryVariant.normal;
    final ultra = variant == ParkingStatusPrimaryVariant.ultraCompact;
    final padding = metrics?.cardPadding ?? 12.0;
    final headerGap = ultra ? 5.0 : compact ? 6.0 : 8.0;
    final metadataGap = ultra ? 3.0 : compact ? 4.0 : 5.0;
    final naturalMapHeight = metrics?.mapMinHeight ??
        (MediaQuery.sizeOf(context).height < 620 ? 144.0 : 158.0);
    final header = Text(
      '차량 위치',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: textTheme.titleSmall?.copyWith(
        color: tokens.textPrimary,
        fontWeight: FontWeight.w900,
      ),
    );
    final mapSkeleton = Container(
      decoration: BoxDecoration(
        color: tokens.surfaceOverlay.withOpacity(.55),
        borderRadius: BorderRadius.circular(12),
      ),
    );
    final metadataSkeleton = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ParkingStatusMetadataSkeleton(tokens: tokens, widthFactor: .72),
        SizedBox(height: metadataGap),
        _ParkingStatusMetadataSkeleton(tokens: tokens, widthFactor: .9),
        if (showBillingDetail) ...[
          SizedBox(height: metadataGap),
          _ParkingStatusMetadataSkeleton(tokens: tokens, widthFactor: .48),
        ],
        if (showMemo) ...[
          SizedBox(height: metadataGap),
          _ParkingStatusMetadataSkeleton(tokens: tokens, widthFactor: .78),
        ],
      ],
    );

    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: expandToFill
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                SizedBox(height: headerGap),
                Expanded(child: mapSkeleton),
                SizedBox(height: headerGap),
                metadataSkeleton,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                SizedBox(height: headerGap),
                SizedBox(height: naturalMapHeight, child: mapSkeleton),
                SizedBox(height: headerGap),
                metadataSkeleton,
              ],
            ),
    );
  }
}

class _ParkingStatusMetadataSkeleton extends StatelessWidget {
  const _ParkingStatusMetadataSkeleton({
    required this.tokens,
    required this.widthFactor,
  });

  final CommonUiTokens tokens;
  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: widthFactor,
        child: Container(
          height: 16,
          decoration: BoxDecoration(
            color: tokens.surfaceOverlay.withOpacity(.55),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}

class _ParkingStatusLocationContent extends StatelessWidget {
  const _ParkingStatusLocationContent({
    super.key,
    required this.resolution,
    required this.plate,
    required this.attention,
    required this.markerAnimation,
    required this.reduceMotion,
    required this.tokens,
    required this.textTheme,
    required this.expandToFill,
  });

  final _ParkingStatusLocationResolution resolution;
  final PlateModel plate;
  final double attention;
  final Animation<double> markerAnimation;
  final bool reduceMotion;
  final CommonUiTokens tokens;
  final TextTheme textTheme;
  final bool expandToFill;

  Widget _mapSurface(ParkingGridModel grid) {
    return AnimatedBuilder(
      animation: markerAnimation,
      builder: (context, _) {
        return ParkingStatusDotMapSurface(
          grid: grid,
          targetRect: resolution.targetRect,
          exact: resolution.precision ==
              _ParkingStatusLocationPrecision.exact,
          pulse: reduceMotion ? 1 : markerAnimation.value,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final grid = resolution.grid;
    final displayLocation = _parkingStatusDisplayLocation(plate.location);
    final billingState = resolveParkingCompletedBillingState(
      billingType: plate.billingType,
      isLocked: plate.isLockedFee == true,
    );
    final billingType = billingState == ParkingCompletedBillingState.notApplicable
        ? '정산 없음'
        : (plate.billingType ?? '').trim();
    final paymentMethod = (plate.paymentMethod ?? '').trim();
    final billingDetail = billingState != ParkingCompletedBillingState.settled
        ? ''
        : '₩${plate.lockedFeeAmount ?? 0}${paymentMethod.isEmpty ? '' : ' · $paymentMethod'}';
    final memo = (plate.customStatus ?? '').trim();
    final safeAttention =
        reduceMotion ? 0.0 : attention.clamp(0.0, 1.0).toDouble();
    final isUnsettled = billingState == ParkingCompletedBillingState.unsettled;
    final borderColor = Color.lerp(
      tokens.borderSubtle,
      tokens.danger,
      isUnsettled ? safeAttention * .8 : 0,
    )!;
    final backgroundColor = Color.lerp(
      tokens.surface,
      tokens.dangerContainer,
      isUnsettled ? safeAttention * .18 : 0,
    )!;
    final metrics = ParkingStatusAdaptiveLayout.maybeOf(context);
    final variant = metrics?.variant ?? ParkingStatusPrimaryVariant.normal;
    final compact = variant != ParkingStatusPrimaryVariant.normal;
    final ultra = variant == ParkingStatusPrimaryVariant.ultraCompact;
    final padding = metrics?.cardPadding ?? 12.0;
    final headerGap = ultra ? 5.0 : compact ? 6.0 : 8.0;
    final metadataGap = ultra ? 3.0 : compact ? 4.0 : 5.0;
    final mapMinHeight = metrics?.mapMinHeight ??
        (MediaQuery.sizeOf(context).height < 620 ? 144.0 : 158.0);
    final mapMaxHeight = metrics?.mapMaxHeight ??
        (MediaQuery.sizeOf(context).height < 620 ? 202.0 : 232.0);
    final locationMaxLines = ultra ? 1 : compact ? 1 : 2;
    final memoMaxLines = variant == ParkingStatusPrimaryVariant.normal ? 2 : 1;

    final header = Text(
      '차량 위치',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: textTheme.titleSmall?.copyWith(
        color: tokens.textPrimary,
        fontWeight: FontWeight.w900,
      ),
    );
    final compactMetadata = _ParkingStatusCompactMetadata(
      showLocation: grid != null,
      location: displayLocation,
      locationMaxLines: locationMaxLines,
      billingType: billingType,
      billingState: billingState,
      billingDetail: billingDetail,
      memo: memo,
      memoMaxLines: memoMaxLines,
      attention: safeAttention,
      gap: metadataGap,
    );

    return AnimatedContainer(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
      curve: CommonUiMotion.standard,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          SizedBox(height: headerGap),
          if (grid != null && expandToFill)
            Expanded(child: _mapSurface(grid))
          else if (grid != null)
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final ratio = grid.cols <= 0 || grid.rows <= 0
                    ? .5
                    : grid.rows / grid.cols;
                final height = (width * ratio.clamp(.42, .78))
                    .clamp(mapMinHeight, mapMaxHeight)
                    .toDouble();
                return SizedBox(height: height, child: _mapSurface(grid));
              },
            )
          else
            _ParkingStatusTextOnlyLocation(
              location: displayLocation,
              textOnly: resolution.reason == 'text_only_parent',
            ),
          SizedBox(height: headerGap),
          compactMetadata,
        ],
      ),
    );
  }
}

class _ParkingStatusTextOnlyLocation extends StatelessWidget {
  const _ParkingStatusTextOnlyLocation({
    required this.location,
    required this.textOnly,
  });

  final String location;
  final bool textOnly;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.surfaceOverlay.withOpacity(.38),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.place_outlined, size: 17, color: tokens.iconSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  location,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: tokens.textPrimary,
                    height: 1.25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  textOnly
                      ? '배치도 없이 위치명으로 관리됩니다.'
                      : '2D 배치 정보를 확인할 수 없습니다.',
                  style: textTheme.labelSmall?.copyWith(
                    color: tokens.textSecondary,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ParkingStatusCompactMetadata extends StatelessWidget {
  const _ParkingStatusCompactMetadata({
    required this.showLocation,
    required this.location,
    required this.locationMaxLines,
    required this.billingType,
    required this.billingState,
    required this.billingDetail,
    required this.memo,
    required this.memoMaxLines,
    required this.attention,
    required this.gap,
  });

  final bool showLocation;
  final String location;
  final int locationMaxLines;
  final String billingType;
  final ParkingCompletedBillingState billingState;
  final String billingDetail;
  final String memo;
  final int memoMaxLines;
  final double attention;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final children = <Widget>[
      if (showLocation)
        _ParkingStatusCompactMetadataRow(
          semanticLabel: '차량 위치, $location',
          icon: Icons.place_outlined,
          child: Text(
            location,
            maxLines: locationMaxLines,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: CommonUiTheme.of(context).textPrimary,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
      _ParkingStatusBillingSummary(
        billingType: billingType,
        billingState: billingState,
        billingDetail: billingDetail,
        attention: attention,
      ),
      if (memo.trim().isNotEmpty)
        _ParkingStatusCompactMetadataRow(
          key: ValueKey<String>('memo-${memo.trim()}'),
          semanticLabel: '상태 메모, ${memo.trim()}',
          icon: Icons.notes_rounded,
          child: Text(
            memo.trim(),
            maxLines: memoMaxLines,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: CommonUiTheme.of(context).textPrimary,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
    ];

    return AnimatedSize(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
      curve: CommonUiMotion.standard,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
        switchInCurve: CommonUiMotion.enter,
        switchOutCurve: CommonUiMotion.exit,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, .025),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        child: Column(
          key: ValueKey<String>(
            '${showLocation ? location : "embedded"}|${billingState.name}|$billingType|$billingDetail|${memo.trim()}',
          ),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < children.length; index++) ...[
              children[index],
              if (index != children.length - 1) SizedBox(height: gap),
            ],
          ],
        ),
      ),
    );
  }
}

class _ParkingStatusCompactMetadataRow extends StatelessWidget {
  const _ParkingStatusCompactMetadataRow({
    super.key,
    required this.semanticLabel,
    required this.icon,
    required this.child,
  });

  final String semanticLabel;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Semantics(
      container: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 15, color: tokens.iconSecondary),
          ),
          const SizedBox(width: 6),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _ParkingStatusBillingSummary extends StatelessWidget {
  const _ParkingStatusBillingSummary({
    required this.billingType,
    required this.billingState,
    required this.billingDetail,
    required this.attention,
  });

  final String billingType;
  final ParkingCompletedBillingState billingState;
  final String billingDetail;
  final double attention;

  String get _statusLabel {
    if (billingState == ParkingCompletedBillingState.unsettled) return '미정산';
    if (billingState == ParkingCompletedBillingState.settled) return '완료';
    return '';
  }

  String get _semanticStatus {
    if (billingState == ParkingCompletedBillingState.unsettled) return '미정산';
    if (billingState == ParkingCompletedBillingState.settled) return '정산 완료';
    return '정산 대상 아님';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final type = billingState == ParkingCompletedBillingState.notApplicable
        ? '정산 없음'
        : billingType.trim().isEmpty
            ? '정산 없음'
            : billingType.trim();
    final semantic = billingState == ParkingCompletedBillingState.notApplicable
        ? '정산 없음'
        : billingDetail.trim().isEmpty
            ? '정산 방식 $type, 정산 상태 $_semanticStatus'
            : '정산 방식 $type, 정산 상태 $_semanticStatus, $billingDetail';
    final unsettled = billingState == ParkingCompletedBillingState.unsettled;
    final settled = billingState == ParkingCompletedBillingState.settled;
    final statusColor = unsettled
        ? tokens.danger
        : settled
            ? tokens.success
            : tokens.textSecondary;
    final statusBackground = unsettled
        ? Color.lerp(tokens.surfaceOverlay, tokens.dangerContainer, .38 + attention * .32)!
        : settled
            ? tokens.successContainer.withOpacity(.58)
            : tokens.surfaceOverlay.withOpacity(.5);
    final statusBorder = unsettled
        ? Color.lerp(tokens.borderSubtle, tokens.danger, .35 + attention * .45)!
        : settled
            ? tokens.success.withOpacity(.34)
            : tokens.borderSubtle;

    return Semantics(
      container: true,
      label: semantic,
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              Icons.receipt_long_rounded,
              size: 15,
              color: unsettled ? tokens.danger : tokens.iconSecondary,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: AnimatedSwitcher(
              duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
              switchInCurve: CommonUiMotion.enter,
              switchOutCurve: CommonUiMotion.exit,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, .05),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: Column(
                key: ValueKey<String>('$type|$billingDetail'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: tokens.textPrimary,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (billingDetail.trim().isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      billingDetail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall?.copyWith(
                        color: tokens.textSecondary,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_statusLabel.isNotEmpty) ...[
            const SizedBox(width: 7),
            AnimatedContainer(
              duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
              curve: CommonUiMotion.standard,
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: statusBackground,
                borderRadius: BorderRadius.circular(CommonUiShapes.pill),
                border: Border.all(color: statusBorder),
              ),
              child: AnimatedSwitcher(
                duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
                child: Text(
                  _statusLabel,
                  key: ValueKey<String>(_statusLabel),
                  style: textTheme.labelSmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _parkingStatusDisplayLocation(String raw) {
  final segments = _parkingStatusLocationSegments(raw);
  if (segments.isEmpty) return '위치 미지정';
  return segments.take(3).join(' - ');
}

_ParkingStatusLocationResolution _resolveParkingStatusLocation({
  required List<LocationModel> locations,
  required String area,
  required String location,
}) {
  final segments = _parkingStatusLocationSegments(location);
  if (segments.isEmpty) {
    return const _ParkingStatusLocationResolution(
      precision: _ParkingStatusLocationPrecision.unavailable,
      parentName: '',
      childName: '',
      reason: 'location_empty',
    );
  }

  final requestedArea = area.trim();
  final pool = requestedArea.isEmpty
      ? locations
      : locations.where((item) {
          final itemArea = item.area.trim();
          return itemArea.isEmpty || itemArea == requestedArea;
        }).toList(growable: false);
  final parentName = segments.first;
  final childName = segments.length >= 2 ? segments[1] : '';
  final slotNo =
      segments.length >= 3 ? _parkingStatusFirstInt(segments[2]) : null;

  LocationModel? parent;
  for (final item in pool) {
    if (_parkingStatusNameEquals(item.locationName, parentName) ||
        _parkingStatusNameEquals(item.id, parentName)) {
      parent = item;
      break;
    }
  }

  LocationModel? child;
  if (childName.isNotEmpty) {
    for (final item in pool) {
      if (!_parkingStatusNameEquals(item.locationName, childName)) continue;
      if (parent == null || _parkingStatusBelongsToParent(item, parent)) {
        child = item;
        break;
      }
    }
  }

  if (parent == null && child != null) {
    final parentId = (child.parentId ?? '').trim();
    final parentRef = (child.parent ?? '').trim();
    for (final item in pool) {
      if ((parentId.isNotEmpty && item.id == parentId) ||
          (parentRef.isNotEmpty &&
              (_parkingStatusNameEquals(item.locationName, parentRef) ||
                  _parkingStatusNameEquals(item.id, parentRef)))) {
        parent = item;
        break;
      }
    }
  }

  final grid = parent?.parkingGrid;
  if (parent == null) {
    return _ParkingStatusLocationResolution(
      precision: _ParkingStatusLocationPrecision.unavailable,
      parentName: parentName,
      childName: childName,
      reason: pool.isEmpty ? 'location_metadata_missing' : 'parent_not_found',
    );
  }
  if (grid == null || grid.rows <= 0 || grid.cols <= 0) {
    return _ParkingStatusLocationResolution(
      precision: _ParkingStatusLocationPrecision.unavailable,
      parentName: parent.locationName,
      childName: childName,
      reason: 'text_only_parent',
    );
  }

  if (child != null && slotNo != null && slotNo > 0) {
    ChildSlot? targetSlot;
    for (final slot in child.childSlots) {
      if (slot.no == slotNo) {
        targetSlot = slot;
        break;
      }
    }
    if (targetSlot != null) {
      return _ParkingStatusLocationResolution(
        precision: _ParkingStatusLocationPrecision.exact,
        parentName: parent.locationName,
        childName: child.locationName,
          reason: 'child_slot_exact',
        grid: grid,
        targetRect: GridRect(
          r0: targetSlot.r0,
          c0: targetSlot.c0,
          r1: targetSlot.r1,
          c1: targetSlot.c1,
        ).normalized(),
        slotNo: slotNo,
      );
    }
  }

  if (child != null) {
    final rect = child.childRect?.normalized();
    if (rect != null) {
      return _ParkingStatusLocationResolution(
        precision: _ParkingStatusLocationPrecision.region,
        parentName: parent.locationName,
        childName: child.locationName,
          reason: slotNo == null ? 'child_region' : 'slot_unresolved_child_region',
        grid: grid,
        targetRect: rect,
        slotNo: slotNo,
      );
    }
    if (child.isTowerChild && grid.towerRects.isNotEmpty) {
      return _ParkingStatusLocationResolution(
        precision: _ParkingStatusLocationPrecision.region,
        parentName: parent.locationName,
        childName: child.locationName,
          reason: 'tower_region',
        grid: grid,
        targetRect: grid.towerRects.first.normalized(),
        slotNo: slotNo,
      );
    }
  }

  return _ParkingStatusLocationResolution(
    precision: _ParkingStatusLocationPrecision.unavailable,
    parentName: parent.locationName,
    childName: childName,
    reason: 'target_coordinate_missing',
    grid: grid,
    slotNo: slotNo,
  );
}

List<String> _parkingStatusLocationSegments(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return const <String>[];
  return value
      .split(RegExp(r'\s+-\s+'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

int? _parkingStatusFirstInt(String raw) {
  final match = RegExp(r'(\d+)').firstMatch(raw);
  if (match == null) return null;
  return int.tryParse(match.group(1) ?? '');
}

String _parkingStatusNameKey(String raw) {
  return raw.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
}

bool _parkingStatusNameEquals(String a, String b) {
  final ka = _parkingStatusNameKey(a);
  final kb = _parkingStatusNameKey(b);
  return ka.isNotEmpty && ka == kb;
}

bool _parkingStatusBelongsToParent(
  LocationModel child,
  LocationModel parent,
) {
  final parentId = (child.parentId ?? '').trim();
  if (parentId.isNotEmpty && parentId == parent.id) return true;
  final parentRef = (child.parent ?? '').trim();
  if (parentRef.isEmpty) return false;
  return _parkingStatusNameEquals(parentRef, parent.locationName) ||
      _parkingStatusNameEquals(parentRef, parent.id);
}

Future<DeveloperOperationTrace> traceParkingStatusLoadingSession({
  required BuildContext context,
  required String mode,
  required String statusTitle,
  required String plateId,
  required String plateNumber,
  required String area,
  required String location,
  required bool cached,
}) async {
  final trace = await DeveloperOperationTrace.start(
    context: context,
    title: '$statusTitle · $plateNumber',
    initialMessage: '$statusTitle 세션을 준비하고 있습니다.',
    developerModeMessage: '개발자 모드 ON: 상태 처리 전체 로그를 누적하고 복사할 수 있습니다.',
    standardModeMessage: '개발자 모드 OFF: 상태 처리 로그를 콘솔에 기록합니다.',
    useCommonUi: true,
    showDialogImmediately: false,
  );
  trace.log(
    'mode=$mode status=$statusTitle plateId=$plateId plate=$plateNumber area=$area location=$location',
    progress: .05,
  );
  trace.log(
    'presentation=right_side_dock direction=right_to_left motion=spring_slide_staggered_reveal detailLoad=inside_dock management=left_rail footer=status_change_only cacheHit=$cached',
    progress: .1,
  );
  return trace;
}

typedef ParkingStatusLoadedContentBuilder = Widget Function(
  BuildContext context,
  PlateModel plate,
);

Future<T?> showParkingStatusLoadingSideDock<T>({
  required BuildContext context,
  required String mode,
  required String statusTitle,
  required String plateId,
  required String plateNumber,
  required String area,
  required String location,
  required PlateModel? cachedPlate,
  required Future<PlateModel?> Function() loadPlate,
  required ParkingStatusLoadedContentBuilder loadedBuilder,
  bool barrierDismissible = true,
  bool finalizeTrace = true,
  Future<void> Function(DeveloperOperationTrace trace, T? result)? onClosed,
}) async {
  final trace = await traceParkingStatusLoadingSession(
    context: context,
    mode: mode,
    statusTitle: statusTitle,
    plateId: plateId,
    plateNumber: plateNumber,
    area: area,
    location: location,
    cached: cachedPlate != null,
  );
  if (!context.mounted) return null;

  final result = await showParkingStatusSideDock<T>(
    context: context,
    trace: trace,
    barrierDismissible: barrierDismissible,
    finalizeTrace: finalizeTrace,
    builder: (dockContext) => _ParkingStatusDetailLoader(
      statusTitle: statusTitle,
      plateId: plateId,
      plateNumber: plateNumber,
      location: location,
      cachedPlate: cachedPlate,
      loadPlate: loadPlate,
      loadedBuilder: loadedBuilder,
      trace: trace,
    ),
  );
  final callback = onClosed;
  if (callback != null) {
    await callback(trace, result);
  }
  return result;
}

class _ParkingStatusDetailLoader extends StatefulWidget {
  const _ParkingStatusDetailLoader({
    required this.statusTitle,
    required this.plateId,
    required this.plateNumber,
    required this.location,
    required this.cachedPlate,
    required this.loadPlate,
    required this.loadedBuilder,
    required this.trace,
  });

  final String statusTitle;
  final String plateId;
  final String plateNumber;
  final String location;
  final PlateModel? cachedPlate;
  final Future<PlateModel?> Function() loadPlate;
  final ParkingStatusLoadedContentBuilder loadedBuilder;
  final DeveloperOperationTrace trace;

  @override
  State<_ParkingStatusDetailLoader> createState() =>
      _ParkingStatusDetailLoaderState();
}

class _ParkingStatusDetailLoaderState extends State<_ParkingStatusDetailLoader>
    with SingleTickerProviderStateMixin {
  static const Duration _placeholderDelay = Duration(milliseconds: 140);

  late final AnimationController _pulseController;
  PlateModel? _plate;
  bool _loading = false;
  bool _showPlaceholder = false;
  String? _errorMessage;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: .35,
      upperBound: .72,
      value: .35,
    )..repeat(reverse: true);

    final cached = widget.cachedPlate;
    if (cached != null) {
      _plate = cached;
      widget.trace.log(
        'plate_detail=ready source=cache loadMs=0 loadingPlaceholderShown=false sectorId=${cached.sectorId ?? ""} sectorName=${cached.sectorName ?? ""}',
        progress: .24,
      );
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    if (_loading && _plate == null) {
      widget.trace.log('plate_detail=load_cancelled reason=dock_closed');
    }
    _loadGeneration++;
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final stopwatch = Stopwatch()..start();
    setState(() {
      _loading = true;
      _showPlaceholder = false;
      _errorMessage = null;
    });
    widget.trace.log(
      'plate_detail=load_start source=repository_or_inflight plateId=${widget.plateId}',
      progress: .18,
    );

    unawaited(Future<void>.delayed(_placeholderDelay, () {
      if (!mounted || generation != _loadGeneration || !_loading) return;
      setState(() => _showPlaceholder = true);
      widget.trace.log(
        'plate_detail=loading_placeholder_shown delayMs=${_placeholderDelay.inMilliseconds}',
        progress: .2,
      );
    }));

    try {
      final plate = await widget.loadPlate();
      stopwatch.stop();
      if (!mounted || generation != _loadGeneration) return;

      if (plate == null) {
        widget.trace.log(
          'plate_detail=not_found loadMs=${stopwatch.elapsedMilliseconds} loadingPlaceholderShown=$_showPlaceholder',
          progress: .28,
        );
        setState(() {
          _loading = false;
          _plate = null;
          _errorMessage = '원본 차량 정보를 찾을 수 없습니다.';
        });
        return;
      }

      widget.trace.log(
        'plate_detail=ready source=repository_or_inflight loadMs=${stopwatch.elapsedMilliseconds} loadingPlaceholderShown=$_showPlaceholder sectorId=${plate.sectorId ?? ""} sectorName=${plate.sectorName ?? ""}',
        progress: .3,
      );
      setState(() {
        _loading = false;
        _plate = plate;
        _errorMessage = null;
      });
    } catch (error, stackTrace) {
      stopwatch.stop();
      if (!mounted || generation != _loadGeneration) return;
      widget.trace.log(
        'plate_detail=load_failed loadMs=${stopwatch.elapsedMilliseconds} error=$error',
        progress: .28,
      );
      widget.trace.log('plate_detail=load_stacktrace $stackTrace');
      setState(() {
        _loading = false;
        _plate = null;
        _errorMessage = '원본 차량 정보를 불러오지 못했습니다.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final plate = _plate;
    final child = plate != null
        ? widget.loadedBuilder(context, plate)
        : _errorMessage != null
            ? _ParkingStatusLoadError(
                plateNumber: widget.plateNumber,
                statusTitle: widget.statusTitle,
                message: _errorMessage!,
                onRetry: _load,
              )
            : _ParkingStatusLoadingPlaceholder(
                plateNumber: widget.plateNumber,
                statusTitle: widget.statusTitle,
                location: widget.location,
                visible: _showPlaceholder,
                pulse: _pulseController,
              );

    return AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, .025),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(
        key: ValueKey<String>(
          plate != null
              ? 'ready:${plate.plateNumber}'
              : _errorMessage != null
                  ? 'error'
                  : _showPlaceholder
                      ? 'loading-placeholder'
                      : 'loading-shell',
        ),
        child: child,
      ),
    );
  }
}

class _ParkingStatusLoadingPlaceholder extends StatelessWidget {
  const _ParkingStatusLoadingPlaceholder({
    required this.plateNumber,
    required this.statusTitle,
    required this.location,
    required this.visible,
    required this.pulse,
  });

  final String plateNumber;
  final String statusTitle;
  final String location;
  final bool visible;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    return ParkingStatusSideDockFrame(
      title: plateNumber,
      subtitle: parkingStatusHeaderSubtitle(statusTitle: statusTitle),
      icon: Icons.settings_rounded,
      onClose: () => Navigator.of(context).pop(),
      leadingRail: _ParkingStatusLoadingManagementRail(
        visible: visible,
        pulse: pulse,
      ),
      footer: _ParkingStatusLoadingPrimaryFooter(
        visible: visible,
        pulse: pulse,
      ),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 18),
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: MediaQuery.maybeOf(context)?.disableAnimations == true
              ? Duration.zero
              : const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: IgnorePointer(
            ignoring: !visible,
            child: _ParkingStatusSkeleton(
              location: location,
              pulse: pulse,
            ),
          ),
        ),
      ),
    );
  }
}


class _ParkingStatusLoadingManagementRail extends StatelessWidget {
  const _ParkingStatusLoadingManagementRail({
    required this.visible,
    required this.pulse,
  });

  final bool visible;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final adaptive = ParkingStatusAdaptiveLayout.maybeOf(context);
    final media = MediaQuery.maybeOf(context);
    final reduceMotion = media?.disableAnimations ?? false;
    final textScale = media?.textScaler.scale(1.0) ?? 1.0;
    final variant = adaptive?.variant ??
        (textScale >= 1.30
            ? ParkingStatusPrimaryVariant.ultraCompact
            : textScale >= 1.15
                ? ParkingStatusPrimaryVariant.compact
                : ParkingStatusPrimaryVariant.normal);
    final compact = variant != ParkingStatusPrimaryVariant.normal;
    final ultra = variant == ParkingStatusPrimaryVariant.ultraCompact;
    final headerHeight = ultra ? 34.0 : compact ? 36.0 : 38.0;
    final outerHorizontal = ultra ? 2.0 : 3.0;
    final outerVertical = ultra ? 6.0 : 7.0;
    final actionInsetHorizontal = ultra ? 2.0 : compact ? 3.0 : 4.0;
    final actionInsetVertical = ultra ? 2.0 : 3.0;

    Widget block({double? height, double radius = 10}) {
      return AnimatedBuilder(
        animation: pulse,
        builder: (context, _) {
          return Container(
            height: height,
            decoration: BoxDecoration(
              color: tokens.surfaceOverlay.withOpacity(
                reduceMotion ? .55 : pulse.value,
              ),
              borderRadius: BorderRadius.circular(radius),
            ),
          );
        },
      );
    }

    return AnimatedOpacity(
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      opacity: visible ? 1 : 0,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: outerHorizontal,
          vertical: outerVertical,
        ),
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: tokens.borderSubtle)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: headerHeight,
              child: Center(
                child: SizedBox(
                  width: 34,
                  child: block(height: 24, radius: 7),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < 4; index++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: actionInsetHorizontal,
                          vertical: actionInsetVertical,
                        ),
                        child: block(radius: 12),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParkingStatusLoadingPrimaryFooter extends StatelessWidget {
  const _ParkingStatusLoadingPrimaryFooter({
    required this.visible,
    required this.pulse,
  });

  final bool visible;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    Widget block(double width, double height, {double radius = 9}) {
      return AnimatedBuilder(
        animation: pulse,
        builder: (context, _) {
          return Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: tokens.surfaceOverlay.withOpacity(
                reduceMotion ? .55 : pulse.value,
              ),
              borderRadius: BorderRadius.circular(radius),
            ),
          );
        },
      );
    }

    return AnimatedOpacity(
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      opacity: visible ? 1 : 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(2, 9, 2, 2),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: tokens.borderSubtle)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: block(72, 14, radius: 6),
            ),
            const SizedBox(height: 5),
            Expanded(child: block(double.infinity, double.infinity, radius: 13)),
          ],
        ),
      ),
    );
  }
}

class _ParkingStatusSkeleton extends StatelessWidget {
  const _ParkingStatusSkeleton({
    required this.location,
    required this.pulse,
  });

  final String location;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final adaptive = ParkingStatusAdaptiveLayout.maybeOf(context);
    final cardPadding = adaptive?.cardPadding ?? 11.0;
    final mapHeight = adaptive?.mapMinHeight ?? 126.0;

    Widget block(double width, double height, {double radius = 8}) {
      return AnimatedBuilder(
        animation: pulse,
        builder: (context, _) {
          final opacity = reduceMotion ? .55 : pulse.value;
          return Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: tokens.surfaceOverlay.withOpacity(opacity),
              borderRadius: BorderRadius.circular(radius),
            ),
          );
        },
      );
    }

    Widget line(double widthFactor, double height) {
      return FractionallySizedBox(
        widthFactor: widthFactor,
        alignment: Alignment.centerLeft,
        child: block(double.infinity, height),
      );
    }

    return _ParkingStatusReveal(
      order: 1,
      offsetY: 6,
      child: Container(
        padding: EdgeInsets.all(cardPadding),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tokens.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: block(76, 14, radius: 6),
            ),
            const SizedBox(height: 7),
            block(double.infinity, mapHeight, radius: 12),
            const SizedBox(height: 7),
            if (location.trim().isNotEmpty) ...[
              line(.82, 11),
              const SizedBox(height: 6),
            ],
            Row(
              children: [
                Expanded(child: line(.72, 11)),
                const SizedBox(width: 8),
                block(44, 20, radius: 10),
              ],
            ),
            const SizedBox(height: 6),
            line(.62, 10),
          ],
        ),
      ),
    );
  }
}

class _ParkingStatusLoadError extends StatelessWidget {
  const _ParkingStatusLoadError({
    required this.plateNumber,
    required this.statusTitle,
    required this.message,
    required this.onRetry,
  });

  final String plateNumber;
  final String statusTitle;
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

    return ParkingStatusSideDockFrame(
      title: plateNumber,
      subtitle: parkingStatusHeaderSubtitle(statusTitle: statusTitle),
      icon: Icons.warning_amber_rounded,
      onClose: () => Navigator.of(context).pop(),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ParkingStatusReveal(
              order: 1,
              offsetY: 6,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: tokens.dangerContainer,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: tokens.danger.withOpacity(.42)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '원본 정보 확인 실패',
                      style: textTheme.titleSmall?.copyWith(
                        color: tokens.onDangerContainer,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      message,
                      style: textTheme.bodySmall?.copyWith(
                        color: tokens.onDangerContainer,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ParkingCompletedSectionCard(
              title: '다시 시도',
              subtitle: '현재 차량의 원본 정보를 다시 확인합니다.',
              child: ParkingCompletedPrimaryCtaButton(
                icon: Icons.refresh_rounded,
                title: '원본 정보 다시 불러오기',
                subtitle: '같은 Side Dock에서 다시 시도합니다.',
                onPressed: onRetry,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


Future<T?> showParkingStatusSideDock<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  DeveloperOperationTrace? trace,
  bool barrierDismissible = true,
  String barrierLabel = '상태 처리',
  bool finalizeTrace = true,
}) async {
  trace?.log(
    'status_side_dock=open direction=right_to_left maxWidth=360 widthFactor=0.92',
    progress: .18,
  );

  try {
    final result = await showCommonRightSideDock<T>(
      context: context,
      barrierLabel: barrierLabel,
      maxWidth: 360,
      widthFactor: .92,
      barrierDismissible: barrierDismissible,
      builder: (dockContext) {
        final child = builder(dockContext);
        if (trace == null) return child;
        return _ParkingStatusTraceScope(trace: trace, child: child);
      },
    );

    if (trace != null) {
      trace.log(
        'status_side_dock=closed result=${result ?? "null"} finalizeTrace=$finalizeTrace',
        progress: .92,
      );
      if (finalizeTrace) {
        await trace.succeed('상태 처리 세션이 종료되었습니다.');
        if (trace.developerMode && context.mounted) {
          await trace.showStatusDialog(context);
        }
      }
    }
    return result;
  } catch (error, stackTrace) {
    if (trace != null) {
      await trace.fail(
        '상태 처리 세션에서 예외가 발생했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
      if (trace.developerMode && context.mounted) {
        await trace.showStatusDialog(context);
      }
    } else {
      debugPrint('[ParkingStatusSideDock] 오류: $error\n$stackTrace');
    }
    rethrow;
  }
}

class ParkingStatusAdaptiveMetrics {
  const ParkingStatusAdaptiveMetrics({
    required this.variant,
    required this.dockHeight,
    required this.footerHeight,
    required this.sectionGap,
    required this.cardPadding,
    required this.mapMinHeight,
    required this.mapMaxHeight,
    required this.managementButtonHeight,
    required this.managementRailWidth,
    required this.managementRailGap,
  });

  final ParkingStatusPrimaryVariant variant;
  final double dockHeight;
  final double footerHeight;
  final double sectionGap;
  final double cardPadding;
  final double mapMinHeight;
  final double mapMaxHeight;
  final double managementButtonHeight;
  final double managementRailWidth;
  final double managementRailGap;

  static ParkingStatusAdaptiveMetrics resolve({
    required double dockHeight,
    required double textScale,
  }) {
    final ultra = dockHeight < 600 || textScale >= 1.30;
    final compact = !ultra && (dockHeight < 720 || textScale >= 1.15);
    final variant = ultra
        ? ParkingStatusPrimaryVariant.ultraCompact
        : compact
            ? ParkingStatusPrimaryVariant.compact
            : ParkingStatusPrimaryVariant.normal;
    final footerHeight = ultra
        ? (dockHeight * .18).clamp(120.0, 132.0).toDouble()
        : compact
            ? (dockHeight * .19).clamp(130.0, 144.0).toDouble()
            : (dockHeight * .20).clamp(142.0, 158.0).toDouble();
    final sectionGap = ultra ? 6.0 : compact ? 8.0 : 10.0;
    final cardPadding = ultra ? 10.0 : compact ? 11.0 : 12.0;
    final mapMinHeight = ultra ? 108.0 : compact ? 126.0 : 150.0;
    final mapMaxHeight = ultra ? 190.0 : compact ? 218.0 : 280.0;
    final railMetrics = CommonSideRailMetrics.resolve(
      dockHeight: dockHeight,
      textScale: textScale,
    );
    final managementButtonHeight = railMetrics.minimumButtonExtent;
    final managementRailWidth = railMetrics.railWidth;
    final managementRailGap = railMetrics.railGap;
    return ParkingStatusAdaptiveMetrics(
      variant: variant,
      dockHeight: dockHeight,
      footerHeight: footerHeight,
      sectionGap: sectionGap,
      cardPadding: cardPadding,
      mapMinHeight: mapMinHeight,
      mapMaxHeight: mapMaxHeight,
      managementButtonHeight: managementButtonHeight,
      managementRailWidth: managementRailWidth,
      managementRailGap: managementRailGap,
    );
  }
}

class ParkingStatusAdaptiveLayout extends InheritedWidget {
  const ParkingStatusAdaptiveLayout({
    super.key,
    required this.metrics,
    required super.child,
  });

  final ParkingStatusAdaptiveMetrics metrics;

  static ParkingStatusAdaptiveMetrics? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<ParkingStatusAdaptiveLayout>()
        ?.metrics;
  }

  @override
  bool updateShouldNotify(ParkingStatusAdaptiveLayout oldWidget) {
    return metrics.variant != oldWidget.metrics.variant ||
        metrics.footerHeight != oldWidget.metrics.footerHeight ||
        metrics.dockHeight != oldWidget.metrics.dockHeight ||
        metrics.managementRailWidth != oldWidget.metrics.managementRailWidth ||
        metrics.managementRailGap != oldWidget.metrics.managementRailGap;
  }
}

class ParkingStatusSideDockFrame extends StatelessWidget {
  const ParkingStatusSideDockFrame({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    required this.onClose,
    this.closeEnabled = true,
    this.onLongPress,
    this.leadingRail,
    this.footer,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;
  final VoidCallback onClose;
  final bool closeEnabled;
  final VoidCallback? onLongPress;
  final Widget? leadingRail;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final textScale = media?.textScaler.scale(1.0) ?? 1.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final dockHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : media?.size.height ?? 720.0;
        final metrics = ParkingStatusAdaptiveMetrics.resolve(
          dockHeight: dockHeight,
          textScale: textScale,
        );

        return ParkingStatusAdaptiveLayout(
          metrics: metrics,
          child: CommonSideDockFrame(
            title: title,
            subtitle: subtitle,
            icon: icon,
            child: child,
            onClose: onClose,
            closeEnabled: closeEnabled,
            onLongPress: onLongPress,
            leadingRail: leadingRail,
            footer: footer,
            sectionGap: metrics.sectionGap,
            footerHeight: footer == null ? null : metrics.footerHeight,
          ),
        );
      },
    );
  }
}

class _ParkingStatusRequestHeightBudget {
  const _ParkingStatusRequestHeightBudget({
    required this.requiredFlexHeight,
    required this.metadataMinHeight,
    required this.locationCardMinHeight,
    required this.leadingMinHeight,
    required this.contentWidth,
    required this.billingMinHeight,
    required this.billingDetailMinHeight,
    required this.memoMinHeight,
    required this.locationPathMinHeight,
    required this.safetyReserve,
  });

  final double requiredFlexHeight;
  final double metadataMinHeight;
  final double locationCardMinHeight;
  final double leadingMinHeight;
  final double contentWidth;
  final double billingMinHeight;
  final double billingDetailMinHeight;
  final double memoMinHeight;
  final double locationPathMinHeight;
  final double safetyReserve;
}

class ParkingStatusAdaptiveRequestBody extends StatefulWidget {
  const ParkingStatusAdaptiveRequestBody({
    super.key,
    required this.plate,
    required this.area,
    required this.debugTarget,
    this.leading = const <Widget>[],
    this.scrollController,
    this.attention = 0,
  });

  final PlateModel plate;
  final String area;
  final String debugTarget;
  final List<Widget> leading;
  final ScrollController? scrollController;
  final double attention;

  @override
  State<ParkingStatusAdaptiveRequestBody> createState() =>
      _ParkingStatusAdaptiveRequestBodyState();
}

class _ParkingStatusAdaptiveRequestBodyState
    extends State<ParkingStatusAdaptiveRequestBody> {
  String _lastLayoutSignature = '';

  double _measureTextHeight({
    required BuildContext context,
    required String text,
    required TextStyle? style,
    required double maxWidth,
    required int maxLines,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text.trim().isEmpty ? ' ' : text,
        style: style,
      ),
      textDirection: Directionality.of(context),
      maxLines: maxLines,
      ellipsis: '…',
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: math.max(1.0, maxWidth).toDouble());
    return painter.height;
  }

  _ParkingStatusRequestHeightBudget _resolveHeightBudget({
    required BuildContext context,
    required double width,
    required double textScale,
    required ParkingStatusAdaptiveMetrics metrics,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final variant = metrics.variant;
    final compact = variant != ParkingStatusPrimaryVariant.normal;
    final ultra = variant == ParkingStatusPrimaryVariant.ultraCompact;
    final headerGap = ultra ? 5.0 : compact ? 6.0 : 8.0;
    final metadataGap = ultra ? 3.0 : compact ? 4.0 : 5.0;
    final cardInset = metrics.cardPadding + 1.0;
    final contentWidth =
        math.max(1.0, width - 4.0 - cardInset * 2.0).toDouble();
    final titleHeight = math.max(
      16.0,
      _measureTextHeight(
        context: context,
        text: '차량 위치',
        style: textTheme.titleSmall,
        maxWidth: contentWidth,
        maxLines: 1,
      ),
    ).toDouble();
    final displayLocation = _parkingStatusDisplayLocation(widget.plate.location);
    final locationMaxLines = variant == ParkingStatusPrimaryVariant.normal ? 2 : 1;
    final locationPathMinHeight = math.max(
      15.0,
      _measureTextHeight(
        context: context,
        text: displayLocation,
        style: textTheme.bodySmall?.copyWith(height: 1.2),
        maxWidth: math.max(1.0, contentWidth - 21.0).toDouble(),
        maxLines: locationMaxLines,
      ),
    ).toDouble();
    final billingState = resolveParkingCompletedBillingState(
      billingType: widget.plate.billingType,
      isLocked: widget.plate.isLockedFee == true,
    );
    final billingType = billingState == ParkingCompletedBillingState.notApplicable
        ? '정산 없음'
        : (widget.plate.billingType ?? '').trim().isEmpty
            ? '정산 없음'
            : (widget.plate.billingType ?? '').trim();
    final statusText = billingState == ParkingCompletedBillingState.unsettled
        ? '미정산'
        : billingState == ParkingCompletedBillingState.settled
            ? '완료'
            : '';
    final statusWidth = statusText.isEmpty ? 0.0 : 54.0;
    final billingTextWidth = math.max(
      1.0,
      contentWidth - 21.0 - (statusText.isEmpty ? 0.0 : statusWidth + 7.0),
    ).toDouble();
    final billingTypeHeight = _measureTextHeight(
      context: context,
      text: billingType,
      style: textTheme.bodySmall?.copyWith(height: 1.2),
      maxWidth: billingTextWidth,
      maxLines: 1,
    );
    final paymentMethod = (widget.plate.paymentMethod ?? '').trim();
    final billingDetail = billingState != ParkingCompletedBillingState.settled
        ? ''
        : paymentMethod.isEmpty
            ? '₩${widget.plate.lockedFeeAmount ?? 0}'
            : '₩${widget.plate.lockedFeeAmount ?? 0} · $paymentMethod';
    final billingDetailMinHeight = billingDetail.isEmpty
        ? 0.0
        : 1.0 +
            _measureTextHeight(
              context: context,
              text: billingDetail,
              style: textTheme.labelSmall?.copyWith(height: 1.15),
              maxWidth: billingTextWidth,
              maxLines: 1,
            );
    final statusPillMinHeight = statusText.isEmpty
        ? 0.0
        : 6.0 +
            _measureTextHeight(
              context: context,
              text: statusText,
              style: textTheme.labelSmall?.copyWith(height: 1.05),
              maxWidth: 64.0,
              maxLines: 1,
            );
    final billingMinHeight = math.max(
      15.0,
      math.max(
        statusPillMinHeight,
        billingTypeHeight + billingDetailMinHeight,
      ),
    ).toDouble();
    final memo = (widget.plate.customStatus ?? '').trim();
    final memoMaxLines = variant == ParkingStatusPrimaryVariant.normal ? 2 : 1;
    final memoMinHeight = memo.isEmpty
        ? 0.0
        : math.max(
            15.0,
            _measureTextHeight(
              context: context,
              text: memo,
              style: textTheme.bodySmall?.copyWith(height: 1.2),
              maxWidth: math.max(1.0, contentWidth - 21.0).toDouble(),
              maxLines: memoMaxLines,
            ),
          ).toDouble();
    var compactMetadataMinHeight =
        locationPathMinHeight + metadataGap + billingMinHeight;
    if (memoMinHeight > 0) {
      compactMetadataMinHeight += metadataGap + memoMinHeight;
    }
    final metadataMinHeight = titleHeight +
        headerGap +
        headerGap +
        compactMetadataMinHeight +
        cardInset * 2.0;
    final locationCardMinHeight = metadataMinHeight + metrics.mapMinHeight;
    final safeTextScale = textScale.clamp(1.0, 1.45).toDouble();
    final leadingUnitHeight = 72.0 + (safeTextScale - 1.0) * 20.0;
    final leadingMinHeight = widget.leading.isEmpty
        ? 0.0
        : (widget.leading.length *
                (leadingUnitHeight + metrics.sectionGap))
            .toDouble();
    final safetyReserve = ultra ? 6.0 : compact ? 8.0 : 10.0;
    final requiredFlexHeight = locationCardMinHeight +
        leadingMinHeight +
        4.0 +
        safetyReserve;
    return _ParkingStatusRequestHeightBudget(
      requiredFlexHeight: requiredFlexHeight,
      metadataMinHeight: metadataMinHeight,
      locationCardMinHeight: locationCardMinHeight,
      leadingMinHeight: leadingMinHeight,
      contentWidth: contentWidth,
      billingMinHeight: billingMinHeight,
      billingDetailMinHeight: billingDetailMinHeight,
      memoMinHeight: memoMinHeight,
      locationPathMinHeight: locationPathMinHeight,
      safetyReserve: safetyReserve,
    );
  }

  void _traceLayout({
    required bool scrollFallback,
    required String fallbackReason,
    required double height,
    required double width,
    required double deficit,
    required ParkingStatusAdaptiveMetrics metrics,
    required _ParkingStatusRequestHeightBudget budget,
  }) {
    final signature =
        '${metrics.variant.name}|${scrollFallback ? "scroll" : "flex"}|${height.toStringAsFixed(0)}|${width.toStringAsFixed(0)}|compact|${budget.requiredFlexHeight.toStringAsFixed(0)}';
    if (_lastLayoutSignature == signature) return;
    _lastLayoutSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      parkingStatusTraceLog(
        context,
        'status_adaptive_body=layout target=${widget.debugTarget} mode=${scrollFallback ? "scroll_fallback" : "linked_flex"} '
        'reason=$fallbackReason variant=${metrics.variant.name} body_height=${height.toStringAsFixed(0)} body_width=${width.toStringAsFixed(0)} '
        'footer_height=${metrics.footerHeight.toStringAsFixed(0)} map_min=${metrics.mapMinHeight.toStringAsFixed(0)} '
        'content_width=${budget.contentWidth.toStringAsFixed(0)} metadata_layout=compact billing_layout=single_row sector_chip=removed '
        'metadata_min=${budget.metadataMinHeight.toStringAsFixed(0)} location_card_min=${budget.locationCardMinHeight.toStringAsFixed(0)} '
        'billing_min=${budget.billingMinHeight.toStringAsFixed(0)} billing_detail_min=${budget.billingDetailMinHeight.toStringAsFixed(0)} '
        'memo_min=${budget.memoMinHeight.toStringAsFixed(0)} location_path_min=${budget.locationPathMinHeight.toStringAsFixed(0)} '
        'leading_min=${budget.leadingMinHeight.toStringAsFixed(0)} required_flex=${budget.requiredFlexHeight.toStringAsFixed(0)} '
        'deficit=${deficit.toStringAsFixed(0)} safety=${budget.safetyReserve.toStringAsFixed(0)} '
        'section_gap=${metrics.sectionGap.toStringAsFixed(0)}',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final textScale = media?.textScaler.scale(1.0) ?? 1.0;
    final reduceMotion = media?.disableAnimations ?? false;
    return LayoutBuilder(
      builder: (context, constraints) {
        final inherited = ParkingStatusAdaptiveLayout.maybeOf(context);
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : media?.size.height ?? 720.0;
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : media?.size.width ?? 320.0;
        final metrics = inherited ??
            ParkingStatusAdaptiveMetrics.resolve(
              dockHeight: height,
              textScale: textScale,
            );
        final budget = _resolveHeightBudget(
          context: context,
          width: width,
          textScale: textScale,
          metrics: metrics,
        );
        final deficit =
            math.max(0.0, budget.requiredFlexHeight - height).toDouble();
        final textScaleFallback = textScale >= 1.45;
        final scrollFallback = textScaleFallback || deficit > .5;
        final fallbackReason = textScaleFallback
            ? 'text_scale'
            : deficit > .5
                ? 'height_budget'
                : 'none';
        _traceLayout(
          scrollFallback: scrollFallback,
          fallbackReason: fallbackReason,
          height: height,
          width: width,
          deficit: deficit,
          metrics: metrics,
          budget: budget,
        );

        final body = scrollFallback
            ? ListView(
                key: const ValueKey<String>('status-request-scroll'),
                controller: widget.scrollController,
                padding: EdgeInsets.fromLTRB(
                  2,
                  2,
                  2,
                  metrics.sectionGap,
                ),
                children: [
                  for (var index = 0; index < widget.leading.length; index++) ...[
                    widget.leading[index],
                    SizedBox(height: metrics.sectionGap),
                  ],
                  ParkingStatusVehicleLocationCard(
                    plate: widget.plate,
                    area: widget.area,
                    attention: widget.attention,
                  ),
                ],
              )
            : Column(
                key: const ValueKey<String>('status-request-flex'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < widget.leading.length; index++) ...[
                    widget.leading[index],
                    SizedBox(height: metrics.sectionGap),
                  ],
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(2, 2, 2, 2),
                      child: ParkingStatusVehicleLocationCard(
                        plate: widget.plate,
                        area: widget.area,
                        attention: widget.attention,
                        expandToFill: true,
                      ),
                    ),
                  ),
                ],
              );

        return SizedBox.expand(
          child: AnimatedSwitcher(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            layoutBuilder: (currentChild, previousChildren) {
              return Stack(
                fit: StackFit.expand,
                alignment: Alignment.center,
                children: [
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              );
            },
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, .015),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
                  child: child,
                ),
              );
            },
            child: body,
          ),
        );
      },
    );
  }
}

class ParkingStatusManagementAction {
  const ParkingStatusManagementAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.displayLabel = '',
    this.enabled = true,
    this.destructive = false,
    this.emphasized = false,
    this.debugAction = '',
    this.linkedGroup = '',
    this.linkedReverse = false,
    this.anchorKey,
  });

  final IconData icon;
  final String label;
  final String displayLabel;
  final FutureOr<void> Function() onPressed;
  final bool enabled;
  final bool destructive;
  final bool emphasized;
  final String debugAction;
  final String linkedGroup;
  final bool linkedReverse;
  final Key? anchorKey;

  String get visualLabel {
    final value = displayLabel.trim();
    return value.isEmpty ? label.trim() : value;
  }

  String get stableSlotKey {
    final group = linkedGroup.trim();
    if (group.isNotEmpty) return 'linked:$group';
    final action = debugAction.trim();
    if (action.isNotEmpty) return 'action:$action';
    return 'label:${label.trim()}';
  }
}

enum ParkingStatusPrimaryVariant {
  normal,
  compact,
  ultraCompact,
}

class ParkingStatusPrimaryLayout extends InheritedWidget {
  const ParkingStatusPrimaryLayout({
    super.key,
    required this.variant,
    required super.child,
  });

  final ParkingStatusPrimaryVariant variant;

  static ParkingStatusPrimaryVariant variantOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<ParkingStatusPrimaryLayout>()
            ?.variant ??
        ParkingStatusPrimaryVariant.normal;
  }

  @override
  bool updateShouldNotify(ParkingStatusPrimaryLayout oldWidget) {
    return variant != oldWidget.variant;
  }
}

class ParkingStatusManagementRail extends StatefulWidget {
  const ParkingStatusManagementRail({
    super.key,
    required this.actions,
    this.title = '차량 관리',
    this.debugTarget = '',
  });

  final List<ParkingStatusManagementAction> actions;
  final String title;
  final String debugTarget;

  @override
  State<ParkingStatusManagementRail> createState() =>
      _ParkingStatusManagementRailState();
}

class _ParkingStatusManagementRailState
    extends State<ParkingStatusManagementRail> {
  final ScrollController _scrollController = ScrollController();
  String? _lastLayoutSignature;

  String get _debugTarget {
    final target = widget.debugTarget.trim();
    return target.isEmpty ? 'vehicle_management' : target;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final reduceMotion = media?.disableAnimations ?? false;
    final adaptive = ParkingStatusAdaptiveLayout.maybeOf(context);
    final textScale = media?.textScaler.scale(1.0) ?? 1.0;
    final railMetrics = CommonSideRailMetrics.resolve(
      dockHeight: adaptive?.dockHeight ?? media?.size.height ?? 720.0,
      textScale: textScale,
    );
    final compact = railMetrics.compact;
    final minimumButtonExtent =
        adaptive?.managementButtonHeight ?? railMetrics.minimumButtonExtent;
    final actionInsetHorizontal = railMetrics.actionInsetHorizontal;
    final actionInsetVertical = railMetrics.actionInsetVertical;
    final variantName = railMetrics.variantName;

    Widget actionButton(
      ParkingStatusManagementAction action, {
      required double extent,
    }) {
      return KeyedSubtree(
        key: action.anchorKey,
        child: AnimatedSwitcher(
          duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
          switchInCurve: CommonUiMotion.standard,
          switchOutCurve: CommonUiMotion.standard,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(-.06, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: _ParkingStatusManagementRailButton(
            key: ValueKey<String>(action.stableSlotKey),
            action: action,
            debugTarget: _debugTarget,
            compact: compact,
            extent: extent,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final railHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : adaptive?.dockHeight ?? 720.0;
        final railWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : adaptive?.managementRailWidth ?? 52.0;
        final actionCount = widget.actions.length;
        final enabledCount =
            widget.actions.where((action) => action.enabled).length;
        final actionStateSignature = widget.actions
            .map(
              (action) =>
                  '${action.debugAction}:${action.visualLabel}:${action.linkedGroup}:${action.linkedReverse}',
            )
            .join(',');
        final visualLabels =
            widget.actions.map((action) => action.visualLabel).join('/');
        final linkedGroups = widget.actions
            .map((action) => action.linkedGroup.trim())
            .where((group) => group.isNotEmpty)
            .toSet()
            .join('/');
        final availableListHeight = math.max(
          0.0,
          railHeight - railMetrics.outerVertical * 2 - railMetrics.headerHeight - railMetrics.headerGap,
        );
        final equalSlotExtent = actionCount == 0
            ? 0.0
            : availableListHeight / actionCount;
        final minimumSlotExtent =
            minimumButtonExtent + actionInsetVertical * 2;
        final scrollable =
            actionCount > 0 && equalSlotExtent + .5 < minimumSlotExtent;
        final distributedButtonExtent = scrollable
            ? minimumButtonExtent
            : math.max(0.0, equalSlotExtent - actionInsetVertical * 2);
        final distribution = actionCount == 0
            ? 'empty'
            : scrollable
                ? 'scroll_fallback'
                : 'equal_fill';
        final signature = [
          variantName,
          railWidth.toStringAsFixed(0),
          railHeight.toStringAsFixed(0),
          actionCount,
          enabledCount,
          distribution,
          equalSlotExtent.toStringAsFixed(1),
          distributedButtonExtent.toStringAsFixed(1),
          actionStateSignature,
        ].join('|');
        if (_lastLayoutSignature != signature) {
          _lastLayoutSignature = signature;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            parkingStatusTraceLog(
              context,
              'vehicle_management_rail=layout railDesign=common_operations railMetricsSource=CommonSideRailMetrics target=$_debugTarget position=left width=${railWidth.toStringAsFixed(0)} height=${railHeight.toStringAsFixed(0)} visible_actions=$actionCount enabled_actions=$enabledCount distribution=$distribution basis=visible_actions label_policy=two_chars labels=$visualLabels linked_groups=${linkedGroups.isEmpty ? "none" : linkedGroups} scroll=$scrollable slot_extent=${equalSlotExtent.toStringAsFixed(1)} button_extent=${distributedButtonExtent.toStringAsFixed(1)} inset_x=${actionInsetHorizontal.toStringAsFixed(0)} inset_y=${actionInsetVertical.toStringAsFixed(0)} variant=$variantName',
            );
          });
        }

        final actionArea = actionCount == 0
            ? const SizedBox.expand()
            : scrollable
                ? Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    thickness: 2,
                    radius: const Radius.circular(2),
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 3),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final action in widget.actions)
                              Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: actionInsetHorizontal,
                                  vertical: actionInsetVertical,
                                ),
                                child: actionButton(
                                  action,
                                  extent: minimumButtonExtent,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  )
                : Column(
                    key: ValueKey<String>(
                      'equal_fill|$variantName|$actionCount',
                    ),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final action in widget.actions)
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: actionInsetHorizontal,
                              vertical: actionInsetVertical,
                            ),
                            child: actionButton(
                              action,
                              extent: distributedButtonExtent,
                            ),
                          ),
                        ),
                    ],
                  );

        return CommonSideRailSurface(
          title: widget.title,
          metrics: railMetrics,
          child: AnimatedSwitcher(
            duration:
                reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeOutCubic,
            layoutBuilder: (currentChild, previousChildren) {
              return Stack(
                fit: StackFit.expand,
                alignment: Alignment.center,
                children: [
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              );
            },
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, -.025),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: KeyedSubtree(
              key: ValueKey<String>(
                '$distribution|$variantName|$actionCount',
              ),
              child: actionArea,
            ),
          ),
        );
      },
    );
  }
}

class ParkingStatusPrimaryFooter extends StatefulWidget {
  const ParkingStatusPrimaryFooter({
    super.key,
    required this.child,
    this.title = '상태 변경',
    this.subtitle = '',
    this.debugTarget = '',
  });

  final Widget child;
  final String title;
  final String subtitle;
  final String debugTarget;

  @override
  State<ParkingStatusPrimaryFooter> createState() =>
      _ParkingStatusPrimaryFooterState();
}

class _ParkingStatusPrimaryFooterState extends State<ParkingStatusPrimaryFooter> {
  ParkingStatusPrimaryVariant? _lastLoggedVariant;

  String get _debugTarget {
    final target = widget.debugTarget.trim();
    return target.isEmpty ? 'status_change' : target;
  }

  Widget _header({
    required BuildContext context,
    required bool compact,
  }) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 3,
          height: 18,
          margin: const EdgeInsets.only(top: 1),
          decoration: BoxDecoration(
            color: tokens.accent,
            borderRadius: BorderRadius.circular(CommonUiShapes.pill),
          ),
        ),
        SizedBox(width: compact ? 6 : 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: (compact ? textTheme.labelLarge : textTheme.titleSmall)
                    ?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w900,
                  height: 1.12,
                ),
              ),
              if (widget.subtitle.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  widget.subtitle.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                    height: 1.2,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final media = MediaQuery.maybeOf(context);
    final reduceMotion = media?.disableAnimations ?? false;
    final screenHeight = media?.size.height ?? 720;
    final safeVertical = (media?.padding.top ?? 0) + (media?.padding.bottom ?? 0);
    final keyboardInset = media?.viewInsets.bottom ?? 0;
    final fallbackUsableHeight =
        math.max(0.0, screenHeight - safeVertical - keyboardInset);
    final textScale = media?.textScaler.scale(1.0) ?? 1.0;
    final adaptive = ParkingStatusAdaptiveLayout.maybeOf(context);
    final usableHeight = adaptive?.dockHeight ?? fallbackUsableHeight;
    final primaryVariant = adaptive?.variant ??
        (usableHeight < 520 || textScale >= 1.30
            ? ParkingStatusPrimaryVariant.ultraCompact
            : usableHeight < 620 || textScale >= 1.15
                ? ParkingStatusPrimaryVariant.compact
                : ParkingStatusPrimaryVariant.normal);
    final primaryCompact = primaryVariant != ParkingStatusPrimaryVariant.normal;
    final primaryUltra =
        primaryVariant == ParkingStatusPrimaryVariant.ultraCompact;
    final topPadding = primaryUltra ? 7.0 : primaryCompact ? 8.0 : 10.0;
    final footerTargetHeight = adaptive?.footerHeight ??
        (primaryUltra ? 128.0 : primaryCompact ? 138.0 : 150.0);
    final variantName = switch (primaryVariant) {
      ParkingStatusPrimaryVariant.normal => 'normal',
      ParkingStatusPrimaryVariant.compact => 'compact',
      ParkingStatusPrimaryVariant.ultraCompact => 'ultra_compact',
    };
    final previousVariant = _lastLoggedVariant;
    if (previousVariant != primaryVariant) {
      _lastLoggedVariant = primaryVariant;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final fromName = switch (previousVariant) {
          ParkingStatusPrimaryVariant.normal => 'normal',
          ParkingStatusPrimaryVariant.compact => 'compact',
          ParkingStatusPrimaryVariant.ultraCompact => 'ultra_compact',
          null => 'none',
        };
        parkingStatusTraceLog(
          context,
          previousVariant == null
              ? 'status_primary_footer=visible target=$_debugTarget layout=primary_only management=left_rail gear_sizing=bounded_fill footer_height=${footerTargetHeight.toStringAsFixed(0)} primary_variant=$variantName usable_height=${usableHeight.toStringAsFixed(0)} text_scale=${textScale.toStringAsFixed(2)}'
              : 'status_primary_footer=layout_change target=$_debugTarget from=$fromName to=$variantName reason=adaptive_metrics layout=primary_only management=left_rail gear_sizing=bounded_fill footer_height=${footerTargetHeight.toStringAsFixed(0)} usable_height=${usableHeight.toStringAsFixed(0)} text_scale=${textScale.toStringAsFixed(2)}',
        );
      });
    }

    return _ParkingStatusReveal(
      order: 1,
      offsetY: 6,
      child: AnimatedContainer(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.fromLTRB(
          2,
          topPadding,
          2,
          2,
        ),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: tokens.borderSubtle)),
        ),
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) {
            parkingStatusTraceLog(
              context,
              'status_primary_footer=interaction target=$_debugTarget primary_variant=$variantName layout=primary_only',
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(
                context: context,
                compact: true,
              ),
              SizedBox(height: primaryUltra ? 3 : 4),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: primaryUltra ? 0 : 2,
                  ),
                  child: ParkingStatusPrimaryLayout(
                    variant: primaryVariant,
                    child: AnimatedSwitcher(
                      duration: reduceMotion
                          ? Duration.zero
                          : CommonUiMotion.selection,
                      switchInCurve: CommonUiMotion.standard,
                      switchOutCurve: CommonUiMotion.standard,
                      layoutBuilder: (currentChild, previousChildren) {
                        return Stack(
                          fit: StackFit.expand,
                          alignment: Alignment.center,
                          children: [
                            ...previousChildren,
                            if (currentChild != null) currentChild,
                          ],
                        );
                      },
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, .04),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: KeyedSubtree(
                        key: ValueKey<String>(
                          'primary|${widget.child.runtimeType}',
                        ),
                        child: widget.child,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum ParkingStatusDirectionalGearTone {
  primary,
  warning,
  danger,
  neutral,
}

enum ParkingStatusDirectionalGearActionResult {
  completed,
  blocked,
  cancelled,
  failed,
}

class ParkingStatusDirectionalGearAction {
  const ParkingStatusDirectionalGearAction({
    required this.label,
    required this.debugAction,
    this.onConfirm,
    this.onConfirmResult,
    this.icon = Icons.arrow_forward_rounded,
    this.tone = ParkingStatusDirectionalGearTone.primary,
  }) : assert(onConfirm != null || onConfirmResult != null);

  final String label;
  final String debugAction;
  final FutureOr<void> Function()? onConfirm;
  final FutureOr<ParkingStatusDirectionalGearActionResult> Function()?
      onConfirmResult;
  final IconData icon;
  final ParkingStatusDirectionalGearTone tone;
}

class ParkingStatusDirectionalGear extends StatefulWidget {
  const ParkingStatusDirectionalGear({
    super.key,
    required this.debugTarget,
    required this.enabled,
    required this.busy,
    required this.driving,
    this.blocked = false,
    this.blockedBy = '',
    this.onStartDriving,
    this.lowerLeft,
    this.lowerRight,
    this.upperDown,
    this.upperRight,
    this.startLabel = '주행',
  });

  final String debugTarget;
  final bool enabled;
  final bool busy;
  final bool driving;
  final bool blocked;
  final String blockedBy;
  final Future<bool> Function()? onStartDriving;
  final ParkingStatusDirectionalGearAction? lowerLeft;
  final ParkingStatusDirectionalGearAction? lowerRight;
  final ParkingStatusDirectionalGearAction? upperDown;
  final ParkingStatusDirectionalGearAction? upperRight;
  final String startLabel;

  @override
  State<ParkingStatusDirectionalGear> createState() =>
      _ParkingStatusDirectionalGearState();
}

enum _ParkingStatusGearDirection {
  up,
  left,
  right,
  down,
}

class _ParkingStatusDirectionalGearState
    extends State<ParkingStatusDirectionalGear> {
  Offset _dragDelta = Offset.zero;
  _ParkingStatusGearDirection? _dragDirection;
  bool _dragging = false;
  bool _thresholdHapticSent = false;
  bool _busyInternal = false;
  double _dragProgress = 0;
  String? _semanticStatus;
  String? _lastLayoutSignature;

  ParkingStatusPrimaryVariant get _variant =>
      ParkingStatusPrimaryLayout.variantOf(context);

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  bool get _canInteract =>
      widget.enabled &&
      !widget.busy &&
      !_busyInternal &&
      !widget.blocked;

  bool get _isBusy => widget.busy || _busyInternal;

  @override
  void didUpdateWidget(covariant ParkingStatusDirectionalGear oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.driving != widget.driving) {
      _resetDragState(notify: false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        parkingStatusTraceLog(
          context,
          'status_directional_gear=detent target=${widget.debugTarget} position=${widget.driving ? "upper" : "lower"}',
        );
      });
    }
    if ((!widget.enabled || widget.blocked) &&
        (oldWidget.enabled || !oldWidget.blocked)) {
      _resetDragState(notify: false);
    }
  }

  void _resetDragState({bool notify = true}) {
    void reset() {
      _dragDelta = Offset.zero;
      _dragDirection = null;
      _dragProgress = 0;
      _dragging = false;
      _thresholdHapticSent = false;
    }

    if (!notify || !mounted) {
      reset();
      return;
    }
    setState(reset);
  }

  ParkingStatusDirectionalGearAction? _actionFor(
    _ParkingStatusGearDirection direction,
  ) {
    if (widget.driving) {
      if (direction == _ParkingStatusGearDirection.down) {
        return widget.upperDown;
      }
      if (direction == _ParkingStatusGearDirection.right) {
        return widget.upperRight;
      }
      return null;
    }
    if (direction == _ParkingStatusGearDirection.left) {
      return widget.lowerLeft;
    }
    if (direction == _ParkingStatusGearDirection.right) {
      return widget.lowerRight;
    }
    return null;
  }

  bool _directionAvailable(_ParkingStatusGearDirection direction) {
    if (widget.driving) {
      return _actionFor(direction) != null;
    }
    if (direction == _ParkingStatusGearDirection.up) {
      return widget.onStartDriving != null;
    }
    return _actionFor(direction) != null;
  }

  String _directionName(_ParkingStatusGearDirection direction) {
    return switch (direction) {
      _ParkingStatusGearDirection.up => 'up',
      _ParkingStatusGearDirection.left => 'left',
      _ParkingStatusGearDirection.right => 'right',
      _ParkingStatusGearDirection.down => 'down',
    };
  }

  void _onPanStart(DragStartDetails details) {
    if (!_canInteract) return;
    setState(() {
      _dragDelta = Offset.zero;
      _dragDirection = null;
      _dragProgress = 0;
      _dragging = true;
      _thresholdHapticSent = false;
      _semanticStatus = null;
    });
  }

  void _resolveDirection() {
    if (_dragDirection != null) return;
    final dx = _dragDelta.dx;
    final dy = _dragDelta.dy;
    final ax = dx.abs();
    final ay = dy.abs();
    if (math.max(ax, ay) < 10) return;

    _ParkingStatusGearDirection? candidate;
    if (widget.driving) {
      if (dx > 0 && ax > ay * 1.15) {
        candidate = _ParkingStatusGearDirection.right;
      } else if (dy > 0 && ay > ax * 1.15) {
        candidate = _ParkingStatusGearDirection.down;
      }
    } else {
      if (dy < 0 && ay > ax * 1.15) {
        candidate = _ParkingStatusGearDirection.up;
      } else if (dx < 0 && ax > ay * 1.15) {
        candidate = _ParkingStatusGearDirection.left;
      } else if (dx > 0 && ax > ay * 1.15) {
        candidate = _ParkingStatusGearDirection.right;
      }
    }

    if (candidate == null || !_directionAvailable(candidate)) return;
    _dragDirection = candidate;
    parkingStatusTraceLog(
      context,
      'status_directional_gear=direction_lock target=${widget.debugTarget} detent=${widget.driving ? "upper" : "lower"} direction=${_directionName(candidate)}',
    );
  }

  double _progressForDirection(_ParkingStatusGearDirection direction) {
    final dx = _dragDelta.dx;
    final dy = _dragDelta.dy;
    return switch (direction) {
      _ParkingStatusGearDirection.up => (-dy / 38).clamp(0.0, 1.0).toDouble(),
      _ParkingStatusGearDirection.down => (dy / 38).clamp(0.0, 1.0).toDouble(),
      _ParkingStatusGearDirection.left => (-dx / 56).clamp(0.0, 1.0).toDouble(),
      _ParkingStatusGearDirection.right => (dx / 56).clamp(0.0, 1.0).toDouble(),
    };
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!_canInteract || !_dragging) return;
    setState(() {
      _dragDelta += details.delta;
      _resolveDirection();
      final direction = _dragDirection;
      if (direction == null) {
        _dragProgress = 0;
        return;
      }
      _dragProgress = _progressForDirection(direction);
      if (_dragProgress >= .78 && !_thresholdHapticSent) {
        _thresholdHapticSent = true;
        try {
          HapticFeedback.selectionClick();
        } catch (_) {}
      } else if (_dragProgress < .72) {
        _thresholdHapticSent = false;
      }
    });
  }

  Future<void> _onPanEnd(DragEndDetails details) async {
    if (!_dragging) return;
    final direction = _dragDirection;
    final armed = direction != null && _dragProgress >= .78;
    if (!armed) {
      _resetDragState();
      return;
    }

    if (direction == _ParkingStatusGearDirection.up && !widget.driving) {
      await _runStartDriving(source: 'release');
      return;
    }

    final action = _actionFor(direction);
    if (action == null) {
      _resetDragState();
      return;
    }

    await _runDirectionalAction(direction, action, source: 'release');
  }

  Future<void> _runStartDriving({required String source}) async {
    final callback = widget.onStartDriving;
    if (callback == null || _isBusy) {
      _resetDragState();
      return;
    }
    setState(() {
      _busyInternal = true;
      _dragging = false;
      _dragProgress = 1;
      _semanticStatus = '${widget.startLabel} 처리 중';
    });
    parkingStatusTraceLog(
      context,
      'status_directional_gear=armed target=${widget.debugTarget} detent=lower direction=up action=driving_start source=$source',
    );
    parkingStatusTraceLog(
      context,
      'status_directional_gear=${source == "accessibility" ? "commit_accessibility" : "commit_on_release"} target=${widget.debugTarget} action=driving_start direction=up',
    );
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}
    var ok = false;
    var semanticStatus = '${widget.startLabel}을 완료하지 못했습니다';
    try {
      ok = await callback();
      semanticStatus = ok
          ? '${widget.startLabel} 완료'
          : '${widget.startLabel}을 진행할 수 없습니다';
      parkingStatusTraceLog(
        context,
        'status_directional_gear=result target=${widget.debugTarget} action=driving_start success=$ok source=$source',
      );
    } catch (error) {
      semanticStatus = '${widget.startLabel} 실패';
      parkingStatusTraceLog(
        context,
        'status_directional_gear=result target=${widget.debugTarget} action=driving_start success=false source=$source error=$error',
      );
    } finally {
      if (mounted) {
        setState(() {
          _busyInternal = false;
          _dragDelta = Offset.zero;
          _dragDirection = null;
          _dragProgress = 0;
          _thresholdHapticSent = false;
          _semanticStatus = semanticStatus;
        });
      }
    }
  }

  Future<void> _runDirectionalAction(
    _ParkingStatusGearDirection direction,
    ParkingStatusDirectionalGearAction action, {
    required String source,
  }) async {
    if (_isBusy) {
      _resetDragState();
      return;
    }
    setState(() {
      _busyInternal = true;
      _dragging = false;
      _dragProgress = 1;
      _thresholdHapticSent = false;
      _semanticStatus = '${_shortLabel(action.label)} 처리 중';
    });
    parkingStatusTraceLog(
      context,
      'status_directional_gear=armed target=${widget.debugTarget} detent=${widget.driving ? "upper" : "lower"} direction=${_directionName(direction)} action=${action.debugAction} source=$source',
    );
    parkingStatusTraceLog(
      context,
      'status_directional_gear=${source == "accessibility" ? "commit_accessibility" : "commit_on_release"} target=${widget.debugTarget} detent=${widget.driving ? "upper" : "lower"} direction=${_directionName(direction)} action=${action.debugAction}',
    );
    try {
      if (action.tone == ParkingStatusDirectionalGearTone.danger) {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.selectionClick();
      }
    } catch (_) {}
    var semanticStatus = '${_shortLabel(action.label)} 실패';
    try {
      final resultCallback = action.onConfirmResult;
      final ParkingStatusDirectionalGearActionResult result;
      if (resultCallback != null) {
        result = await resultCallback();
      } else {
        await action.onConfirm?.call();
        result = ParkingStatusDirectionalGearActionResult.completed;
      }
      semanticStatus = switch (result) {
        ParkingStatusDirectionalGearActionResult.completed =>
          '${_shortLabel(action.label)} 완료',
        ParkingStatusDirectionalGearActionResult.blocked =>
          '${_shortLabel(action.label)}을 진행할 수 없습니다',
        ParkingStatusDirectionalGearActionResult.cancelled =>
          '${_shortLabel(action.label)} 취소',
        ParkingStatusDirectionalGearActionResult.failed =>
          '${_shortLabel(action.label)} 실패',
      };
      if (mounted) {
        parkingStatusTraceLog(
          context,
          'status_directional_gear=result target=${widget.debugTarget} action=${action.debugAction} business_result=${result.name} source=$source',
        );
      }
    } catch (error) {
      semanticStatus = '${_shortLabel(action.label)} 실패';
      if (mounted) {
        parkingStatusTraceLog(
          context,
          'status_directional_gear=result target=${widget.debugTarget} action=${action.debugAction} business_result=failed source=$source error=$error',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busyInternal = false;
          _dragDelta = Offset.zero;
          _dragDirection = null;
          _dragProgress = 0;
          _dragging = false;
          _thresholdHapticSent = false;
          _semanticStatus = semanticStatus;
        });
      }
    }
  }

  String _semanticDirectionLabel(
    _ParkingStatusGearDirection direction,
    String label,
  ) {
    final directionLabel = switch (direction) {
      _ParkingStatusGearDirection.up => '위쪽',
      _ParkingStatusGearDirection.left => '왼쪽',
      _ParkingStatusGearDirection.right => '오른쪽',
      _ParkingStatusGearDirection.down => '아래쪽',
    };
    return '$directionLabel ${_shortLabel(label)}';
  }

  Map<CustomSemanticsAction, VoidCallback> _semanticActions() {
    if (!_canInteract) {
      return <CustomSemanticsAction, VoidCallback>{};
    }
    final actions = <CustomSemanticsAction, VoidCallback>{};

    void addDirectional(
      _ParkingStatusGearDirection direction,
      ParkingStatusDirectionalGearAction? action,
    ) {
      if (action == null) return;
      final semanticAction = CustomSemanticsAction(
        label: _semanticDirectionLabel(direction, action.label),
      );
      actions[semanticAction] = () {
        unawaited(
          _runDirectionalAction(
            direction,
            action,
            source: 'accessibility',
          ),
        );
      };
    }

    if (!widget.driving && widget.onStartDriving != null) {
      final semanticAction = CustomSemanticsAction(
        label: _semanticDirectionLabel(
          _ParkingStatusGearDirection.up,
          widget.startLabel,
        ),
      );
      actions[semanticAction] = () {
        unawaited(_runStartDriving(source: 'accessibility'));
      };
    }
    if (widget.driving) {
      addDirectional(_ParkingStatusGearDirection.down, widget.upperDown);
      addDirectional(_ParkingStatusGearDirection.right, widget.upperRight);
    } else {
      addDirectional(_ParkingStatusGearDirection.left, widget.lowerLeft);
      addDirectional(_ParkingStatusGearDirection.right, widget.lowerRight);
    }
    return actions;
  }

  String _semanticValue() {
    if (widget.blocked) {
      final owner = widget.blockedBy.trim();
      return owner.isEmpty ? '사용 불가' : '사용 불가, $owner 사용 중';
    }
    if (!widget.enabled) return '사용 불가';
    if (_isBusy) return _semanticStatus ?? '처리 중';
    final labels = <String>[];
    if (!widget.driving && widget.onStartDriving != null) {
      labels.add(_semanticDirectionLabel(
        _ParkingStatusGearDirection.up,
        widget.startLabel,
      ));
    }
    if (widget.driving) {
      if (widget.upperDown != null) {
        labels.add(_semanticDirectionLabel(
          _ParkingStatusGearDirection.down,
          widget.upperDown!.label,
        ));
      }
      if (widget.upperRight != null) {
        labels.add(_semanticDirectionLabel(
          _ParkingStatusGearDirection.right,
          widget.upperRight!.label,
        ));
      }
    } else {
      if (widget.lowerLeft != null) {
        labels.add(_semanticDirectionLabel(
          _ParkingStatusGearDirection.left,
          widget.lowerLeft!.label,
        ));
      }
      if (widget.lowerRight != null) {
        labels.add(_semanticDirectionLabel(
          _ParkingStatusGearDirection.right,
          widget.lowerRight!.label,
        ));
      }
    }
    final state = _semanticStatus ?? (widget.driving ? '주행 중' : '정지');
    if (labels.isEmpty) return state;
    return '$state, 사용 가능한 작업 ${labels.join(', ')}';
  }

  Color _toneColor(
    ColorScheme cs,
    ParkingStatusDirectionalGearTone tone,
  ) {
    return switch (tone) {
      ParkingStatusDirectionalGearTone.primary => cs.primary,
      ParkingStatusDirectionalGearTone.warning => cs.tertiary,
      ParkingStatusDirectionalGearTone.danger => cs.error,
      ParkingStatusDirectionalGearTone.neutral => cs.onSurfaceVariant,
    };
  }

  String _shortLabel(String value) {
    final label = value.trim();
    if (label == '입차 요청으로') return '입차 요청';
    if (label == '입차 완료로') return '입차 완료';
    if (label == '주행 스킵 후 입차 완료') return '입차 완료';
    if (label == '주행 스킵 후 출차 완료') return '출차 완료';
    if (label == '출차 요청으로 이동') return '출차 요청';
    if (label == '출차 완료로 이동') return '출차 완료';
    return label;
  }

  Widget _endpointLabel({
    required String text,
    required IconData icon,
    required Alignment alignment,
    required Color color,
  }) {
    return Align(
      alignment: alignment,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 2),
          Flexible(
            child: Text(
              _shortLabel(text),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 9,
                height: 1,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Offset _handleOffset({
    required double horizontalTravel,
    required double verticalTravel,
  }) {
    final direction = _dragDirection;
    if (direction == null) return Offset.zero;
    final progress = _dragProgress.clamp(0.0, 1.0);
    return switch (direction) {
      _ParkingStatusGearDirection.up => Offset(0, -verticalTravel * progress),
      _ParkingStatusGearDirection.down => Offset(0, verticalTravel * progress),
      _ParkingStatusGearDirection.left => Offset(-horizontalTravel * progress, 0),
      _ParkingStatusGearDirection.right => Offset(horizontalTravel * progress, 0),
    };
  }

  Widget _track(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final compact = _variant != ParkingStatusPrimaryVariant.normal;
    final ultra = _variant == ParkingStatusPrimaryVariant.ultraCompact;
    final fallbackTrackHeight = ultra ? 54.0 : compact ? 58.0 : 62.0;
    final handleSize = ultra ? 34.0 : compact ? 36.0 : 38.0;
    final lineThickness = ultra ? 6.0 : 7.0;
    final activeColor = cs.primary;
    final baseColor = cs.outlineVariant.withOpacity(.72);
    final blockedColor = cs.onSurfaceVariant.withOpacity(.45);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 200.0;
        final trackHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : fallbackTrackHeight;
        final centerX = width / 2;
        final edgeInset = math.max(13.0, handleSize / 2 + 1);
        final topY = edgeInset;
        final bottomY = math.max(topY, trackHeight - edgeInset);
        final verticalTravel = math.max(0.0, bottomY - topY);
        final horizontalTravel = math.max(34.0, width * .29);
        final baseY = widget.driving ? topY : bottomY;
        final offset = _handleOffset(
          horizontalTravel: horizontalTravel,
          verticalTravel: verticalTravel,
        );
        final handleLeft = centerX - handleSize / 2 + offset.dx;
        final handleTop = baseY - handleSize / 2 + offset.dy;
        final enabledColor = widget.blocked ? blockedColor : activeColor;
        final activeDirection = _dragDirection;
        final currentAction = activeDirection == null
            ? null
            : _actionFor(activeDirection);
        final handleColor = currentAction == null
            ? enabledColor
            : _toneColor(cs, currentAction.tone);

        return SizedBox(
          height: trackHeight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: _canInteract ? _onPanStart : null,
            onPanUpdate: _canInteract ? _onPanUpdate : null,
            onPanEnd: _canInteract ? _onPanEnd : null,
            onPanCancel: _canInteract ? _resetDragState : null,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (widget.driving ||
                    widget.onStartDriving != null ||
                    widget.upperDown != null)
                  Positioned(
                    left: centerX - lineThickness / 2,
                    top: topY,
                    width: lineThickness,
                    height: verticalTravel,
                    child: Container(
                      decoration: BoxDecoration(
                        color: baseColor,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                if (!widget.driving && widget.onStartDriving != null)
                  Positioned(
                    left: centerX - lineThickness / 2,
                    top: topY,
                    width: lineThickness,
                    height: verticalTravel,
                    child: FractionallySizedBox(
                      heightFactor: (_dragDirection ==
                                  _ParkingStatusGearDirection.up)
                          ? _dragProgress.clamp(0.0, 1.0)
                          : 0,
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        decoration: BoxDecoration(
                          color: activeColor.withOpacity(.36),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
                if (!widget.driving && widget.lowerLeft != null)
                  Positioned(
                    left: centerX - horizontalTravel,
                    top: bottomY - lineThickness / 2,
                    width: horizontalTravel,
                    height: lineThickness,
                    child: AnimatedContainer(
                      duration: _dragging || _reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 140),
                      decoration: BoxDecoration(
                        color: (_dragDirection ==
                                    _ParkingStatusGearDirection.left)
                            ? activeColor.withOpacity(.42)
                            : baseColor,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                if (!widget.driving && widget.lowerRight != null)
                  Positioned(
                    left: centerX,
                    top: bottomY - lineThickness / 2,
                    width: horizontalTravel,
                    height: lineThickness,
                    child: AnimatedContainer(
                      duration: _dragging || _reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 140),
                      decoration: BoxDecoration(
                        color: (_dragDirection ==
                                    _ParkingStatusGearDirection.right)
                            ? activeColor.withOpacity(.42)
                            : baseColor,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                if (widget.driving && widget.upperRight != null)
                  Positioned(
                    left: centerX,
                    top: topY - lineThickness / 2,
                    width: horizontalTravel,
                    height: lineThickness,
                    child: AnimatedContainer(
                      duration: _dragging || _reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 140),
                      decoration: BoxDecoration(
                        color: (_dragDirection ==
                                    _ParkingStatusGearDirection.right)
                            ? activeColor.withOpacity(.42)
                            : baseColor,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                if (widget.driving && widget.upperDown != null)
                  Positioned(
                    left: centerX - lineThickness / 2,
                    top: topY,
                    width: lineThickness,
                    height: verticalTravel,
                    child: AnimatedContainer(
                      duration: _dragging || _reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 140),
                      decoration: BoxDecoration(
                        color: (_dragDirection ==
                                    _ParkingStatusGearDirection.down)
                            ? activeColor.withOpacity(.42)
                            : baseColor,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                if (!widget.driving && widget.onStartDriving != null)
                  Positioned(
                    left: centerX - 32,
                    top: 0,
                    width: 64,
                    child: _endpointLabel(
                      text: widget.startLabel,
                      icon: Icons.keyboard_arrow_up_rounded,
                      alignment: Alignment.center,
                      color: widget.blocked
                          ? blockedColor
                          : cs.onSurfaceVariant,
                    ),
                  ),
                if (!widget.driving && widget.lowerLeft != null)
                  Positioned(
                    left: 0,
                    bottom: 0,
                    width: math.max(48.0, centerX - 24),
                    child: _endpointLabel(
                      text: widget.lowerLeft!.label,
                      icon: Icons.chevron_left_rounded,
                      alignment: Alignment.centerLeft,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                if (!widget.driving && widget.lowerRight != null)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    width: math.max(48.0, centerX - 24),
                    child: _endpointLabel(
                      text: widget.lowerRight!.label,
                      icon: Icons.chevron_right_rounded,
                      alignment: Alignment.centerRight,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                if (widget.driving && widget.upperRight != null)
                  Positioned(
                    right: 0,
                    top: 0,
                    width: math.max(48.0, centerX - 24),
                    child: _endpointLabel(
                      text: widget.upperRight!.label,
                      icon: Icons.chevron_right_rounded,
                      alignment: Alignment.centerRight,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                if (widget.driving && widget.upperDown != null)
                  Positioned(
                    left: 0,
                    bottom: 0,
                    width: math.max(48.0, centerX - 24),
                    child: _endpointLabel(
                      text: widget.upperDown!.label,
                      icon: Icons.keyboard_arrow_down_rounded,
                      alignment: Alignment.centerLeft,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                AnimatedPositioned(
                  duration: _dragging || _reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  curve: Curves.easeOutBack,
                  left: handleLeft,
                  top: handleTop,
                  width: handleSize,
                  height: handleSize,
                  child: AnimatedContainer(
                    duration: _reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 160),
                    curve: Curves.easeOutCubic,
                    decoration: BoxDecoration(
                      color: _isBusy
                          ? cs.surfaceContainerHighest
                          : handleColor,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: _isBusy
                            ? cs.outlineVariant
                            : handleColor.withOpacity(.7),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: cs.shadow.withOpacity(.16),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: AnimatedSwitcher(
                      duration: _reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 150),
                      child: _isBusy
                          ? SizedBox(
                              key: const ValueKey<String>('busy'),
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: cs.primary,
                              ),
                            )
                          : Icon(
                              widget.driving
                                  ? Icons.directions_car_filled_rounded
                                  : Icons.drag_handle_rounded,
                              key: ValueKey<bool>(widget.driving),
                              size: 20,
                              color: cs.onPrimary,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final compact = _variant != ParkingStatusPrimaryVariant.normal;
    final ultra = _variant == ParkingStatusPrimaryVariant.ultraCompact;
    final fallbackHeight = ultra ? 86.0 : compact ? 96.0 : 108.0;
    final verticalPadding = ultra ? 4.0 : compact ? 5.0 : 6.0;
    final horizontalPadding = ultra ? 7.0 : compact ? 8.0 : 9.0;
    final enabled = widget.enabled && !widget.blocked;
    final variantName = ultra ? 'ultra_compact' : compact ? 'compact' : 'normal';

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : fallbackHeight;
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 220.0;
        final signature = [
          variantName,
          availableWidth.toStringAsFixed(0),
          availableHeight.toStringAsFixed(0),
        ].join('|');
        if (_lastLayoutSignature != signature) {
          _lastLayoutSignature = signature;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            parkingStatusTraceLog(
              context,
              'status_directional_gear=layout target=${widget.debugTarget} sizing=bounded_fill width=${availableWidth.toStringAsFixed(0)} height=${availableHeight.toStringAsFixed(0)} variant=$variantName',
            );
          });
        }

        return Semantics(
          container: true,
          excludeSemantics: true,
          liveRegion: true,
          enabled: _canInteract,
          label: '상태 변경',
          value: _semanticValue(),
          customSemanticsActions: _semanticActions(),
          child: SizedBox(
            width: availableWidth,
            height: availableHeight,
            child: AnimatedOpacity(
              duration: _reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 160),
              opacity: enabled || widget.driving ? 1 : .58,
              child: AnimatedContainer(
                duration: _reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  verticalPadding,
                  horizontalPadding,
                  verticalPadding,
                ),
                decoration: BoxDecoration(
                  color: widget.driving
                      ? cs.primaryContainer.withOpacity(.26)
                      : cs.surfaceContainerLow.withOpacity(.72),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: widget.driving
                        ? cs.primary.withOpacity(.42)
                        : cs.outlineVariant.withOpacity(.62),
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SizedBox(
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      child: _track(context),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

}


class _ParkingStatusManagementRailButton extends StatefulWidget {
  const _ParkingStatusManagementRailButton({
    super.key,
    required this.action,
    required this.debugTarget,
    required this.compact,
    required this.extent,
  });

  final ParkingStatusManagementAction action;
  final String debugTarget;
  final bool compact;
  final double extent;

  @override
  State<_ParkingStatusManagementRailButton> createState() =>
      _ParkingStatusManagementRailButtonState();
}

class _ParkingStatusManagementRailButtonState
    extends State<_ParkingStatusManagementRailButton> {
  bool _busy = false;

  Future<void> _invoke() async {
    if (!widget.action.enabled || _busy) return;
    setState(() {
      _busy = true;
    });
    final actionName = widget.action.debugAction.trim().isEmpty
        ? widget.action.label.trim()
        : widget.action.debugAction.trim();
    final linkedGroup = widget.action.linkedGroup.trim();
    parkingStatusTraceLog(
      context,
      'vehicle_management_rail=interaction action=$actionName visual_label=${widget.action.visualLabel} full_label=${jsonEncode(widget.action.label)} linked_group=${linkedGroup.isEmpty ? "none" : linkedGroup} linked_reverse=${widget.action.linkedReverse} target=${widget.debugTarget} railDesign=common_operations',
    );
    if (widget.action.destructive) {
      await HapticFeedback.mediumImpact();
    } else {
      await HapticFeedback.selectionClick();
    }
    try {
      await widget.action.onPressed();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final enabled = widget.action.enabled && !_busy;
    final linked = widget.action.linkedGroup.trim().isNotEmpty;
    final foreground = widget.action.destructive
        ? tokens.danger
        : linked && enabled
            ? tokens.accent
            : widget.action.emphasized && enabled
                ? tokens.accent
                : enabled
                    ? tokens.iconPrimary
                    : tokens.iconDisabled;
    final textColor = widget.action.destructive
        ? tokens.danger
        : linked && enabled
            ? tokens.accent
            : widget.action.emphasized && enabled
                ? tokens.accent
                : enabled
                    ? tokens.textPrimary
                    : tokens.textDisabled;
    final background = widget.action.destructive
        ? tokens.dangerContainer.withOpacity(enabled ? .46 : .22)
        : linked && enabled
            ? tokens.accentContainer.withOpacity(
                widget.action.emphasized
                    ? .68
                    : widget.action.linkedReverse
                        ? .38
                        : .48,
              )
            : widget.action.emphasized && enabled
                ? tokens.accentContainer.withOpacity(.62)
                : enabled
                    ? tokens.surfaceRaised
                    : tokens.surfaceDisabled;
    final pressedBackground = widget.action.destructive
        ? tokens.dangerContainer.withOpacity(enabled ? .56 : .22)
        : linked && enabled
            ? tokens.accentContainer.withOpacity(
                widget.action.emphasized
                    ? .88
                    : widget.action.linkedReverse
                        ? .64
                        : .72,
              )
            : widget.action.emphasized && enabled
                ? tokens.accentContainer.withOpacity(.86)
                : enabled
                    ? tokens.accentContainer.withOpacity(.72)
                    : tokens.surfaceDisabled;
    final border = widget.action.destructive
        ? tokens.danger.withOpacity(enabled ? .34 : .16)
        : linked && enabled
            ? tokens.accent.withOpacity(
                widget.action.emphasized
                    ? .44
                    : widget.action.linkedReverse
                        ? .34
                        : .38,
              )
            : widget.action.emphasized && enabled
                ? tokens.accent.withOpacity(.38)
                : tokens.borderSubtle;
    final pressedBorder = widget.action.destructive
        ? tokens.danger.withOpacity(enabled ? .5 : .16)
        : linked && enabled
            ? tokens.accent.withOpacity(
                widget.action.emphasized
                    ? .62
                    : widget.action.linkedReverse
                        ? .52
                        : .56,
              )
            : widget.action.emphasized && enabled
                ? tokens.accent.withOpacity(.58)
                : enabled
                    ? tokens.accent.withOpacity(.42)
                    : tokens.borderSubtle;

    Widget iconChild;
    if (_busy) {
      iconChild = SizedBox(
        key: const ValueKey<String>('busy'),
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: foreground,
        ),
      );
    } else {
      iconChild = SizedBox(
        key: ValueKey<String>(
          'icon:${widget.action.icon.codePoint}:${widget.action.linkedReverse}',
        ),
        width: 26,
        height: 23,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Icon(
              widget.action.icon,
              size: widget.compact ? 19 : 20,
              color: foreground,
            ),
            if (linked)
              Positioned(
                right: -2,
                bottom: -2,
                child: AnimatedRotation(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  turns: widget.action.linkedReverse ? .5 : 0,
                  child: Icon(
                    Icons.sync_alt_rounded,
                    size: 10,
                    color: foreground,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return CommonSideRailActionButton(
      semanticLabel: widget.action.label,
      visualLabel: widget.action.visualLabel,
      selected: false,
      enabled: enabled,
      compact: widget.compact,
      extent: widget.extent,
      onTap: () {
        unawaited(_invoke());
      },
      iconChild: iconChild,
      tooltip: widget.action.label,
      visuals: CommonSideRailButtonVisuals(
        foreground: foreground,
        textColor: textColor,
        background: background,
        pressedBackground: pressedBackground,
        border: border,
        pressedBorder: pressedBorder,
      ),
    );
  }
}

class ParkingStatusContentReveal extends StatelessWidget {
  const ParkingStatusContentReveal({
    super.key,
    required this.order,
    required this.child,
    this.offsetY = 6,
  });

  final int order;
  final Widget child;
  final double offsetY;

  @override
  Widget build(BuildContext context) {
    return _ParkingStatusReveal(
      order: order,
      offsetY: offsetY,
      child: child,
    );
  }
}

class ParkingCompletedActionList extends StatelessWidget {
  const ParkingCompletedActionList({
    super.key,
    required this.children,
    this.spacing = 10,
  });

  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < children.length; index++) ...[
          _ParkingStatusReveal(
            order: index,
            child: children[index],
          ),
          if (index != children.length - 1) SizedBox(height: spacing),
        ],
      ],
    );
  }
}

class _ParkingStatusReveal extends StatelessWidget {
  const _ParkingStatusReveal({
    required this.order,
    required this.child,
    this.offsetY = 9,
  });

  final int order;
  final Widget child;
  final double offsetY;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return child;

    final delayMs = order.clamp(0, 10).toInt() * 22;
    const motionMs = 190;
    final totalMs = delayMs + motionMs;
    final start = delayMs / totalMs;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: totalMs),
      curve: Curves.linear,
      child: child,
      builder: (context, value, animatedChild) {
        final normalized = value <= start
            ? 0.0
            : ((value - start) / (1 - start)).clamp(0.0, 1.0).toDouble();
        final motion = Curves.easeOutCubic.transform(normalized);
        return Opacity(
          opacity: motion,
          child: Transform.translate(
            offset: Offset(0, offsetY * (1 - motion)),
            child: animatedChild,
          ),
        );
      },
    );
  }
}

enum ParkingCompletedBillingState {
  notApplicable,
  unsettled,
  settled,
}

ParkingCompletedBillingState resolveParkingCompletedBillingState({
  required String? billingType,
  required bool isLocked,
}) {
  if ((billingType ?? '').trim().isEmpty) {
    return ParkingCompletedBillingState.notApplicable;
  }
  return isLocked
      ? ParkingCompletedBillingState.settled
      : ParkingCompletedBillingState.unsettled;
}

String parkingCompletedBillingStateDebugName(
  ParkingCompletedBillingState state,
) {
  if (state == ParkingCompletedBillingState.notApplicable) {
    return 'not_applicable';
  }
  if (state == ParkingCompletedBillingState.settled) {
    return 'settled';
  }
  return 'unsettled';
}

class ParkingCompletedSectionCard extends StatelessWidget {
  const ParkingCompletedSectionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.colorScheme,
    this.borderColor,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final ColorScheme? colorScheme;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final displayTitle = title == '핵심 작업'
        ? '상태 변경'
        : title == '빠른 실행'
            ? '차량 관리'
            : title;

    var revealOrder = 2;
    if (displayTitle == '상태 변경') {
      revealOrder = 4;
    } else if (displayTitle == '차량 관리') {
      revealOrder = 3;
    }

    return CommonSideDockSection(
      title: displayTitle,
      subtitle: subtitle,
      accentColor: borderColor,
      order: revealOrder,
      child: child,
    );
  }
}

class ParkingCompletedPrimaryCtaButton extends StatelessWidget {
  const ParkingCompletedPrimaryCtaButton({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPressed,
    this.enabled = true,
    this.backgroundColor,
    this.foregroundColor,
    this.colorScheme,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final FutureOr<void> Function() onPressed;
  final bool enabled;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final ColorScheme? colorScheme;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final variant = ParkingStatusPrimaryLayout.variantOf(context);
    final requestedAccent = backgroundColor ?? tokens.accent;
    final requestedForeground = foregroundColor ?? tokens.onAccent;
    return _ParkingCompletedActionButton(
      icon: icon,
      title: title,
      subtitle: variant == ParkingStatusPrimaryVariant.normal ? subtitle : null,
      onPressed: enabled ? onPressed : null,
      background: tokens.surface,
      foreground: tokens.textPrimary,
      border: requestedAccent.withOpacity(.28),
      iconColor: requestedForeground,
      iconBackground: requestedAccent,
      minHeight: variant == ParkingStatusPrimaryVariant.ultraCompact
          ? 46
          : variant == ParkingStatusPrimaryVariant.compact
              ? 50
              : 54,
      defaultBackground: false,
      haptic: CommonHaptic.medium,
    );
  }
}

class ParkingCompletedSecondaryActionButton extends StatelessWidget {
  const ParkingCompletedSecondaryActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.subtitle,
    this.enabled = true,
    this.badgeText,
    this.backgroundColor,
    this.borderColor,
    this.foregroundColor,
    this.attention = 0,
    this.iconColor,
    this.badgeColor,
    this.baseBackgroundColor,
    this.baseBorderColor,
    this.colorScheme,
  });

  final IconData icon;
  final String label;
  final FutureOr<void> Function() onPressed;
  final String? subtitle;
  final bool enabled;
  final String? badgeText;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? foregroundColor;
  final double attention;
  final Color? iconColor;
  final Color? badgeColor;
  final Color? baseBackgroundColor;
  final Color? baseBorderColor;
  final ColorScheme? colorScheme;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final safeAttention = reduceMotion ? 0.0 : attention.clamp(0.0, 1.0).toDouble();
    final baseBg = backgroundColor ?? baseBackgroundColor ?? tokens.surface;
    final baseBd = borderColor ?? baseBorderColor ?? tokens.borderSubtle;
    final effectiveForeground = foregroundColor ?? tokens.onAccentContainer;
    final effectiveIcon = iconColor ?? effectiveForeground;
    final effectiveBadge = badgeColor ?? effectiveForeground;
    final resolvedSubtitle = subtitle?.trim().isNotEmpty == true
        ? subtitle!.trim()
        : _secondaryActionSubtitle(label);
    final bg = Color.lerp(baseBg, tokens.dangerContainer, safeAttention * .48)!;
    final bd = Color.lerp(baseBd, tokens.danger, safeAttention * .52)!;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        _ParkingCompletedActionButton(
          icon: icon,
          title: label,
          subtitle: resolvedSubtitle,
          onPressed: enabled ? onPressed : null,
          background: bg,
          foreground: effectiveForeground,
          iconColor: effectiveIcon,
          iconBackground: Color.alphaBlend(
            effectiveIcon.withOpacity(.12),
            bg,
          ),
          border: bd,
          minHeight: 48,
          haptic: CommonHaptic.selection,
        ),
        if (badgeText != null && badgeText!.trim().isNotEmpty)
          Positioned(
            top: -7,
            right: -5,
            child: AnimatedContainer(
              duration:
                  reduceMotion ? Duration.zero : CommonUiMotion.selection,
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: tokens.surfaceRaised,
                borderRadius: BorderRadius.circular(CommonUiShapes.pill),
                border: Border.all(color: effectiveBadge.withOpacity(.48)),
                boxShadow: [
                  BoxShadow(
                    color: tokens.shadow.withOpacity(.12),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Text(
                badgeText!.trim(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: effectiveBadge,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          ),
      ],
    );
  }
}

class ParkingCompletedBillingActionButton extends StatelessWidget {
  const ParkingCompletedBillingActionButton({
    super.key,
    required this.billingState,
    required this.onSettle,
    required this.onCancel,
    this.requiredSettlement = false,
    this.enabled = true,
    this.attention = 0,
    this.colorScheme,
  });

  final ParkingCompletedBillingState billingState;
  final FutureOr<void> Function() onSettle;
  final FutureOr<void> Function() onCancel;
  final bool requiredSettlement;
  final bool enabled;
  final double attention;
  final ColorScheme? colorScheme;

  @override
  Widget build(BuildContext context) {
    if (billingState == ParkingCompletedBillingState.notApplicable) {
      return const SizedBox.shrink();
    }
    final cs = colorScheme ?? Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final settled = billingState == ParkingCompletedBillingState.settled;
    final requiredNow = requiredSettlement && !settled;
    final duration = reduceMotion ? Duration.zero : const Duration(milliseconds: 220);

    final child = ParkingCompletedSecondaryActionButton(
      key: ValueKey<String>(settled ? 'billing-cancel' : 'billing-settle'),
      colorScheme: cs,
      icon: settled ? Icons.lock_open_rounded : Icons.receipt_long_rounded,
      label: settled ? '정산 취소' : '정산',
      subtitle: settled
          ? '완료된 사전 정산을 취소합니다.'
          : requiredNow
              ? '출차 전에 정산을 완료합니다.'
              : '차량의 사전 정산을 처리합니다.',
      enabled: enabled,
      badgeText: settled ? '정산 완료' : requiredNow ? '필수' : null,
      attention: requiredNow ? attention : 0,
      backgroundColor: settled
          ? cs.tertiaryContainer.withOpacity(.38)
          : requiredNow
              ? cs.errorContainer.withOpacity(.28)
              : cs.surfaceContainerLow,
      borderColor: settled
          ? cs.tertiary.withOpacity(.38)
          : requiredNow
              ? cs.error.withOpacity(.48)
              : cs.outlineVariant.withOpacity(.85),
      foregroundColor: settled
          ? cs.tertiary
          : requiredNow
              ? cs.error
              : cs.onSurface,
      iconColor: settled
          ? cs.tertiary
          : requiredNow
              ? cs.error
              : cs.primary,
      badgeColor: settled
          ? cs.tertiary
          : requiredNow
              ? cs.error
              : cs.primary,
      onPressed: () async {
        parkingStatusTraceLog(
          context,
          'billing_action=tap state=${settled ? "settled" : "unsettled"} action=${settled ? "cancel" : "settle"}',
        );
        if (settled) {
          await onCancel();
        } else {
          await onSettle();
        }
      },
    );

    return AnimatedSwitcher(
      duration: duration,
      reverseDuration: reduceMotion ? Duration.zero : const Duration(milliseconds: 160),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.center,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (child, animation) {
        final offset = Tween<Offset>(
          begin: const Offset(0, .08),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        );
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offset, child: child),
        );
      },
      child: child,
    );
  }
}

String _secondaryActionSubtitle(String label) {
  final value = label.trim();
  if (value.contains('로그')) {
    return '차량 처리 이력을 확인합니다.';
  }
  if (value.contains('정보 수정')) {
    return '차량 정보를 수정합니다.';
  }
  if (value.contains('정산 취소')) {
    return '완료된 사전 정산을 취소합니다.';
  }
  if (value.contains('정산 완료')) {
    return '현재 차량의 사전 정산 상태를 확인합니다.';
  }
  if (value.contains('정산')) {
    return '차량의 사전 정산을 처리합니다.';
  }
  if (value.contains('입차 요청')) {
    return '차량 상태를 입차 요청으로 되돌립니다.';
  }
  if (value.contains('입차 완료')) {
    return '차량 상태를 입차 완료로 되돌립니다.';
  }
  if (value.contains('출차 요청')) {
    return '차량 상태를 출차 요청으로 전환합니다.';
  }
  if (value.contains('출차 완료')) {
    return '차량 상태를 출차 완료로 전환합니다.';
  }
  return '현재 차량에서 이 작업을 실행합니다.';
}

class ParkingCompletedDangerActionButton extends StatelessWidget {
  const ParkingCompletedDangerActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.enabled = true,
    this.colorScheme,
  });

  final IconData icon;
  final String label;
  final FutureOr<void> Function() onPressed;
  final bool enabled;
  final ColorScheme? colorScheme;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        Row(
          children: [
            Container(
              width: 3,
              height: 18,
              decoration: BoxDecoration(
                color: tokens.danger,
                borderRadius: BorderRadius.circular(CommonUiShapes.pill),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '관리',
              style: textTheme.titleSmall?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 10),
          child: _ParkingCompletedActionButton(
            icon: icon,
            title: label,
            subtitle: '이 차량 기록을 삭제합니다.',
            onPressed: enabled ? onPressed : null,
            background: tokens.surface,
            foreground: tokens.textPrimary,
            iconColor: tokens.danger,
            iconBackground: tokens.dangerContainer,
            border: tokens.danger.withOpacity(.38),
            minHeight: 54,
            haptic: CommonHaptic.medium,
          ),
        ),
      ],
    );
  }
}

class _ParkingCompletedActionButton extends StatefulWidget {
  const _ParkingCompletedActionButton({
    required this.icon,
    required this.title,
    required this.onPressed,
    required this.background,
    required this.foreground,
    required this.border,
    required this.haptic,
    this.subtitle,
    this.iconColor,
    this.iconBackground,
    this.minHeight = 54,
    this.defaultBackground = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final FutureOr<void> Function()? onPressed;
  final Color background;
  final Color foreground;
  final Color border;
  final Color? iconColor;
  final Color? iconBackground;
  final double minHeight;
  final bool defaultBackground;
  final CommonHaptic haptic;

  @override
  State<_ParkingCompletedActionButton> createState() =>
      _ParkingCompletedActionButtonState();
}

class _ParkingCompletedActionButtonState
    extends State<_ParkingCompletedActionButton> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;
  bool _invoking = false;
  bool? _pendingPressed;
  bool? _pendingHovered;
  bool? _pendingFocused;
  bool _frameScheduled = false;

  bool get _available => widget.onPressed != null;
  bool get _enabled => _available && !_invoking;

  void _queue({bool? pressed, bool? hovered, bool? focused}) {
    if (pressed != null) _pendingPressed = pressed;
    if (hovered != null) _pendingHovered = hovered;
    if (focused != null) _pendingFocused = focused;
    if (_frameScheduled) return;
    _frameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _frameScheduled = false;
      if (!mounted) return;
      final pressedValue = _pendingPressed;
      final hoveredValue = _pendingHovered;
      final focusedValue = _pendingFocused;
      _pendingPressed = null;
      _pendingHovered = null;
      _pendingFocused = null;
      final changed =
          pressedValue != null && pressedValue != _pressed ||
          hoveredValue != null && hoveredValue != _hovered ||
          focusedValue != null && focusedValue != _focused;
      if (!changed) return;
      setState(() {
        if (pressedValue != null) _pressed = pressedValue;
        if (hoveredValue != null) _hovered = hoveredValue;
        if (focusedValue != null) _focused = focusedValue;
      });
    });
  }

  Future<void> _activate() async {
    if (!_enabled) return;
    setState(() => _invoking = true);
    try {
      switch (widget.haptic) {
        case CommonHaptic.none:
          break;
        case CommonHaptic.selection:
          await HapticFeedback.selectionClick();
          break;
        case CommonHaptic.light:
          await HapticFeedback.lightImpact();
          break;
        case CommonHaptic.medium:
          await HapticFeedback.mediumImpact();
          break;
        case CommonHaptic.heavy:
          await HapticFeedback.heavyImpact();
          break;
      }
      await widget.onPressed!.call();
    } finally {
      if (mounted) {
        setState(() {
          _invoking = false;
          _pressed = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final primaryVariant = ParkingStatusPrimaryLayout.variantOf(context);
    final compactPrimary = primaryVariant != ParkingStatusPrimaryVariant.normal;
    final ultraPrimary =
        primaryVariant == ParkingStatusPrimaryVariant.ultraCompact;
    final horizontalPadding = ultraPrimary ? 9.0 : compactPrimary ? 10.0 : 12.0;
    final verticalPadding = ultraPrimary ? 7.0 : compactPrimary ? 8.0 : 11.0;
    final iconExtent = ultraPrimary ? 34.0 : compactPrimary ? 38.0 : 42.0;
    final iconSize = ultraPrimary ? 18.0 : compactPrimary ? 20.0 : 21.0;
    final contentGap = ultraPrimary ? 8.0 : compactPrimary ? 10.0 : 12.0;
    final disabled = !_available;
    final background = disabled
        ? tokens.surfaceDisabled
        : widget.defaultBackground
            ? _pressed
                ? tokens.accentPressed
                : _hovered
                    ? tokens.accentHover
                    : widget.background
            : widget.background;
    final foreground = disabled ? tokens.textDisabled : widget.foreground;
    final border = disabled ? tokens.borderSubtle : widget.border;

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.title,
      value: _invoking ? '처리 중' : null,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
        curve: CommonUiMotion.standard,
        constraints: BoxConstraints(minHeight: widget.minHeight),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(CommonUiShapes.button),
          border: Border.all(
            color: _focused ? tokens.focusRing : border,
            width: _focused ? 2 : 1,
          ),
          boxShadow: [
            if (_hovered && _enabled)
              BoxShadow(
                color: tokens.shadow,
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
          ],
        ),
        child: Material(
          color: tokens.transparent,
          borderRadius: BorderRadius.circular(CommonUiShapes.button),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _available ? _activate : null,
            onHighlightChanged: (value) => _queue(pressed: value),
            onHover: (value) => _queue(hovered: value),
            onFocusChange: (value) => _queue(focused: value),
            borderRadius: BorderRadius.circular(CommonUiShapes.button),
            overlayColor: WidgetStatePropertyAll(
              foreground.withOpacity(_pressed ? .12 : .06),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: verticalPadding,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedOpacity(
                    duration:
                        reduceMotion ? Duration.zero : CommonUiMotion.instant,
                    opacity: _invoking ? 0 : 1,
                    child: AnimatedScale(
                      scale: _pressed && _enabled ? .98 : 1,
                      duration:
                          reduceMotion ? Duration.zero : CommonUiMotion.press,
                      curve: CommonUiMotion.enter,
                      child: Row(
                        children: [
                          AnimatedContainer(
                            duration: reduceMotion
                                ? Duration.zero
                                : CommonUiMotion.selection,
                            width: iconExtent,
                            height: iconExtent,
                            decoration: BoxDecoration(
                              color: disabled
                                  ? tokens.surfaceDisabled
                                  : widget.iconBackground ??
                                      Color.alphaBlend(
                                        (widget.iconColor ?? foreground)
                                            .withOpacity(.12),
                                        background,
                                      ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                if (_hovered && _enabled)
                                  BoxShadow(
                                    color: tokens.shadow.withOpacity(.18),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              widget.icon,
                              size: iconSize,
                              color: disabled
                                  ? tokens.iconDisabled
                                  : widget.iconColor ?? foreground,
                            ),
                          ),
                          SizedBox(width: contentGap),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.labelLarge?.copyWith(
                                    color: foreground,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (widget.subtitle != null &&
                                    widget.subtitle!.trim().isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    widget.subtitle!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.bodySmall?.copyWith(
                                      color: foreground.withOpacity(.88),
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          SizedBox(width: ultraPrimary ? 4 : 8),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: ultraPrimary ? 18 : 21,
                            color: foreground,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_invoking)
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: foreground,
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
}
