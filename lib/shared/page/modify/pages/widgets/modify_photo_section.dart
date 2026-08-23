import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../../design_system/common_ui/common_ui_side_dock_frame.dart';
import '../../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../plate/editor/workspaces/plate_image_viewer.dart';
import '../../application/modify_plate_service.dart';
import '../../../../plate/editor/widgets/plate_editor_workspace_switcher.dart';

class ModifyPhotoSection extends StatelessWidget {
  const ModifyPhotoSection({
    super.key,
    required this.capturedImages,
    required this.imageUrls,
    this.onPreviewRequested,
  });

  final List<XFile> capturedImages;
  final List<String> imageUrls;
  final void Function(List<dynamic> images, int index)? onPreviewRequested;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final items = <dynamic>[...imageUrls, ...capturedImages];

    return CommonSideDockSection(
      order: 2,
      title: '촬영 사진',
      subtitle: '등록 ${imageUrls.length} · 신규 ${capturedImages.length}',
      child: SizedBox(
        height: 92,
        child: items.isEmpty
            ? Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tokens.surfaceOverlay,
                  borderRadius: BorderRadius.circular(CommonUiShapes.control),
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
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final isUrl = item is String;
                  final path = isUrl ? item : (item as XFile).path;
                  final child = ClipRRect(
                    borderRadius: BorderRadius.circular(CommonUiShapes.control),
                    child: Container(
                      width: 92,
                      decoration: BoxDecoration(
                        color: tokens.surfaceOverlay,
                        border: Border.all(color: tokens.borderSubtle),
                      ),
                      child: isUrl
                          ? Image.network(
                              path,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Center(
                                child: Icon(
                                  Icons.broken_image_rounded,
                                  color: tokens.danger,
                                ),
                              ),
                            )
                          : FutureBuilder<bool>(
                              future: File(path).exists(),
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
                                if (snapshot.data != true) {
                                  return Center(
                                    child: Icon(
                                      Icons.broken_image_rounded,
                                      color: tokens.danger,
                                    ),
                                  );
                                }
                                return Image.file(
                                  File(path),
                                  fit: BoxFit.cover,
                                  cacheWidth: 220,
                                  filterQuality: FilterQuality.low,
                                );
                              },
                            ),
                    ),
                  );
                  if (onPreviewRequested == null) return child;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onPreviewRequested!(items, index),
                    child: child,
                  );
                },
              ),
      ),
    );
  }
}

class ModifySavedPhotosContent extends StatefulWidget {
  const ModifySavedPhotosContent({
    super.key,
    required this.plateNumber,
    required this.onBack,
    this.onDebug,
  });

  final String plateNumber;
  final VoidCallback onBack;
  final ValueChanged<String>? onDebug;

  @override
  State<ModifySavedPhotosContent> createState() =>
      _ModifySavedPhotosContentState();
}

class _ModifySavedPhotosContentState extends State<ModifySavedPhotosContent> {
  late final List<String> _yearMonths;
  late int _monthIndex;
  late Future<List<String>> _future;
  List<String> _previewUrls = const <String>[];
  int _previewIndex = 0;
  bool _previewing = false;

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

  String get _selectedYearMonth => _yearMonths[_monthIndex];

  @override
  void initState() {
    super.initState();
    _yearMonths = _recentUtcYearMonths();
    _monthIndex = 0;
    _future = _load(_selectedYearMonth);
  }

  Future<List<String>> _load(String yearMonth) async {
    widget.onDebug?.call(
      'saved_photos=load_start plate=${widget.plateNumber} yearMonth=$yearMonth',
    );
    try {
      final urls = await ModifyPlateService.listPlateImages(
        context: context,
        plateNumber: widget.plateNumber,
        yearMonth: yearMonth,
      );
      widget.onDebug?.call(
        'saved_photos=load_success yearMonth=$yearMonth count=${urls.length}',
      );
      return urls;
    } catch (error, stackTrace) {
      widget.onDebug?.call(
        'saved_photos=load_failed yearMonth=$yearMonth error=$error',
      );
      debugPrint('[ModifySavedPhotosContent] error=$error\n$stackTrace');
      rethrow;
    }
  }

  void _stepMonth(int delta) {
    final next = (_monthIndex + delta).clamp(0, _yearMonths.length - 1).toInt();
    if (next == _monthIndex) return;
    setState(() {
      _previewing = false;
      _previewUrls = const <String>[];
      _monthIndex = next;
      _future = _load(_selectedYearMonth);
    });
  }

