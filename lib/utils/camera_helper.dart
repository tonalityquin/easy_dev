// ------------------- camera_helper.dart -------------------
// [기존: import 'dart:io'; -> 제거]
// [기존 코드에서 불필요한 dart:io import 제거]

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class CameraHelper {
  CameraController? cameraController;
  bool isCameraInitialized = false;
  final List<XFile> capturedImages = [];

  // ------------------- 카메라 초기화 -------------------
  Future<void> initializeCamera() async {
    final cameras = await availableCameras();
    final backCamera = cameras.first;
    cameraController = CameraController(
      backCamera,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    await cameraController!.initialize();
    isCameraInitialized = true;
  }

  // ------------------- 사진 촬영 -------------------
  Future<void> captureImage() async {
    if (cameraController == null) return;
    if (!cameraController!.value.isInitialized || cameraController!.value.isTakingPicture) {
      return;
    }
    try {
      final XFile image = await cameraController!.takePicture();
      capturedImages.add(image);
    } catch (e) {
      debugPrint("사진 촬영 오류: $e");
    }
  }

  // ------------------- 촬영된 사진 삭제 -------------------
  void removeImage(int index) {
    if (index < 0 || index >= capturedImages.length) return;
    capturedImages.removeAt(index);
  }

  // ------------------- 카메라 자원 해제 -------------------
  void dispose() {
    cameraController?.dispose();
  }
}
