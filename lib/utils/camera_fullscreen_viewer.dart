import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

void showFullScreenImageViewer(BuildContext context, List<XFile> images, int initialIndex) {
  showDialog(
    context: context,
    useSafeArea: true,
    barrierDismissible: true,
    builder: (_) {
      return Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: SafeArea(
          child: Stack(
            children: [
              PageView.builder(
                controller: PageController(initialPage: initialIndex),
                itemCount: images.length,
                itemBuilder: (context, index) {
                  final image = images[index];
                  return Center(
                    child: Hero(
                      tag: image.path,
                      child: InteractiveViewer(
                        minScale: 0.8,
                        maxScale: 4.0,
                        child: FutureBuilder<bool>(
                          future: File(image.path).exists(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState != ConnectionState.done) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            if (snapshot.hasError || snapshot.data == false) {
                              return const Center(child: Icon(Icons.broken_image, color: Colors.red));
                            }
                            return Image.file(
                              File(image.path),
                              fit: BoxFit.contain,
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 30),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: '닫기',
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

void showFullScreenImageViewerFromUrls(BuildContext context, List<String> imageUrls, int initialIndex) {
  showDialog(
    context: context,
    useSafeArea: true,
    barrierDismissible: true,
    builder: (_) {
      return Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: SafeArea(
          child: Stack(
            children: [
              PageView.builder(
                controller: PageController(initialPage: initialIndex),
                itemCount: imageUrls.length,
                itemBuilder: (context, index) {
                  final imageUrl = imageUrls[index];
                  return Center(
                    child: Hero(
                      tag: imageUrl,
                      child: InteractiveViewer(
                        minScale: 0.8,
                        maxScale: 4.0,
                        child: Image.network(
                          imageUrl,
                          fit: BoxFit.contain,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return const Center(child: CircularProgressIndicator());
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(child: Icon(Icons.error, color: Colors.red));
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 30),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: '닫기',
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
