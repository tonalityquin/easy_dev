import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import '../utils/input_camera_helper.dart';

class InputCameraPreviewDialog extends StatefulWidget {
  final void Function(List<XFile>)? onCaptureComplete;
  final void Function(XFile)? onImageCaptured;

  const InputCameraPreviewDialog({
    super.key,
    this.onCaptureComplete,
    this.onImageCaptured,
  });

  @override
  State<InputCameraPreviewDialog> createState() => _InputCameraPreviewDialogState();
}

class _InputCameraPreviewDialogState extends State<InputCameraPreviewDialog> {
  late final InputCameraHelper _cameraHelper;
  final List<XFile> _capturedImages = [];
  bool _isCameraReady = false;

  Future<void>? _initFuture;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _cameraHelper = InputCameraHelper();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    debugPrint('📸 CameraHelper: initializeCamera() 호출');
    _initFuture = _cameraHelper.initializeInputCamera();
    try {
      await _initFuture;
      if (!mounted) return;
      setState(() => _isCameraReady = true);
      debugPrint('✅ CameraHelper: 카메라 초기화 완료');
    } catch (e) {
      debugPrint('❌ Camera 초기화 실패: $e');
      if (mounted) setState(() => _isCameraReady = false);
    }
  }

  @override
  void dispose() {
    debugPrint('🧹 CameraHelper: dispose() 호출');
    widget.onCaptureComplete?.call(_capturedImages);

    final f = _initFuture;
    Future(() async {
      if (f != null) { try { await f; } catch (_) {} }
      try { await _cameraHelper.dispose(); } catch (_) {}
    });

    super.dispose();
  }

  Future<void> _onCapturePressed() async {
    final ctrl = _cameraHelper.cameraController;

    if (!_isCameraReady || ctrl == null || !ctrl.value.isInitialized || ctrl.value.isTakingPicture) {
      debugPrint('⚠️ 촬영 불가 상태(초기화 전/촬영 중/컨트롤러 없음)');
      return;
    }

    debugPrint('📸 촬영 버튼 클릭됨');
    final image = await _cameraHelper.captureImage();
    if (!mounted) return;

    if (image != null) {
      debugPrint('✅ CameraHelper: 사진 촬영 성공 - ${image.path}');
      setState(() {
        _capturedImages.add(image);
      });
      widget.onImageCaptured?.call(image);
    } else {
      debugPrint('⚠️ 이미지 촬영 실패 또는 null');
    }
  }

  void _openGalleryView() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GalleryView(
          images: List<XFile>.from(_capturedImages),
          onDelete: (index) {
            setState(() {
              _capturedImages.removeAt(index);
            });
          },
        ),
      ),
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
        try { await WidgetsBinding.instance.endOfFrame; } catch (_) {}
        return true;
      },
      child: SafeArea(
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              if (_isCameraReady && ctrl != null && ctrl.value.isInitialized)
                Positioned.fill(
                  child: RotatedBox(
                    quarterTurns: 1,
                    child: CameraPreview(ctrl),
                  ),
                )
              else
                const Center(child: CircularProgressIndicator()),

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
                          ),
                        );
                      },
                    ),
                  ),
                ),

              Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: Center(
                  child: ElevatedButton(
                    onPressed: (!_isCameraReady ||
                        ctrl == null ||
                        !ctrl.value.isInitialized ||
                        ctrl.value.isTakingPicture)
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GalleryView extends StatelessWidget {
  final List<XFile> images;
  final void Function(int index) onDelete;

  const GalleryView({super.key, required this.images, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('촬영된 사진'),
        backgroundColor: Colors.black,
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
                      Navigator.pop(context); // 닫기
                      onDelete(deleteIndex); // 삭제 콜백
                    },
                  ),
                ),
              );
            },
            child: Image.file(
              File(images[index].path),
              fit: BoxFit.cover,
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
        onPageChanged: (index) {
          setState(() => _currentIndex = index);
        },
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
