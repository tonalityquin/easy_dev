import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../../utils/camera_helper.dart';

class CameraPreviewDialog extends StatefulWidget {
  final CameraHelper cameraHelper;

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
                            File(widget.cameraHelper.capturedImages[index].path),
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

  void _removeImage(int index) {
    setState(() {
      widget.cameraHelper.removeImage(index);
    });
  }

  void _showFullPreviewDialog(XFile imageFile) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.file(
                File(imageFile.path),
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
