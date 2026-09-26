import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../../../design_system/common_ui/common_ui_side_dock_frame.dart';
import '../../../../../design_system/common_ui/common_ui_theme.dart';

class ModifyPhotoSection extends StatelessWidget {
  const ModifyPhotoSection({
    super.key,
    required this.capturedImages,
    required this.imageUrls,
    this.onPreviewRequested,
  });

  final List<XFile> capturedImages;
  final List<String> imageUrls;
  final void Function(List<dynamic> images, int index)? onPreviewRequested;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final items = <dynamic>[...imageUrls, ...capturedImages];

    return CommonSideDockSection(
      order: 2,
      title: '촬영 사진',
      subtitle: '등록 ${imageUrls.length} · 신규 ${capturedImages.length}',
      child: SizedBox(
        height: 92,
        child: items.isEmpty
            ? Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tokens.surfaceOverlay,
            borderRadius: BorderRadius.circular(CommonUiShapes.control),
            border: Border.all(color: tokens.borderSubtle),
          ),
          child: Text(
            '촬영된 사진 없음',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: tokens.textSecondary,
            ),
          ),
        )
            : ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final item = items[index];
            final isUrl = item is String;
            final path = isUrl ? item : (item as XFile).path;
            final child = ClipRRect(
              borderRadius: BorderRadius.circular(CommonUiShapes.control),
              child: Container(
                width: 92,
                decoration: BoxDecoration(
                  color: tokens.surfaceOverlay,
                  border: Border.all(color: tokens.borderSubtle),
                ),
                child: isUrl
                    ? Image.network(
                  path,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Center(
                    child: Icon(
                      Icons.broken_image_rounded,
                      color: tokens.danger,
                    ),
                  ),
                )
                    : FutureBuilder<bool>(
                  future: File(path).exists(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState !=
                        ConnectionState.done) {
                      return Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: tokens.accent,
                        ),
                      );
                    }
                    if (snapshot.data != true) {
                      return Center(
                        child: Icon(
                          Icons.broken_image_rounded,
                          color: tokens.danger,
                        ),
                      );
                    }
                    return Image.file(
                      File(path),
                      fit: BoxFit.cover,
                      cacheWidth: 220,
                      filterQuality: FilterQuality.low,
                    );
                  },
                ),
              ),
            );
            if (onPreviewRequested == null) return child;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onPreviewRequested!(items, index),
              child: child,
            );
          },
        ),
      ),
    );
  }
}
