import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../app/utils/status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import 'plate_image_viewer.dart';
import '../application/plate_camera_helper.dart';
import '../widgets/plate_editor_workspace_switcher.dart';

enum _CameraWorkspaceMode {
  camera,
  gallery,
  savedPhotos,
  preview,
}

class PlateCameraWorkspace extends StatefulWidget {
  const PlateCameraWorkspace({
    super.key,
    required this.plateNumber,
    required this.initialCapturedImages,
    required this.onExit,
    this.onCaptureComplete,
    this.onImageCaptured,
    this.onImageDeleted,
    this.onDebug,
    this.trace,
    this.initialPreviewImages = const <dynamic>[],
    this.initialPreviewIndex = 0,
    this.startInPreview = false,
    this.savedPhotosBuilder,
  });

  final String plateNumber;
  final List<XFile> initialCapturedImages;
  final VoidCallback onExit;
  final void Function(List<XFile>)? onCaptureComplete;
  final Future<void> Function(XFile)? onImageCaptured;
  final void Function(XFile)? onImageDeleted;
  final ValueChanged<String>? onDebug;
  final DeveloperOperationTrace? trace;
  final List<dynamic> initialPreviewImages;
  final int initialPreviewIndex;
  final bool startInPreview;
  final Widget Function(BuildContext context, VoidCallback onBack)? savedPhotosBuilder;

  @override
  State<PlateCameraWorkspace> createState() => _PlateCameraWorkspaceState();
}

class _PlateCameraWorkspaceState extends State<PlateCameraWorkspace> {
  late final PlateCameraHelper _cameraHelper;
  late final List<XFile> _capturedImages;
  late _CameraWorkspaceMode _mode;
  List<dynamic> _previewImages = const <dynamic>[];
  int _previewIndex = 0;
  _CameraWorkspaceMode _previewBackMode = _CameraWorkspaceMode.camera;
  bool _isCameraReady = false;
  bool _initFailed = false;
  bool _flashVisible = false;
  bool _shutterPressed = false;
  bool _captureBusy = false;
  String _capturePhase = 'ready';
  String? _pendingImagePath;
  Offset? _focusLocalPosition;
  bool _focusVisible = false;
  int _focusSequence = 0;
  Future<void>? _initFuture;

  @override
  void initState() {
    super.initState();
    _capturedImages = List<XFile>.from(widget.initialCapturedImages);
    _cameraHelper = PlateCameraHelper(
      jpegQuality: 82,
      maxLongSide: 2560,
      thumbnailJpegQuality: 65,
      thumbnailLongSide: 400,
      keepOriginalAlso: false,
      resolution: ResolutionPreset.high,
      onDebug: (message) => _debug('camera_helper=$message'),
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
    final normalized = message.trim();
    if (normalized.isEmpty) return;
    final logger = widget.onDebug;
    if (logger != null) {
      logger(normalized);
      return;
    }
    final trace = widget.trace;
    if (trace != null) {
      trace.log(normalized);
      return;
    }
    debugPrint('[PlateCameraWorkspace] $normalized');
  }

  Future<void> _initializeCamera() async {
    if (mounted) {
      setState(() {
        _initFailed = false;
        _isCameraReady = false;
      });
    }
    _debug('camera=initialize_start');
    _initFuture = _cameraHelper.initializeCamera();
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
      _debug('camera=initialize_stack_trace\n$stackTrace');
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
        _captureBusy ||
        _initFailed) {
      return;
    }

    setState(() {
      _captureBusy = true;
      _capturePhase = 'capturing';
      _pendingImagePath = null;
      _shutterPressed = false;
    });
    _debug('capture=started phase=$_capturePhase');

    try {
      final image = await _cameraHelper.captureImage();
      if (!mounted) return;
      if (image == null) {
        _debug('capture=failed phase=camera_processing');
        await StatusDialog.showFailure(
          context,
          title: StatusDialog.photoSaveFailed,
          useCommonUi: true,
        );
        return;
      }

      setState(() {
        _capturePhase = 'recent_preparing';
        _pendingImagePath = image.path;
        _flashVisible = true;
      });
      _debug(
        'capture=processing phase=$_capturePhase path=${image.path} capturedAtUtc=${PlateCameraHelper.capturedAtUtcFor(image)?.toIso8601String() ?? '-'} displayBytes=${_cameraHelper.lastDisplayBytes} thumbnailBytes=${_cameraHelper.lastThumbnailBytes}',
      );

      final recentFile = _gridFileFor(image);
      try {
        await precacheImage(ResizeImage(FileImage(recentFile), width: 130), context);
        _debug('recent_photo=precache_ready path=${recentFile.path}');
      } catch (error, stackTrace) {
        _debug('recent_photo=precache_failed path=${recentFile.path} error=$error');
        _debug('recent_photo=precache_stack_trace\n$stackTrace');
      }
      if (!mounted) return;

      setState(() {
        _capturePhase = 'recent_sync';
        _capturedImages.add(image);
      });
      _debug(
        'recent_photo=commit_start path=${image.path} count=${_capturedImages.length}',
      );

      final callback = widget.onImageCaptured;
      if (callback != null) {
        try {
          await callback(image);
          _debug(
            'recent_photo=parent_synced path=${image.path} count=${_capturedImages.length}',
          );
        } catch (error, stackTrace) {
          _debug('recent_photo=parent_sync_failed path=${image.path} error=$error');
          _debug('recent_photo=parent_sync_stack_trace\n$stackTrace');
        }
      }

      if (!mounted) return;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      _debug(
        'recent_photo=updated path=${image.path} count=${_capturedImages.length}',
      );
      _debug(
        'capture=success path=${image.path} capturedAtUtc=${PlateCameraHelper.capturedAtUtcFor(image)?.toIso8601String() ?? '-'} count=${_capturedImages.length} displayBytes=${_cameraHelper.lastDisplayBytes} thumbnailBytes=${_cameraHelper.lastThumbnailBytes} thumbnailPath=${_cameraHelper.lastThumbnailPath ?? '-'}',
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (mounted) setState(() => _flashVisible = false);
    } catch (error, stackTrace) {
      _debug('capture=failed phase=$_capturePhase error=$error');
      _debug('capture=stack_trace\n$stackTrace');
      if (mounted) {
        await StatusDialog.showFailure(
          context,
          title: StatusDialog.photoSaveFailed,
          useCommonUi: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _captureBusy = false;
          _capturePhase = 'ready';
          _pendingImagePath = null;
          _shutterPressed = false;
          _flashVisible = false;
        });
        _debug('capture=ready count=${_capturedImages.length}');
      }
    }
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
    if (_captureBusy || _capturedImages.isEmpty) return;
    await _setMode(_CameraWorkspaceMode.gallery);
  }

