import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

void normalInputShowFullScreenImageViewer(BuildContext context, List<XFile> images, int initialIndex) {
  showDialog(
    context: context,
    useSafeArea: true,
    barrierDismissible: true,
    builder: (_) {
      return Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: SafeArea(
          child: _buildViewerBody(
            context: context,
            itemCount: images.length,
            initialIndex: initialIndex,
            imageBuilder: (index) => Image.file(
              File(images[index].path),
              fit: BoxFit.contain,
            ),
            tagBuilder: (index) => images[index].path,
            metadataBuilder: (index) => _parseMetadataFromFileName(File(images[index].path).uri.pathSegments.last),
            fileExistenceCheck: (index) => File(images[index].path).exists(),
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
          child: _buildViewerBody(
            context: context,
            itemCount: imageUrls.length,
            initialIndex: initialIndex,
            imageBuilder: (index) => Image.network(
              imageUrls[index],
              fit: BoxFit.contain,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const Center(child: CircularProgressIndicator());
              },
              errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.error, color: Colors.red)),
            ),
            tagBuilder: (index) => imageUrls[index],
            metadataBuilder: (index) => _parseMetadataFromFileName(Uri.parse(imageUrls[index]).pathSegments.last),
          ),
        ),
      );
    },
  );
}

Widget _buildViewerBody({
  required BuildContext context,
  required int itemCount,
  required int initialIndex,
  required Widget Function(int index) imageBuilder,
  required String Function(int index) tagBuilder,
  required String Function(int index) metadataBuilder,
  Future<bool> Function(int index)? fileExistenceCheck,
}) {
  return Stack(
    children: [
      PageView.builder(
        controller: PageController(initialPage: initialIndex),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          final tag = tagBuilder(index);
          final metadata = metadataBuilder(index);

          return Stack(
            children: [
              Center(
                child: Hero(
                  tag: tag,
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4.0,
                    child: fileExistenceCheck != null
                        ? FutureBuilder<bool>(
                      future: fileExistenceCheck(index),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError || !(snapshot.data ?? false)) {
                          return const Center(child: Icon(Icons.broken_image, color: Colors.red));
                        }
                        return imageBuilder(index);
                      },
                    )
                        : imageBuilder(index),
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
  );
}

String _parseMetadataFromFileName(String fileName) {
  try {
    final name = fileName.replaceAll('.jpg', '');
    final parts = name.split('_');
    if (parts.length < 4) return '';

    final date = parts[0]; // YYYY-MM-DD
    final time = parts[1]; // HHMMSS or millis
    final plate = parts[2]; // 차량번호
    final user = parts.sublist(3).join('_');

    final timeText = time.length == 6
        ? '${time.substring(0, 2)}:${time.substring(2, 4)}:${time.substring(4, 6)}'
        : (() {
      final millis = int.tryParse(time);
      if (millis == null) return '';
      final dt = DateTime.fromMillisecondsSinceEpoch(millis);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
    })();

    return timeText.isEmpty ? '' : '촬영일: $date $timeText\n차량번호: $plate\n촬영자: $user';
  } catch (_) {
    return '';
  }
}
