import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../shared/operational_cache/domain/repositories/operational_local_repository.dart';
import '../../../../shared/parking_dot_map/parking_status_dot_map_surface.dart';
import '../../../../shared/parking_spatial/parking_spatial_child_region_widgets.dart';
import '../../../../shared/parking_spatial/parking_spatial_child_regions.dart';
import '../../../../shared/parking_spatial/parking_spatial_hierarchy.dart';
import '../../../../shared/parking_spatial/parking_spatial_tower_slot_grid.dart';
import '../../../../shared/parking_spatial/parking_spatial_transition.dart';
import '../../../location/domain/models/grid_rect.dart';
import '../../../location/domain/models/location_model.dart';
import '../../../location/domain/models/parking_grid_model.dart';
import '../../application/single_inside_diagnostics.dart';

class SingleInsideSpatialDotMap extends StatefulWidget {
  const SingleInsideSpatialDotMap({
    super.key,
    required this.area,
    required this.refreshRevision,
  });

  final String area;
  final int refreshRevision;

  @override
  State<SingleInsideSpatialDotMap> createState() =>
      _SingleInsideSpatialDotMapState();
}

class _SingleInsideSpatialDotMapState extends State<SingleInsideSpatialDotMap> {
  final PageController _pageController = PageController();
  List<_SingleSpatialMapEntry> _entries = const <_SingleSpatialMapEntry>[];
  bool _loading = true;
  bool _failed = false;
  bool _childDialogOpen = false;
  int _pageIndex = 0;
  int _loadToken = 0;
  String? _focusedChildKey;
  String _childCloseSource = 'route';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(covariant SingleInsideSpatialDotMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.area.trim() != widget.area.trim() ||
        oldWidget.refreshRevision != widget.refreshRevision) {
      _load();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    final area = widget.area.trim();
    if (mounted) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }
    SingleInsideDiagnostics.log(
      'dotmap',
      'load_start area=$area revision=${widget.refreshRevision}',
    );

