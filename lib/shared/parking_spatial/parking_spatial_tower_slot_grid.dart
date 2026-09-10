import 'package:flutter/material.dart';

typedef ParkingSpatialTowerSlotBuilder = Widget Function(
  BuildContext context,
  int index,
);

class ParkingSpatialTowerSlotGrid extends StatelessWidget {
  const ParkingSpatialTowerSlotGrid({
    super.key,
    required this.itemCount,
    required this.revealProgress,
    required this.reduceMotion,
    required this.interactionEnabled,
    required this.itemBuilder,
  });

  final int itemCount;
  final double revealProgress;
  final bool reduceMotion;
  final bool interactionEnabled;
  final ParkingSpatialTowerSlotBuilder itemBuilder;

  int _columnsForWidth(double width) {
    if (width >= 620) return 8;
    if (width >= 420) return 6;
    return 4;
  }

  @override
  Widget build(BuildContext context) {
    if (itemCount <= 0) return const SizedBox.expand();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnsForWidth(constraints.maxWidth);
        final spacing = constraints.maxWidth < 360 ? 6.0 : 8.0;
        return GridView.builder(
          padding: const EdgeInsets.all(4),
          physics: interactionEnabled
              ? const ClampingScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: 1.05,
          ),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            final phase = index % 4;
            final progress = reduceMotion
                ? 1.0
                : ((revealProgress - (.42 + phase * .025)) / .34)
                    .clamp(0.0, 1.0)
                    .toDouble();
            final eased = Curves.easeOutCubic.transform(progress);
            return Opacity(
              opacity: eased,
              child: Transform.scale(
                scale: .97 + .03 * eased,
                child: itemBuilder(context, index),
              ),
            );
          },
        );
      },
    );
  }
}
