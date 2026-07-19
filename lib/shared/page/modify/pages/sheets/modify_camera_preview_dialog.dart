import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../../../../../app/utils/status_dialog.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../application/modify_camera_helper.dart';


Route<T> _modifyPromptPageRoute<T>(BuildContext context, Widget child) {
  final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  return PageRouteBuilder<T>(
    pageBuilder: (_, __, ___) => child,
    transitionDuration: reduceMotion ? Duration.zero : PromptUiMotion.component,
    reverseTransitionDuration:
        reduceMotion ? Duration.zero : PromptUiMotion.selection,
    transitionsBuilder: (_, animation, __, routeChild) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: PromptUiMotion.enter,
        reverseCurve: PromptUiMotion.exit,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, .025),
            end: Offset.zero,
          ).animate(curved),
          child: routeChild,
        ),
      );
    },
  );
}

class ModifyCameraPreviewDialog extends StatefulWidget {
  final void Function(List<XFile>)? onCaptureComplete;
  final void Function(XFile)? onImageCaptured;

  const ModifyCameraPreviewDialog({
    super.key,
    this.onCaptureComplete,
    this.onImageCaptured,
  });

  @override
  State<ModifyCameraPreviewDialog> createState() =>
      _ModifyCameraPreviewDialogState();
}

class _ModifyCameraPreviewDialogState extends State<ModifyCameraPreviewDialog> {
  late final ModifyCameraHelper _cameraHelper;
  final List<XFile> _capturedImages = [];

  bool _isCameraReady = false;
  bool _closing = false;
  bool _initFailed = false;

  Future<void>? _initFuture;

  @override
  void initState() {
    super.initState();

    _cameraHelper = ModifyCameraHelper(
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
    } catch (_) {
      if (mounted) {
        setState(() {
          _isCameraReady = false;
          _initFailed = true;
        });
      }
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

    final image = await _cameraHelper.captureImage();
    if (!mounted) return;

    if (image != null) {
      setState(() => _capturedImages.add(image));
      widget.onImageCaptured?.call(image);
      return;
    }

    await StatusDialog.showFailure(
      context,
      title: StatusDialog.photoSaveFailed,
      usePromptUi: true,
    );
  }

  Future<void> _openModifyGalleryView() async {
    final ctrl = _cameraHelper.cameraController;
    final canPause = ctrl != null && ctrl.value.isInitialized;

    if (canPause) {
      try {
        await _cameraHelper.pausePreview();
      } catch (_) {}
    }

    await Navigator.of(context).push(
      _modifyPromptPageRoute<void>(
        context,
        ModifyGalleryView(
          images: List<XFile>.from(_capturedImages),
          onDelete: (index) => setState(() => _capturedImages.removeAt(index)),
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
    final tokens = PromptUiTheme.of(context);
    final cameraForeground =
        tokens.isDark ? tokens.textPrimary : tokens.surfaceRaised;
    final cs = Theme.of(context).colorScheme;
    final ctrl = _cameraHelper.cameraController;

    if (_initFailed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber_rounded, color: cs.error, size: 48),
              const SizedBox(height: 12),
              Text(
                '카메라를 초기화할 수 없습니다.\n권한을 확인한 뒤 다시 시도해 주세요.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cameraForeground),
              ),
              const SizedBox(height: 12),
              PromptButton(
                label: '다시 시도',
                icon: Icons.refresh_rounded,
                onPressed: _initializeCamera,
              ),
            ],
          ),
        ),
      );
    }