  void _openPreview(List<String> urls, int index) {
    if (urls.isEmpty) return;
    final safeIndex = index.clamp(0, urls.length - 1).toInt();
    widget.onDebug?.call(
      'saved_photos=preview_open index=$safeIndex count=${urls.length}',
    );
    setState(() {
      _previewUrls = List<String>.from(urls);
      _previewIndex = safeIndex;
      _previewing = true;
    });
  }

  void _closePreview() {
    widget.onDebug?.call('saved_photos=preview_close');
    setState(() => _previewing = false);
  }

  Widget _buildPhotoList(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Container(
      key: const ValueKey<String>('saved_photo_list'),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Row(
              children: [
                CommonIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: '촬영으로',
                  size: 36,
                  iconSize: 18,
                  onPressed: widget.onBack,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    '저장된 사진',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: tokens.borderSubtle),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CommonIconButton(
                  icon: Icons.chevron_left_rounded,
                  tooltip: '최근 월',
                  size: 34,
                  iconSize: 19,
                  onPressed: _monthIndex > 0 ? () => _stepMonth(-1) : null,
                ),
                const SizedBox(width: 8),
                AnimatedSwitcher(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 150),
                  child: Text(
                    _selectedYearMonth,
                    key: ValueKey<String>(_selectedYearMonth),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                const SizedBox(width: 8),
                CommonIconButton(
                  icon: Icons.chevron_right_rounded,
                  tooltip: '이전 월',
                  size: 34,
                  iconSize: 19,
                  onPressed: _monthIndex < _yearMonths.length - 1
                      ? () => _stepMonth(1)
                      : null,
                ),
              ],
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 170),
              child: FutureBuilder<List<String>>(
                key: ValueKey<String>(_selectedYearMonth),
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(10, 4, 10, 14),
                      itemCount: 6,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 1,
                      ),
                      itemBuilder: (_, __) => Container(
                        decoration: BoxDecoration(
                          color: tokens.surfaceOverlay,
                          borderRadius:
                              BorderRadius.circular(CommonUiShapes.control),
                          border: Border.all(color: tokens.borderSubtle),
                        ),
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: tokens.danger,
                              size: 34,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '사진 목록을 불러오지 못했습니다.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: tokens.textPrimary,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 12),
                            CommonButton(
                              label: '다시 시도',
                              icon: Icons.refresh_rounded,
                              onPressed: () => setState(() {
                                _future = _load(_selectedYearMonth);
                              }),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  final urls = snapshot.data ?? const <String>[];
                  if (urls.isEmpty) {
                    return Center(
                      child: Text(
                        '저장된 이미지가 없습니다.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: tokens.textSecondary,
                            ),
                      ),
                    );
                  }
                  return GridView.builder(
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 14),
                    itemCount: urls.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 1,
                    ),
                    itemBuilder: (context, index) {
                      final url = urls[index];
                      return Material(
                        color: tokens.surfaceOverlay,
                        borderRadius:
                            BorderRadius.circular(CommonUiShapes.control),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => _openPreview(urls, index),
                          child: Image.network(
                            url,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Center(
                              child: Icon(
                                Icons.broken_image_rounded,
                                color: tokens.danger,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final tokens = CommonUiTheme.of(context);
    return Container(
      key: const ValueKey<String>('saved_photo_preview'),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: .93, end: 1),
        duration: const Duration(milliseconds: 230),
        curve: Curves.easeInOutCubic,
        builder: (context, value, child) {
          final reduceMotion =
              MediaQuery.maybeOf(context)?.disableAnimations ?? false;
          return Opacity(
            opacity: reduceMotion ? 1 : value,
            child: Transform.scale(
              scale: reduceMotion ? 1 : value,
              child: child,
            ),
          );
        },
        child: PlateEmbeddedImageViewerContent(
          images: List<dynamic>.from(_previewUrls),
          initialIndex: _previewIndex,
          onBack: _closePreview,
          onPageChanged: (index) => _previewIndex = index,
          onDebug: widget.onDebug,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PlateEditorWorkspaceSwitcher(
      activeKey: _previewing ? 'saved_photo_preview' : 'saved_photo_list',
      activeOrder: _previewing ? 1 : 0,
      child: _previewing ? _buildPreview() : _buildPhotoList(context),
    );
  }
}
