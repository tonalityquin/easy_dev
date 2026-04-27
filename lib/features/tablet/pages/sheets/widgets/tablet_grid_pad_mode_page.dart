import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../applications/tablet_parking_completed_view_toggle_state.dart';
import '../../../domain/models/two_d/tablet_grid_2d_preview.dart';
import '../../../domain/models/two_d/tablet_status_preview_card_area.dart' as grid2d;
import '../../panels/tablet_right_panel.dart';

class TabletGridPadModePage extends StatelessWidget {
  const TabletGridPadModePage({
    super.key,
    required this.area,
  });

  final String area;

  static List<grid2d.ParkingStatusOverlaySpec> _overlaySpecs({
    required bool includeParkingCompletedView,
  }) => <grid2d.ParkingStatusOverlaySpec>[
    if (includeParkingCompletedView)
      const grid2d.ParkingStatusOverlaySpec(
        collection: 'parking_completed_view',
        status: ParkingSlotStatus.parked,
      ),
    const grid2d.ParkingStatusOverlaySpec(
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

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ColoredBox(
            color: cs.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _GridPaneCard(
                child: ColoredBox(
                  color: cs.surfaceContainerLowest,
                  child: resolvedArea.isEmpty
                      ? const SizedBox.expand()
                      : grid2d.ParkingStatusPreviewCardArea(
                          key: ValueKey('grid-pad-2d-$resolvedArea'),
                          area: resolvedArea,
                          overlay: overlaySpecs,
                        ),
                ),
              ),
            ),
          ),
        ),
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: cs.outlineVariant,
        ),
        Expanded(
          child: ColoredBox(
            color: cs.surface,
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
              ),
              child: RightPaneSearchPanel(
                key: ValueKey('grid-pad-right-$resolvedArea'),
                area: resolvedArea,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GridPaneCard extends StatelessWidget {
  const _GridPaneCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DecoratedBox(
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
        child: child,
      ),
    );
  }
}
