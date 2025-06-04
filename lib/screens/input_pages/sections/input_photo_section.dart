import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../utils/input_camera_fullscreen_viewer.dart';
import '../input_plate_service.dart'; // 서비스 클래스 임포트 필요

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
              onPressed: () async {
                showDialog(
                  context: context,
                  builder: (context) => FutureBuilder<List<String>>(
                    future: InputPlateService.listPlateImages(
                      context: context,
                      plateNumber: plateNumber,
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const AlertDialog(
                          content: SizedBox(
                            height: 100,
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        );
                      }

                      if (snapshot.hasError) {
                        return AlertDialog(
                          title: const Text('에러'),
                          content: const Text('이미지 불러오기 실패'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('닫기'),
                            )
                          ],
                        );
                      }

                      final urls = snapshot.data ?? [];

                      if (urls.isEmpty) {
                        return AlertDialog(
                          title: const Text('사진 없음'),
                          content: const Text('GCS에 저장된 이미지가 없습니다.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('닫기'),
                            )
                          ],
                        );
                      }

                      return AlertDialog(
                        title: const Text('저장된 사진 목록'),
                        content: SizedBox(
                          width: double.maxFinite,
                          height: 300,
                          child: ListView.builder(
                            itemCount: urls.length,
                            itemBuilder: (context, index) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4.0),
                                child: GestureDetector(
                                  onTap: () => showFullScreenImageViewerFromUrls(
                                    context,
                                    urls,
                                    index,
                                  ),
                                  child: Image.network(
                                    urls[index],
                                    height: 80,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('닫기'),
                          ),
                        ],
                      );
                    },
                  ),
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