  Future<void> _openSavedPhotos() async {
    if (_captureBusy || widget.savedPhotosBuilder == null) return;
    await _setMode(_CameraWorkspaceMode.savedPhotos);
  }

  File _gridFileFor(XFile image) {
    final thumbnail = PlateCameraHelper.thumbnailFileFor(image);
    return thumbnail.existsSync() ? thumbnail : File(image.path);
  }

  Future<void> _showDeveloperStatus() async {
    final trace = widget.trace;
    if (trace == null || !trace.developerMode || !mounted) return;
    _debug(
      'camera=developer_status_open mode=${_mode.name} captured=${_capturedImages.length}',
    );
    await trace.showSnapshotStatusDialog(
      context,
      title: '사진 작업 디버그 상태',
      description: <String>[
        'plate=${widget.plateNumber}',
        'mode=${_mode.name}',
        'cameraReady=$_isCameraReady',
        'initFailed=$_initFailed',
        'captureBusy=$_captureBusy',
        'capturePhase=$_capturePhase',
        'pendingImagePath=${_pendingImagePath ?? '-'}',
        'recentCommitPending=${_captureBusy && _capturePhase != 'capturing'}',
        'captured=${_capturedImages.length}',
        'previewIndex=$_previewIndex',
        'previewCount=${_previewImages.length}',
        'lastDisplayBytes=${_cameraHelper.lastDisplayBytes}',
        'lastThumbnailBytes=${_cameraHelper.lastThumbnailBytes}',
        'lastDisplayPath=${_cameraHelper.lastDisplayPath ?? '-'}',
        'lastThumbnailPath=${_cameraHelper.lastThumbnailPath ?? '-'}',
        'lastCapturedAtUtc=${_cameraHelper.lastCapturedAtUtc?.toIso8601String() ?? '-'}',
      ].join('\n'),
    );
  }

