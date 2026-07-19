import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../../../app/utils/status_dialog.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../application/input_camera_fullscreen_viewer.dart';
import '../../application/input_plate_service.dart';
import '../prompt_input_ui.dart';

class InputPhotoSection extends StatelessWidget {
  final List<XFile> capturedImages;
  final String plateNumber;

  const InputPhotoSection({
    super.key,
    required this.capturedImages,
    required this.plateNumber,
  });

  String _twoDigits(int value) => value.toString().padLeft(2, '0');

  String _utcYearMonth(DateTime utcNow) {
    return '${utcNow.year.toString().padLeft(4, '0')}-${_twoDigits(utcNow.month)}';
  }

  List<String> _recentUtcYearMonths({int count = 12}) {
    final nowUtc = DateTime.now().toUtc();
    return List<String>.generate(count, (index) {
      final date = DateTime.utc(nowUtc.year, nowUtc.month - index, 1);
      return _utcYearMonth(date);
    });
  }

  Future<void> _showSavedPhotos(BuildContext context) async {
    await showPromptOverlayBottomSheet<void>(
      context: context,
      useSafeArea: false,
      builder: (sheetContext) {
        final yearMonths = _recentUtcYearMonths();
        final defaultYearMonth = _utcYearMonth(DateTime.now().toUtc());
        var selectedYearMonth = defaultYearMonth;
        var loadFailureDialogShown = false;
        var future = InputPlateService.listPlateImages(
          context: sheetContext,
          plateNumber: plateNumber,
          yearMonth: selectedYearMonth,
        );

        return DraggableScrollableSheet(
          initialChildSize: .72,
          minChildSize: .45,
          maxChildSize: .95,
          builder: (sheetContext, scrollController) {
            return PromptSheetScaffold(
              title: '저장된 사진 목록',
              icon: Icons.photo_library_rounded,
              onClose: () => Navigator.of(sheetContext).pop(),
              body: StatefulBuilder(
                builder: (context, setModalState) {
                  final tokens = PromptUiTheme.of(context);
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: DropdownButtonFormField<String>(
                          value: selectedYearMonth,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: '조회 월',
                            prefixIcon: Icon(Icons.calendar_month_rounded),
                          ),
                          dropdownColor: tokens.surfaceRaised,
                          items: yearMonths
                              .map(
                                (value) => DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(value),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setModalState(() {
                              selectedYearMonth = value;
                              loadFailureDialogShown = false;
                              future = InputPlateService.listPlateImages(
                                context: context,
                                plateNumber: plateNumber,
                                yearMonth: selectedYearMonth,
                              );
                            });
                          },
                        ),
                      ),
                      Expanded(
                        child: FutureBuilder<List<String>>(
                          future: future,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return Center(
                                child: CircularProgressIndicator(
                                  color: tokens.accent,
                                ),
                              );
                            }
                            if (snapshot.hasError) {
                              if (!loadFailureDialogShown) {
                                loadFailureDialogShown = true;
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (context.mounted) {
                                    StatusDialog.showFailure(
                                      context,
                                      title: StatusDialog.photoLoadFailed,
                                      usePromptUi: true,
                                    );
                                  }
                                });
                              }
                              return Center(
                                child: Text(
                                  StatusDialog.photoLoadFailed,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(color: tokens.danger),
                                ),
                              );
                            }
                            final urls = snapshot.data ?? const <String>[];
                            if (urls.isEmpty) {
                              return Center(
                                child: Text(
                                  'DB에 저장된 이미지가 없습니다.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(color: tokens.textSecondary),
                                ),
                              );
                            }
                            return ListView.separated(
                              controller: scrollController,
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              itemCount: urls.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final url = urls[index];
                                final fileName = url.split('/').last;
                                final segments = fileName.split('_');
                                final date = segments.isNotEmpty
                                    ? segments[0]
                                    : '날짜 없음';
                                final number = segments.length > 2
                                    ? segments[2]
                                    : '번호판 없음';
                                final userWithExt = segments.length > 3
                                    ? segments[3]
                                    : '미상';
                                final user =
                                    userWithExt.replaceAll('.jpg', '');
                                return Material(
                                  color: tokens.surfaceOverlay,
                                  borderRadius: BorderRadius.circular(
                                    PromptUiShapes.control,
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    onTap: () =>
                                        showFullScreenImageViewerFromUrls(
                                      context,
                                      urls,
                                      index,
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: tokens.borderSubtle,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          PromptUiShapes.control,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              PromptUiShapes.control,
                                            ),
                                            child: SizedBox(
                                              width: 88,
                                              height: 72,
                                              child: Image.network(
                                                url,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) =>
                                                    Center(
                                                  child: Icon(
                                                    Icons.broken_image_rounded,
                                                    color: tokens.danger,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  date,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(
                                                        color:
                                                            tokens.textPrimary,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  number,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: tokens
                                                            .textSecondary,
                                                      ),
                                                ),
                                                Text(
                                                  user,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: tokens
                                                            .textSecondary,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Icon(
                                            Icons.open_in_full_rounded,
                                            color: tokens.iconSecondary,
                                          ),
                                        ],
                                      ),
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
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    return PromptAnimatedReveal(
      delay: const Duration(milliseconds: 80),
      child: PromptInputSectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PromptInputSectionTitle(
              icon: Icons.photo_camera_back_rounded,
              title: '촬영 사진',
              subtitle: '현장 사진을 확인하거나 서버 저장 사진을 불러옵니다.',
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 104,
              child: capturedImages.isEmpty
                  ? Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: tokens.surfaceOverlay,
                        borderRadius:
                            BorderRadius.circular(PromptUiShapes.control),
                        border: Border.all(color: tokens.borderSubtle),
                      ),
                      child: Text(
                        '촬영된 사진 없음',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: tokens.textSecondary,
                            ),
                      ),
                    )
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: capturedImages.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final imageFile = capturedImages[index];
                        return GestureDetector(
                          onTap: () => inputShowFullScreenImageViewer(
                            context,
                            capturedImages,
                            index,
                          ),
                          child: Hero(
                            tag: imageFile.path,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                PromptUiShapes.control,
                              ),
                              child: Container(
                                width: 104,
                                decoration: BoxDecoration(
                                  color: tokens.surfaceOverlay,
                                  border: Border.all(
                                    color: tokens.borderSubtle,
                                  ),
                                ),
                                child: FutureBuilder<bool>(
                                  future: File(imageFile.path).exists(),
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState !=
                                        ConnectionState.done) {
                                      return Center(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: tokens.accent,
                                        ),
                                      );
                                    }
                                    if (snapshot.hasError ||
                                        !(snapshot.data ?? false)) {
                                      return Center(
                                        child: Icon(
                                          Icons.broken_image_rounded,
                                          color: tokens.danger,
                                        ),
                                      );
                                    }
                                    return Image.file(
                                      File(imageFile.path),
                                      key: ValueKey(imageFile.path),
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
            const SizedBox(height: 12),
            PromptButton(
              label: '사진 불러오기',
              icon: Icons.cloud_download_rounded,
              variant: PromptButtonVariant.secondary,
              expand: true,
              onPressed: () => _showSavedPhotos(context),
            ),
          ],
        ),
      ),
    );
  }
}
