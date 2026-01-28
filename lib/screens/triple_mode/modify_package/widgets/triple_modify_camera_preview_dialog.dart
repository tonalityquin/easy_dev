import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // HapticFeedback
import '../utils/triple_modify_camera_helper.dart';

class TripleModifyCameraPreviewDialog extends StatefulWidget {
  final void Function(List<XFile>)? onCaptureComplete;
  final void Function(XFile)? onImageCaptured;

  const TripleModifyCameraPreviewDialog({
    super.key,
    this.onCaptureComplete,
    this.onImageCaptured,
  });

  @override
  State<TripleModifyCameraPreviewDialog> createState() => _TripleModifyCameraPreviewDialogState();
}

class _TripleModifyCameraPreviewDialogState extends State<TripleModifyCameraPreviewDialog> {
  late final TripleModifyCameraHelper _cameraHelper;
  final List<XFile> _capturedImages = [];

  bool _isCameraReady = false;
  bool _closing = false;
  bool _initFailed = false;

  Future<void>? _initFuture;

  @override
  void initState() {
    super.initState();

    _cameraHelper = TripleModifyCameraHelper(
      jpegQuality: 75,
      maxLongSide: 2560,
      keepOriginalAlso: false,
      resolution: ResolutionPreset.medium,
    );

    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    setState(() {
      _initFailed = false;
      _isCameraReady = false;
    });

    _initFuture = _cameraHelper.initializeInputCamera();
    try {
      await _initFuture;
      await _cameraHelper.lockPortrait();
      if (!mounted) return;
      setState(() => _isCameraReady = true);
      debugPrint('✅ CameraHelper: 카메라 초기화 완료');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isCameraReady = false;
        _initFailed = true;
      });
    }
  }

  @override
  void dispose() {
    widget.onCaptureComplete?.call(_capturedImages);

    final f = _initFuture;
    Future(() async {
      if (f != null) {
        try {
          await f;
        } catch (_) {}
      }
      try {
        await _cameraHelper.unlockOrientation();
      } catch (_) {}
      try {
        await _cameraHelper.dispose();
      } catch (_) {}
    });

    super.dispose();
  }

  Future<void> _onCapturePressed() async {
    final ctrl = _cameraHelper.cameraController;
    if (!_isCameraReady ||
        ctrl == null ||
        !ctrl.value.isInitialized ||
        ctrl.value.isTakingPicture ||
        _closing) {
      return;
    }

    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}

    final image = await _cameraHelper.captureImage();
    if (!mounted) return;

    if (image != null) {
      setState(() => _capturedImages.add(image));
      widget.onImageCaptured?.call(image);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('촬영에 실패했습니다. 다시 시도해 주세요.')),
      );
    }
  }

  Future<void> _openGalleryView() async {
    final ctrl = _cameraHelper.cameraController;
    final canPause = ctrl != null && ctrl.value.isInitialized;
    if (canPause) {
      try {
        await _cameraHelper.pausePreview();
      } catch (_) {}
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GalleryView(
          images: List<XFile>.from(_capturedImages),
          onDelete: (index) {
            setState(() => _capturedImages.removeAt(index));
          },
        ),
      ),
    );

    if (mounted && canPause) {
      try {
        await _cameraHelper.resumePreview();
      } catch (_) {}
    }
  }

  Widget _buildPreview() {
    final cs = Theme.of(context).colorScheme;
    final ctrl = _cameraHelper.cameraController;

    if (_initFailed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 48),
              const SizedBox(height: 12),
              const Text(
                '카메라를 초기화할 수 없습니다.\n권한을 확인한 뒤 다시 시도해 주세요.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _initializeCamera,
                style: FilledButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                ),
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isCameraReady || ctrl == null || !ctrl.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final sizeV = ctrl.value.previewSize;
    if (sizeV == null || sizeV.width == 0 || sizeV.height == 0) {
      final fallbackRatio = 1 / ctrl.value.aspectRatio;
      return Center(
        child: AspectRatio(
          aspectRatio: fallbackRatio,
          child: CameraPreview(ctrl),
        ),
      );
    }

    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    final previewW = isPortrait ? sizeV.height : sizeV.width;
    final previewH = isPortrait ? sizeV.width : sizeV.height;
    final previewRatio = previewW / previewH;

    return Stack(
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: previewRatio,
            child: LayoutBuilder(
              builder: (_, constraints) {
                final renderSize = constraints.biggest;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) async {
                    final local = d.localPosition;
                    final point = Offset(
                      (local.dx / renderSize.width).clamp(0.0, 1.0),
                      (local.dy / renderSize.height).clamp(0.0, 1.0),
                    );
                    try {
                      await ctrl.setFocusPoint(point);
                      await ctrl.setExposurePoint(point);
                    } catch (_) {}
                  },
                  child: CameraPreview(ctrl),
                );
              },
            ),
          ),
        ),

        if (_capturedImages.isNotEmpty)
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            height: 80,
            child: GestureDetector(
              onTap: _openGalleryView,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _capturedImages.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Image.file(
                      File(_capturedImages[index].path),
                      width: 70,
                      height: 70,
                      fit: BoxFit.cover,
                      cacheWidth: 160,
                      filterQuality: FilterQuality.low,
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _cameraHelper.cameraController;

    return WillPopScope(
      onWillPop: () async {
        if (_closing) return true;
        _closing = true;
        if (mounted) setState(() => _isCameraReady = false);
        try {
          await WidgetsBinding.instance.endOfFrame;
        } catch (_) {}
        return true;
      },
      child: SafeArea(
        child: Scaffold(
          backgroundColor: Colors.black,
          body: _buildPreview(),
          bottomNavigationBar: Padding(
            padding: const EdgeInsets.only(bottom: 20, top: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: (!_isCameraReady ||
                      ctrl == null ||
                      !(ctrl.value.isInitialized) ||
                      ctrl.value.isTakingPicture ||
                      _initFailed ||
                      _closing)
                      ? null
                      : _onCapturePressed,
                  style: ElevatedButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(20),
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    elevation: 4,
                  ),
                  child: const Icon(Icons.camera_alt, size: 30),
                ),
                const SizedBox(width: 16),
                if (_capturedImages.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: _openGalleryView,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                    ),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('갤러리'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class GalleryView extends StatelessWidget {
  final List<XFile> images;
  final void Function(int index) onDelete;

  const GalleryView({
    super.key,
    required this.images,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('촬영된 사진'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.black,
      body: GridView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: images.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemBuilder: (context, index) {
          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FullScreenGalleryView(
                    images: images,
                    initialIndex: index,
                    onDelete: (deleteIndex) {
                      Navigator.pop(context);
                      onDelete(deleteIndex);
                    },
                  ),
                ),
              );
            },
            child: Image.file(
              File(images[index].path),
              fit: BoxFit.cover,
              cacheWidth: 360,
              filterQuality: FilterQuality.low,
            ),
          );
        },
      ),
    );
  }
}

class FullScreenGalleryView extends StatefulWidget {
  final List<XFile> images;
  final int initialIndex;
  final void Function(int index)? onDelete;

  const FullScreenGalleryView({
    super.key,
    required this.images,
    required this.initialIndex,
    this.onDelete,
  });

  @override
  State<FullScreenGalleryView> createState() => _FullScreenGalleryViewState();
}

class _FullScreenGalleryViewState extends State<FullScreenGalleryView> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
  }

  void _handleDelete() {
    widget.onDelete?.call(_currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (widget.onDelete != null)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _handleDelete,
            ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.images.length,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemBuilder: (context, index) {
          return Center(
            child: InteractiveViewer(
              minScale: 1.0,
              maxScale: 4.0,
              child: Image.file(
                File(widget.images[index].path),
                fit: BoxFit.contain,
              ),
            ),
          );
        },
      ),
    );
  }
}
