import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/utils/developer_operation_status_dialog.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../editor/domain/stored_plate_photo.dart';
import 'stored_plate_photo_fullscreen_viewer.dart';
import 'stored_plate_photo_surfaces.dart';

typedef StoredPlatePhotoListLoader = Future<List<StoredPlatePhoto>> Function(
  BuildContext context,
  String yearMonth,
  ValueChanged<String>? onDebug,
);

enum _StoredPhotoView {
  list,
  thumbnailPreview,
}

Future<T?> showStoredPlatePhotoDialog<T>({
  required BuildContext context,
  required Widget child,
}) {
  final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  final tokens = CommonUiTheme.of(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '사진',
    barrierColor: tokens.scrim.withOpacity(.48),
    transitionDuration:
        reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
    pageBuilder: (_, __, ___) => child,
    transitionBuilder: (_, animation, __, routeChild) {
      if (reduceMotion) return routeChild;
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: routeChild,
      );
    },
  );
}

class StoredPlatePhotoListScreen extends StatefulWidget {
  const StoredPlatePhotoListScreen({
    super.key,
    required this.plateNumber,
    required this.diagnosticSource,
    required this.loadPhotos,
  });

  final String plateNumber;
  final String diagnosticSource;
  final StoredPlatePhotoListLoader loadPhotos;

  @override
  State<StoredPlatePhotoListScreen> createState() =>
      _StoredPlatePhotoListScreenState();
}

