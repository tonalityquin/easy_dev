import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../../../app/utils/status_dialog.dart';
import '../../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../../design_system/common_ui/common_ui_theme.dart';
import '../../application/modify_camera_fullscreen_viewer.dart';
import '../../application/modify_camera_helper.dart';
import '../widgets/modify_photo_section.dart';
import '../widgets/modify_workspace_switcher.dart';

enum _CameraWorkspaceMode {
  camera,
  gallery,
  savedPhotos,
  preview,
}

class ModifyCameraWorkspace extends StatefulWidget {
  const ModifyCameraWorkspace({
    super.key,
    required this.plateNumber,
    required this.initialCapturedImages,
    required this.onExit,
    this.onCaptureComplete,
    this.onImageCaptured,
    this.onImageDeleted,
    this.onDebug,
    this.initialPreviewImages = const <dynamic>[],
    this.initialPreviewIndex = 0,
    this.startInPreview = false,
  });

  final String plateNumber;
  final List<XFile> initialCapturedImages;
  final VoidCallback onExit;
  final void Function(List<XFile>)? onCaptureComplete;
  final void Function(XFile)? onImageCaptured;
  final void Function(XFile)? onImageDeleted;
  final ValueChanged<String>? onDebug;
  final List<dynamic> initialPreviewImages;
  final int initialPreviewIndex;
  final bool startInPreview;

  @override
  State<ModifyCameraWorkspace> createState() => _ModifyCameraWorkspaceState();
}

class _ModifyCameraWorkspaceState extends State<ModifyCameraWorkspace> {
  late final ModifyCameraHelper _cameraHelper;
  late final List<XFile> _capturedImages;
  late _CameraWorkspaceMode _mode;
  List<dynamic> _previewImages = const <dynamic>[];
  int _previewIndex = 0;
  _CameraWorkspaceMode _previewBackMode = _CameraWorkspaceMode.camera;
  bool _isCameraReady = false;
  bool _initFailed = false;
  bool _flashVisible = false;
  bool _shutterPressed = false;
  Future<void>? _initFuture;

  @override
  void initState() {
    super.initState();
    _capturedImages = List<XFile>.from(widget.initialCapturedImages);
    _cameraHelper = ModifyCameraHelper(
      jpegQuality: 75,
      maxLongSide: 2560,
      keepOriginalAlso: false,
      resolution: ResolutionPreset.medium,
    );
    if (widget.startInPreview && widget.initialPreviewImages.isNotEmpty) {
      _mode = _CameraWorkspaceMode.preview;
      _previewImages = List<dynamic>.from(widget.initialPreviewImages);
      _previewIndex = widget.initialPreviewIndex
          .clamp(0, _previewImages.length - 1)
          .toInt();
      _previewBackMode = _CameraWorkspaceMode.camera;
    } else {
      _mode = _CameraWorkspaceMode.camera;
    }
    _initializeCamera();
  }

  void _debug(String message) {
    widget.onDebug?.call(message);
    debugPrint('[ModifyCameraWorkspace] $message');
  }