  Widget _buildDeveloperAction(BuildContext context) {
    final trace = widget.trace;
    if (trace == null || !trace.developerMode) {
      return const SizedBox.shrink();
    }
    final tokens = CommonUiTheme.of(context);
    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        onPressed: () => unawaited(_showDeveloperStatus()),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          foregroundColor: tokens.iconPrimary,
          backgroundColor: tokens.surfaceOverlay,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CommonUiShapes.control),
            side: BorderSide(color: tokens.borderSubtle),
          ),
        ),
        icon: const Icon(Icons.bug_report_rounded, size: 18),
      ),
    );
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
    PlateCameraHelper.forgetCaptureMetadata(removed);
    final thumbnail = PlateCameraHelper.thumbnailFileFor(removed);
    if (thumbnail.existsSync()) {
      try {
        thumbnail.deleteSync();
        _debug('camera_gallery=thumbnail_deleted path=${thumbnail.path}');
      } catch (error) {
        _debug(
          'camera_gallery=thumbnail_delete_failed path=${thumbnail.path} error=$error',
        );
      }
    }
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
                final reduceMotion =
                    MediaQuery.maybeOf(context)?.disableAnimations ?? false;
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
                    final sequence = ++_focusSequence;
                    if (mounted) {
                      setState(() {
                        _focusLocalPosition = details.localPosition;
                        _focusVisible = true;
                      });
                    }
                    _debug(
                      'camera=focus_request x=${point.dx.toStringAsFixed(3)} y=${point.dy.toStringAsFixed(3)}',
                    );
                    try {
                      await controller.setFocusPoint(point);
                      await controller.setExposurePoint(point);
                      _debug(
                        'camera=focus_success x=${point.dx.toStringAsFixed(3)} y=${point.dy.toStringAsFixed(3)}',
                      );
                    } catch (error) {
                      _debug('camera=focus_failed error=$error');
                    }
                    await Future<void>.delayed(
                      reduceMotion
                          ? const Duration(milliseconds: 120)
                          : const Duration(milliseconds: 650),
                    );
                    if (!mounted || sequence != _focusSequence) return;
                    setState(() => _focusVisible = false);
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(controller),
                      if (_focusLocalPosition != null)
                        Positioned(
                          left: (_focusLocalPosition!.dx - 25)
                              .clamp(0.0, constraints.maxWidth - 50)
                              .toDouble(),
                          top: (_focusLocalPosition!.dy - 25)
                              .clamp(0.0, constraints.maxHeight - 50)
                              .toDouble(),
                          child: IgnorePointer(
                            child: AnimatedOpacity(
                              duration: reduceMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 160),
                              curve: Curves.easeOutCubic,
                              opacity: _focusVisible ? 1 : 0,
                              child: TweenAnimationBuilder<double>(
                                key: ValueKey<int>(_focusSequence),
                                tween: Tween<double>(begin: 1.24, end: 1),
                                duration: reduceMotion
                                    ? Duration.zero
                                    : const Duration(milliseconds: 190),
                                curve: Curves.easeOutCubic,
                                builder: (context, value, child) {
                                  return Transform.scale(
                                    scale: value,
                                    child: child,
                                  );
                                },
                                child: Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: tokens.onAccent,
                                      width: 2,
                                    ),
                                  ),
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
        !_captureBusy &&
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
                  icon: Icons.close_rounded,
                  tooltip: '닫기',
                  size: 36,
                  iconSize: 18,
                  onPressed: _captureBusy ? null : widget.onExit,
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
                Text(
                  '신규 ${_capturedImages.length}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                if (widget.trace?.developerMode == true) ...[
                  const SizedBox(width: 7),
                  _buildDeveloperAction(context),
                ],
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
                    onPressed: _captureBusy || widget.savedPhotosBuilder == null
                        ? null
                        : _openSavedPhotos,
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
                          unawaited(_capture());
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
                      child: AnimatedSwitcher(
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 160),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child: _captureBusy
                            ? SizedBox(
                                key: const ValueKey<String>('capture_busy'),
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: tokens.onAccent,
                                ),
                              )
                            : Icon(
                                Icons.camera_alt_rounded,
                                key: const ValueKey<String>('capture_ready'),
                                color: canCapture
                                    ? tokens.onAccent
                                    : tokens.iconDisabled,
                                size: 26,
                              ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 150),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: _captureBusy
                        ? Row(
                            key: const ValueKey<String>('recent_processing'),
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: tokens.accent,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  '사진 처리 중...',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(
                                        color: tokens.textSecondary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                              ),
                            ],
                          )
                        : latest == null
                            ? CommonButton(
                                key: const ValueKey<String>('recent_empty'),
                                label: '최근 0',
                                icon: Icons.photo_library_outlined,
                                variant: CommonButtonVariant.secondary,
                                onPressed: null,
                              )
                            : GestureDetector(
                                key: ValueKey<String>('recent_${latest.path}'),
                                onTap: _openGallery,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Image.file(
                                        _gridFileFor(latest),
                                        width: 42,
                                        height: 42,
                                        fit: BoxFit.cover,
                                        cacheWidth: 130,
                                        filterQuality: FilterQuality.low,
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
                if (widget.trace?.developerMode == true) ...[
                  const SizedBox(width: 7),
                  _buildDeveloperAction(context),
                ],
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
                      _gridFileFor(image),
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
    final builder = widget.savedPhotosBuilder;
    if (builder == null) {
      return _buildCameraMode(context);
    }
    return KeyedSubtree(
      key: const ValueKey<String>('saved_photos'),
      child: builder(
        context,
        () => _setMode(_CameraWorkspaceMode.camera),
      ),
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
            child: Stack(
              fit: StackFit.expand,
              children: [
                PlateEmbeddedImageViewerContent(
                  images: _previewImages,
                  initialIndex: _previewIndex,
                  onBack: widget.startInPreview
                      ? widget.onExit
                      : () => _setMode(_previewBackMode),
                  onPageChanged: (index) =>
                      setState(() => _previewIndex = index),
                  onDebug: _debug,
                ),
                if (widget.trace?.developerMode == true)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _buildDeveloperAction(context),
                  ),
              ],
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
    return PlateEditorWorkspaceSwitcher(
      activeKey: _mode.name,
      activeOrder: _mode.index,
      child: child,
    );
  }
}
