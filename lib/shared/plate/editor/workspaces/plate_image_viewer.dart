import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

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
  late final PageController _pageController;
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
    if (image == null || image is! String) return false;
    final uri = Uri.tryParse(image);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  String _pathOf(dynamic image) {
    if (image is XFile) return image.path;
    if (image is String) return image;
    return '';
  }

  Widget _buildImage(BuildContext context, dynamic image) {
    final tokens = CommonUiTheme.of(context);
    if (image == null) {
      return Center(
        child: Icon(
          Icons.image_outlined,
          color: tokens.iconSecondary,
          size: 44,
        ),
      );
    }

    if (_isNetwork(image)) {
      return Image.network(
        image.toString(),
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
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
    if (path.trim().isEmpty) {
      return Center(
        child: Icon(
          Icons.image_outlined,
          color: tokens.iconSecondary,
          size: 44,
        ),
      );
    }
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
        return Image.file(
          File(path),
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
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
            return Padding(
              padding: const EdgeInsets.fromLTRB(8, 46, 8, 8),
              child: Center(
                child: InteractiveViewer(
                  minScale: .8,
                  maxScale: 4,
                  child: _buildImage(context, widget.images[index]),
                ),
              ),
            );
          },
        ),
        Positioned(
          top: 8,
          left: 8,
          right: 8,
          child: Row(
            children: [
              if (widget.onBack != null)
                IconButton(
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: tokens.iconPrimary,
                  style: IconButton.styleFrom(
                    backgroundColor: tokens.surfaceRaised.withOpacity(.94),
                  ),
                ),
              const Spacer(),
              Container(
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
