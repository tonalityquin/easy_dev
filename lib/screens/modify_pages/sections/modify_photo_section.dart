import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../utils/modify_camera_fullscreen_viewer.dart';
import '../modify_plate_service.dart';

class ModifyPhotoSection extends StatelessWidget {
  final List<XFile> capturedImages;
  final List<String> imageUrls;
  final String plateNumber;

  const ModifyPhotoSection({
    super.key,
    required this.capturedImages,
    required this.imageUrls,
    required this.plateNumber,
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
                      onTap: () => modifyshowFullScreenImageViewer(
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
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) {
                    return DraggableScrollableSheet(
                      initialChildSize: 0.7,
                      minChildSize: 0.4,
                      maxChildSize: 0.95,
                      builder: (context, scrollController) {
                        return SafeArea(
                          child: Material(
                            color: Colors.white,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 4,
                                    margin: const EdgeInsets.only(bottom: 16),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade300,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const Text(
                                    '저장된 사진 목록',
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 16),
                                  Expanded(
                                    child: FutureBuilder<List<String>>(
                                      future: ModifyPlateService.listPlateImages(
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
                                          controller: scrollController,
                                          itemCount: urls.length,
                                          itemBuilder: (context, index) {
                                            final url = urls[index];
                                            final segments = url.split('/').last.split('_');
                                            final date = segments.length > 0 ? segments[0] : '날짜 없음';
                                            final number = segments.length > 2 ? segments[2] : '번호판 없음';
                                            final userWithExt = segments.length > 3 ? segments[3] : '미상';
                                            final user = userWithExt.replaceAll('.jpg', '');

                                            return GestureDetector(
                                              onTap: () => modifyshowFullScreenImageViewer(
                                                context,
                                                urls,
                                                index,
                                                isUrlList: true,
                                              ),
                                              child: Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
                                                child: Row(
                                                  children: [
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
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
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
