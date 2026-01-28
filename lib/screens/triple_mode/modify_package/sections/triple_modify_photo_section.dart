import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../utils/triple_modify_camera_fullscreen_viewer.dart';
import '../utils/triple_modify_plate_service.dart';

class TripleModifyPhotoSection extends StatelessWidget {
  final List<XFile> capturedImages;
  final List<String> imageUrls;
  final String plateNumber;

  const TripleModifyPhotoSection({
    super.key,
    required this.capturedImages,
    required this.imageUrls,
    required this.plateNumber,
  });

  String _twoDigits(int v) => v.toString().padLeft(2, '0');

  String _utcYearMonth(DateTime utcNow) {
    return '${utcNow.year.toString().padLeft(4, '0')}-${_twoDigits(utcNow.month)}';
  }

  /// 최근 N개월(UTC) yyyy-MM 리스트 생성 (현재월 포함)
  List<String> _recentUtcYearMonths({int count = 12}) {
    final nowUtc = DateTime.now().toUtc();
    final result = <String>[];
    for (int i = 0; i < count; i++) {
      final dt = DateTime.utc(nowUtc.year, nowUtc.month - i, 1);
      result.add(_utcYearMonth(dt));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final totalItems = [...imageUrls, ...capturedImages.map((e) => e.path)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '촬영 사진',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
            color: cs.onSurface,
          ) ??
              TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: cs.onSurface,
              ),
        ),
        const SizedBox(height: 8.0),
        SizedBox(
          height: 100,
          child: totalItems.isEmpty
              ? Text(
            '촬영된 사진 없음',
            style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700),
          )
              : ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: totalItems.length,
            itemBuilder: (context, index) {
              final isUrl = index < imageUrls.length;
              final tag = isUrl ? imageUrls[index] : capturedImages[index - imageUrls.length].path;

              return GestureDetector(
                onTap: () => tripleModifyshowFullScreenImageViewer(
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
                      errorBuilder: (_, __, ___) =>
                          Icon(Icons.broken_image, color: cs.error),
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
                          return SizedBox(
                            width: 100,
                            height: 100,
                            child: Center(child: Icon(Icons.broken_image, color: cs.error)),
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
                foregroundColor: cs.onSurface,
                backgroundColor: cs.surface,
                side: BorderSide(color: cs.outlineVariant.withOpacity(0.85)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              ).copyWith(
                overlayColor: MaterialStateProperty.resolveWith<Color?>(
                      (states) => states.contains(MaterialState.pressed)
                      ? cs.outlineVariant.withOpacity(0.12)
                      : null,
                ),
              ),
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) {
                    final yearMonths = _recentUtcYearMonths(count: 12);
                    final defaultYm = _utcYearMonth(DateTime.now().toUtc());

                    String selectedYearMonth = defaultYm;
                    Future<List<String>> future = TripleModifyPlateService.listPlateImages(
                      context: context,
                      plateNumber: plateNumber,
                      yearMonth: selectedYearMonth,
                    );

                    return DraggableScrollableSheet(
                      initialChildSize: 0.7,
                      minChildSize: 0.4,
                      maxChildSize: 0.95,
                      builder: (context, scrollController) {
                        final csModal = Theme.of(context).colorScheme;

                        return SafeArea(
                          child: Material(
                            color: csModal.surface,
                            surfaceTintColor: Colors.transparent,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: StatefulBuilder(
                                builder: (context, setModalState) {
                                  return Column(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 4,
                                        margin: const EdgeInsets.only(bottom: 16),
                                        decoration: BoxDecoration(
                                          color: csModal.outlineVariant.withOpacity(0.85),
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                      ),
                                      Text(
                                        '저장된 사진 목록',
                                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w900,
                                          color: csModal.onSurface,
                                        ) ??
                                            TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w900,
                                              color: csModal.onSurface,
                                            ),
                                      ),
                                      const SizedBox(height: 12),

                                      // ✅ 월 선택(UTC 기준)
                                      Row(
                                        children: [
                                          Text(
                                            '월(UTC): ',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w800,
                                              color: csModal.onSurface,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12),
                                              decoration: BoxDecoration(
                                                border: Border.all(color: csModal.outlineVariant.withOpacity(0.85)),
                                                borderRadius: BorderRadius.circular(8),
                                                color: csModal.surface,
                                              ),
                                              child: DropdownButtonHideUnderline(
                                                child: DropdownButton<String>(
                                                  value: selectedYearMonth,
                                                  isExpanded: true,
                                                  icon: Icon(Icons.expand_more, color: csModal.onSurfaceVariant),
                                                  items: yearMonths
                                                      .map(
                                                        (ym) => DropdownMenuItem<String>(
                                                      value: ym,
                                                      child: Text(
                                                        ym,
                                                        style: TextStyle(
                                                          color: csModal.onSurface,
                                                          fontWeight: FontWeight.w700,
                                                        ),
                                                      ),
                                                    ),
                                                  )
                                                      .toList(),
                                                  onChanged: (value) {
                                                    if (value == null) return;
                                                    setModalState(() {
                                                      selectedYearMonth = value;
                                                      future = TripleModifyPlateService.listPlateImages(
                                                        context: context,
                                                        plateNumber: plateNumber,
                                                        yearMonth: selectedYearMonth,
                                                      );
                                                    });
                                                  },
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 16),

                                      Expanded(
                                        child: FutureBuilder<List<String>>(
                                          future: future,
                                          builder: (context, snapshot) {
                                            if (snapshot.connectionState == ConnectionState.waiting) {
                                              return const Center(child: CircularProgressIndicator());
                                            }
                                            if (snapshot.hasError) {
                                              return Text(
                                                '이미지 불러오기 실패',
                                                style: TextStyle(color: csModal.error, fontWeight: FontWeight.w800),
                                              );
                                            }
                                            final urls = snapshot.data ?? [];
                                            if (urls.isEmpty) {
                                              return Text(
                                                'DB에 저장된 이미지가 없습니다.',
                                                style: TextStyle(color: csModal.onSurfaceVariant, fontWeight: FontWeight.w700),
                                              );
                                            }

                                            return ListView.builder(
                                              controller: scrollController,
                                              itemCount: urls.length,
                                              itemBuilder: (context, index) {
                                                final url = urls[index];

                                                final fileName = url.split('/').last;
                                                final segments = fileName.split('_');

                                                final date = segments.isNotEmpty ? segments[0] : '날짜 없음';
                                                final number = segments.length > 2 ? segments[2] : '번호판 없음';
                                                final userWithExt = segments.length > 3 ? segments[3] : '미상';
                                                final user = userWithExt.replaceAll('.jpg', '');

                                                return GestureDetector(
                                                  onTap: () => tripleModifyshowFullScreenImageViewer(
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
                                                            border: Border.all(color: csModal.outlineVariant.withOpacity(0.85)),
                                                          ),
                                                          clipBehavior: Clip.hardEdge,
                                                          child: Image.network(
                                                            url,
                                                            fit: BoxFit.cover,
                                                            errorBuilder: (_, __, ___) => Icon(Icons.broken_image, color: csModal.error),
                                                          ),
                                                        ),
                                                        const SizedBox(width: 12),
                                                        Expanded(
                                                          child: Column(
                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                            children: [
                                                              Text('📅 $date', style: TextStyle(fontSize: 14, color: csModal.onSurface, fontWeight: FontWeight.w700)),
                                                              Text('🚘 $number', style: TextStyle(fontSize: 14, color: csModal.onSurface, fontWeight: FontWeight.w700)),
                                                              Text('👤 $user', style: TextStyle(fontSize: 14, color: csModal.onSurfaceVariant, fontWeight: FontWeight.w600)),
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
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
              child: const Text(
                '사진 불러오기',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