class _StoredPlatePhotoListScreenState
    extends State<StoredPlatePhotoListScreen> {
  Future<List<StoredPlatePhoto>>? _future;
  late final DateTime _currentMonth;
  late DateTime _selectedMonth;
  DeveloperOperationTrace? _trace;
  bool _initialized = false;
  _StoredPhotoView _view = _StoredPhotoView.list;
  List<StoredPlatePhoto> _photos = const <StoredPlatePhoto>[];
  int _selectedIndex = 0;
  int _loadCount = 0;
  int _lastPhotoCount = 0;
  int _lastThumbnailCount = 0;
  int _lastMissingThumbnailCount = 0;
  String? _lastError;
  DateTime? _lastLoadStartedAt;
  DateTime? _lastLoadCompletedAt;
  final Set<String> _thumbnailRequests = <String>{};
  final Set<String> _displayRequests = <String>{};
  final Set<String> _missingThumbnailLogs = <String>{};
  bool _displayTransitionPending = false;
  int _monthTransitionDirection = 0;

  String _twoDigits(int value) => value.toString().padLeft(2, '0');

  String _yearMonth(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-${_twoDigits(value.month)}';
  }

  String get _selectedYearMonth => _yearMonth(_selectedMonth);

  bool get _canStepNewer => _selectedMonth.isBefore(_currentMonth);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final now = DateTime.now();
    _currentMonth = DateTime(now.year, now.month, 1);
    _selectedMonth = _currentMonth;
    _future = _initializeAndLoad();
  }

  Future<List<StoredPlatePhoto>> _initializeAndLoad() async {
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '차량 사진 조회',
      initialMessage:
          'stored_photos=open source=${widget.diagnosticSource} plate=${widget.plateNumber} yearMonth=$_selectedYearMonth',
      useCommonUi: true,
      developerModeMessage: '',
      standardModeMessage: '',
      showDialogImmediately: false,
    );
    if (!mounted) return const <StoredPlatePhoto>[];
    setState(() => _trace = trace);
    return _load();
  }

  void _debug(String message) {
    final normalized = message.trim();
    if (normalized.isEmpty) return;
    final trace = _trace;
    if (trace != null) {
      trace.log(normalized);
      return;
    }
    debugPrint('[StoredPlatePhotoListScreen] $normalized');
  }

  Future<List<StoredPlatePhoto>> _load() async {
    final startedAt = DateTime.now();
    _loadCount++;
    _lastLoadStartedAt = startedAt;
    _lastError = null;
    _debug(
      'stored_photos=load_start source=${widget.diagnosticSource} plate=${widget.plateNumber} yearMonth=$_selectedYearMonth loadCount=$_loadCount',
    );
    try {
      final photos = await widget.loadPhotos(
        context,
        _selectedYearMonth,
        _debug,
      );
      final normalized = photos
          .where((photo) => photo.displayUrl.trim().isNotEmpty)
          .toList(growable: false);
      _photos = normalized;
      _lastPhotoCount = normalized.length;
      _lastThumbnailCount = normalized.where((photo) => photo.hasThumbnail).length;
      _lastMissingThumbnailCount = _lastPhotoCount - _lastThumbnailCount;
      _lastLoadCompletedAt = DateTime.now();
      _debug(
        'stored_photos=load_success source=${widget.diagnosticSource} plate=${widget.plateNumber} yearMonth=$_selectedYearMonth photos=$_lastPhotoCount thumbnails=$_lastThumbnailCount missingThumbnails=$_lastMissingThumbnailCount elapsedMs=${_lastLoadCompletedAt!.difference(startedAt).inMilliseconds}',
      );
      return normalized;
    } catch (error, stackTrace) {
      _photos = const <StoredPlatePhoto>[];
      _lastPhotoCount = 0;
      _lastThumbnailCount = 0;
      _lastMissingThumbnailCount = 0;
      _lastError = error.toString();
      _lastLoadCompletedAt = DateTime.now();
      _debug(
        'stored_photos=load_failed source=${widget.diagnosticSource} plate=${widget.plateNumber} yearMonth=$_selectedYearMonth elapsedMs=${_lastLoadCompletedAt!.difference(startedAt).inMilliseconds} error=$error',
      );
      _debug('stored_photos=stack_trace\n$stackTrace');
      rethrow;
    }
  }

  void _changeMonth(int monthOffset) {
    if (monthOffset == 0) return;
    final next = DateTime(
      _selectedMonth.year,
      _selectedMonth.month + monthOffset,
      1,
    );
    if (next.isAfter(_currentMonth)) return;
    final previous = _selectedYearMonth;
    setState(() {
      _monthTransitionDirection = monthOffset < 0 ? -1 : 1;
      _view = _StoredPhotoView.list;
      _photos = const <StoredPlatePhoto>[];
      _selectedMonth = next;
      _future = _load();
    });
    _debug(
      'stored_photos=month_changed source=${widget.diagnosticSource} direction=${monthOffset < 0 ? 'older' : 'newer'} previous=$previous current=$_selectedYearMonth',
    );
  }

  void _showOlderMonth() => _changeMonth(-1);

  void _showNewerMonth() => _changeMonth(1);

  void _retry() {
    _debug(
      'stored_photos=retry source=${widget.diagnosticSource} plate=${widget.plateNumber} yearMonth=$_selectedYearMonth',
    );
    setState(() {
      _view = _StoredPhotoView.list;
      _future = _load();
    });
  }

  void _markThumbnailRequest(StoredPlatePhoto photo) {
    if (!mounted) return;
    final metadata = photo.metadata;
    final path = photo.thumbnailObjectPath;
    if (!photo.hasThumbnail || path == null || path.trim().isEmpty) {
      if (_missingThumbnailLogs.add(photo.displayObjectPath)) {
        _debug(
          'photo_asset=missing type=thumbnail source=${widget.diagnosticSource} displayObject=${photo.displayObjectPath} capturedDate=${metadata.capturedDate} capturedTime=${metadata.capturedTime} plate=${metadata.plateNumber} capturedBy=${metadata.capturedBy}',
        );
      }
      return;
    }
    if (_thumbnailRequests.add(path)) {
      _debug(
        'photo_asset=request type=thumbnail action=list_or_preview source=${widget.diagnosticSource} object=$path capturedDate=${metadata.capturedDate} capturedTime=${metadata.capturedTime} plate=${metadata.plateNumber} capturedBy=${metadata.capturedBy}',
      );
    }
  }

  void _markDisplayRequest(StoredPlatePhoto photo) {
    if (!mounted) return;
    if (!_displayRequests.add(photo.displayObjectPath)) return;
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
    setState(() => _view = _StoredPhotoView.thumbnailPreview);
  }

  void _closeThumbnailPreview() {
    _debug(
      'stored_photos=thumbnail_preview_close source=${widget.diagnosticSource} yearMonth=$_selectedYearMonth index=$_selectedIndex',
    );
    setState(() => _view = _StoredPhotoView.list);
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
        trace: _trace,
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
    final trace = _trace;
    if (trace == null || !trace.developerMode || !mounted) return;
    final description = <String>[
      'source=${widget.diagnosticSource}',
      'plate=${widget.plateNumber}',
      'yearMonth=$_selectedYearMonth',
      'viewMode=${_view.name}',
      'selectedIndex=$_selectedIndex',
      'loadCount=$_loadCount',
      'lastPhotoCount=$_lastPhotoCount',
      'lastThumbnailCount=$_lastThumbnailCount',
      'lastMissingThumbnailCount=$_lastMissingThumbnailCount',
      'thumbnailRequests=${_thumbnailRequests.length}',
      'displayRequests=${_displayRequests.length}',
      'displayTransitionPending=$_displayTransitionPending',
      'lastLoadStartedAt=${_lastLoadStartedAt?.toIso8601String() ?? '-'}',
      'lastLoadCompletedAt=${_lastLoadCompletedAt?.toIso8601String() ?? '-'}',
      'lastError=${_lastError ?? '-'}',
    ].join('\n');
    _debug(
      'stored_photos=developer_status_open source=${widget.diagnosticSource} plate=${widget.plateNumber}',
    );
    await trace.showSnapshotStatusDialog(
      context,
      title: '차량 사진 디버그 상태',
      description: description,
      failure: _lastError != null,
    );
  }

  Widget _buildListBody(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final future = _future;
    if (future == null) {
      return Center(child: CircularProgressIndicator(color: tokens.accent));
    }
    return FutureBuilder<List<StoredPlatePhoto>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: tokens.accent));
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: tokens.danger,
                    size: 38,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '이미지 불러오기 실패',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('다시 시도'),
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
        return StoredPlatePhotoListSurface(
          photos: photos,
          onSelect: _openThumbnailPreview,
          onThumbnailRequested: _markThumbnailRequest,
        );
      },
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_photos.isNotEmpty && _view == _StoredPhotoView.thumbnailPreview) {
      return StoredPlatePhotoThumbnailPreviewSurface(
        key: const ValueKey<String>('thumbnail_preview'),
        photos: _photos,
        initialIndex: _selectedIndex,
        onBack: _closeThumbnailPreview,
        onOpenDisplay: (index) => unawaited(_openFullscreenDisplay(index)),
        onPageChanged: _handleThumbnailPageChanged,
        onThumbnailRequested: _markThumbnailRequest,
      );
    }
    return KeyedSubtree(
      key: const ValueKey<String>('list'),
      child: _buildListBody(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final size = MediaQuery.sizeOf(context);
    final width = size.width < 760 ? size.width - 24 : 720.0;
    final height = size.height < 760 ? size.height - 24 : size.height * .88;
    return SafeArea(
      child: Center(
        child: SizedBox(
          width: width,
          height: height,
          child: Material(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(CommonUiShapes.dialog),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '저장된 사진',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: tokens.textPrimary,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.plateNumber,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: tokens.textSecondary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      if (_trace?.developerMode == true)
                        IconButton(
                          onPressed: () => unawaited(_showDeveloperStatus()),
                          icon: const Icon(Icons.bug_report_rounded),
                          color: tokens.iconPrimary,
                        ),
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.close_rounded),
                        color: tokens.iconPrimary,
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: tokens.borderSubtle),
                if (_view == _StoredPhotoView.list) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: _showOlderMonth,
                          icon: const Icon(Icons.chevron_left_rounded),
                          color: tokens.iconPrimary,
                          visualDensity: VisualDensity.compact,
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
                        IconButton(
                          onPressed: _canStepNewer ? _showNewerMonth : null,
                          icon: const Icon(Icons.chevron_right_rounded),
                          color: tokens.iconPrimary,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: tokens.borderSubtle),
                ],
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: AnimatedSwitcher(
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 170),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        if (reduceMotion) return child;
                        final slide = Tween<Offset>(
                          begin: const Offset(.025, 0),
                          end: Offset.zero,
                        ).animate(animation);
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(position: slide, child: child),
                        );
                      },
                      child: _buildBody(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
