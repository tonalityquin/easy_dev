import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:easydev/utils/camera_fullscreen_viewer.dart';

class ModifyPhotoSection extends StatelessWidget {
  final List<String> existingImageUrls;
  final List<XFile> capturedImages;

  const ModifyPhotoSection({
    super.key,
    required this.existingImageUrls,
    required this.capturedImages,
  });

  @override
  Widget build(BuildContext context) {
    final isEmpty = existingImageUrls.isEmpty && capturedImages.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '촬영 사진',
          style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8.0),
        SizedBox(
          height: 100,
          child: isEmpty
              ? const Center(child: Text('촬영된 사진 없음'))
              : ListView(
            scrollDirection: Axis.horizontal,
            children: [
              // ✅ 기존 이미지 (URL 기반)
              ...existingImageUrls.asMap().entries.map((entry) {
                final index = entry.key;
                final url = entry.value;
                return GestureDetector(
                  onTap: () => showFullScreenImageViewerFromUrls(
                    context,
                    existingImageUrls,
                    index,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Image.network(
                      url,
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.broken_image, size: 50),
                    ),
                  ),
                );
              }),

              // ✅ 새로 촬영한 로컬 이미지
              ...capturedImages.asMap().entries.map((entry) {
                final index = entry.key;
                final image = entry.value;
                return GestureDetector(
                  onTap: () => showFullScreenImageViewer(
                    context,
                    capturedImages,
                    index,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Image.file(
                      File(image.path),
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }
}
