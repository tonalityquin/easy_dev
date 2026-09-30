import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../widgets/stored_plate_photo_fullscreen_viewer.dart';
import '../../widgets/stored_plate_photo_surfaces.dart';
import '../domain/stored_plate_photo.dart';
import '../widgets/plate_editor_workspace_switcher.dart';

typedef PlateSavedPhotoLoader = Future<List<StoredPlatePhoto>> Function(
  BuildContext context,
  String yearMonth,
);

enum _SavedPhotoView {
  list,
  thumbnailPreview,
}

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
  late Future<List<StoredPlatePhoto>> _future;
  List<StoredPlatePhoto> _photos = const <StoredPlatePhoto>[];
  DeveloperOperationTrace? _localTrace;
  bool _localTraceChecked = false;
  final List<String> _pendingDebugLines = <String>[];
  final Set<String> _thumbnailRequestPaths = <String>{};
  final Set<String> _displayRequestPaths = <String>{};
  final Set<String> _missingThumbnailPaths = <String>{};
  _SavedPhotoView _view = _SavedPhotoView.list;
  int _selectedIndex = 0;
  int _loadCount = 0;
  int _lastResultCount = 0;
  int _lastThumbnailCount = 0;
  int _lastMissingThumbnailCount = 0;
  DateTime? _lastLoadStartedAt;
  DateTime? _lastLoadCompletedAt;
  String? _lastError;
  bool _displayTransitionPending = false;
  int _monthTransitionDirection = 0;

  String _twoDigits(int value) => value.toString().padLeft(2, '0');

  String _yearMonth(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-${_twoDigits(value.month)}';
  }

  List<String> _recentYearMonths({int count = 12}) {
    final now = DateTime.now();
    return List<String>.generate(count, (index) {
      final date = DateTime(now.year, now.month - index, 1);
      return _yearMonth(date);
    });
  }

  String get _selectedYearMonth => _yearMonths[_monthIndex];

  DeveloperOperationTrace? get _effectiveTrace => widget.trace ?? _localTrace;

  @override
  void initState() {
    super.initState();
    _yearMonths = _recentYearMonths();
    _monthIndex = 0;
    _future = _load(_selectedYearMonth);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _debug(
        'saved_photos=open source=${widget.diagnosticSource} plate=${widget.plateNumber} yearMonth=$_selectedYearMonth',
      );
      if (widget.trace == null) {
        unawaited(_initializeLocalTrace());
      }
    });
  }

  @override
  void dispose() {
    _debug(
      'saved_photos=close source=${widget.diagnosticSource} plate=${widget.plateNumber} yearMonth=$_selectedYearMonth viewMode=${_view.name} loadCount=$_loadCount lastResultCount=$_lastResultCount thumbnailRequests=${_thumbnailRequestPaths.length} displayRequests=${_displayRequestPaths.length}',
    );
    super.dispose();
  }

  Future<void> _initializeLocalTrace() async {
    if (!mounted || widget.trace != null || _localTrace != null) return;
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '저장 사진',
      initialMessage:
          'saved_photos=trace_start source=${widget.diagnosticSource} plate=${widget.plateNumber}',
      useCommonUi: true,
      developerModeMessage: '',
      standardModeMessage: '',
      showDialogImmediately: false,
    );
    if (!mounted) return;
    _localTraceChecked = true;
    if (!trace.developerMode) {
      _pendingDebugLines.clear();
      return;
    }
    _localTrace = trace;
    final pending = List<String>.from(_pendingDebugLines);
    _pendingDebugLines.clear();
    for (final line in pending) {
      trace.log(line);
    }
    setState(() {});
  }

  void _debug(String message) {
    final normalized = message.trim();
    if (normalized.isEmpty) return;
    final logger = widget.onDebug;
    final providedTrace = widget.trace;
    if (providedTrace != null) {
      if (logger != null) {
        logger(normalized);
      } else {
        providedTrace.log(normalized);
      }
      return;
    }
    logger?.call(normalized);
    final localTrace = _localTrace;
    if (localTrace != null) {
      localTrace.log(normalized);
      return;
    }
    if (!_localTraceChecked) {
      _pendingDebugLines.add(normalized);
    }
    if (logger == null) {
      debugPrint('[PlateSavedPhotosContent] $normalized');
    }
  }

  Future<List<StoredPlatePhoto>> _load(String yearMonth) async {
    final startedAt = DateTime.now();
    _loadCount++;
    _lastLoadStartedAt = startedAt;
    _lastError = null;
    _debug(
      'saved_photos=load_start source=${widget.diagnosticSource} plate=${widget.plateNumber} yearMonth=$yearMonth loadCount=$_loadCount',
    );
    try {
      final loaded = await widget.loadImages(context, yearMonth);
      final photos = loaded
          .where((photo) => photo.displayUrl.trim().isNotEmpty)
          .toList(growable: false);
      _photos = photos;
      _lastResultCount = photos.length;
      _lastThumbnailCount = photos.where((photo) => photo.hasThumbnail).length;
      _lastMissingThumbnailCount = photos.length - _lastThumbnailCount;
      _lastLoadCompletedAt = DateTime.now();
      _debug(
        'saved_photos=load_success source=${widget.diagnosticSource} plate=${widget.plateNumber} yearMonth=$yearMonth count=${photos.length} thumbnails=$_lastThumbnailCount missingThumbnails=$_lastMissingThumbnailCount loadCount=$_loadCount elapsedMs=${_lastLoadCompletedAt!.difference(startedAt).inMilliseconds}',
      );
      return photos;
    } catch (error, stackTrace) {
      _photos = const <StoredPlatePhoto>[];
      _lastResultCount = 0;
      _lastThumbnailCount = 0;
      _lastMissingThumbnailCount = 0;
      _lastLoadCompletedAt = DateTime.now();
      _lastError = error.toString();
      _debug(
        'saved_photos=load_failed source=${widget.diagnosticSource} plate=${widget.plateNumber} yearMonth=$yearMonth loadCount=$_loadCount elapsedMs=${_lastLoadCompletedAt!.difference(startedAt).inMilliseconds} error=$error',
      );
      _debug('saved_photos=stack_trace\n$stackTrace');
      rethrow;
    }
  }

  void _changeMonthIndex(int nextIndex, String direction) {
    final next = nextIndex.clamp(0, _yearMonths.length - 1).toInt();
    if (next == _monthIndex) return;
    final previous = _selectedYearMonth;
    setState(() {
      _monthTransitionDirection = direction == 'older' ? -1 : 1;
      _view = _SavedPhotoView.list;
      _photos = const <StoredPlatePhoto>[];
      _monthIndex = next;
      _future = _load(_selectedYearMonth);
    });
    _debug(
      'saved_photos=month_changed source=${widget.diagnosticSource} direction=$direction previous=$previous current=$_selectedYearMonth',
    );
  }

  void _showOlderMonth() => _changeMonthIndex(_monthIndex + 1, 'older');

  void _showNewerMonth() => _changeMonthIndex(_monthIndex - 1, 'newer');

  void _retry() {
    _debug(
      'saved_photos=retry source=${widget.diagnosticSource} yearMonth=$_selectedYearMonth',
    );
    setState(() {
      _view = _SavedPhotoView.list;
      _future = _load(_selectedYearMonth);
    });
  }

  void _markThumbnailRequest(StoredPlatePhoto photo) {
    if (!mounted) return;
    final metadata = photo.metadata;
    final path = photo.thumbnailObjectPath;
    if (!photo.hasThumbnail || path == null || path.trim().isEmpty) {
      if (_missingThumbnailPaths.add(photo.displayObjectPath)) {
        _debug(
          'photo_asset=missing type=thumbnail source=${widget.diagnosticSource} displayObject=${photo.displayObjectPath} capturedDate=${metadata.capturedDate} capturedTime=${metadata.capturedTime} plate=${metadata.plateNumber} capturedBy=${metadata.capturedBy}',
        );
      }
      return;
    }
    if (_thumbnailRequestPaths.add(path)) {
      _debug(
        'photo_asset=request type=thumbnail action=list_or_preview source=${widget.diagnosticSource} object=$path capturedDate=${metadata.capturedDate} capturedTime=${metadata.capturedTime} plate=${metadata.plateNumber} capturedBy=${metadata.capturedBy}',
      );
    }
  }

  void _markDisplayRequest(StoredPlatePhoto photo) {
    if (!mounted) return;
    if (!_displayRequestPaths.add(photo.displayObjectPath)) return;
    final metadata = photo.metadata;
    _debug(
      'photo_asset=request type=display action=thumbnail_double_tap source=${widget.diagnosticSource} object=${photo.displayObjectPath} capturedDate=${metadata.capturedDate} capturedTime=${metadata.capturedTime} plate=${metadata.plateNumber} capturedBy=${metadata.capturedBy}',
    );
  }

  void _openThumbnailPreview(int index) {
    if (_photos.isEmpty) return;
    final safeIndex = index.clamp(0, _photos.length - 1).toInt();
    _selectedIndex = safeIndex;
    final photo = _photos[safeIndex];
    _debug(
      'stored_photos=thumbnail_preview_open source=${widget.diagnosticSource} yearMonth=$_selectedYearMonth index=$safeIndex count=${_photos.length} thumbnailObject=${photo.thumbnailObjectPath ?? '-'}',
    );
    setState(() => _view = _SavedPhotoView.thumbnailPreview);
  }

  void _closeThumbnailPreview() {
    _debug(
      'stored_photos=thumbnail_preview_close source=${widget.diagnosticSource} yearMonth=$_selectedYearMonth index=$_selectedIndex',
    );
    setState(() => _view = _SavedPhotoView.list);
  }

  Future<void> _openFullscreenDisplay(int index) async {
    if (_photos.isEmpty || _displayTransitionPending) return;
    final safeIndex = index.clamp(0, _photos.length - 1).toInt();
    _selectedIndex = safeIndex;
    final photo = _photos[safeIndex];
    _displayTransitionPending = true;
    _debug(
      'stored_photos=display_double_tap source=${widget.diagnosticSource} yearMonth=$_selectedYearMonth index=$safeIndex object=${photo.displayObjectPath}',
    );
    _debug(
      'stored_photos=display_open_requested trigger=thumbnail_double_tap source=${widget.diagnosticSource} yearMonth=$_selectedYearMonth index=$safeIndex object=${photo.displayObjectPath}',
    );
    _markDisplayRequest(photo);
    try {
      await showStoredPlatePhotoFullscreenViewer(
        context: context,
        photo: photo,
        diagnosticSource: widget.diagnosticSource,
        yearMonth: _selectedYearMonth,
        index: safeIndex,
        trace: _effectiveTrace,
        onDebug: _debug,
      );
      if (!mounted) return;
      _debug(
        'display_mode=closed source=${widget.diagnosticSource} yearMonth=$_selectedYearMonth index=$safeIndex',
      );
      _debug(
        'thumbnail_preview=restored source=${widget.diagnosticSource} yearMonth=$_selectedYearMonth index=$safeIndex',
      );
    } finally {
      _displayTransitionPending = false;
    }
  }

  void _handleThumbnailPageChanged(int index) {
    if (index < 0 || index >= _photos.length) return;
    _selectedIndex = index;
    _debug(
      'stored_photos=thumbnail_preview_page source=${widget.diagnosticSource} yearMonth=$_selectedYearMonth index=$index count=${_photos.length}',
    );
  }

  Future<void> _showDeveloperStatus() async {
    final trace = _effectiveTrace;
    if (trace == null || !trace.developerMode || !mounted) return;
    final description = <String>[
      'source=${widget.diagnosticSource}',
      'plate=${widget.plateNumber}',
      'yearMonth=$_selectedYearMonth',
      'viewMode=${_view.name}',
      'selectedIndex=$_selectedIndex',
      'photoCount=${_photos.length}',
      'thumbnailRequests=${_thumbnailRequestPaths.length}',
      'displayRequests=${_displayRequestPaths.length}',
      'displayTransitionPending=$_displayTransitionPending',
      'missingThumbnailLogs=${_missingThumbnailPaths.length}',
      'loadCount=$_loadCount',
      'lastResultCount=$_lastResultCount',
      'lastThumbnailCount=$_lastThumbnailCount',
      'lastMissingThumbnailCount=$_lastMissingThumbnailCount',
      'lastLoadStartedAt=${_lastLoadStartedAt?.toIso8601String() ?? '-'}',
      'lastLoadCompletedAt=${_lastLoadCompletedAt?.toIso8601String() ?? '-'}',
      'lastError=${_lastError ?? '-'}',
    ].join('\n');
    _debug(
      'saved_photos=developer_status_open source=${widget.diagnosticSource} plate=${widget.plateNumber}',
    );
    await trace.showSnapshotStatusDialog(
      context,
      title: '저장 사진 디버그 상태',
      description: description,
      failure: _lastError != null,
    );
  }

  Widget _headerIcon({
    required BuildContext context,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    final tokens = CommonUiTheme.of(context);
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      color: onPressed == null ? tokens.iconDisabled : tokens.iconPrimary,
      constraints: const BoxConstraints.tightFor(width: 38, height: 38),
      padding: EdgeInsets.zero,
    );
  }

  Widget? _developerAction() {
    if (_effectiveTrace?.developerMode != true) return null;
    return IconButton(
      onPressed: () => unawaited(_showDeveloperStatus()),
      icon: const Icon(Icons.bug_report_rounded),
    );
  }

  Widget _buildListBody(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Container(
      key: const ValueKey<String>('saved_photo_list'),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(CommonUiShapes.card),
        border: Border.all(color: tokens.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Row(
              children: [
                _headerIcon(
                  context: context,
                  icon: Icons.arrow_back_rounded,
                  onPressed: widget.onBack,
                ),
                const SizedBox(width: 6),
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
                if (_effectiveTrace?.developerMode == true)
                  _headerIcon(
                    context: context,
                    icon: Icons.bug_report_rounded,
                    onPressed: () => unawaited(_showDeveloperStatus()),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: tokens.borderSubtle),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                _headerIcon(
                  context: context,
                  icon: Icons.chevron_left_rounded,
                  onPressed: _monthIndex < _yearMonths.length - 1
                      ? _showOlderMonth
                      : null,
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 140),
                    transitionBuilder: (child, animation) {
                      if (reduceMotion || _monthTransitionDirection == 0) {
                        return child;
                      }
                      final slide = Tween<Offset>(
                        begin: Offset(
                          _monthTransitionDirection < 0 ? -.04 : .04,
                          0,
                        ),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                        ),
                      );
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(position: slide, child: child),
                      );
                    },
                    child: Text(
                      _selectedYearMonth,
                      key: ValueKey<String>(_selectedYearMonth),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                ),
                _headerIcon(
                  context: context,
                  icon: Icons.chevron_right_rounded,
                  onPressed: _monthIndex > 0 ? _showNewerMonth : null,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: tokens.borderSubtle),
          Expanded(
            child: FutureBuilder<List<StoredPlatePhoto>>(
              key: ValueKey<String>('saved_photo_future_$_selectedYearMonth'),
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(color: tokens.accent),
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
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
                final photos = snapshot.data ?? const <StoredPlatePhoto>[];
                if (photos.isEmpty) {
                  return Center(
                    child: Text(
                      '저장된 이미지가 없습니다.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: tokens.textSecondary,
                          ),
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.all(8),
                  child: StoredPlatePhotoListSurface(
                    photos: photos,
                    onSelect: _openThumbnailPreview,
                    onThumbnailRequested: _markThumbnailRequest,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnailPreviewBody() {
    return KeyedSubtree(
      key: const ValueKey<String>('saved_photo_thumbnail_preview'),
      child: StoredPlatePhotoThumbnailPreviewSurface(
        photos: _photos,
        initialIndex: _selectedIndex,
        onBack: _closeThumbnailPreview,
        onOpenDisplay: (index) => unawaited(_openFullscreenDisplay(index)),
        onPageChanged: _handleThumbnailPageChanged,
        onThumbnailRequested: _markThumbnailRequest,
        trailing: _developerAction(),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final Widget child;
    final String activeKey;
    final int activeOrder;
    if (_photos.isNotEmpty && _view == _SavedPhotoView.thumbnailPreview) {
      child = _buildThumbnailPreviewBody();
      activeKey = 'saved_photo_thumbnail_preview';
      activeOrder = 1;
    } else {
      child = _buildListBody(context);
      activeKey = 'saved_photo_list';
      activeOrder = 0;
    }
    return PlateEditorWorkspaceSwitcher(
      activeKey: activeKey,
      activeOrder: activeOrder,
      child: child,
    );
  }
}
