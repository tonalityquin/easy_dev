import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../applications/tablet_parking_completed_view_toggle_state.dart';
import '../../../domain/models/two_d/tablet_grid_2d_preview.dart';
import '../../../domain/models/two_d/tablet_status_preview_card_area.dart' as grid3d;

class TabletGridModePage extends StatelessWidget {
  const TabletGridModePage({
    super.key,
    required this.area,
  });

  final String area;

  static List<grid3d.ParkingStatusOverlaySpec> _overlaySpecs({
    required bool includeParkingCompletedView,
  }) =>
      <grid3d.ParkingStatusOverlaySpec>[
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final resolvedArea = area.trim();
    final includeParkingCompletedView =
        context.select<TabletParkingCompletedViewToggleState, bool>(
      (s) => s.includeParkingCompletedView,
    );
    final overlaySpecs = _overlaySpecs(
      includeParkingCompletedView: includeParkingCompletedView,
    );

    return Padding(
      padding: const EdgeInsets.all(24),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outline.withOpacity(.12)),
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withOpacity(.04),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: ColoredBox(
            color: cs.surfaceContainerLowest,
            child: resolvedArea.isEmpty
                ? const SizedBox.expand()
                : grid3d.ParkingStatusPreviewCardArea(
                    area: resolvedArea,
                    overlay: overlaySpecs,
                  ),
          ),
        ),
      ),
    );
  }
}
