import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/utils/developer_operation_status_dialog.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../editor/domain/stored_plate_photo.dart';

enum StoredPlatePhotoDisplayPhase {
  opening,
  loading,
  ready,
  failed,
  closing,
}

Future<void> showStoredPlatePhotoFullscreenViewer({
  required BuildContext context,
  required StoredPlatePhoto photo,
  required String diagnosticSource,
  required String yearMonth,
  required int index,
  DeveloperOperationTrace? trace,
  ValueChanged<String>? onDebug,
}) async {
  final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  final tokens = CommonUiTheme.of(context);
  await showGeneralDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    barrierLabel: 'DISPLAY',
    barrierColor: tokens.scrim.withOpacity(.72),
    transitionDuration:
        reduceMotion ? Duration.zero : const Duration(milliseconds: 210),
    pageBuilder: (_, __, ___) => StoredPlatePhotoFullscreenViewer(
      photo: photo,
      diagnosticSource: diagnosticSource,
      yearMonth: yearMonth,
      index: index,
      trace: trace,
      onDebug: onDebug,
    ),
    transitionBuilder: (_, animation, __, child) {
      if (reduceMotion) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: .985, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class StoredPlatePhotoFullscreenViewer extends StatefulWidget {
  const StoredPlatePhotoFullscreenViewer({
    super.key,
    required this.photo,
    required this.diagnosticSource,
    required this.yearMonth,
    required this.index,
    this.trace,
    this.onDebug,
  });

  final StoredPlatePhoto photo;
  final String diagnosticSource;
  final String yearMonth;
  final int index;
  final DeveloperOperationTrace? trace;
  final ValueChanged<String>? onDebug;

  @override
  State<StoredPlatePhotoFullscreenViewer> createState() =>
      _StoredPlatePhotoFullscreenViewerState();
}

class _StoredPlatePhotoFullscreenViewerState
    extends State<StoredPlatePhotoFullscreenViewer> {
  late final TransformationController _transformationController;
  late final DateTime _openedAt;
  StoredPlatePhotoDisplayPhase _phase = StoredPlatePhotoDisplayPhase.opening;
  DateTime? _loadStartedAt;
  DateTime? _firstFrameAt;
  String? _lastError;
  bool _firstFrameScheduled = false;
  bool _failureScheduled = false;
  bool _closeRequested = false;

  @override
  void initState() {
    super.initState();
    _openedAt = DateTime.now();
    _loadStartedAt = _openedAt;
    _transformationController = TransformationController();
    _debug(
      'display_mode=opening source=${widget.diagnosticSource} yearMonth=${widget.yearMonth} index=${widget.index} object=${widget.photo.displayObjectPath}',
    );
    _debug(
      'display_asset=load_start source=${widget.diagnosticSource} yearMonth=${widget.yearMonth} index=${widget.index} object=${widget.photo.displayObjectPath}',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startLoading();
    });
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _debug(String message) {
    final normalized = message.trim();
    if (normalized.isEmpty) return;
    final callback = widget.onDebug;
    if (callback != null) {
      callback(normalized);
      return;
    }
    widget.trace?.log(normalized);
    if (widget.trace == null) {
      debugPrint('[StoredPlatePhotoFullscreenViewer] $normalized');
    }
  }

  void _startLoading() {
    if (_phase != StoredPlatePhotoDisplayPhase.opening) return;
    setState(() => _phase = StoredPlatePhotoDisplayPhase.loading);
  }

  void _scheduleReady() {
    if (_firstFrameScheduled || _phase == StoredPlatePhotoDisplayPhase.ready) {
      return;
    }
    _firstFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _firstFrameScheduled = false;
      if (!mounted || _closeRequested) return;
      final now = DateTime.now();
      _firstFrameAt = now;
      final startedAt = _loadStartedAt ?? _openedAt;
      setState(() => _phase = StoredPlatePhotoDisplayPhase.ready);
      _debug(
        'display_asset=first_frame source=${widget.diagnosticSource} yearMonth=${widget.yearMonth} index=${widget.index} object=${widget.photo.displayObjectPath} elapsedMs=${now.difference(startedAt).inMilliseconds}',
      );
      _debug(
        'display_mode=ready source=${widget.diagnosticSource} yearMonth=${widget.yearMonth} index=${widget.index}',
      );
    });
  }

  void _scheduleFailure(Object error) {
    if (_failureScheduled || _phase == StoredPlatePhotoDisplayPhase.failed) {
      return;
    }
    _failureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _failureScheduled = false;
      if (!mounted || _closeRequested) return;
      _lastError = error.toString();
      setState(() => _phase = StoredPlatePhotoDisplayPhase.failed);
      _debug(
        'display_asset=failed source=${widget.diagnosticSource} yearMonth=${widget.yearMonth} index=${widget.index} object=${widget.photo.displayObjectPath} error=$error',
      );
    });
  }

  Future<void> _requestClose() async {
    if (_closeRequested || !mounted) return;
    _closeRequested = true;
    _debug(
      'display_mode=close_requested source=${widget.diagnosticSource} yearMonth=${widget.yearMonth} index=${widget.index} phase=${_phase.name}',
    );
    setState(() => _phase = StoredPlatePhotoDisplayPhase.closing);
    _debug(
      'display_mode=closing source=${widget.diagnosticSource} yearMonth=${widget.yearMonth} index=${widget.index}',
    );
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _showDeveloperStatus() async {
    final trace = widget.trace;
    if (trace == null || !trace.developerMode || !mounted) return;
    final scale = _transformationController.value.getMaxScaleOnAxis();
    final description = <String>[
      'source=${widget.diagnosticSource}',
      'yearMonth=${widget.yearMonth}',
      'index=${widget.index}',
      'phase=${_phase.name}',
      'displayObject=${widget.photo.displayObjectPath}',
      'thumbnailObject=${widget.photo.thumbnailObjectPath ?? '-'}',
      'capturedDate=${widget.photo.metadata.capturedDate}',
      'capturedTime=${widget.photo.metadata.capturedTime}',
      'plate=${widget.photo.metadata.plateNumber}',
      'capturedBy=${widget.photo.metadata.capturedBy}',
      'openedAt=${_openedAt.toIso8601String()}',
      'loadStartedAt=${_loadStartedAt?.toIso8601String() ?? '-'}',
      'firstFrameAt=${_firstFrameAt?.toIso8601String() ?? '-'}',
      'zoomScale=${scale.toStringAsFixed(2)}',
      'lastError=${_lastError ?? '-'}',
    ].join('\n');
    _debug(
      'display_mode=developer_status_open source=${widget.diagnosticSource} yearMonth=${widget.yearMonth} index=${widget.index} phase=${_phase.name}',
    );
    await trace.showSnapshotStatusDialog(
      context,
      title: 'DISPLAY 디버그 상태',
      description: description,
      failure: _phase == StoredPlatePhotoDisplayPhase.failed,
    );
  }

  Widget _buildThumbnail(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final url = widget.photo.gridThumbnailUrl;
    if (url == null || url.trim().isEmpty) {
      return Center(
        child: Icon(
          Icons.image_outlined,
          size: 58,
          color: tokens.iconSecondary,
        ),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.contain,
      cacheWidth: 900,
      filterQuality: FilterQuality.low,
      errorBuilder: (_, __, ___) => Center(
        child: Icon(
          Icons.image_outlined,
          size: 58,
          color: tokens.iconSecondary,
        ),
      ),
    );
  }

  Widget _buildDisplayImage() {
    final url = widget.photo.displayUrl.trim();
    if (url.isEmpty) {
      _scheduleFailure(StateError('displayUrl is empty'));
      return const SizedBox.expand();
    }
    return Image.network(
      url,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          _scheduleReady();
        }
        return child;
      },
      errorBuilder: (_, error, __) {
        _scheduleFailure(error);
        return const SizedBox.expand();
      },
    );
  }

  Widget _phaseBadge(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final String label;
    switch (_phase) {
      case StoredPlatePhotoDisplayPhase.opening:
        label = 'OPENING';
        break;
      case StoredPlatePhotoDisplayPhase.loading:
        label = 'LOADING';
        break;
      case StoredPlatePhotoDisplayPhase.ready:
        label = 'READY';
        break;
      case StoredPlatePhotoDisplayPhase.failed:
        label = 'FAILED';
        break;
      case StoredPlatePhotoDisplayPhase.closing:
        label = 'CLOSING';
        break;
    }
    return AnimatedSwitcher(
      duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
          ? Duration.zero
          : const Duration(milliseconds: 130),
      child: Container(
        key: ValueKey<String>(label),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _phase == StoredPlatePhotoDisplayPhase.failed
              ? tokens.danger.withOpacity(.12)
              : tokens.surfaceOverlay,
          borderRadius: BorderRadius.circular(CommonUiShapes.pill),
          border: Border.all(
            color: _phase == StoredPlatePhotoDisplayPhase.failed
                ? tokens.danger.withOpacity(.45)
                : tokens.borderSubtle,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: _phase == StoredPlatePhotoDisplayPhase.failed
                    ? tokens.danger
                    : tokens.textSecondary,
                fontWeight: FontWeight.w900,
                letterSpacing: .4,
              ),
        ),
      ),
    );
  }

  Widget _infoCell(BuildContext context, String label, String value) {
    final tokens = CommonUiTheme.of(context);
    final shown = value.trim().isEmpty ? '-' : value.trim();
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 116, maxWidth: 190),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label ',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
          ),
          Flexible(
            child: Text(
              shown,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final ready = _phase == StoredPlatePhotoDisplayPhase.ready;
    final loading = _phase == StoredPlatePhotoDisplayPhase.opening ||
        _phase == StoredPlatePhotoDisplayPhase.loading;
    final closing = _phase == StoredPlatePhotoDisplayPhase.closing;
    final failed = _phase == StoredPlatePhotoDisplayPhase.failed;
    final metadata = widget.photo.metadata;
    final crossFadeDuration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 120);

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) {
          unawaited(_requestClose());
        }
      },
      child: Material(
        color: tokens.surface,
        child: SizedBox.expand(
          child: Column(
            children: [
              SafeArea(
                bottom: false,
                child: Container(
                  height: 54,
                  color: tokens.surfaceRaised,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: closing ? null : () => unawaited(_requestClose()),
                        icon: const Icon(Icons.arrow_back_rounded),
                        color: tokens.iconPrimary,
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.accentContainer,
                          borderRadius: BorderRadius.circular(CommonUiShapes.pill),
                          border: Border.all(
                            color: tokens.accent.withOpacity(.42),
                          ),
                        ),
                        child: Text(
                          'DISPLAY',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: tokens.onAccentContainer,
                                fontWeight: FontWeight.w900,
                                letterSpacing: .4,
                              ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          metadata.plateNumber.trim().isEmpty
                              ? '-'
                              : metadata.plateNumber.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: tokens.textPrimary,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                      ),
                      _phaseBadge(context),
                      if (widget.trace?.developerMode == true) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          onPressed: () => unawaited(_showDeveloperStatus()),
                          icon: const Icon(Icons.bug_report_rounded),
                          color: tokens.iconPrimary,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              AnimatedContainer(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 120),
                height: loading || closing ? 2 : 0,
                child: loading || closing
                    ? LinearProgressIndicator(
                        color: tokens.accent,
                        backgroundColor: tokens.surfaceOverlay,
                      )
                    : const SizedBox.shrink(),
              ),
              Expanded(
                child: ColoredBox(
                  color: tokens.surfaceOverlay,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: AnimatedOpacity(
                          opacity: ready ? 0 : 1,
                          duration: crossFadeDuration,
                          child: _buildThumbnail(context),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: IgnorePointer(
                          ignoring: !ready,
                          child: AnimatedOpacity(
                            opacity: ready ? 1 : 0,
                            duration: crossFadeDuration,
                            child: InteractiveViewer(
                              transformationController: _transformationController,
                              minScale: 1,
                              maxScale: 4,
                              panEnabled: ready,
                              scaleEnabled: ready,
                              child: Center(child: _buildDisplayImage()),
                            ),
                          ),
                        ),
                      ),
                      if (loading)
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: tokens.surfaceRaised.withOpacity(.94),
                              borderRadius:
                                  BorderRadius.circular(CommonUiShapes.control),
                              border: Border.all(color: tokens.borderSubtle),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: tokens.accent,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'DISPLAY 불러오는 중',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(
                                        color: tokens.textPrimary,
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (failed)
                        Center(
                          child: Container(
                            margin: const EdgeInsets.all(24),
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: tokens.surfaceRaised,
                              borderRadius:
                                  BorderRadius.circular(CommonUiShapes.card),
                              border: Border.all(color: tokens.borderSubtle),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.broken_image_rounded,
                                  color: tokens.danger,
                                  size: 38,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'DISPLAY를 불러오지 못했습니다.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: tokens.textPrimary,
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                                const SizedBox(height: 14),
                                FilledButton.icon(
                                  onPressed: () => unawaited(_requestClose()),
                                  icon: const Icon(Icons.arrow_back_rounded),
                                  label: const Text('돌아가기'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (closing)
                        Positioned.fill(
                          child: AbsorbPointer(
                            child: ColoredBox(
                              color: tokens.scrim.withOpacity(.08),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Container(
                  width: double.infinity,
                  color: tokens.surfaceRaised,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
                  child: Wrap(
                    spacing: 14,
                    runSpacing: 5,
                    alignment: WrapAlignment.start,
                    children: [
                      _infoCell(context, '촬영일', metadata.capturedDate),
                      _infoCell(context, '촬영 시간', metadata.capturedTime),
                      _infoCell(context, '차량번호', metadata.plateNumber),
                      _infoCell(context, '촬영자', metadata.capturedBy),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
