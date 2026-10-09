import 'package:flutter/material.dart';

import '../../../../design_system/common_ui/common_ui_side_rail.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../domain/plate_editor_workspace.dart';

class PlateEditorRail extends StatelessWidget {
  const PlateEditorRail({
    super.key,
    required this.enabled,
    required this.policy,
    required this.selectedWorkspace,
    required this.onSelected,
    this.title = '차량 관리',
    this.onSensorLiveOcr,
    this.onLiveOcr,
    this.disabledWorkspaces = const <PlateEditorWorkspace>{},
  });

  final bool enabled;
  final PlateEditorPolicy policy;
  final PlateEditorWorkspace? selectedWorkspace;
  final ValueChanged<PlateEditorWorkspace> onSelected;
  final String title;
  final ValueChanged<Rect>? onSensorLiveOcr;
  final ValueChanged<Rect>? onLiveOcr;
  final Set<PlateEditorWorkspace> disabledWorkspaces;

  String _label(PlateEditorWorkspace workspace) {
    switch (workspace) {
      case PlateEditorWorkspace.parking:
        return '주차';
      case PlateEditorWorkspace.camera:
        return '촬영';
      case PlateEditorWorkspace.sector:
        return '방문';
      case PlateEditorWorkspace.variableBilling:
        return '정산';
      case PlateEditorWorkspace.regularBilling:
        return '정기';
      case PlateEditorWorkspace.memo:
        return '메모';
      case PlateEditorWorkspace.overview:
        return '정보';
      case PlateEditorWorkspace.vehicleIdentity:
        return '차량';
    }
  }

  String _semantic(PlateEditorWorkspace workspace) {
    switch (workspace) {
      case PlateEditorWorkspace.parking:
        return '주차 구역';
      case PlateEditorWorkspace.camera:
        return '사진 촬영';
      case PlateEditorWorkspace.sector:
        return '방문 구역';
      case PlateEditorWorkspace.variableBilling:
        return '정산 유형';
      case PlateEditorWorkspace.regularBilling:
        return '정기 정산';
      case PlateEditorWorkspace.memo:
        return '상태 메모';
      case PlateEditorWorkspace.overview:
        return '차량 정보 요약';
      case PlateEditorWorkspace.vehicleIdentity:
        return '차량 식별정보';
    }
  }

