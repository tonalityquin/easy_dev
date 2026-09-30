import 'package:flutter/material.dart';

import '../../../plate/editor/workspaces/plate_image_viewer.dart';

class ModifyEmbeddedImageViewerContent extends StatelessWidget {
  const ModifyEmbeddedImageViewerContent({
    super.key,
    required this.images,
    required this.initialIndex,
    this.onBack,
    this.onPageChanged,
    this.onDebug,
  });

  final List<dynamic> images;
  final int initialIndex;
  final VoidCallback? onBack;
  final ValueChanged<int>? onPageChanged;
  final ValueChanged<String>? onDebug;

  @override
  Widget build(BuildContext context) {
    return PlateEmbeddedImageViewerContent(
      images: images,
      initialIndex: initialIndex,
      onBack: onBack,
      onPageChanged: onPageChanged,
      onDebug: onDebug,
    );
  }
}
