import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../utils/input_camera_fullscreen_viewer.dart';
import '../input_plate_service.dart';

class InputPhotoSection extends StatelessWidget {
  final List<XFile> capturedImages;
  final String plateNumber;

  const InputPhotoSection({
    super.key,
    required this.capturedImages,
    required this.plateNumber,
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
                onTap: () => inputshowFullScreenImageViewer(context, capturedImages, index),
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Hero(
                    tag: imageFile.path,
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
              );
            },
          ),
        ),
        const SizedBox(height: 12.0),
        Center(
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black,
                backgroundColor: Colors.white,
                side: const BorderSide(color: Colors.black),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
              ),
              onPressed: () {
                showGeneralDialog(
                  context: context,
                  barrierDismissible: true,
                  barrierLabel: "사진 불러오기",
                  transitionDuration: const Duration(milliseconds: 300),
                  pageBuilder: (context, animation, secondaryAnimation) {
                    return Scaffold(
                      backgroundColor: Colors.white,
                      appBar: AppBar(
                        centerTitle: true,
                        title: const Text('저장된 사진 목록'),
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        elevation: 1,
                      ),
                      body: FutureBuilder<List<String>>(
                        future: InputPlateService.listPlateImages(
                          context: context,
                          plateNumber: plateNumber,
                        ),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }

                          if (snapshot.hasError) {
                            return const Center(child: Text('이미지 불러오기 실패'));
                          }

                          final urls = snapshot.data ?? [];

                          if (urls.isEmpty) {
                            return const Center(child: Text('GCS에 저장된 이미지가 없습니다.'));
                          }

                          return ListView.builder(
                            itemCount: urls.length,
                            itemBuilder: (context, index) {
                              final url = urls[index];
                              final segments = url.split('/').last.split('_');

                              final date = segments.length > 0 ? segments[0] : '날짜 없음';
                              final number = segments.length > 2 ? segments[2] : '번호판 없음';
                              final userWithExt = segments.length > 3 ? segments[3] : '미상';
                              final user = userWithExt.replaceAll('.jpg', '');

                              return GestureDetector(
                                onTap: () => showFullScreenImageViewerFromUrls(context, urls, index),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
                                  child: Row(
                                    children: [
                                      // 썸네일 2:8 비율
                                      Container(
                                        width: MediaQuery.of(context).size.width * 0.2,
                                        height: 80,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: Colors.grey.shade300),
                                        ),
                                        clipBehavior: Clip.hardEdge,
                                        child: Image.network(
                                          url,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                          const Icon(Icons.broken_image, color: Colors.red),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('📅 $date', style: const TextStyle(fontSize: 14)),
                                            Text('🚘 $number', style: const TextStyle(fontSize: 14)),
                                            Text('👤 $user', style: const TextStyle(fontSize: 14)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    );
                  },
                );
              },
              child: const Text('사진 불러오기'),
            ),
          ),
        ),
      ],
    );
  }
}
