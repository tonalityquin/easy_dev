import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../../../utils/camera_fullscreen_viewer.dart';

class PhotoInputSection extends StatelessWidget {
  final List<XFile> capturedImages;

  const PhotoInputSection({
    super.key,
    required this.capturedImages,
  });

  @override
  Widget build(BuildContext context) {
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
          child: capturedImages.isEmpty
              ? const Center(child: Text('촬영된 사진 없음'))
              : ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: capturedImages.length,
            itemBuilder: (context, index) {
              final imageFile = capturedImages[index];
              return GestureDetector(
                onTap: () => showFullScreenImageViewer(context, capturedImages, index),
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Hero(
                    tag: imageFile.path,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      transitionBuilder: (child, animation) => ScaleTransition(
                        scale: CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutBack,
                        ),
                        child: FadeTransition(opacity: animation, child: child),
                      ),
                      child: FutureBuilder<bool>(
                        future: File(imageFile.path).exists(),
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
                            File(imageFile.path),
                            key: ValueKey(imageFile.path),
                            width: 100,
                            height: 100,
                            fit: BoxFit.cover,
                          );
                        },
                      ),
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
