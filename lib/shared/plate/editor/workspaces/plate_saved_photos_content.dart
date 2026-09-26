import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../widgets/plate_editor_workspace_switcher.dart';
import 'plate_image_viewer.dart';

typedef PlateSavedPhotoLoader = Future<List<String>> Function(
  BuildContext context,
  String yearMonth,
);

class PlateSavedPhotosContent extends StatefulWidget {
  const PlateSavedPhotosContent({
    super.key,
    required this.plateNumber,
    required this.diagnosticSource,
    required this.loadImages,
    required this.onBack,
    this.onDebug,
    this.trace,
  });

  final String plateNumber;
  final String diagnosticSource;
  final PlateSavedPhotoLoader loadImages;
  final VoidCallback onBack;
  final ValueChanged<String>? onDebug;
  final DeveloperOperationTrace? trace;

  @override
  State<PlateSavedPhotosContent> createState() =>
      _PlateSavedPhotosContentState();
}

class _PlateSavedPhotosContentState extends State<PlateSavedPhotosContent> {
  late final List<String> _yearMonths;
  late int _monthIndex;
  late Future<List<String>> _future;
  List<String> _previewUrls = const <String>[];
  int _previewIndex = 0;
  bool _previewing = false;
  int _loadCount = 0;
  int _lastResultCount = 0;
  DateTime? _lastLoadStartedAt;
  DateTime? _lastLoadCompletedAt;
  String? _lastError;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _debug(
        'saved_photos=open source=${widget.diagnosticSource} plate=${widget.plateNumber} yearMonth=$_selectedYearMonth',
      );
    });
  }

  @override
  void dispose() {
    _debug(
      'saved_photos=close source=${widget.diagnosticSource} plate=${widget.plateNumber} yearMonth=$_selectedYearMonth previewing=$_previewing loadCount=$_loadCount lastResultCount=$_lastResultCount',
    );
    super.dispose();
  }

  void _debug(String message) {
    final normalized = message.trim();
    if (normalized.isEmpty) return;
    final logger = widget.onDebug;
    if (logger != null) {
      logger(normalized);
      return;
    }
    final trace = widget.trace;
    if (trace != null) {
      trace.log(normalized);
      return;
    }
    debugPrint('[PlateSavedPhotosContent] $normalized');
  }

  Future<List<String>> _load(String yearMonth) async {
    final startedAt = DateTime.now();
    _loadCount++;
    _lastLoadStartedAt = startedAt;
    _lastError = null;
    _debug(
      'saved_photos=load_start source=${widget.diagnosticSource} plate=${widget.plateNumber} yearMonth=$yearMonth loadCount=$_loadCount',
    );
    try {
      final urls = await widget.loadImages(context, yearMonth);
      _lastResultCount = urls.length;
      _lastLoadCompletedAt = DateTime.now();
      _debug(
        'saved_photos=load_success source=${widget.diagnosticSource} plate=${widget.plateNumber} yearMonth=$yearMonth count=${urls.length} loadCount=$_loadCount elapsedMs=${_lastLoadCompletedAt!.difference(startedAt).inMilliseconds}',
      );
      return urls;
    } catch (error, stackTrace) {
      _lastResultCount = 0;
      _lastLoadCompletedAt = DateTime.now();
      _lastError = error.toString();
      _debug(
        'saved_photos=load_failed source=${widget.diagnosticSource} plate=${widget.plateNumber} yearMonth=$yearMonth loadCount=$_loadCount elapsedMs=${_lastLoadCompletedAt!.difference(startedAt).inMilliseconds} error=$error',
      );
      _debug('saved_photos=stack_trace\n$stackTrace');
      rethrow;
    }
  }

  void _stepMonth(int delta) {
    final next = (_monthIndex + delta).clamp(0, _yearMonths.length - 1).toInt();
    if (next == _monthIndex) return;
    final previous = _selectedYearMonth;
    setState(() {
      _previewing = false;
      _previewUrls = const <String>[];
      _monthIndex = next;
      _future = _load(_selectedYearMonth);
    });
    _debug(
      'saved_photos=month_changed source=${widget.diagnosticSource} previous=$previous current=$_selectedYearMonth',
    );
  }

  void _retry() {
    _debug(
      'saved_photos=retry source=${widget.diagnosticSource} yearMonth=$_selectedYearMonth',
    );
    setState(() {
      _future = _load(_selectedYearMonth);
    });
  }

  void _openPreview(List<String> urls, int index) {
    if (urls.isEmpty) return;
    final safeIndex = index.clamp(0, urls.length - 1).toInt();
    _debug(
      'saved_photos=preview_open source=${widget.diagnosticSource} yearMonth=$_selectedYearMonth index=$safeIndex count=${urls.length}',
    );
    setState(() {
      _previewUrls = List<String>.from(urls);
      _previewIndex = safeIndex;
      _previewing = true;
    });
  }

  void _closePreview() {
    _debug(
      'saved_photos=preview_close source=${widget.diagnosticSource} yearMonth=$_selectedYearMonth index=$_previewIndex',
    );
    setState(() => _previewing = false);
  }

  Future<void> _showDeveloperStatus() async {
    final trace = widget.trace;
    if (trace == null || !trace.developerMode || !mounted) return;
    final description = <String>[
      'source=${widget.diagnosticSource}',
      'plate=${widget.plateNumber}',
      'yearMonth=$_selectedYearMonth',
      'previewing=$_previewing',
      'previewIndex=$_previewIndex',
      'previewCount=${_previewUrls.length}',
      'loadCount=$_loadCount',
      'lastResultCount=$_lastResultCount',
      'lastLoadStartedAt=${_lastLoadStartedAt?.toIso8601String() ?? '-'}',
      'lastLoadCompletedAt=${_lastLoadCompletedAt?.toIso8601String() ?? '-'}',
      'lastError=${_lastError ?? '-'}',
    ].join('\n');
    _debug(
      'saved_photos=developer_status_open source=${widget.diagnosticSource} plate=${widget.plateNumber} yearMonth=$_selectedYearMonth failure=${_lastError != null}',
    );
    await trace.showSnapshotStatusDialog(
      context,
      title: '저장 사진 디버그 상태',
      description: description,
      failure: _lastError != null,
    );
  }

  Widget _buildHeaderIcon({
    required BuildContext context,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    final tokens = CommonUiTheme.of(context);
    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          foregroundColor: tokens.iconPrimary,
          disabledForegroundColor: tokens.iconDisabled,
          backgroundColor: tokens.surfaceOverlay,
          disabledBackgroundColor: tokens.surfaceDisabled,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CommonUiShapes.control),
            side: BorderSide(color: tokens.borderSubtle),
          ),
        ),
        icon: Icon(icon, size: 19),
      ),
    );
  }

  Widget _animatedSwap({
    required Widget child,
    required Duration duration,
    double beginScale = .97,
  }) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: CommonUiMotion.enter,
      switchOutCurve: CommonUiMotion.exit,
      transitionBuilder: (child, animation) {
        final scale = Tween<double>(begin: beginScale, end: 1).animate(
          CurvedAnimation(parent: animation, curve: CommonUiMotion.enter),
        );
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: scale, child: child),
        );
      },
      child: child,
    );
  }

  Widget _buildLoadingGrid(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return GridView.builder(
      key: const ValueKey<String>('saved_photo_loading'),
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 14),
      itemCount: 6,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, index) {
        final tile = Container(
          decoration: BoxDecoration(
            color: tokens.surfaceOverlay,
            borderRadius: BorderRadius.circular(CommonUiShapes.control),
            border: Border.all(color: tokens.borderSubtle),
          ),
        );
        if (reduceMotion) return tile;
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: .55, end: 1),
          duration: Duration(milliseconds: 180 + index * 18),
          curve: CommonUiMotion.enter,
          builder: (context, value, child) {
            return Opacity(opacity: value, child: child);
          },
          child: tile,
        );
      },
    );
  }

  Widget _buildPhotoGrid(BuildContext context, List<String> urls) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return GridView.builder(
      key: ValueKey<String>('saved_photo_grid_$_selectedYearMonth'),
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 14),
      itemCount: urls.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, index) {
        final url = urls[index];
        final tile = Material(
          color: tokens.surfaceOverlay,
          borderRadius: BorderRadius.circular(CommonUiShapes.control),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _openPreview(urls, index),
            child: Image.network(
              url,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: tokens.accent,
                  ),
                );
              },
              errorBuilder: (_, __, ___) => Center(
                child: Icon(
                  Icons.broken_image_rounded,
                  color: tokens.danger,
                ),
              ),
            ),
          ),
        );
        if (reduceMotion) return tile;
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: .94, end: 1),
          duration: Duration(
            milliseconds: 180 + index.clamp(0, 6).toInt() * 18,
          ),
          curve: CommonUiMotion.enter,
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: Transform.scale(scale: value, child: child),
            );
          },
          child: tile,
        );
      },
    );
  }

  Widget _buildPhotoList(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final trace = widget.trace;

    return Container(
      key: const ValueKey<String>('saved_photo_list'),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(CommonUiShapes.button),
        border: Border.all(color: tokens.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                _buildHeaderIcon(
                  context: context,
                  icon: Icons.arrow_back_rounded,
                  onPressed: widget.onBack,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '저장된 사진',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: tokens.textPrimary,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.plateNumber,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: tokens.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ),
                if (trace != null && trace.developerMode) ...[
                  const SizedBox(width: 7),
                  _buildHeaderIcon(
                    context: context,
                    icon: Icons.bug_report_rounded,
                    onPressed: () => unawaited(_showDeveloperStatus()),
                  ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: tokens.borderSubtle),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildHeaderIcon(
                  context: context,
                  icon: Icons.chevron_left_rounded,
                  onPressed: _monthIndex > 0 ? () => _stepMonth(-1) : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Center(
                    child: _animatedSwap(
                      duration: reduceMotion
                          ? Duration.zero
                          : CommonUiMotion.selection,
                      beginScale: .96,
                      child: Text(
                        _selectedYearMonth,
                        key: ValueKey<String>(_selectedYearMonth),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: tokens.textPrimary,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _buildHeaderIcon(
                  context: context,
                  icon: Icons.chevron_right_rounded,
                  onPressed: _monthIndex < _yearMonths.length - 1
                      ? () => _stepMonth(1)
                      : null,
                ),
              ],
            ),
          ),
          Expanded(
            child: _animatedSwap(
              duration:
                  reduceMotion ? Duration.zero : CommonUiMotion.component,
              child: FutureBuilder<List<String>>(
                key: ValueKey<String>('saved_photo_future_$_selectedYearMonth'),
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return _buildLoadingGrid(context);
                  }
                  if (snapshot.hasError) {
                    return Center(
                      key: ValueKey<String>(
                        'saved_photo_error_$_selectedYearMonth',
                      ),
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
                              onPressed: _retry,
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  final urls = snapshot.data ?? const <String>[];
                  if (urls.isEmpty) {
                    return Center(
                      key: ValueKey<String>(
                        'saved_photo_empty_$_selectedYearMonth',
                      ),
                      child: Text(
                        '저장된 이미지가 없습니다.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: tokens.textSecondary,
                            ),
                      ),
                    );
                  }
                  return _buildPhotoGrid(context, urls);
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
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final trace = widget.trace;
    final child = Container(
      key: const ValueKey<String>('saved_photo_preview'),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(CommonUiShapes.button),
        border: Border.all(color: tokens.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlateEmbeddedImageViewerContent(
            images: List<dynamic>.from(_previewUrls),
            initialIndex: _previewIndex,
            onBack: _closePreview,
            onPageChanged: (index) {
              _previewIndex = index;
              _debug(
                'saved_photos=preview_page source=${widget.diagnosticSource} index=$index count=${_previewUrls.length}',
              );
            },
            onDebug: _debug,
          ),
          if (trace != null && trace.developerMode)
            Positioned(
              top: 8,
              right: 8,
              child: _buildHeaderIcon(
                context: context,
                icon: Icons.bug_report_rounded,
                onPressed: () => unawaited(_showDeveloperStatus()),
              ),
            ),
        ],
      ),
    );
    if (reduceMotion) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: .93, end: 1),
      duration: CommonUiMotion.component,
      curve: CommonUiMotion.standard,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.scale(scale: value, child: child),
        );
      },
      child: child,
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