  Future<void> _initializeCamera() async {
    if (mounted) {
      setState(() {
        _initFailed = false;
        _isCameraReady = false;
      });
    }
    _debug('camera=initialize_start');
    _initFuture = _cameraHelper.initializeInputCamera();
    try {
      await _initFuture;
      await _cameraHelper.lockPortrait();
      if (!mounted) return;
      setState(() => _isCameraReady = true);
      if (_mode != _CameraWorkspaceMode.camera) {
        try {
          await _cameraHelper.pausePreview();
        } catch (_) {}
      }
      _debug('camera=initialize_success');
    } catch (error, stackTrace) {
      _debug('camera=initialize_failed error=$error');
      debugPrint('[ModifyCameraWorkspace] error=$error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _isCameraReady = false;
        _initFailed = true;
      });
    }
  }

  @override
  void dispose() {
    widget.onCaptureComplete?.call(List<XFile>.from(_capturedImages));
    final future = _initFuture;
    Future(() async {
      if (future != null) {
        try {
          await future;
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

  Future<void> _capture() async {
    final controller = _cameraHelper.cameraController;
    if (!_isCameraReady ||
        controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture ||
        _initFailed) {
      return;
    }

    _debug('camera=capture_start');
    final image = await _cameraHelper.captureImage();
    if (!mounted) return;
    if (image == null) {
      _debug('camera=capture_failed');
      await StatusDialog.showFailure(
        context,
        title: StatusDialog.photoSaveFailed,
        useCommonUi: true,
      );
      return;
    }

    setState(() {
      _capturedImages.add(image);
      _flashVisible = true;
    });
    widget.onImageCaptured?.call(image);
    _debug('camera=capture_success path=${image.path} count=${_capturedImages.length}');
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (mounted) setState(() => _flashVisible = false);
  }

  Future<void> _pausePreview() async {
    final controller = _cameraHelper.cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await _cameraHelper.pausePreview();
    } catch (_) {}
  }

  Future<void> _resumePreview() async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final controller = _cameraHelper.cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await _cameraHelper.resumePreview();
    } catch (_) {}
  }

  Future<void> _setMode(_CameraWorkspaceMode mode) async {
    if (_mode == mode) return;
    final previous = _mode;
    if (previous == _CameraWorkspaceMode.camera && mode != previous) {
      await _pausePreview();
    }
    if (!mounted) return;
    setState(() => _mode = mode);
    if (mode == _CameraWorkspaceMode.camera) {
      await _resumePreview();
    }
    _debug('camera_mode=changed from=${previous.name} to=${mode.name}');
  }

  Future<void> _openGallery() async {
    if (_capturedImages.isEmpty) return;
    await _setMode(_CameraWorkspaceMode.gallery);
  }

  Future<void> _openSavedPhotos() async {
    await _setMode(_CameraWorkspaceMode.savedPhotos);
  }

  Future<void> _openSessionPreview(int index) async {
    if (_capturedImages.isEmpty) return;
    final safeIndex = index.clamp(0, _capturedImages.length - 1).toInt();
    _previewImages = List<dynamic>.from(_capturedImages);
    _previewIndex = safeIndex;
    _previewBackMode = _CameraWorkspaceMode.gallery;
    _debug('camera_gallery=preview_open index=$safeIndex count=${_capturedImages.length}');
    await _setMode(_CameraWorkspaceMode.preview);
  }

  void _deletePreviewImage() {
    if (_previewImages.isEmpty) return;
    final current = _previewIndex.clamp(0, _previewImages.length - 1).toInt();
    final target = _previewImages[current];
    if (target is! XFile) return;
    final capturedIndex =
        _capturedImages.indexWhere((item) => item.path == target.path);
    if (capturedIndex < 0) return;
    final removed = _capturedImages.removeAt(capturedIndex);
    widget.onImageDeleted?.call(removed);
    _debug('camera_gallery=deleted path=${removed.path} count=${_capturedImages.length}');
    if (_capturedImages.isEmpty) {
      _previewImages = const <dynamic>[];
      _previewIndex = 0;
      _setMode(_CameraWorkspaceMode.camera);
      setState(() {});
      return;
    }
    _previewImages = List<dynamic>.from(_capturedImages);
    _previewIndex = _previewIndex.clamp(0, _previewImages.length - 1).toInt();
    setState(() {});
  }

  Widget _buildCameraPreview(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final controller = _cameraHelper.cameraController;
    if (_initFailed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber_rounded, color: tokens.danger, size: 44),
              const SizedBox(height: 10),
              Text(
                '카메라를 초기화할 수 없습니다.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 12),
              CommonButton(
                label: '다시 시도',
                icon: Icons.refresh_rounded,
                onPressed: _initializeCamera,
              ),
            ],
          ),
        ),
      );
    }
    if (!_isCameraReady || controller == null || !controller.value.isInitialized) {
      return Center(child: CircularProgressIndicator(color: tokens.accent));
    }

    final previewSize = controller.value.previewSize!;
    final portrait = MediaQuery.of(context).orientation == Orientation.portrait;
    final width = portrait ? previewSize.height : previewSize.width;
    final height = portrait ? previewSize.width : previewSize.height;
    final ratio = width / height;

    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: ratio,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) async {
                    final point = Offset(
                      (details.localPosition.dx / constraints.maxWidth)
                          .clamp(0.0, 1.0)
                          .toDouble(),
                      (details.localPosition.dy / constraints.maxHeight)
                          .clamp(0.0, 1.0)
                          .toDouble(),
                    );
                    try {
                      await controller.setFocusPoint(point);
                      await controller.setExposurePoint(point);
                    } catch (_) {}
                  },
                  child: CameraPreview(controller),
                );
              },
            ),
          ),
        ),
        IgnorePointer(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 80),
            opacity: _flashVisible ? .78 : 0,
            child: const ColoredBox(color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _buildCameraMode(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final controller = _cameraHelper.cameraController;
    final canCapture = _isCameraReady &&
        controller != null &&
        controller.value.isInitialized &&
        !controller.value.isTakingPicture &&
        !_initFailed;
    final latest = _capturedImages.isEmpty ? null : _capturedImages.last;

    return Container(
      key: const ValueKey<String>('camera'),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
            child: Row(
              children: [
                CommonIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: '차량 정보로',
                  size: 36,
                  iconSize: 18,
                  onPressed: widget.onExit,
                ),
                const SizedBox(width: 6),
                Icon(Icons.photo_camera_rounded, color: tokens.accent, size: 21),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    '촬영',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                AnimatedSwitcher(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 150),
                  child: Text(
                    '신규 ${_capturedImages.length}',
                    key: ValueKey<int>(_capturedImages.length),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: tokens.textSecondary,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: tokens.borderSubtle),
          Expanded(
            child: ColoredBox(
              color: tokens.scrim,
              child: _buildCameraPreview(context),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            color: tokens.surfaceRaised,
            child: Row(
              children: [
                Expanded(
                  child: CommonButton(
                    label: '저장 사진',
                    icon: Icons.collections_rounded,
                    variant: CommonButtonVariant.secondary,
                    onPressed: _openSavedPhotos,
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTapDown: canCapture
                      ? (_) => setState(() => _shutterPressed = true)
                      : null,
                  onTapCancel: canCapture
                      ? () => setState(() => _shutterPressed = false)
                      : null,
                  onTapUp: canCapture
                      ? (_) {
                          setState(() => _shutterPressed = false);
                          _capture();
                        }
                      : null,
                  child: AnimatedScale(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 100),
                    curve: Curves.easeOutCubic,
                    scale: _shutterPressed ? .9 : 1,
                    child: Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: canCapture ? tokens.accent : tokens.surfaceDisabled,
                        border: Border.all(
                          color: canCapture
                              ? tokens.onAccent.withOpacity(.8)
                              : tokens.borderSubtle,
                          width: 4,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: tokens.shadow,
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.camera_alt_rounded,
                        color: canCapture ? tokens.onAccent : tokens.iconDisabled,
                        size: 26,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: latest == null
                      ? CommonButton(
                          label: '최근 0',
                          icon: Icons.photo_library_outlined,
                          variant: CommonButtonVariant.secondary,
                          onPressed: null,
                        )
                      : GestureDetector(
                          onTap: _openGallery,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              AnimatedSwitcher(
                                duration: reduceMotion
                                    ? Duration.zero
                                    : const Duration(milliseconds: 170),
                                transitionBuilder: (child, animation) {
                                  return FadeTransition(
                                    opacity: animation,
                                    child: ScaleTransition(
                                      scale: Tween<double>(begin: .82, end: 1)
                                          .animate(
                                        CurvedAnimation(
                                          parent: animation,
                                          curve: Curves.easeOutBack,
                                        ),
                                      ),
                                      child: child,
                                    ),
                                  );
                                },
                                child: ClipRRect(
                                  key: ValueKey<String>(latest.path),
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.file(
                                    File(latest.path),
                                    width: 42,
                                    height: 42,
                                    fit: BoxFit.cover,
                                    cacheWidth: 130,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 7),
                              Text(
                                '${_capturedImages.length}',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(
                                      color: tokens.textPrimary,
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGalleryMode(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Container(
      key: const ValueKey<String>('gallery'),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
            child: Row(
              children: [
                CommonIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: '촬영으로',
                  size: 36,
                  iconSize: 18,
                  onPressed: () => _setMode(_CameraWorkspaceMode.camera),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '이번 촬영',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                Text(
                  '${_capturedImages.length}장',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: tokens.borderSubtle),
          Expanded(
            child: GridView.builder(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.all(10),
              itemCount: _capturedImages.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1,
              ),
              itemBuilder: (context, index) {
                final image = _capturedImages[index];
                return Material(
                  color: tokens.surfaceOverlay,
                  borderRadius: BorderRadius.circular(CommonUiShapes.control),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _openSessionPreview(index),
                    child: Image.file(
                      File(image.path),
                      fit: BoxFit.cover,
                      cacheWidth: 420,
                      filterQuality: FilterQuality.low,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSavedPhotosMode(BuildContext context) {
    return ModifySavedPhotosContent(
      key: const ValueKey<String>('saved_photos'),
      plateNumber: widget.plateNumber,
      onBack: () => _setMode(_CameraWorkspaceMode.camera),
      onDebug: widget.onDebug,
    );
  }

  Widget _buildPreviewMode(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final current = _previewImages.isEmpty
        ? null
        : _previewImages[_previewIndex.clamp(0, _previewImages.length - 1)];
    final canDelete = current is XFile &&
        _capturedImages.any((item) => item.path == current.path);
    return Container(
      key: const ValueKey<String>('preview'),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: .93, end: 1),
              duration: const Duration(milliseconds: 230),
              curve: Curves.easeInOutCubic,
              builder: (context, value, child) {
                final reduceMotion =
                    MediaQuery.maybeOf(context)?.disableAnimations ?? false;
                return Opacity(
                  opacity: reduceMotion ? 1 : value,
                  child: Transform.scale(
                    scale: reduceMotion ? 1 : value,
                    child: child,
                  ),
                );
              },
              child: ModifyEmbeddedImageViewerContent(
                images: _previewImages,
                initialIndex: _previewIndex,
                onBack: widget.startInPreview
                    ? widget.onExit
                    : () => _setMode(_previewBackMode),
                onPageChanged: (index) => setState(() => _previewIndex = index),
                onDebug: widget.onDebug,
              ),
            ),
          ),
          if (canDelete)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: BoxDecoration(
                color: tokens.surfaceRaised,
                border: Border(top: BorderSide(color: tokens.borderSubtle)),
              ),
              child: CommonButton(
                label: '이 사진 삭제',
                icon: Icons.delete_outline_rounded,
                variant: CommonButtonVariant.destructive,
                expand: true,
                onPressed: _deletePreviewImage,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final child = switch (_mode) {
      _CameraWorkspaceMode.camera => _buildCameraMode(context),
      _CameraWorkspaceMode.gallery => _buildGalleryMode(context),
      _CameraWorkspaceMode.savedPhotos => _buildSavedPhotosMode(context),
      _CameraWorkspaceMode.preview => _buildPreviewMode(context),
    };
    return ModifyWorkspaceSwitcher(
      activeKey: _mode.name,
      activeOrder: _mode.index,
      child: child,
    );
  }
}
