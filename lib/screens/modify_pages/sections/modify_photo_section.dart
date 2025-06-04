import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../utils/modify_camera_fullscreen_viewer.dart';

class ModifyPhotoSection extends StatelessWidget {
  final List<XFile> capturedImages;
  final List<String> imageUrls;

  const ModifyPhotoSection({
    super.key,
    required this.capturedImages,
    required this.imageUrls,
  });

  @override
  Widget build(BuildContext context) {
    final totalItems = [...imageUrls, ...capturedImages.map((e) => e.path)];

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
          child: totalItems.isEmpty
              ? const Center(child: Text('촬영된 사진 없음'))
              : ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: totalItems.length,
            itemBuilder: (context, index) {
              final isUrl = index < imageUrls.length;
              final tag = isUrl ? imageUrls[index] : capturedImages[index - imageUrls.length].path;

              return GestureDetector(
                onTap: () => showFullScreenImageViewer(
                  context,
                  imageUrls + capturedImages.map((e) => e.path).toList(),
                  index,
                  isUrlList: true,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Hero(
                    tag: tag,
                    child: isUrl
                        ? Image.network(
                      imageUrls[index],
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.red),
                    )
                        : FutureBuilder<bool>(
                      future: File(capturedImages[index - imageUrls.length].path).exists(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const SizedBox(
                            width: 100,
                            height: 100,
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }

                        if (snapshot.hasError || !(snapshot.data ?? false)) {
                          return const SizedBox(
                            width: 100,
                            height: 100,
                            child: Center(child: Icon(Icons.broken_image, color: Colors.red)),
                          );
                        }

                        return Image.file(
                          File(capturedImages[index - imageUrls.length].path),
                          key: ValueKey(capturedImages[index - imageUrls.length].path),
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
