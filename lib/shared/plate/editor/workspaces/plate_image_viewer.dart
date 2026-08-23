import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';

class PlateEmbeddedImageViewerContent extends StatefulWidget {
  const PlateEmbeddedImageViewerContent({
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
  State<PlateEmbeddedImageViewerContent> createState() =>
      _PlateEmbeddedImageViewerContentState();
}

class _PlateEmbeddedImageViewerContentState
    extends State<PlateEmbeddedImageViewerContent> {
  late PageController _pageController;
  late int _currentIndex;

  int _safeIndex(int value) {
    if (widget.images.isEmpty) return 0;
    return value.clamp(0, widget.images.length - 1).toInt();
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = _safeIndex(widget.initialIndex);
    _pageController = PageController(initialPage: _currentIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onDebug?.call(
        'photo_preview=open index=$_currentIndex count=${widget.images.length}',
      );
    });
  }

  @override
  void dispose() {
    widget.onDebug?.call(
      'photo_preview=close index=$_currentIndex count=${widget.images.length}',
    );
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
    final tokens = CommonUiTheme.of(context);
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
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    if (widget.images.isEmpty) {
      return Center(
        child: Text(
          '표시할 사진이 없습니다.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: tokens.textSecondary,
              ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _pageController,
          itemCount: widget.images.length,
          onPageChanged: (index) {
            setState(() => _currentIndex = index);
            widget.onPageChanged?.call(index);
            widget.onDebug?.call(
              'photo_preview=page_changed index=$index count=${widget.images.length}',
            );
          },
          itemBuilder: (context, index) {
            final image = widget.images[index];
            final metadata = _metadataOf(image);
            return Padding(
              padding: const EdgeInsets.fromLTRB(8, 46, 8, 8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: InteractiveViewer(
                      minScale: .8,
                      maxScale: 4,
                      child: _buildImage(context, image),
                    ),
                  ),
                  if (metadata.isNotEmpty)
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 10,
                      child: AnimatedOpacity(
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 190),
                        opacity: 1,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.surfaceRaised.withOpacity(.94),
                            borderRadius:
                                BorderRadius.circular(CommonUiShapes.control),
                            border: Border.all(color: tokens.borderSubtle),
                          ),
                          child: Text(
                            metadata,
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: tokens.textPrimary,
                                  height: 1.35,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        Positioned(
          top: 8,
          left: 8,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.onBack != null) ...[
                CommonIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: '이전',
                  size: 36,
                  iconSize: 18,
                  haptic: CommonHaptic.selection,
                  onPressed: widget.onBack,
                ),
                const SizedBox(width: 6),
              ],
              AnimatedContainer(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: tokens.surfaceRaised.withOpacity(.94),
                  borderRadius: BorderRadius.circular(CommonUiShapes.pill),
                  border: Border.all(color: tokens.borderSubtle),
                ),
                child: Text(
                  '${_currentIndex + 1} / ${widget.images.length}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ],
          ),
        ),
      ],
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
