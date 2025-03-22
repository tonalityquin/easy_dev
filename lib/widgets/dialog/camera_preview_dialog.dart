import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../../utils/camera_helper.dart';

class CameraPreviewDialog extends StatefulWidget {
  /// 촬영 완료 후 전체 이미지 리스트를 콜백으로 전달
  final void Function(List<XFile>)? onCaptureComplete;

  const CameraPreviewDialog({
    super.key,
    this.onCaptureComplete,
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

    /// ✅ 다이얼로그가 닫힐 때 이미지 리스트 전달
    widget.onCaptureComplete?.call(_capturedImages);

    _cameraHelper.dispose();
    super.dispose();
  }

  Future<void> _onCapturePressed() async {
    debugPrint('📸 촬영 버튼 클릭됨');
    final image = await _cameraHelper.captureImage();

    if (image != null) {
      debugPrint('✅ CameraHelper: 사진 촬영 성공 - ${image.path}');
      setState(() {
        _capturedImages.add(image);
      });
    } else {
      debugPrint('⚠️ 이미지 촬영 실패 또는 null');
    }
  }

  void _showFullScreenViewer(int index) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            PageView.builder(
              controller: PageController(initialPage: index),
              itemCount: _capturedImages.length,
              itemBuilder: (context, i) {
                return InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4.0,
                  child: Image.file(
                    File(_capturedImages[i].path),
                    fit: BoxFit.contain,
                  ),
                );
              },
            ),
            Positioned(
              top: 30,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // 📷 카메라 프리뷰
            if (_isCameraReady && _cameraHelper.cameraController != null)
              Positioned.fill(
                child: RotatedBox(
                  quarterTurns: 1,
                  child: CameraPreview(_cameraHelper.cameraController!),
                ),
              )
            else
              const Center(child: CircularProgressIndicator()),

            // 📸 촬영 버튼
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

            // ✅ 하단 썸네일 리스트
            if (_capturedImages.isNotEmpty)
              Positioned(
                bottom: 100,
                left: 0,
                right: 0,
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: _capturedImages.length,
                  itemBuilder: (context, index) {
                    final image = _capturedImages[index];
                    return GestureDetector(
                      onTap: () => _showFullScreenViewer(index),
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Image.file(
                          File(image.path),
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