    if (!_isCameraReady || ctrl == null || !ctrl.value.isInitialized) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
        ),
      );
    }

    final previewSize = ctrl.value.previewSize!;
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;

    final previewW = isPortrait ? previewSize.height : previewSize.width;
    final previewH = isPortrait ? previewSize.width : previewSize.height;
    final previewRatio = previewW / previewH;

    return Stack(
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: previewRatio,
            child: LayoutBuilder(
              builder: (_, constraints) {
                final size = constraints.biggest;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) async {
                    final local = d.localPosition;
                    final point = Offset(
                      (local.dx / size.width).clamp(0.0, 1.0).toDouble(),
                      (local.dy / size.height).clamp(0.0, 1.0).toDouble(),
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
              onTap: _openModifyGalleryView,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _capturedImages.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: cs.outlineVariant.withOpacity(0.55)),
                        ),
                        child: Image.file(
                          File(_capturedImages[index].path),
                          width: 70,
                          height: 70,
                          fit: BoxFit.cover,
                          cacheWidth: 160,
                          filterQuality: FilterQuality.low,
                        ),
                      ),
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
    return PromptUiScope(
      child: Builder(builder: _buildPromptCameraPreview),
    );
  }

  Widget _buildPromptCameraPreview(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
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
          backgroundColor: tokens.scrim,
          body: _buildPreview(),
          bottomNavigationBar: PromptAnimatedReveal(
            delay: const Duration(milliseconds: 80),
            offset: const Offset(0, .04),
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  PromptIconButton(
                    icon: Icons.camera_alt_rounded,
                    tooltip: '사진 촬영',
                    size: 68,
                    iconSize: 30,
                    selected: true,
                    haptic: PromptHaptic.medium,
                    onPressed: (!_isCameraReady ||
                            ctrl == null ||
                            !(ctrl.value.isInitialized) ||
                            ctrl.value.isTakingPicture ||
                            _initFailed ||
                            _closing)
                        ? null
                        : _onCapturePressed,
                  ),
                  if (_capturedImages.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    PromptButton(
                      label: '갤러리 ${_capturedImages.length}',
                      icon: Icons.photo_library_rounded,
                      variant: PromptButtonVariant.secondary,
                      onPressed: _openModifyGalleryView,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ModifyGalleryView extends StatelessWidget {
  final List<XFile> images;
  final void Function(int index) onDelete;

  const ModifyGalleryView({
    super.key,
    required this.images,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return PromptUiScope(
      child: Builder(builder: _buildPromptGallery),
    );
  }

  Widget _buildPromptGallery(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final cameraForeground =
        tokens.isDark ? tokens.textPrimary : tokens.surfaceRaised;

    return Scaffold(
      appBar: AppBar(
        title: const Text('촬영된 사진'),
        backgroundColor: tokens.scrim,
        foregroundColor: cameraForeground,
        elevation: 0,
        surfaceTintColor: tokens.transparent,
      ),
      backgroundColor: tokens.scrim,
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
                _modifyPromptPageRoute<void>(
                  context,
                  FullScreenModifyGalleryView(
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
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                File(images[index].path),
                fit: BoxFit.cover,
                cacheWidth: 360,
                filterQuality: FilterQuality.low,
              ),
            ),
          );
        },
      ),
    );
  }
}

class FullScreenModifyGalleryView extends StatefulWidget {
  final List<XFile> images;
  final int initialIndex;
  final void Function(int index)? onDelete;

  const FullScreenModifyGalleryView({
    super.key,
    required this.images,
    required this.initialIndex,
    this.onDelete,
  });

  @override
  State<FullScreenModifyGalleryView> createState() => _FullScreenModifyGalleryViewState();
}

class _FullScreenModifyGalleryViewState extends State<FullScreenModifyGalleryView> {
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
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PromptUiScope(
      child: Builder(builder: _buildPromptFullScreenGallery),
    );
  }

  Widget _buildPromptFullScreenGallery(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final cameraForeground =
        tokens.isDark ? tokens.textPrimary : tokens.surfaceRaised;

    return Scaffold(
      backgroundColor: tokens.scrim,
      appBar: AppBar(
        backgroundColor: tokens.scrim,
        foregroundColor: cameraForeground,
        elevation: 0,
        surfaceTintColor: tokens.transparent,
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
