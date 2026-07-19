import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';

void modifyShowFullScreenImageViewer(
  BuildContext context,
  List<dynamic> images,
  int initialIndex, {
  bool isUrlList = false,
}) {
  if (images.isEmpty) return;
  final safeIndex = initialIndex.clamp(0, images.length - 1).toInt();
  showPromptOverlayDialog<void>(
    context: context,
    builder: (dialogContext) => _ModifyPromptImageViewer(
      images: images,
      initialIndex: safeIndex,
    ),
  );
}

class _ModifyPromptImageViewer extends StatefulWidget {
  const _ModifyPromptImageViewer({
    required this.images,
    required this.initialIndex,
  });

  final List<dynamic> images;
  final int initialIndex;

  @override
  State<_ModifyPromptImageViewer> createState() =>
      _ModifyPromptImageViewerState();
}

class _ModifyPromptImageViewerState
    extends State<_ModifyPromptImageViewer> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool _isNetwork(dynamic image) {
    if (image is! String) return false;
    final uri = Uri.tryParse(image);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  String _pathOf(dynamic image) {
    if (image is XFile) return image.path;
    return image.toString();
  }

  String _tagOf(dynamic image) => _pathOf(image);

  String _metadataOf(dynamic image) {
    if (_isNetwork(image)) {
      final segments = Uri.tryParse(image.toString())?.pathSegments;
      return _parseMetadataFromFileName(
        segments == null || segments.isEmpty ? '' : segments.last,
      );
    }
    final path = _pathOf(image);
    return _parseMetadataFromFileName(File(path).uri.pathSegments.last);
  }

  Widget _buildImage(BuildContext context, dynamic image) {
    final tokens = PromptUiTheme.of(context);
    if (_isNetwork(image)) {
      return Image.network(
        image.toString(),
        fit: BoxFit.contain,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Center(
            child: CircularProgressIndicator(color: tokens.accent),
          );
        },
        errorBuilder: (_, __, ___) => Center(
          child: Icon(
            Icons.broken_image_rounded,
            color: tokens.danger,
            size: 44,
          ),
        ),
      );
    }

    final path = _pathOf(image);
    return FutureBuilder<bool>(
      future: File(path).exists(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(
            child: CircularProgressIndicator(color: tokens.accent),
          );
        }
        if (snapshot.hasError || !(snapshot.data ?? false)) {
          return Center(
            child: Icon(
              Icons.broken_image_rounded,
              color: tokens.danger,
              size: 44,
            ),
          );
        }
        return Image.file(File(path), fit: BoxFit.contain);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    return SizedBox.expand(
      child: Material(
        color: tokens.canvas,
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: widget.images.length,
              onPageChanged: (index) => setState(() => _currentIndex = index),
              itemBuilder: (context, index) {
                final image = widget.images[index];
                final metadata = _metadataOf(image);
                return Stack(
                  children: [
                    Center(
                      child: Hero(
                        tag: _tagOf(image),
                        child: InteractiveViewer(
                          minScale: .8,
                          maxScale: 4,
                          child: _buildImage(context, image),
                        ),
                      ),
                    ),
                    if (metadata.isNotEmpty)
                      Positioned(
                        left: 18,
                        right: 18,
                        bottom: 24,
                        child: PromptAnimatedReveal(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              color: tokens.surfaceRaised,
                              borderRadius: BorderRadius.circular(
                                PromptUiShapes.control,
                              ),
                              border: Border.all(color: tokens.borderSubtle),
                              boxShadow: [
                                BoxShadow(
                                  color: tokens.shadow,
                                  blurRadius: 14,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Text(
                              metadata,
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: tokens.textPrimary,
                                    height: 1.4,
                                  ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: tokens.surfaceRaised,
                  borderRadius: BorderRadius.circular(PromptUiShapes.pill),
                  border: Border.all(color: tokens.borderSubtle),
                ),
                child: Text(
                  '${_currentIndex + 1} / ${widget.images.length}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: PromptIconButton(
                icon: Icons.close_rounded,
                tooltip: '닫기',
                haptic: PromptHaptic.selection,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _parseMetadataFromFileName(String fileName) {
  try {
    final name = fileName.replaceAll('.jpg', '');
    final parts = name.split('_');
    if (parts.length < 4) return '';
    final date = parts[0];
    final timeValue = parts[1];
    final plate = parts[2];
    final user = parts.sublist(3).join('_');
    final timeText = timeValue.length == 6
        ? '${timeValue.substring(0, 2)}:${timeValue.substring(2, 4)}:${timeValue.substring(4, 6)}'
        : (() {
            final millis = int.tryParse(timeValue);
            if (millis == null) return '';
            final dateTime = DateTime.fromMillisecondsSinceEpoch(millis);
            return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
          })();
    if (timeText.isEmpty) return '';
    return '촬영일: $date $timeText\n차량번호: $plate\n촬영자: $user';
  } catch (_) {
    return '';
  }
}
