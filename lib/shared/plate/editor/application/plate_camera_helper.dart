import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show ValueChanged, compute, debugPrint;
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

class PlateCameraHelper {
  PlateCameraHelper({
    this.jpegQuality = 82,
    this.maxLongSide,
    this.thumbnailJpegQuality = 65,
    this.thumbnailLongSide = 400,
    this.keepOriginalAlso = false,
    this.resolution = ResolutionPreset.high,
    this.onDebug,
  });

  final int jpegQuality;
  final int? maxLongSide;
  final int thumbnailJpegQuality;
  final int thumbnailLongSide;
  final bool keepOriginalAlso;
  final ResolutionPreset resolution;
  final ValueChanged<String>? onDebug;

  CameraController? _controller;
  CameraController? get cameraController => _controller;
  bool get isCameraInitialized => _controller?.value.isInitialized == true;

  static final Map<String, DateTime> _capturedAtUtcByPath = <String, DateTime>{};

  final List<XFile> capturedImages = <XFile>[];

  bool _isInitializing = false;
  Future<void>? _initFuture;
  bool _isDisposing = false;
  bool _captureInProgress = false;
  bool _disposeInProgress = false;
  String? _lastDisplayPath;
  String? _lastThumbnailPath;
  int _lastDisplayBytes = 0;
  int _lastThumbnailBytes = 0;
  DateTime? _lastCapturedAtUtc;

  String? get lastDisplayPath => _lastDisplayPath;
  String? get lastThumbnailPath => _lastThumbnailPath;
  int get lastDisplayBytes => _lastDisplayBytes;
  int get lastThumbnailBytes => _lastThumbnailBytes;
  DateTime? get lastCapturedAtUtc => _lastCapturedAtUtc;
  bool get _hasController => _controller != null;

  static DateTime? capturedAtUtcFor(XFile image) {
    return _capturedAtUtcByPath[image.path];
  }

  static DateTime? capturedAtUtcForPath(String path) {
    return _capturedAtUtcByPath[path];
  }

  static void forgetCaptureMetadata(XFile image) {
    _capturedAtUtcByPath.remove(image.path);
  }

  static String thumbnailPathFor(String displayPath) {
    return '$displayPath.thumb.jpg';
  }

  static File thumbnailFileFor(XFile displayImage) {
    return File(thumbnailPathFor(displayImage.path));
  }

  void _debug(String message) {
    final normalized = message.trim();
    if (normalized.isEmpty) return;
    final callback = onDebug;
    if (callback != null) {
      callback(normalized);
      return;
    }
    debugPrint('[PlateCameraHelper] $normalized');
  }

