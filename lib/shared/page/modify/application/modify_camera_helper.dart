
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:image/image.dart' as img;






class ModifyCameraHelper {
  ModifyCameraHelper({
    this.jpegQuality = 75,
    this.maxLongSide,
    this.keepOriginalAlso = false,
    this.resolution = ResolutionPreset.medium,
  });

  
  final int jpegQuality;

  
  final int? maxLongSide;

  
  final bool keepOriginalAlso;

  
  final ResolutionPreset resolution;

  CameraController? _controller;
  CameraController? get cameraController => _controller;

  bool get isCameraInitialized => _controller?.value.isInitialized == true;

  final List<XFile> capturedImages = [];

  bool _isInitializing = false;
  Future<void>? _initFuture;
  bool _isDisposing = false;
  bool _captureInProgress = false;

  Future<void> initializeInputCamera() async {
    if (isCameraInitialized && _controller != null) {
      debugPrint('📸 ModifyCameraHelper: 이미 초기화됨(재사용)');
      return;
    }
    if (_isInitializing && _initFuture != null) {
      debugPrint('📸 ModifyCameraHelper: 초기화 진행 중(Future 공유)');
      await _initFuture!;
      return;
    }

    _isInitializing = true;
    _initFuture = _doInitialize();
    try {
      await _initFuture;
      debugPrint('✅ ModifyCameraHelper: 카메라 초기화 완료');
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
          (c) => c.lensDirection == CameraLensDirection.back,
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
    } on CameraException catch (e) {
      debugPrint('⚠️ JPEG 포맷 초기화 실패 → 포맷 미지정으로 재시도: $e');
      _controller = CameraController(
        back,
        resolution,
        enableAudio: false,
      );
      await _controller!.initialize();
    }
  }

  
  Future<void> lockPortrait() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    try {
      await c.lockCaptureOrientation(DeviceOrientation.portraitUp);
    } catch (_) {}
  }

  
  Future<void> unlockOrientation() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    try {
      await c.unlockCaptureOrientation();
    } catch (_) {}
  }

  
  Future<XFile?> captureImage() async {
    
    if (_isDisposing) {
      debugPrint('⚠️ dispose 중: 촬영 불가');
      return null;
    }
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      debugPrint('⚠️ 카메라가 초기화되지 않음');
      return null;
    }
    if (c.value.isTakingPicture) {
      debugPrint('⏳ 이미 촬영 중');
      return null;
    }
    
    if (_captureInProgress) {
      debugPrint('⏳ captureInProgress=true (중복 방지)');
      return null;
    }

    _captureInProgress = true;
    try {
      final XFile image = await c.takePicture();
      debugPrint('✅ 촬영 성공 - ${image.path}');

      
      final file = File(image.path);
      final bytes = await file.readAsBytes();

      
      final compressed = await compute<_CompressPayload, List<int>>(
        _compressJpegOnIsolate,
        _CompressPayload(
          bytes,
          quality: jpegQuality,
          maxLongSide: maxLongSide,
        ),
      );

      if (keepOriginalAlso) {
        try {
          final origPath = '${image.path}.orig.jpg';
          await File(origPath).writeAsBytes(bytes, flush: true);
          debugPrint('📦 원본 보존: $origPath');
        } catch (e) {
          debugPrint('⚠️ 원본 보존 실패: $e');
        }
      }

      
      await file.writeAsBytes(compressed, flush: true);
      debugPrint('✅ 압축 완료 - ${compressed.length ~/ 1024}KB');

      capturedImages.add(image);
      return image;
    } catch (e) {
      debugPrint('❌ 촬영/압축 오류: $e');
      return null;
    } finally {
      _captureInProgress = false;
    }
  }

  Future<void> pausePreview() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    try {
      await c.pausePreview();
    } catch (_) {}
  }

  Future<void> resumePreview() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    try {
      await c.resumePreview();
    } catch (_) {}
  }

  bool get _hasController => _controller != null;

  bool _disposeInProgress = false;

  Future<void> dispose() async {
    debugPrint('🧹 ModifyCameraHelper: dispose() 호출');

    
    if (_isDisposing || _disposeInProgress) {
      debugPrint('⚠️ 이미 dispose 중');
      return;
    }
    _isDisposing = true;
    _disposeInProgress = true;

    try {
      try {
        await _initFuture?.catchError((_) {});
      } catch (_) {}

      if (!_hasController) {
        debugPrint('⚠️ CameraController=null');
        return;
      }
      final c = _controller!;
      try {
        if (c.value.isInitialized) {
          debugPrint('🧹 Controller dispose 시작');
        }
        await c.dispose();
        debugPrint('✅ Controller dispose 완료');
      } on PlatformException catch (e) {
        final msg = e.message ?? '';
        if (e.code == 'IllegalStateException' &&
            msg.contains('releaseFlutterSurfaceTexture')) {
          debugPrint('! dispose 예외(무시 가능): $e');
        } else {
          debugPrint('! dispose PlatformException(로그만): $e');
        }
      } catch (e) {
        debugPrint('! dispose 기타 예외(로그만): $e');
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


class _CompressPayload {
  final Uint8List bytes;
  final int quality;
  final int? maxLongSide;
  const _CompressPayload(
      this.bytes, {
        this.quality = 75,
        this.maxLongSide,
      });
}


List<int> _compressJpegOnIsolate(_CompressPayload payload) {
  final decoded = img.decodeImage(payload.bytes);
  if (decoded == null) return payload.bytes;

  img.Image baked = img.bakeOrientation(decoded);

  
  if (payload.maxLongSide != null) {
    final maxSide = payload.maxLongSide!;
    final longer = baked.width >= baked.height ? baked.width : baked.height;
    if (longer > maxSide) {
      final scale = maxSide / longer;
      final targetW = (baked.width * scale).round();
      final targetH = (baked.height * scale).round();
      baked = img.copyResize(
        baked,
        width: targetW,
        height: targetH,
        interpolation: img.Interpolation.linear,
      );
    }
  }

  
  return img.encodeJpg(baked, quality: payload.quality);
}
