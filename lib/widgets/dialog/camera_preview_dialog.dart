import 'dart:io'; // ✅ 파일 처리를 위해 import
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../../utils/camera_helper.dart'; // ✅ CameraHelper 가져오기

/// **카메라 미리보기 및 촬영을 위한 다이얼로그 위젯**
class CameraPreviewDialog extends StatefulWidget {
  final CameraHelper cameraHelper; // CameraHelper 인스턴스

  const CameraPreviewDialog({super.key, required this.cameraHelper});

  @override
  State<CameraPreviewDialog> createState() => _CameraPreviewDialogState();
}

class _CameraPreviewDialogState extends State<CameraPreviewDialog> {
  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Column(
        children: [
          Expanded(
            child: AspectRatio(
              aspectRatio: 1.0,
              child: RotatedBox(
                quarterTurns: 1,
                child: CameraPreview(widget.cameraHelper.cameraController!),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: () async {
                  await widget.cameraHelper.captureImage();
                  setState(() {}); // ✅ UI 갱신
                },
                child: const Text('촬영'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context, true); // ✅ 팝업 닫고 이미지 리스트 갱신
                },
                child: const Text('완료'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (widget.cameraHelper.capturedImages.isNotEmpty)
            SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: widget.cameraHelper.capturedImages.length,
                itemBuilder: (context, index) {
                  return GestureDetector(
                    onTap: () {
                      _showFullPreviewDialog(widget.cameraHelper.capturedImages[index]);
                    },
                    child: Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Image.file(
                            File(widget.cameraHelper.capturedImages[index].path), // ✅ 올바른 파일 경로 사용
                            width: 100,
                            height: 100,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: () => _removeImage(index),
                            child: Container(
                              padding: const EdgeInsets.all(4.0),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.white,
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
        ],
      ),
    );
  }

  /// ✅ **개별 사진 삭제**
  void _removeImage(int index) {
    setState(() {
      widget.cameraHelper.removeImage(index);
    });
  }

  /// ✅ **전체 화면 미리보기**
  void _showFullPreviewDialog(XFile imageFile) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.file(
                File(imageFile.path), // ✅ 올바른 경로 전달
                fit: BoxFit.contain,
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("닫기"),
              ),
            ],
          ),
        );
      },
    );
  }
}