  Future<void> initializeCamera() async {
    if (isCameraInitialized && _controller != null) {
      _debug('camera_initialize=reuse');
      return;
    }
    if (_isInitializing && _initFuture != null) {
      _debug('camera_initialize=join_existing');
      await _initFuture!;
      return;
    }

    _isInitializing = true;
    _initFuture = _doInitialize();
    try {
      await _initFuture;
      _debug('camera_initialize=success resolution=${resolution.name}');
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> _doInitialize() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw CameraException('no_camera', 'No cameras available');
    }

    final back = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    try {
      _controller = CameraController(
        back,
        resolution,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await _controller!.initialize();
    } on CameraException catch (error) {
      _debug('camera_initialize=jpeg_retry error=$error');
      _controller = CameraController(
        back,
        resolution,
        enableAudio: false,
      );
      await _controller!.initialize();
    }
  }

  Future<void> lockPortrait() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
    } catch (error) {
      _debug('camera_orientation=lock_failed error=$error');
    }
  }

  Future<void> unlockOrientation() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await controller.unlockCaptureOrientation();
    } catch (error) {
      _debug('camera_orientation=unlock_failed error=$error');
    }
  }

  Future<XFile?> captureImage() async {
    if (_isDisposing) {
      _debug('capture=blocked reason=disposing');
      return null;
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      _debug('capture=blocked reason=not_initialized');
      return null;
    }
    if (controller.value.isTakingPicture) {
      _debug('capture=blocked reason=camera_busy');
      return null;
    }
    if (_captureInProgress) {
      _debug('capture=blocked reason=processing_busy');
      return null;
    }

    _captureInProgress = true;
    final stopwatch = Stopwatch()..start();
    XFile? capturedImage;
    try {
      final capturedAtUtc = DateTime.now().toUtc();
      _debug('capture=requested capturedAtUtc=${capturedAtUtc.toIso8601String()}');
      final image = await controller.takePicture();
      capturedImage = image;
      _capturedAtUtcByPath[image.path] = capturedAtUtc;
      _lastCapturedAtUtc = capturedAtUtc;
      final file = File(image.path);
      final sourceBytes = await file.readAsBytes();
      _debug(
        'capture=source path=${image.path} capturedAtUtc=${capturedAtUtc.toIso8601String()} bytes=${sourceBytes.length} displayQuality=$jpegQuality displayMaxLong=${maxLongSide ?? 0} thumbnailQuality=$thumbnailJpegQuality thumbnailLong=$thumbnailLongSide',
      );

      final processed = await compute<_ProcessPayload, Map<String, List<int>>>(
        _processJpegOnIsolate,
        _ProcessPayload(
          sourceBytes,
          displayQuality: jpegQuality,
          displayMaxLongSide: maxLongSide,
          thumbnailQuality: thumbnailJpegQuality,
          thumbnailLongSide: thumbnailLongSide,
        ),
      );

      if (keepOriginalAlso) {
        try {
          final originalPath = '${image.path}.orig.jpg';
          await File(originalPath).writeAsBytes(sourceBytes, flush: true);
          _debug('capture=original_saved path=$originalPath bytes=${sourceBytes.length}');
        } catch (error) {
          _debug('capture=original_save_failed error=$error');
        }
      }

      final displayBytes = processed['display'] ?? sourceBytes;
      await file.writeAsBytes(displayBytes, flush: true);

      final thumbnailPath = thumbnailPathFor(image.path);
      final thumbnailBytes = processed['thumbnail'] ?? const <int>[];
      var thumbnailWritten = false;
      if (thumbnailBytes.isNotEmpty) {
        try {
          await File(thumbnailPath).writeAsBytes(thumbnailBytes, flush: true);
          thumbnailWritten = true;
        } catch (error) {
          _debug('thumbnail=write_failed path=$thumbnailPath error=$error');
        }
      }

      _lastDisplayPath = image.path;
      _lastThumbnailPath = thumbnailWritten ? thumbnailPath : null;
      _lastDisplayBytes = displayBytes.length;
      _lastThumbnailBytes = thumbnailWritten ? thumbnailBytes.length : 0;
      capturedImages.add(image);
      stopwatch.stop();
      _debug(
        'capture=success path=${image.path} capturedAtUtc=${capturedAtUtc.toIso8601String()} displayBytes=$_lastDisplayBytes thumbnailPath=${_lastThumbnailPath ?? '-'} thumbnailBytes=$_lastThumbnailBytes elapsedMs=${stopwatch.elapsedMilliseconds}',
      );
      return image;
    } catch (error, stackTrace) {
      final failedImage = capturedImage;
      if (failedImage != null) {
        _capturedAtUtcByPath.remove(failedImage.path);
      }
      stopwatch.stop();
      _debug('capture=failed elapsedMs=${stopwatch.elapsedMilliseconds} error=$error');
      _debug('capture=stack_trace\n$stackTrace');
      return null;
    } finally {
      _captureInProgress = false;
    }
  }

  Future<void> pausePreview() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await controller.pausePreview();
      _debug('preview=pause_success');
    } catch (error) {
      _debug('preview=pause_failed error=$error');
    }
  }

  Future<void> resumePreview() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await controller.resumePreview();
      _debug('preview=resume_success');
    } catch (error) {
      _debug('preview=resume_failed error=$error');
    }
  }

  Future<void> dispose() async {
    _debug('camera_dispose=start');
    if (_isDisposing || _disposeInProgress) {
      _debug('camera_dispose=skip reason=already_disposing');
      return;
    }
    _isDisposing = true;
    _disposeInProgress = true;

    try {
      try {
        await _initFuture?.catchError((_) {});
      } catch (_) {}

      if (!_hasController) {
        _debug('camera_dispose=skip reason=no_controller');
        return;
      }
      final controller = _controller!;
      try {
        await controller.dispose();
        _debug('camera_dispose=success');
      } on PlatformException catch (error) {
        final message = error.message ?? '';
        if (error.code == 'IllegalStateException' &&
            message.contains('releaseFlutterSurfaceTexture')) {
          _debug('camera_dispose=platform_ignored error=$error');
        } else {
          _debug('camera_dispose=platform_failed error=$error');
        }
      } catch (error) {
        _debug('camera_dispose=failed error=$error');
      } finally {
        _controller = null;
        capturedImages.clear();
      }
    } finally {
      _isDisposing = false;
      _disposeInProgress = false;
    }
  }
}

class _ProcessPayload {
  const _ProcessPayload(
    this.bytes, {
    required this.displayQuality,
    required this.displayMaxLongSide,
    required this.thumbnailQuality,
    required this.thumbnailLongSide,
  });

  final Uint8List bytes;
  final int displayQuality;
  final int? displayMaxLongSide;
  final int thumbnailQuality;
  final int thumbnailLongSide;
}

Map<String, List<int>> _processJpegOnIsolate(_ProcessPayload payload) {
  final decoded = img.decodeImage(payload.bytes);
  if (decoded == null) {
    return <String, List<int>>{
      'display': payload.bytes,
      'thumbnail': const <int>[],
    };
  }

  final baked = img.bakeOrientation(decoded);
  final display = _resizeLongSide(baked, payload.displayMaxLongSide);
  final displayBytes = img.encodeJpg(
    display,
    quality: payload.displayQuality.clamp(1, 100).toInt(),
  );

  List<int> thumbnailBytes = const <int>[];
  if (payload.thumbnailLongSide > 0) {
    try {
      final thumbnail = _resizeLongSide(baked, payload.thumbnailLongSide);
      thumbnailBytes = img.encodeJpg(
        thumbnail,
        quality: payload.thumbnailQuality.clamp(1, 100).toInt(),
      );
    } catch (_) {
      thumbnailBytes = const <int>[];
    }
  }

  return <String, List<int>>{
    'display': displayBytes,
    'thumbnail': thumbnailBytes,
  };
}

img.Image _resizeLongSide(img.Image source, int? maxLongSide) {
  if (maxLongSide == null || maxLongSide <= 0) return source;
  final longer = source.width >= source.height ? source.width : source.height;
  if (longer <= maxLongSide) return source;
  final scale = maxLongSide / longer;
  return img.copyResize(
    source,
    width: (source.width * scale).round(),
    height: (source.height * scale).round(),
    interpolation: img.Interpolation.linear,
  );
}
