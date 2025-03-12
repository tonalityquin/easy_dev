import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class CameraHelper {
  CameraController? cameraController;
  bool isCameraInitialized = false;
  final List<XFile> capturedImages = [];

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

  void removeImage(int index) {
    if (index < 0 || index >= capturedImages.length) return;
    capturedImages.removeAt(index);
  }

  void dispose() {
    cameraController?.dispose();
  }
}
