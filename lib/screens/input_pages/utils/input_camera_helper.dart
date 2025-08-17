import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ← PlatformException
import 'package:image/image.dart' as img;

class InputCameraHelper {
  CameraController? _controller;
  CameraController? get cameraController => _controller;

  bool get isCameraInitialized => _controller?.value.isInitialized == true;

  final List<XFile> capturedImages = [];

  bool _isInitializing = false;
  Future<void>? _initFuture;

  bool _isDisposing = false;

  // ── 초기화: 중복 호출/경합 방지 (idempotent)
  Future<void> initializeInputCamera() async {
    if (isCameraInitialized && _controller != null) {
      debugPrint('📸 CameraHelper: 이미 초기화됨(재사용)');
      return;
    }
    if (_isInitializing && _initFuture != null) {
      debugPrint('📸 CameraHelper: 초기화 진행 중(Future 공유)');
      await _initFuture!;
      return;
    }

    _isInitializing = true;
    _initFuture = _doInitialize();
    try {
      await _initFuture;
      debugPrint('✅ CameraHelper: 카메라 초기화 완료');
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> _doInitialize() async {
    debugPrint('📸 CameraHelper: initializeCamera() 호출');
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw CameraException('no_camera', 'No cameras available');
    }
    final back = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      back,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    await controller.initialize();
    _controller = controller;
  }

  Future<XFile?> captureImage() async {
    debugPrint('📸 CameraHelper: 사진 촬영 시도');
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      debugPrint('⚠️ CameraHelper: 카메라가 초기화되지 않음');
      return null;
    }
    if (c.value.isTakingPicture) {
      debugPrint('⏳ CameraHelper: 현재 사진 촬영 중');
      return null;
    }

    try {
      final XFile image = await c.takePicture();
      debugPrint('✅ CameraHelper: 사진 촬영 성공 - ${image.path}');

      // JPEG 압축
      final file = File(image.path);
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        debugPrint('❌ 이미지 디코딩 실패');
        return null;
      }
      final compressed = img.encodeJpg(decoded, quality: 75);
      await file.writeAsBytes(compressed);
      debugPrint('✅ 이미지 압축 완료 - ${compressed.length ~/ 1024}KB');

      capturedImages.add(image);
      return image;
    } catch (e) {
      debugPrint('❌ CameraHelper: 사진 촬영 또는 압축 오류: $e');
      return null;
    }
  }

  // ── 안전한 dispose: 초기화 중 대기 + 모든 경로에서 PlatformException 무시 처리
  Future<void> dispose() async {
    debugPrint('🧹 CameraHelper: dispose() 호출');

    if (_isDisposing) {
      debugPrint('⚠️ 이미 dispose 중입니다');
      return;
    }
    _isDisposing = true;

    try {
      // 초기화 중이면 완료까지 대기
      try {
        await _initFuture?.catchError((_) {});
      } catch (_) {}

      final c = _controller;
      if (c == null) {
        debugPrint('⚠️ CameraController가 null입니다');
        return;
      }

      // 초기화 여부와 무관하게 동일한 예외 무시 로직 적용
      try {
        if (c.value.isInitialized) {
          debugPrint('🧹 CameraController 초기화됨 → dispose 시작');
        }
        await c.dispose();
        debugPrint('✅ CameraController dispose 완료');
      } on PlatformException catch (e) {
        final msg = e.message ?? '';
        // CameraX가 프리뷰 SurfaceTexture가 없을 때 내는 예외 → 무시
        if (e.code == 'IllegalStateException' &&
            msg.contains('releaseFlutterSurfaceTexture')) {
          debugPrint('! CameraController dispose 중 예외(무시): $e');
        } else {
          // 그 외 PlatformException은 로깅만 하고 진행
          debugPrint('! CameraController dispose 중 PlatformException(기록만): $e');
        }
      } catch (e) {
        // 기타 예외도 앱 크래시 방지를 위해 로깅만
        debugPrint('! CameraController dispose 중 기타 예외(기록만): $e');
      } finally {
        _controller = null;
        capturedImages.clear();
      }
    } finally {
      _isDisposing = false;
    }
  }
}
