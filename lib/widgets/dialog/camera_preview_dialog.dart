import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../../utils/camera_helper.dart'; // CameraHelper 불러오기

/// 카메라 미리보기 및 촬영을 위한 다이얼로그 위젯
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
                  setState(() {}); // 다이얼로그 내에서 UI 갱신
                },
                child: const Text('촬영'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context, true); // 완료 버튼을 눌러야 다이얼로그 닫힘
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
                  return Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: GestureDetector(
                          onTap: () {
                            _showFullPreviewDialog(widget.cameraHelper.capturedImages[index]);
                          },
                          child: Image.file(
                            File(widget.cameraHelper.capturedImages[index].path),
                            width: 100,
                            height: 100,
                            fit: BoxFit.cover,
                          ),
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
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  /// 개별 사진 삭제
  void _removeImage(int index) {
    widget.cameraHelper.removeImage(index);
    setState(() {}); // UI 갱신
  }

  /// 전체 화면 미리보기
  void _showFullPreviewDialog(XFile imageFile) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          child: Image.file(
            File(imageFile.path),
            fit: BoxFit.contain,
          ),
        );
      },
    );
  }
}
