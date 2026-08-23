import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../features/location/domain/models/grid_rect.dart';
import '../../../../features/location/domain/models/location_model.dart';
import '../../../../features/location/domain/models/parking_grid_model.dart';
import '../../../parking_dot_map/parking_status_dot_map_surface.dart';

class PlateParkingParentSelector extends StatefulWidget {
  const PlateParkingParentSelector({
    super.key,
    required this.parents,
    required this.childrenForParent,
    required this.onSelected,
    this.recentParentName,
    this.area = '',
    this.onDebug,
  });

  final List<LocationModel> parents;
  final List<LocationModel> Function(LocationModel parent) childrenForParent;
  final ValueChanged<LocationModel> onSelected;
  final String? recentParentName;
  final String area;
  final ValueChanged<String>? onDebug;

  @override
  State<PlateParkingParentSelector> createState() =>
      _PlateParkingParentSelectorState();
}

class _PlateParkingParentSelectorState
    extends State<PlateParkingParentSelector> {
  String _lastSignature = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportReady());
  }

  @override
  void didUpdateWidget(covariant PlateParkingParentSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportReady());
  }

  void _reportReady() {
    if (!mounted) return;
    final signature = '${widget.area}|${widget.parents.map((e) => e.locationName).join('|')}';
    if (signature == _lastSignature) return;
    _lastSignature = signature;
    widget.onDebug?.call(
      'parking_parent_selector=ready area=${widget.area} count=${widget.parents.length} preview=parking_grid_with_child_rects',
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Material(
      color: tokens.surface,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 8),
            decoration: BoxDecoration(
              color: tokens.surfaceRaised,
              border: Border(bottom: BorderSide(color: tokens.borderSubtle)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.grid_view_rounded,
                  size: 18,
                  color: tokens.accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '부모 주차 구역',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                Text(
                  '${widget.parents.length}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final mediaWidth = MediaQuery.sizeOf(context).width;
                final availableWidth = constraints.hasBoundedWidth
                    ? constraints.maxWidth
                    : mediaWidth;
                final width = math.max(1.0, availableWidth).toDouble();
                final desiredCellWidth = width < 520 ? 148.0 : 164.0;
                var columns = (width / desiredCellWidth).floor();
                columns = columns.clamp(2, 4).toInt();
                final effectiveColumns = math.min(
                  columns,
                  math.max(1, widget.parents.length),
                ).toInt();
                const spacing = 8.0;
                const horizontalPadding = 12.0;
                final availableGridWidth = math.max(
                  1.0,
                  width - horizontalPadding * 2,
                ).toDouble();
                final desiredGridWidth = desiredCellWidth * effectiveColumns +
                    spacing * (effectiveColumns - 1);
                final gridWidth =
                    math.min(availableGridWidth, desiredGridWidth).toDouble();
                final tileWidth = math.max(
                  1.0,
                  (gridWidth - spacing * (effectiveColumns - 1)) /
                      effectiveColumns,
                ).toDouble();
                final previewHeight =
                    (tileWidth * .62).clamp(62.0, 110.0).toDouble();
                final tileHeight = previewHeight + 42;
                final ratio = tileWidth / tileHeight;
                final minHeight = (constraints.maxHeight - 28)
                    .clamp(0.0, double.infinity)
                    .toDouble();
                return SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    horizontalPadding,
                    14,
                    horizontalPadding,
                    14,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: minHeight),
                    child: Center(
                      child: SizedBox(
                        width: gridWidth,
                        child: GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: EdgeInsets.zero,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: effectiveColumns,
                            crossAxisSpacing: spacing,
                            mainAxisSpacing: spacing,
                            childAspectRatio: ratio,
                          ),
                          itemCount: widget.parents.length,
                          itemBuilder: (context, index) {
                            final parent = widget.parents[index];
                            final children = widget.childrenForParent(parent);
                            final rects = children
                                .map((child) => child.childRect)
                                .whereType<GridRect>()
                                .map((rect) => rect.normalized())
                                .toList(growable: false);
                            final selected = _sameName(
                              parent.locationName,
                              widget.recentParentName ?? '',
                            );
                            return _PlateParkingParentTile(
                              parent: parent,
                              childRects: rects,
                              previewHeight: previewHeight,
                              selected: selected,
                              onTap: () => widget.onSelected(parent),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static bool _sameName(String a, String b) {
    String normalize(String value) =>
        value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    return normalize(a) == normalize(b);
  }
}

class _PlateParkingParentTile extends StatefulWidget {
  const _PlateParkingParentTile({
    required this.parent,
    required this.childRects,
    required this.previewHeight,
    required this.selected,
    required this.onTap,
  });

  final LocationModel parent;
  final List<GridRect> childRects;
  final double previewHeight;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_PlateParkingParentTile> createState() =>
      _PlateParkingParentTileState();
}

class _PlateParkingParentTileState extends State<_PlateParkingParentTile> {
  bool _pressed = false;
  bool _activating = false;

  void _setPressed(bool value) {
    if (!mounted || _activating || _pressed == value) return;
    setState(() => _pressed = value);
  }

  Future<void> _activate() async {
    if (_activating) return;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    setState(() {
      _pressed = false;
      _activating = true;
    });
    if (!reduceMotion) {
      await Future<void>.delayed(const Duration(milliseconds: 90));
      if (!mounted) return;
    }
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final selected = widget.selected || _activating;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 110);
    final scale = _activating ? .94 : (_pressed ? .97 : 1.0);
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.parent.locationName,
      child: AnimatedScale(
        scale: scale,
        duration: duration,
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _pressed ? .84 : 1,
          duration: duration,
          curve: Curves.easeOutCubic,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTapDown: (_) => _setPressed(true),
              onTapCancel: () => _setPressed(false),
              onTapUp: (_) => _setPressed(false),
              onTap: () => unawaited(_activate()),
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 7),
                decoration: BoxDecoration(
                  color: selected
                      ? tokens.surfaceSelected
                      : tokens.surfaceRaised,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? tokens.accent : tokens.borderSubtle,
                    width: selected ? 1.25 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    SizedBox(
                      height: widget.previewHeight,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          IgnorePointer(
                            child: ExcludeSemantics(
                              child: _PlateParkingParentPreview(
                                grid: widget.parent.parkingGrid,
                                childRects: widget.childRects,
                                selected: selected,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 0,
                            right: 0,
                            child: AnimatedSwitcher(
                              duration: reduceMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 150),
                              transitionBuilder: (child, animation) =>
                                  ScaleTransition(
                                scale: animation,
                                child: FadeTransition(
                                  opacity: animation,
                                  child: child,
                                ),
                              ),
                              child: selected
                                  ? Icon(
                                      Icons.check_circle_rounded,
                                      key: const ValueKey<String>('selected'),
                                      size: 19,
                                      color: tokens.accent,
                                    )
                                  : const SizedBox(
                                      key: ValueKey<String>('idle'),
                                      width: 19,
                                      height: 19,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Center(
                        child: Text(
                          widget.parent.locationName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: selected
                                    ? tokens.accent
                                    : tokens.textPrimary,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlateParkingParentPreview extends StatelessWidget {
  const _PlateParkingParentPreview({
    required this.grid,
    required this.childRects,
    required this.selected,
  });

  final ParkingGridModel? grid;
  final List<GridRect> childRects;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final resolvedGrid = grid;
    if (resolvedGrid == null ||
        resolvedGrid.rows <= 0 ||
        resolvedGrid.cols <= 0) {
      return Center(
        child: Icon(
          Icons.local_parking_outlined,
          size: 24,
          color: selected
              ? tokens.accent
              : tokens.textSecondary.withOpacity(.68),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        ParkingStatusDotMapSurface(
          grid: resolvedGrid,
          framed: false,
          padding: 2,
        ),
        if (childRects.isNotEmpty)
          CustomPaint(
            painter: _PlateParkingParentRectOverlayPainter(
              grid: resolvedGrid,
              rects: childRects,
              color: selected ? tokens.accent : tokens.textSecondary,
              selected: selected,
            ),
            child: const SizedBox.expand(),
          ),
      ],
    );
  }
}

class _PlateParkingParentRectOverlayPainter extends CustomPainter {
  const _PlateParkingParentRectOverlayPainter({
    required this.grid,
    required this.rects,
    required this.color,
    required this.selected,
  });

  final ParkingGridModel grid;
  final List<GridRect> rects;
  final Color color;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final layout = ParkingStatusDotMapLayout.resolve(
      size: size,
      grid: grid,
      padding: 2,
    );
    if (layout == null) return;
    canvas.save();
    canvas.clipRect(layout.mapRect);
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withOpacity(selected ? .055 : .025);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 1.15 : .8
      ..color = color.withOpacity(selected ? .58 : .30);
    for (final raw in rects) {
      final screen = layout.rectFor(raw.normalized());
      final radius = math
          .min(2.5, math.min(screen.width, screen.height) * .14)
          .toDouble();
      final rrect = RRect.fromRectAndRadius(
        screen,
        Radius.circular(radius),
      );
      canvas.drawRRect(rrect, fill);
      canvas.drawRRect(rrect, stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(
    covariant _PlateParkingParentRectOverlayPainter oldDelegate,
  ) {
    return oldDelegate.grid != grid ||
        oldDelegate.rects != rects ||
        oldDelegate.color != color ||
        oldDelegate.selected != selected;
  }
}