    if (area.isEmpty) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        _entries = const <_SingleSpatialMapEntry>[];
        _loading = false;
      });
      SingleInsideDiagnostics.log('dotmap', 'load_empty_area');
      return;
    }

    try {
      final locations =
          await context.read<OperationalLocalRepository>().readLocations(area);
      final hierarchy = resolveParkingSpatialHierarchy(locations);
      final entries = <_SingleSpatialMapEntry>[];
      var childCount = 0;
      var slotCount = 0;
      var towerCount = 0;
      for (final group in hierarchy) {
        final parent = group.parentSource;
        final grid = parent?.parkingGrid;
        if (parent == null || grid == null || grid.rows <= 0 || grid.cols <= 0) {
          continue;
        }
        childCount += group.children.length;
        for (final child in group.children) {
          slotCount += parkingSpatialCapacityForChild(child);
          if (child.isTowerChild) towerCount++;
        }
        entries.add(
          _SingleSpatialMapEntry(
            group: group,
            parent: parent,
            grid: grid,
          ),
        );
      }

      if (!mounted || token != _loadToken) return;
      final nextIndex = entries.isEmpty
          ? 0
          : math.min(_pageIndex, entries.length - 1).toInt();
      setState(() {
        _entries = List<_SingleSpatialMapEntry>.unmodifiable(entries);
        _pageIndex = nextIndex;
        _loading = false;
        _failed = false;
      });
      SingleInsideDiagnostics.log(
        'dotmap',
        'hierarchy_resolved area=$area locationCount=${locations.length} parents=${entries.length} children=$childCount slots=$slotCount towers=$towerCount plateData=false viewCollection=false',
      );
      SingleInsideDiagnostics.log(
        'dotmap',
        'load_complete area=$area mapCount=${entries.length} pageIndex=$nextIndex',
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_pageController.hasClients || entries.isEmpty) return;
        final current = _pageController.page?.round() ?? 0;
        if (current != nextIndex) {
          _pageController.jumpToPage(nextIndex);
        }
      });
    } catch (error, stackTrace) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        _entries = const <_SingleSpatialMapEntry>[];
        _loading = false;
        _failed = true;
        _pageIndex = 0;
      });
      SingleInsideDiagnostics.log(
        'dotmap',
        'load_failure area=$area error=$error stack=$stackTrace',
      );
      unawaited(
        SingleInsideDiagnostics.showStatus(
          context,
          title: 'Single 공간 상태',
          description: '공간 계층 데이터를 불러오지 못했습니다.',
          failure: true,
        ),
      );
    }
  }

  void _onPageChanged(int index) {
    if (_pageIndex == index) return;
    setState(() => _pageIndex = index);
    HapticFeedback.selectionClick();
    final entry = index >= 0 && index < _entries.length ? _entries[index] : null;
    SingleInsideDiagnostics.log(
      'dotmap',
      'page_changed index=$index id=${entry?.id ?? ''} name=${entry?.name ?? ''}',
    );
  }

  Future<void> _focusChild(
    _SingleSpatialMapEntry entry,
    ParkingSpatialChildRegion<LocationModel> region,
    Rect sourceRect,
  ) async {
    if (_childDialogOpen) {
      SingleInsideDiagnostics.log(
        'dotmap',
        'child_focus_blocked parent=${entry.name} child=${region.source.locationName} reason=dialog_open',
      );
      return;
    }
    final child = region.source;
    final childName = child.locationName.trim().isEmpty
        ? child.id
        : child.locationName.trim();
    final childKey = '${entry.id}:${child.id}';
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final targetRect = parkingSpatialTargetRect(context);
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 340);
    _childCloseSource = 'route';
    _childDialogOpen = true;
    if (mounted) {
      setState(() => _focusedChildKey = childKey);
    }
    HapticFeedback.selectionClick();
    SingleInsideDiagnostics.log(
      'dotmap',
      'child_focus_started parent=${entry.name} child=$childName childKind=${child.isTowerChild ? 'tower' : 'spatial'} viewport=${region.childRect.toKey()} sourceRect=${parkingSpatialRectDebug(sourceRect)} targetRect=${parkingSpatialRectDebug(targetRect)} durationMs=${duration.inMilliseconds} slots=${parkingSpatialCapacityForChild(child)} areaIds=${region.effectiveParkingAreaIds.length} plateData=false',
    );

    try {
      if (!reduceMotion) {
        await Future<void>.delayed(const Duration(milliseconds: 48));
        if (!mounted || _focusedChildKey != childKey) return;
      }
      await showGeneralDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        barrierLabel: '$childName 주차 구역',
        barrierColor: Colors.transparent,
        transitionDuration: duration,
        pageBuilder: (_, __, ___) => const SizedBox.expand(),
        transitionBuilder: (dialogContext, animation, _, __) {
          void close(String source) {
            if (_childCloseSource != 'route') return;
            _childCloseSource = source;
            HapticFeedback.selectionClick();
            SingleInsideDiagnostics.log(
              'dotmap',
              'child_focus_collapse_started parent=${entry.name} child=$childName source=$source',
            );
            Navigator.of(dialogContext).pop();
          }

          return ParkingSpatialSourceRectTransition(
            animation: animation,
            sourceRect: sourceRect,
            targetRect: targetRect,
            reduceMotion: reduceMotion,
            closeSemanticsLabel: '$childName 닫기',
            onCloseRequested: close,
            onSystemPop: () {
              if (_childCloseSource == 'route') {
                _childCloseSource = 'system_back';
                HapticFeedback.selectionClick();
                SingleInsideDiagnostics.log(
                  'dotmap',
                  'child_focus_collapse_started parent=${entry.name} child=$childName source=system_back',
                );
              }
            },
            onExpanded: () {
              SingleInsideDiagnostics.log(
                'dotmap',
                'child_focus_completed parent=${entry.name} child=$childName center=${parkingSpatialRectDebug(targetRect)} slots=${parkingSpatialCapacityForChild(child)} plateData=false',
              );
            },
            onCollapseLifecycle: (info) {
              SingleInsideDiagnostics.log(
                'dotmap',
                'child_focus_collapse_lifecycle parent=${entry.name} child=$childName expanded=${info.expandedBeforeCollapse} early=${info.earlyCollapse} maxProgress=${info.maxRawProgress.toStringAsFixed(3)}',
              );
            },
            onCollapsed: () {
              SingleInsideDiagnostics.log(
                'dotmap',
                'child_focus_collapse_completed parent=${entry.name} child=$childName source=$_childCloseSource target=${parkingSpatialRectDebug(sourceRect)}',
              );
            },
            builder: (context, progress, interactionEnabled) {
              return _SingleChildFocusSurface(
                child: child,
                grid: entry.grid,
                childRect: region.childRect,
                effectiveParkingAreaIds: region.effectiveParkingAreaIds,
                progress: progress,
                reduceMotion: reduceMotion,
                interactionEnabled: interactionEnabled,
                onClose: () => close('dialog_header'),
              );
            },
          );
        },
      );
    } catch (error, stackTrace) {
      SingleInsideDiagnostics.log(
        'dotmap',
        'child_focus_failure parent=${entry.name} child=$childName error=$error stack=$stackTrace',
      );
      if (mounted) {
        unawaited(
          SingleInsideDiagnostics.showStatus(
            context,
            title: 'Single 공간 상태',
            description: '$childName 구역 전환 중 오류가 발생했습니다.',
            failure: true,
          ),
        );
      }
    } finally {
      _childDialogOpen = false;
      if (mounted && _focusedChildKey == childKey) {
        setState(() => _focusedChildKey = null);
      } else if (_focusedChildKey == childKey) {
        _focusedChildKey = null;
      }
      SingleInsideDiagnostics.log(
        'dotmap',
        'child_focus_closed parent=${entry.name} child=$childName source=$_childCloseSource return=parent_overview',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        if (reduceMotion) return child;
        final offset = Tween<Offset>(
          begin: const Offset(0, .025),
          end: Offset.zero,
        ).animate(animation);
        final scale = Tween<double>(begin: .985, end: 1).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: offset,
            child: ScaleTransition(scale: scale, child: child),
          ),
        );
      },
      child: _loading
          ? _SingleSpatialStateSurface(
              key: const ValueKey<String>('single_dotmap_loading'),
              icon: Icons.grid_view_rounded,
              label: '공간 정보 로딩 중',
              loading: true,
            )
          : _failed
              ? const _SingleSpatialStateSurface(
                  key: ValueKey<String>('single_dotmap_failure'),
                  icon: Icons.error_outline_rounded,
                  label: '공간 정보를 불러오지 못했습니다',
                )
              : _entries.isEmpty
                  ? const _SingleSpatialStateSurface(
                      key: ValueKey<String>('single_dotmap_empty'),
                      icon: Icons.grid_off_rounded,
                      label: '등록된 공간 정보가 없습니다',
                    )
                  : Container(
                      key: ValueKey<String>(
                        'single_dotmap_loaded_${widget.area}_${widget.refreshRevision}',
                      ),
                      color: tokens.canvas,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: PageView.builder(
                              controller: _pageController,
                              physics: _childDialogOpen
                                  ? const NeverScrollableScrollPhysics()
                                  : const ClampingScrollPhysics(),
                              itemCount: _entries.length,
                              onPageChanged: _onPageChanged,
                              itemBuilder: (context, index) {
                                final entry = _entries[index];
                                return _SingleSpatialMapPage(
                                  entry: entry,
                                  focusedChildKey: _focusedChildKey,
                                  reduceMotion: reduceMotion,
                                  onChildTap: (region, sourceRect) {
                                    unawaited(
                                      _focusChild(entry, region, sourceRect),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                          Positioned(
                            left: 16,
                            right: 16,
                            top: 14,
                            child: IgnorePointer(
                              child: _SingleSpatialHeader(
                                entry: _entries[_pageIndex],
                                index: _pageIndex,
                                count: _entries.length,
                              ),
                            ),
                          ),
                          if (_entries.length > 1)
                            Positioned(
                              left: 16,
                              right: 16,
                              bottom: 14,
                              child: IgnorePointer(
                                child: _SingleSpatialPageIndicator(
                                  count: _entries.length,
                                  index: _pageIndex,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
    );
  }
}

class _SingleSpatialMapEntry {
  const _SingleSpatialMapEntry({
    required this.group,
    required this.parent,
    required this.grid,
  });

  final ParkingSpatialHierarchyGroup group;
  final LocationModel parent;
  final ParkingGridModel grid;

  String get id => parent.id;

  String get name {
    final value = parent.locationName.trim();
    return value.isEmpty ? group.parentName : value;
  }

  List<LocationModel> get children => group.children;
}

class _SingleSpatialMapPage extends StatelessWidget {
  const _SingleSpatialMapPage({
    required this.entry,
    required this.focusedChildKey,
    required this.reduceMotion,
    required this.onChildTap,
  });

  final _SingleSpatialMapEntry entry;
  final String? focusedChildKey;
  final bool reduceMotion;
  final void Function(
    ParkingSpatialChildRegion<LocationModel> region,
    Rect sourceRect,
  ) onChildTap;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final surface = Container(
      margin: const EdgeInsets.fromLTRB(14, 54, 14, 42),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tokens.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: tokens.shadow,
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: _SingleParentDotMap(
            entry: entry,
            focusedChildKey: focusedChildKey,
            reduceMotion: reduceMotion,
            onChildTap: onChildTap,
          ),
        ),
      ),
    );

    return Semantics(
      label: '${entry.name} 공간 DOT MAP',
      child: reduceMotion
          ? surface
          : TweenAnimationBuilder<double>(
              key: ValueKey<String>('single_dotmap_page_${entry.id}'),
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 340),
              curve: Curves.easeOutCubic,
              child: surface,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.scale(
                    scale: .97 + (.03 * value),
                    child: child,
                  ),
                );
              },
            ),
    );
  }
}

