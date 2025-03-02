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
          _buildCameraPreview(),
          _buildActionButtons(),
          _buildCapturedImagesPreview(),
        ],
      ),
    );
  }

  /// 카메라 미리보기 화면 구성
  Widget _buildCameraPreview() {
    return Expanded(
      child: AspectRatio(
        aspectRatio: 1.0,
        child: RotatedBox(
          quarterTurns: 1,
          child: CameraPreview(widget.cameraHelper.cameraController!),
        ),
      ),
    );
  }

  /// 하단 액션 버튼 (촬영, 완료) 구성
  Widget _buildActionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        ElevatedButton(
          onPressed: () async {
            await widget.cameraHelper.captureImage();
            setState(() {});
          },
          child: const Text('촬영'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context, true);
          },
          child: const Text('완료'),
        ),
      ],
    );
  }

  /// 캡처된 이미지 리스트 미리보기
  Widget _buildCapturedImagesPreview() {
    if (widget.cameraHelper.capturedImages.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: widget.cameraHelper.capturedImages.length,
        itemBuilder: (context, index) {
          return _buildImageThumbnail(index);
        },
      ),
    );
  }

  /// 개별 이미지 썸네일 위젯 구성
  Widget _buildImageThumbnail(int index) {
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(4.0),
          child: GestureDetector(
            onTap: () => _showFullPreviewDialog(widget.cameraHelper.capturedImages[index]),
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
  }

  /// 개별 사진 삭제
  void _removeImage(int index) {
    widget.cameraHelper.removeImage(index);
    setState(() {});
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