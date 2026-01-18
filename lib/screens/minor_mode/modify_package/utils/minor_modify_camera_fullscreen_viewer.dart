import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

void minorModifyShowFullScreenImageViewer(
    BuildContext context,
    List<dynamic> images,
    int initialIndex, {
      bool isUrlList = false,
    }) {
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
                  final tag = isUrlList ? image : (image as XFile).path;
                  final metadata = isUrlList
                      ? _parseMetadataFromUrl(image)
                      : _parseMetadataFromFileName(File(image.path).uri.pathSegments.last);

                  return Stack(
                    children: [
                      Center(
                        child: Hero(
                          tag: tag,
                          child: InteractiveViewer(
                            minScale: 0.8,
                            maxScale: 4.0,
                            child: isUrlList
                                ? Image.network(
                              image,
                              fit: BoxFit.contain,
                              loadingBuilder: (context, child, progress) {
                                if (progress == null) return child;
                                return const Center(child: CircularProgressIndicator());
                              },
                              errorBuilder: (_, __, ___) =>
                              const Icon(Icons.error, color: Colors.red),
                            )
                                : FutureBuilder<bool>(
                              future: File(image.path).exists(),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState != ConnectionState.done) {
                                  return const Center(child: CircularProgressIndicator());
                                }
                                if (snapshot.hasError || !(snapshot.data ?? false)) {
                                  return const Center(
                                      child: Icon(Icons.broken_image, color: Colors.red));
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
                      if (metadata.isNotEmpty)
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
                                metadata,
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
    final millis = int.tryParse(parts[1]) ?? 0;
    final plate = parts[2];
    final user = parts.sublist(3).join('_');

    final dateTime = DateTime.fromMillisecondsSinceEpoch(millis);
    final timeFormatted =
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';

    return '촬영일: $date $timeFormatted\n차량번호: $plate\n촬영자: $user';
  } catch (_) {
    return '';
  }
}

String _parseMetadataFromUrl(String url) {
  try {
    final segments = Uri.parse(url).pathSegments;
    final fileName = segments.isNotEmpty ? segments.last : '';
    return _parseMetadataFromFileName(fileName);
  } catch (_) {
    return '';
  }
}
