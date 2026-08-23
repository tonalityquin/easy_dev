import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_overlays.dart';

enum PlateEditorDialogSize {
  compact,
  standard,
  wide,
  immersive,
}

Future<T?> showPlateEditorDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  required String barrierLabel,
  PlateEditorDialogSize size = PlateEditorDialogSize.standard,
  bool barrierDismissible = false,
}) {
  return showCommonOverlayDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    useRootNavigator: true,
    barrierLabel: barrierLabel,
    builder: (dialogContext) {
      final media = MediaQuery.of(dialogContext);
      final availableWidth = math.max(
        280.0,
        media.size.width - media.padding.horizontal - 24,
      ).toDouble();
      final availableHeight = math.max(
        360.0,
        media.size.height - media.padding.vertical - 24,
      ).toDouble();
      final spec = _resolveDialogSpec(size);
      final width = math.min(availableWidth * spec.widthFactor, spec.maxWidth).toDouble();
      final height = math.min(availableHeight * spec.heightFactor, spec.maxHeight).toDouble();
      return CommonDialogFrame(
        animate: false,
        child: SizedBox(
          width: width,
          height: height,
          child: builder(dialogContext),
        ),
      );
    },
  );
}

class _PlateEditorDialogSpec {
  const _PlateEditorDialogSpec({
    required this.widthFactor,
    required this.heightFactor,
    required this.maxWidth,
    required this.maxHeight,
  });

  final double widthFactor;
  final double heightFactor;
  final double maxWidth;
  final double maxHeight;
}

_PlateEditorDialogSpec _resolveDialogSpec(PlateEditorDialogSize size) {
  switch (size) {
    case PlateEditorDialogSize.compact:
      return const _PlateEditorDialogSpec(
        widthFactor: .82,
        heightFactor: .74,
        maxWidth: 560,
        maxHeight: 640,
      );
    case PlateEditorDialogSize.standard:
      return const _PlateEditorDialogSpec(
        widthFactor: .88,
        heightFactor: .84,
        maxWidth: 680,
        maxHeight: 760,
      );
    case PlateEditorDialogSize.wide:
      return const _PlateEditorDialogSpec(
        widthFactor: .92,
        heightFactor: .88,
        maxWidth: 920,
        maxHeight: 800,
      );
    case PlateEditorDialogSize.immersive:
      return const _PlateEditorDialogSpec(
        widthFactor: .95,
        heightFactor: .92,
        maxWidth: 1080,
        maxHeight: 860,
      );
  }
}
