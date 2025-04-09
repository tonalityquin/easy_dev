import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../../utils/camera_helper.dart';

class CameraPreviewDialog extends StatefulWidget {
  final void Function(List<XFile>)? onCaptureComplete;

  final void Function(XFile)? onImageCaptured;

  const CameraPreviewDialog({
    super.key,
    this.onCaptureComplete,
    this.onImageCaptured,
  });

  @override
  State<CameraPreviewDialog> createState() => _CameraPreviewDialogState();
}

class _CameraPreviewDialogState extends State<CameraPreviewDialog> {
  late final CameraHelper _cameraHelper;
  final List<XFile> _capturedImages = [];
  bool _isCameraReady = false;

  @override
  void initState() {
    super.initState();
    _cameraHelper = CameraHelper();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    debugPrint('📸 CameraHelper: initializeCamera() 호출');
    await _cameraHelper.initializeCamera();
    setState(() => _isCameraReady = true);
    debugPrint('✅ CameraHelper: 카메라 초기화 완료');
  }

  @override
  void dispose() {
    debugPrint('🧹 CameraHelper: dispose() 호출');
    widget.onCaptureComplete?.call(_capturedImages);
    _cameraHelper.dispose();
    super.dispose();
  }

  Future<void> _onCapturePressed() async {
    debugPrint('📸 촬영 버튼 클릭됨');
    final image = await _cameraHelper.captureImage();

    if (image != null) {
      debugPrint('✅ CameraHelper: 사진 촬영 성공 - ${image.path}');
      _capturedImages.add(image);
      widget.onImageCaptured?.call(image);
    } else {
      debugPrint('⚠️ 이미지 촬영 실패 또는 null');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            if (_isCameraReady && _cameraHelper.cameraController != null)
              Positioned.fill(
                child: RotatedBox(
                  quarterTurns: 1,
                  child: CameraPreview(_cameraHelper.cameraController!),
                ),
              )
            else
              const Center(child: CircularProgressIndicator()),
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Center(
                child: ElevatedButton(
                  onPressed: _onCapturePressed,
                  style: ElevatedButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(20),
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    elevation: 4,
                  ),
                  child: const Icon(Icons.camera_alt, size: 30),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