  IconData _icon(PlateEditorWorkspace workspace) {
    switch (workspace) {
      case PlateEditorWorkspace.parking:
        return Icons.local_parking_rounded;
      case PlateEditorWorkspace.camera:
        return Icons.photo_camera_rounded;
      case PlateEditorWorkspace.sector:
        return Icons.place_rounded;
      case PlateEditorWorkspace.variableBilling:
        return Icons.receipt_long_rounded;
      case PlateEditorWorkspace.regularBilling:
        return Icons.calendar_month_rounded;
      case PlateEditorWorkspace.memo:
        return Icons.notes_rounded;
      case PlateEditorWorkspace.overview:
        return Icons.dashboard_outlined;
      case PlateEditorWorkspace.vehicleIdentity:
        return Icons.badge_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final textScale = media?.textScaler.scale(1.0) ?? 1.0;
    final reduceMotion = media?.disableAnimations ?? false;
    final tokens = CommonUiTheme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : media?.size.height ?? 720.0;
        final metrics = CommonSideRailMetrics.resolve(
          dockHeight: height,
          textScale: textScale,
        );
        final gap = metrics.ultra ? 4.0 : 6.0;

        Widget action(PlateEditorWorkspace workspace) {
          final selected = selectedWorkspace == workspace;
          final workspaceEnabled = enabled && !disabledWorkspaces.contains(workspace);
          return AnimatedOpacity(
            duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            opacity: workspaceEnabled ? 1 : .42,
            child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              CommonSideRailActionButton(
                semanticLabel: _semantic(workspace),
                visualLabel: _label(workspace),
                icon: _icon(workspace),
                selected: selected,
                enabled: workspaceEnabled,
                compact: metrics.compact,
                extent: metrics.minimumButtonExtent,
                tooltip: _semantic(workspace),
                onTap: () => onSelected(workspace),
              ),
              IgnorePointer(
                child: AnimatedContainer(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 170),
                  curve: Curves.easeOutCubic,
                  width: 3,
                  height: selected ? 20 : 0,
                  decoration: BoxDecoration(
                    color: tokens.accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ],
            ),
          );
        }

        final entries = <Widget>[];
        for (var i = 0; i < policy.railWorkspaces.length; i++) {
          if (i > 0) entries.add(SizedBox(height: gap));
          entries.add(action(policy.railWorkspaces[i]));
        }

        final navigation = ListView(
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.symmetric(
            horizontal: metrics.actionInsetHorizontal,
            vertical: metrics.actionInsetVertical,
          ),
          children: entries,
        );

        final sensorLiveOcr = onSensorLiveOcr;
        final liveOcr = onLiveOcr;
        final hasOcrActions = sensorLiveOcr != null || liveOcr != null;
        return CommonSideRailSurface(
          title: title,
          metrics: metrics,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: navigation),
              AnimatedSwitcher(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 170),
                reverseDuration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 130),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final slide = Tween<Offset>(
                    begin: const Offset(0, .08),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  );
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(position: slide, child: child),
                  );
                },
                child: !hasOcrActions
                    ? const SizedBox.shrink(key: ValueKey<String>('no_live_ocr'))
                    : Column(
                        key: ValueKey<String>(
                          'live_ocr_${sensorLiveOcr != null}_${liveOcr != null}',
                        ),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: metrics.actionInsetHorizontal + 2,
                              vertical: metrics.actionInsetVertical + 2,
                            ),
                            child: Divider(
                              height: 1,
                              color: tokens.borderSubtle,
                            ),
                          ),
                          if (sensorLiveOcr != null)
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                metrics.actionInsetHorizontal,
                                metrics.actionInsetVertical,
                                metrics.actionInsetHorizontal,
                                liveOcr == null ? metrics.actionInsetVertical : 2,
                              ),
                              child: _PlateEditorLiveOcrAction(
                                enabled: enabled,
                                compact: metrics.compact,
                                extent: metrics.minimumButtonExtent,
                                visualLabel: 'Sensor OCR',
                                semanticLabel: 'Sensor Live OCR',
                                tooltip: 'Sensor Live OCR',
                                icon: Icons.directions_car_filled_rounded,
                                onTap: sensorLiveOcr,
                              ),
                            ),
                          if (liveOcr != null)
                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: metrics.actionInsetHorizontal,
                                vertical: metrics.actionInsetVertical,
                              ),
                              child: _PlateEditorLiveOcrAction(
                                enabled: enabled,
                                compact: metrics.compact,
                                extent: metrics.minimumButtonExtent,
                                onTap: liveOcr,
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PlateEditorLiveOcrAction extends StatefulWidget {
  const _PlateEditorLiveOcrAction({
    required this.enabled,
    required this.compact,
    required this.extent,
    required this.onTap,
    this.visualLabel = 'OCR',
    this.semanticLabel = 'Live OCR',
    this.tooltip = 'Live OCR',
    this.icon = Icons.document_scanner_rounded,
  });

  final bool enabled;
  final bool compact;
  final double extent;
  final ValueChanged<Rect> onTap;
  final String visualLabel;
  final String semanticLabel;
  final String tooltip;
  final IconData icon;

  @override
  State<_PlateEditorLiveOcrAction> createState() =>
      _PlateEditorLiveOcrActionState();
}

class _PlateEditorLiveOcrActionState
    extends State<_PlateEditorLiveOcrAction> {
  void _handleTap() {
    final renderObject = context.findRenderObject();
    final mediaSize = MediaQuery.sizeOf(context);
    final rect = renderObject is RenderBox && renderObject.hasSize
        ? (() {
            final origin = renderObject.localToGlobal(Offset.zero);
            final extent = renderObject.size.shortestSide
                .clamp(1.0, 48.0)
                .toDouble();
            return Rect.fromCenter(
              center: origin + renderObject.size.center(Offset.zero),
              width: extent,
              height: extent,
            );
          })()
        : Rect.fromCenter(
            center: mediaSize.center(Offset.zero),
            width: 44,
            height: 44,
          );
    widget.onTap(rect);
  }

  @override
  Widget build(BuildContext context) {
    return CommonSideRailActionButton(
      semanticLabel: widget.semanticLabel,
      visualLabel: widget.visualLabel,
      icon: widget.icon,
      selected: false,
      enabled: widget.enabled,
      compact: widget.compact,
      extent: widget.extent,
      tooltip: widget.tooltip,
      onTap: _handleTap,
    );
  }
}
