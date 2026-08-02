import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../applications/tablet_grid_render_mode_state.dart';
import '../../../applications/tablet_parking_completed_view_toggle_state.dart';
import '../../../domain/models/three_d_lite/tablet_status_preview_card_area.dart'
    as grid3d;
import '../../../domain/models/two_d/tablet_grid_2d_preview.dart' as grid2d;
import '../../../domain/models/two_d/tablet_status_preview_card_area.dart'
    as status2d;
import '../../widgets/tablet_common_components.dart';

class TabletGridModePage extends StatelessWidget {
  const TabletGridModePage({
    super.key,
    required this.area,
  });

  final String area;

  static List<status2d.ParkingStatusOverlaySpec> _overlaySpecs2d({
    required bool includeParkingCompletedView,
  }) {
    return <status2d.ParkingStatusOverlaySpec>[
      if (includeParkingCompletedView)
        const status2d.ParkingStatusOverlaySpec(
          collection: 'parking_completed_view',
          status: grid2d.ParkingSlotStatus.parked,
        ),
      const status2d.ParkingStatusOverlaySpec(
        collection: 'departure_requests_view',
        status: grid2d.ParkingSlotStatus.departureRequest,
      ),
    ];
  }

  static List<grid3d.ParkingStatusOverlaySpec> _overlaySpecs3d({
    required bool includeParkingCompletedView,
  }) {
    return <grid3d.ParkingStatusOverlaySpec>[
      if (includeParkingCompletedView)
        const grid3d.ParkingStatusOverlaySpec(
          collection: 'parking_completed_view',
          status: grid2d.ParkingSlotStatus.parked,
        ),
      const grid3d.ParkingStatusOverlaySpec(
        collection: 'departure_requests_view',
        status: grid2d.ParkingSlotStatus.departureRequest,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final resolvedArea = area.trim();
    final includeParkingCompletedView =
        context.select<TabletParkingCompletedViewToggleState, bool>(
      (state) => state.includeParkingCompletedView,
    );
    final renderState = context.watch<TabletGridRenderModeState>();

    if (!renderState.isReady) {
      return ColoredBox(
        color: tokens.canvas,
        child: const Center(
          child: TabletCommonLoadingState(label: '주차장 보기 설정 불러오는 중'),
        ),
      );
    }

    final overlay2d = _overlaySpecs2d(
      includeParkingCompletedView: includeParkingCompletedView,
    );
    final overlay3d = _overlaySpecs3d(
      includeParkingCompletedView: includeParkingCompletedView,
    );

    return ColoredBox(
      color: tokens.canvas,
      child: AnimatedSwitcher(
        duration: tabletCommonDuration(
          context,
          CommonUiMotion.component,
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
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
              child: child,
            ),
          );
        },
        child: resolvedArea.isEmpty
            ? const TabletCommonEmptyState(
                key: ValueKey<String>('grid-empty'),
                title: '선택된 지역이 없습니다',
                message: '상단 메뉴에서 운영 지역을 선택하세요.',
                icon: Icons.map_outlined,
              )
            : ColoredBox(
                key: ValueKey<String>(
                  'grid-${renderState.mode.name}-$resolvedArea',
                ),
                color: tokens.surface,
                child: renderState.isThreeD
                    ? grid3d.ParkingStatusPreviewCardArea(
                        area: resolvedArea,
                        overlay: overlay3d,
                      )
                    : status2d.ParkingStatusPreviewCardArea(
                        area: resolvedArea,
                        overlay: overlay2d,
                        cleanPresentation: true,
                      ),
              ),
      ),
    );
  }
}