class _SingleParentDotMap extends StatefulWidget {
  const _SingleParentDotMap({
    required this.entry,
    required this.focusedChildKey,
    required this.reduceMotion,
    required this.onChildTap,
  });

  final _SingleSpatialMapEntry entry;
  final String? focusedChildKey;
  final bool reduceMotion;
  final void Function(
    ParkingSpatialChildRegion<LocationModel> region,
    Rect sourceRect,
  ) onChildTap;

  @override
  State<_SingleParentDotMap> createState() => _SingleParentDotMapState();
}

class _SingleParentDotMapState extends State<_SingleParentDotMap> {
  final GlobalKey _mapKey = GlobalKey();
  String _lastGeometrySignature = '';

  void _recordGeometry(
    List<ParkingSpatialChildRegion<LocationModel>> regions,
  ) {
    final signature = regions
        .map(
          (entry) => '${entry.source.id}:${entry.childRect.toKey()}:${entry.effectiveParkingAreaIds.length}:${entry.cutParkingAreaCount}',
        )
        .join('|');
    if (_lastGeometrySignature == signature) return;
    _lastGeometrySignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _lastGeometrySignature != signature) return;
      final slots = regions.fold<int>(
        0,
        (sum, entry) => sum + parkingSpatialCapacityForChild(entry.source),
      );
      SingleInsideDiagnostics.log(
        'dotmap',
        'child_regions_resolved parent=${widget.entry.name} children=${regions.length} slots=$slots effective=${regions.where((entry) => entry.useEffectiveShape).length} towers=${regions.where((entry) => !entry.useEffectiveShape).length} hitTest=effective_path_contains entryMotionMs=${widget.reduceMotion ? 0 : 220} highlightMotionMs=${widget.reduceMotion ? 0 : 170}',
      );
    });
  }

  void _handleTap(ParkingSpatialChildRegion<LocationModel> region) {
    final renderObject = _mapKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    final origin = renderObject.localToGlobal(Offset.zero);
    final sourceRect = region.nominalRect.shift(origin);
    final childName = region.source.locationName.trim();
    SingleInsideDiagnostics.log(
      'dotmap',
      'child_region_tapped parent=${widget.entry.name} child=$childName sourceRect=${parkingSpatialRectDebug(sourceRect)} viewport=${region.childRect.toKey()} effectiveShape=${region.useEffectiveShape ? 'child_slot_area_ids_difference_path' : 'nominal_rect_tower'} ownedParkingAreas=${region.ownedParkingAreaCount} cutParkingAreas=${region.cutParkingAreaCount}',
    );
    widget.onChildTap(region, sourceRect);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final layout = ParkingStatusDotMapLayout.resolve(
          size: size,
          grid: widget.entry.grid,
          padding: 10,
        );
        final regions = layout == null
            ? const <ParkingSpatialChildRegion<LocationModel>>[]
            : resolveParkingSpatialChildRegions<LocationModel>(
                zones: widget.entry.children,
                sourceOf: (child) => child,
                grid: widget.entry.grid,
                layout: layout,
              );
        _recordGeometry(regions);
        return SizedBox(
          key: _mapKey,
          width: size.width,
          height: size.height,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: ParkingStatusDotMapSurface(
                  grid: widget.entry.grid,
                  framed: false,
                  padding: 10,
                ),
              ),
              for (final region in regions)
                ParkingSpatialChildRegionVisual<LocationModel>(
                  key: ValueKey<String>(
                    'single_child_visual_${widget.entry.id}_${region.source.id}',
                  ),
                  entry: region,
                  selected:
                      widget.focusedChildKey == '${widget.entry.id}:${region.source.id}',
                  peeked: false,
                  reduceMotion: widget.reduceMotion,
                ),
              for (final region in regions)
                ParkingSpatialChildRegionHitTarget<LocationModel>(
                  key: ValueKey<String>(
                    'single_child_hit_${widget.entry.id}_${region.source.id}',
                  ),
                  entry: region,
                  semanticsLabel:
                      '${widget.entry.name} ${region.source.locationName} 주차 구역',
                  onTap: () => _handleTap(region),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SingleChildFocusSurface extends StatelessWidget {
  const _SingleChildFocusSurface({
    required this.child,
    required this.grid,
    required this.childRect,
    required this.effectiveParkingAreaIds,
    required this.progress,
    required this.reduceMotion,
    required this.interactionEnabled,
    required this.onClose,
  });

  final LocationModel child;
  final ParkingGridModel grid;
  final GridRect childRect;
  final Set<String> effectiveParkingAreaIds;
  final double progress;
  final bool reduceMotion;
  final bool interactionEnabled;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final headerProgress = ((progress - .52) / .48).clamp(0.0, 1.0).toDouble();
    final outerPadding = 10.0 * progress;
    final headerHeight = 34.0 * headerProgress;
    final mapTop = headerHeight + 7.0 * progress;
    final surfaceOpacity = (.92 + .04 * progress).clamp(0.0, 1.0).toDouble();
    final childName = child.locationName.trim().isEmpty ? child.id : child.locationName.trim();
    final slotCount = parkingSpatialCapacityForChild(child);

    return Material(
      color: colors.surface.withOpacity(surfaceOpacity),
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                outerPadding,
                mapTop,
                outerPadding,
                outerPadding,
              ),
              child: child.isTowerChild
                  ? _SingleTowerSlotGrid(
                      child: child,
                      revealProgress: progress,
                      reduceMotion: reduceMotion,
                      interactionEnabled: interactionEnabled,
                    )
                  : _SingleChildDotMap(
                      child: child,
                      grid: grid,
                      viewport: childRect,
                      effectiveParkingAreaIds: effectiveParkingAreaIds,
                      revealProgress: progress,
                      reduceMotion: reduceMotion,
                    ),
            ),
          ),
          if (headerProgress > .01)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 34,
              child: IgnorePointer(
                ignoring: headerProgress < .9,
                child: Opacity(
                  opacity: headerProgress,
                  child: Transform.translate(
                    offset: Offset(0, -8 * (1 - headerProgress)),
                    child: ColoredBox(
                      color: colors.surface.withOpacity(.94),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          children: [
                            Semantics(
                              button: true,
                              label: '$childName 닫기',
                              child: IconButton(
                                onPressed: interactionEnabled ? onClose : null,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(
                                  width: 34,
                                  height: 34,
                                ),
                                splashRadius: 18,
                                icon: const Icon(
                                  Icons.arrow_back_rounded,
                                  size: 20,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                childName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.titleSmall?.copyWith(
                                  color: colors.onSurface,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '슬롯 $slotCount',
                              maxLines: 1,
                              style: text.labelSmall?.copyWith(
                                color: colors.onSurfaceVariant,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SingleChildDotMap extends StatelessWidget {
  const _SingleChildDotMap({
    required this.child,
    required this.grid,
    required this.viewport,
    required this.effectiveParkingAreaIds,
    required this.revealProgress,
    required this.reduceMotion,
  });

  final LocationModel child;
  final ParkingGridModel grid;
  final GridRect viewport;
  final Set<String> effectiveParkingAreaIds;
  final double revealProgress;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final layout = ParkingStatusDotMapLayout.resolve(
          size: size,
          grid: grid,
          viewport: viewport,
        );
        final regions = layout == null
            ? const <ParkingSpatialChildRegion<LocationModel>>[]
            : resolveParkingSpatialChildRegions<LocationModel>(
                zones: <LocationModel>[child],
                sourceOf: (location) => location,
                grid: grid,
                layout: layout,
              );
        final region = regions.isEmpty ? null : regions.first;
        final regionProgress = reduceMotion
            ? 1.0
            : ((revealProgress - .28) / .72).clamp(0.0, 1.0).toDouble();
        return SizedBox(
          width: size.width,
          height: size.height,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: ParkingStatusDotMapSurface(
                  grid: grid,
                  viewport: viewport,
                  visibleParkingAreaIds: effectiveParkingAreaIds,
                  framed: false,
                ),
              ),
              if (region != null)
                ParkingSpatialChildFocusRegionVisual(
                  nominalRect: region.nominalRect,
                  effectivePath: region.effectivePath,
                  useEffectiveShape: region.useEffectiveShape,
                  progress: regionProgress,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SingleTowerSlotGrid extends StatelessWidget {
  const _SingleTowerSlotGrid({
    required this.child,
    required this.revealProgress,
    required this.reduceMotion,
    required this.interactionEnabled,
  });

  final LocationModel child;
  final double revealProgress;
  final bool reduceMotion;
  final bool interactionEnabled;

  @override
  Widget build(BuildContext context) {
    final capacity = parkingSpatialCapacityForChild(child);
    return ParkingSpatialTowerSlotGrid(
      itemCount: capacity,
      revealProgress: revealProgress,
      reduceMotion: reduceMotion,
      interactionEnabled: interactionEnabled,
      itemBuilder: (context, index) => _SingleTowerSlotCard(slotNo: index + 1),
    );
  }
}

class _SingleTowerSlotCard extends StatelessWidget {
  const _SingleTowerSlotCard({required this.slotNo});

  final int slotNo;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: '슬롯 $slotNo',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface.withOpacity(.42),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: colors.outlineVariant.withOpacity(.46),
            width: 1,
          ),
        ),
        child: Center(
          child: Text(
            '$slotNo',
            maxLines: 1,
            style: text.titleSmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _SingleSpatialHeader extends StatelessWidget {
  const _SingleSpatialHeader({
    required this.entry,
    required this.index,
    required this.count,
  });

  final _SingleSpatialMapEntry entry;
  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Row(
      children: [
        Expanded(
          child: AnimatedSwitcher(
            duration:
                reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              if (reduceMotion) return child;
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, .12),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: Text(
              entry.name,
              key: ValueKey<String>(entry.id),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleMedium?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        AnimatedSwitcher(
          duration:
              reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
          child: Text(
            '${index + 1} / $count',
            key: ValueKey<int>(index),
            style: textTheme.labelLarge?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _SingleSpatialPageIndicator extends StatelessWidget {
  const _SingleSpatialPageIndicator({
    required this.count,
    required this.index,
  });

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List<Widget>.generate(count, (itemIndex) {
          final selected = itemIndex == index;
          return AnimatedContainer(
            duration:
                reduceMotion ? Duration.zero : const Duration(milliseconds: 190),
            curve: Curves.easeOutCubic,
            width: selected ? 18 : 6,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: selected ? tokens.accent : tokens.borderStrong,
              borderRadius: BorderRadius.circular(999),
            ),
          );
        }),
      ),
    );
  }
}

class _SingleSpatialStateSurface extends StatelessWidget {
  const _SingleSpatialStateSurface({
    super.key,
    required this.icon,
    required this.label,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(
                strokeWidth: 2.6,
                color: tokens.accent,
              ),
            )
          else
            Icon(icon, size: 34, color: tokens.iconSecondary),
          const SizedBox(height: 12),
          Text(
            label,
            style: textTheme.bodyMedium?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
