import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
void showFullScreenImageViewer(BuildContext context, List<XFile> images, int initialIndex) {
  showDialog(
    context: context,
    builder: (_) {
      return Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
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
                      child: Image.file(
                        File(image.path),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                );
              },
            ),
            Positioned(
              top: 30,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      );
    },
  );
}
