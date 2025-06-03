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
                  final fileName = File(image.path).uri.pathSegments.last;
                  final infoText = _parseMetadataFromFileName(fileName);

                  return Stack(
                    children: [
                      Center(
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
                      ),
                      Positioned(
                        bottom: 30,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              infoText,
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    ],
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

String _parseMetadataFromFileName(String fileName) {
  try {
    final name = fileName.replaceAll('.jpg', '');
    final parts = name.split('_');
    if (parts.length < 4) return '';

    final date = parts[0]; // YYYY-MM-DD
    final time = parts[1]; // HHMMSS
    final plate = parts[2]; // 번호판
    final user = parts.sublist(3).join('_'); // 사용자 이름 (공백 포함 가능)

    final timeFormatted = '${time.substring(0, 2)}:${time.substring(2, 4)}:${time.substring(4, 6)}';
    return '촬영일: $date $timeFormatted\n차량번호: $plate\n촬영자: $user';
  } catch (_) {
    return '';
  }
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
