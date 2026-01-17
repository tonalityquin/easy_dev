// modify_camera_helper.dart
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // DeviceOrientation, PlatformException
import 'package:image/image.dart' as img;

/// 카메라 초기화/촬영/정리 헬퍼.
/// - A) 다운스케일 + 품질 인자화 (jpegQuality, maxLongSide, keepOriginalAlso)
/// - B) 포맷 폴백(ImageFormatGroup.jpeg 실패 시 포맷 미지정 재시도)
/// - C) 촬영 가드(초기화/중복 촬영/정리 경합)
/// - 프리뷰/촬영 일치 보조: capture orientation 잠금 제공
class DoubleModifyCameraHelper {
  DoubleModifyCameraHelper({
    this.jpegQuality = 75,
    this.maxLongSide,
    this.keepOriginalAlso = false,
    this.resolution = ResolutionPreset.medium,
  });

  /// JPEG 인코딩 품질(1~100)
  final int jpegQuality;

  /// 다운스케일: 긴 변 최대 길이(px). null이면 원본 크기 유지.
  final int? maxLongSide;

  /// 원본 파일도 유지(.orig.jpg로 보관)
  final bool keepOriginalAlso;

  /// 카메라 해상도 프리셋
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
    // 후면 우선 선택
    final back = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    // B) 포맷 폴백
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

  /// (선택) 세로 고정 → 프리뷰/촬영 간 회전 튐 방지
  Future<void> lockPortrait() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    try {
      await c.lockCaptureOrientation(DeviceOrientation.portraitUp);
    } catch (_) {}
  }

  /// (선택) 잠금 해제
  Future<void> unlockOrientation() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    try {
      await c.unlockCaptureOrientation();
    } catch (_) {}
  }

  /// 사진 촬영 + (옵션)EXIF 방향 굽기 + (옵션)다운스케일 + JPEG 압축.
  Future<XFile?> captureImage() async {
    // C-1) 상태 가드
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
    // C-2) 중복 촬영 가드
    if (_captureInProgress) {
      debugPrint('⏳ captureInProgress=true (중복 방지)');
      return null;
    }

    _captureInProgress = true;
    try {
      final XFile image = await c.takePicture();
      debugPrint('✅ 촬영 성공 - ${image.path}');

      // 파일 읽기
      final file = File(image.path);
      final bytes = await file.readAsBytes();

      // A) Isolate로 압축(방향 굽기 + 다운스케일 + 품질)
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

      // 동일 경로에 덮어쓰기
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

    // C-3) 정리 경합 가드
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

/// Isolate 페이로드
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

/// EXIF 방향 굽기 + (옵션)긴 변 기준 다운스케일 + JPEG 인코딩
List<int> _compressJpegOnIsolate(_CompressPayload payload) {
  final decoded = img.decodeImage(payload.bytes);
  if (decoded == null) return payload.bytes;

  img.Image baked = img.bakeOrientation(decoded);

  // 다운스케일
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

  // 품질 인자화
  return img.encodeJpg(baked, quality: payload.quality);
}
