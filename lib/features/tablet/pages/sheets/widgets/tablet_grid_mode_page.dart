import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../applications/tablet_parking_completed_view_toggle_state.dart';
import '../../../domain/models/two_d/tablet_grid_2d_preview.dart';
import '../../../domain/models/two_d/tablet_status_preview_card_area.dart' as grid3d;
import '../../widgets/tablet_common_components.dart';

class TabletGridModePage extends StatelessWidget {
  const TabletGridModePage({
    super.key,
    required this.area,
  });

  final String area;

  static List<grid3d.ParkingStatusOverlaySpec> _overlaySpecs({
    required bool includeParkingCompletedView,
  }) {
    return <grid3d.ParkingStatusOverlaySpec>[
      if (includeParkingCompletedView)
        const grid3d.ParkingStatusOverlaySpec(
          collection: 'parking_completed_view',
          status: ParkingSlotStatus.parked,
        ),
      const grid3d.ParkingStatusOverlaySpec(
        collection: 'departure_requests_view',
        status: ParkingSlotStatus.departureRequest,
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
    final overlaySpecs = _overlaySpecs(
      includeParkingCompletedView: includeParkingCompletedView,
    );
    return ColoredBox(
      color: tokens.canvas,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: TabletCommonPanel(
          padding: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: AnimatedSwitcher(
            duration: tabletCommonDuration(context, CommonUiMotion.component),
            switchInCurve: CommonUiMotion.enter,
            switchOutCurve: CommonUiMotion.exit,
            child: resolvedArea.isEmpty
                ? const TabletCommonEmptyState(
                    key: ValueKey<String>('grid-empty'),
                    title: '선택된 지역이 없습니다',
                    message: '상단 메뉴에서 운영 지역을 선택하세요.',
                    icon: Icons.map_outlined,
                  )
                : ColoredBox(
                    key: ValueKey<String>('grid-$resolvedArea'),
                    color: tokens.surface,
                    child: grid3d.ParkingStatusPreviewCardArea(
                      area: resolvedArea,
                      overlay: overlaySpecs,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
