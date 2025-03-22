import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class CameraHelper {
  CameraController? cameraController;
  bool isCameraInitialized = false;
  final List<XFile> capturedImages = [];

  Future<void> initializeCamera() async {
    debugPrint('📸 CameraHelper: initializeCamera() 호출');
    final cameras = await availableCameras();
    final backCamera = cameras.first;
    cameraController = CameraController(
      backCamera,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    await cameraController!.initialize();
    isCameraInitialized = true;
    debugPrint('✅ CameraHelper: 카메라 초기화 완료');
  }

  Future<XFile?> captureImage() async {
    debugPrint('📸 CameraHelper: 사진 촬영 시도');
    if (cameraController == null || !cameraController!.value.isInitialized) {
      debugPrint('⚠️ CameraHelper: 카메라가 초기화되지 않음');
      return null;
    }
    if (cameraController!.value.isTakingPicture) {
      debugPrint('⏳ CameraHelper: 현재 사진 촬영 중');
      return null;
    }

    try {
      final XFile image = await cameraController!.takePicture();
      capturedImages.add(image);
      debugPrint('✅ CameraHelper: 사진 촬영 성공 - ${image.path}');
      return image;
    } catch (e) {
      debugPrint("❌ CameraHelper: 사진 촬영 오류: $e");
      return null;
    }
  }

  bool _isDisposing = false;

  Future<void> dispose() async {
    debugPrint('🧹 CameraHelper: dispose() 호출');

    if (_isDisposing) {
      debugPrint('⚠️ 이미 dispose 중입니다');
      return;
    }

    if (cameraController == null) {
      debugPrint('⚠️ CameraController가 null입니다');
      return;
    }

    _isDisposing = true;

    try {
      if (cameraController!.value.isInitialized) {
        debugPrint('🧹 CameraController 초기화됨 → dispose 시작');
        await cameraController!.dispose();
      }
      debugPrint('✅ CameraController dispose 완료');
      cameraController = null;
      isCameraInitialized = false;
      capturedImages.clear();
    } catch (e) {
      debugPrint('❌ CameraHelper: dispose 중 오류: $e');
    } finally {
      _isDisposing = false;
    }
  }

}
