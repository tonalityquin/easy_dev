import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../../../shared/page/modify/application/modify_plate_service.dart';

class MinorDepartureCompletedPlateImageDialog extends StatelessWidget {
  final String plateNumber;

  const MinorDepartureCompletedPlateImageDialog({
    super.key,
    required this.plateNumber,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        centerTitle: true,
        title: const Text('저장된 사진 목록'),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 1,
        surfaceTintColor: Colors.transparent,
      ),
      body: FutureBuilder<List<String>>(
        future: ModifyPlateService.listPlateImages(
          context: context,
          plateNumber: plateNumber,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _ErrorState(
              title: '이미지 불러오기 실패',
              message: '${snapshot.error}',
              onRetry: () => Navigator.of(context).maybePop(),
            );
          }

          final urls = (snapshot.data ?? <String>[]).where((e) => e.trim().isNotEmpty).toList();

          if (urls.isEmpty) {
            return const _EmptyState(message: '저장된 이미지가 없습니다.');
          }

          return ListView.separated(
            itemCount: urls.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: cs.outlineVariant.withOpacity(0.6)),
            itemBuilder: (context, index) {
              final url = urls[index];
              final meta = _ImageMeta.fromUrl(
                url,
                fallbackPlateNumber: plateNumber,
              );
              final infoLines = _buildListInfoLines(context, meta);

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => showMinorDepartureCompletedFullScreenImageViewerFromUrls(
                    context,
                    urls,
                    index,
                    fallbackPlateNumber: plateNumber,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                    child: Row(
                      children: [
                        Hero(
                          tag: _heroTagForUrl(url),
                          child: _Thumb(
                            url: url,
                            width: MediaQuery.of(context).size.width * 0.22,
                            height: 84,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: infoLines,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

Future<void> showMinorDepartureCompletedFullScreenImageViewerFromUrls(
  BuildContext context,
  List<String> urls,
  int initialIndex, {
  String fallbackPlateNumber = '',
}) async {
  await showDialog<void>(
    context: context,
    useSafeArea: true,
    barrierDismissible: true,
    builder: (_) => _MinorFullScreenImageViewer(
      mode: _ViewerMode.urls,
      urlImages: urls,
      fileImages: const <XFile>[],
      initialIndex: initialIndex,
      fallbackPlateNumber: fallbackPlateNumber,
    ),
  );
}

Future<void> showMinorDepartureCompletedFullScreenImageViewerFromFiles(
  BuildContext context,
  List<XFile> files,
  int initialIndex, {
  String fallbackPlateNumber = '',
}) async {
  await showDialog<void>(
    context: context,
    useSafeArea: true,
    barrierDismissible: true,
    builder: (_) => _MinorFullScreenImageViewer(
      mode: _ViewerMode.files,
      urlImages: const <String>[],
      fileImages: files,
      initialIndex: initialIndex,
      fallbackPlateNumber: fallbackPlateNumber,
    ),
  );
}

enum _ViewerMode { urls, files }

class _MinorFullScreenImageViewer extends StatefulWidget {
  const _MinorFullScreenImageViewer({
    required this.mode,
    required this.urlImages,
    required this.fileImages,
    required this.initialIndex,
    required this.fallbackPlateNumber,
  });

  final _ViewerMode mode;
  final List<String> urlImages;
  final List<XFile> fileImages;
  final int initialIndex;
  final String fallbackPlateNumber;

  int get length => mode == _ViewerMode.urls ? urlImages.length : fileImages.length;

  @override
  State<_MinorFullScreenImageViewer> createState() => _MinorFullScreenImageViewerState();
}

class _MinorFullScreenImageViewerState extends State<_MinorFullScreenImageViewer> {
  late final PageController _pageController;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, (widget.length - 1).clamp(0, 1 << 30));
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String _metadataForIndex(int i) {
    if (widget.mode == _ViewerMode.urls) {
      final url = widget.urlImages[i];
      final meta = _ImageMeta.fromUrl(
        url,
        fallbackPlateNumber: widget.fallbackPlateNumber,
      );
      return meta.toOverlayText();
    }
    final file = widget.fileImages[i];
    final meta = _ImageMeta.fromFileName(
      file.path.split(Platform.pathSeparator).last,
      fallbackPlateNumber: widget.fallbackPlateNumber,
    );
    return meta.toOverlayText();
  }

  Widget _buildImage(int i) {
    if (widget.mode == _ViewerMode.urls) {
      final url = widget.urlImages[i];
      return Hero(
        tag: _heroTagForUrl(url),
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4.0,
          child: Image.network(
            url,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return const Center(child: CircularProgressIndicator());
            },
            errorBuilder: (_, __, ___) => const Center(
              child: Icon(Icons.error, color: Colors.red),
            ),
          ),
        ),
      );
    }

    final file = widget.fileImages[i];
    return Hero(
      tag: _heroTagForFile(file.path),
      child: InteractiveViewer(
        minScale: 0.8,
        maxScale: 4.0,
        child: FutureBuilder<bool>(
          future: File(file.path).exists(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || !(snapshot.data ?? false)) {
              return const Center(child: Icon(Icons.broken_image, color: Colors.red));
            }
            return Image.file(
              File(file.path),
              fit: BoxFit.contain,
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: EdgeInsets.zero,
      child: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: widget.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) {
                final metadata = _metadataForIndex(i);

                return Stack(
                  children: [
                    Center(child: _buildImage(i)),
                    if (metadata.trim().isNotEmpty)
                      Positioned(
                        bottom: 30,
                        left: 12,
                        right: 12,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.60),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white.withOpacity(0.15)),
                            ),
                            child: Text(
                              metadata,
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: '닫기',
                ),
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white.withOpacity(0.12)),
                  ),
                  child: Text(
                    '${_index + 1} / ${widget.length}',
                    style: TextStyle(
                      color: cs.onPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final String url;
  final double width;
  final double height;

  const _Thumb({
    required this.url,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
        color: cs.surfaceVariant.withOpacity(0.35),
      ),
      clipBehavior: Clip.hardEdge,
      child: Image.network(
        url,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image, color: Colors.red),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;

  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 44, color: cs.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 44, color: cs.error),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('닫고 다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}

List<Widget> _buildListInfoLines(BuildContext context, _ImageMeta meta) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final baseStyle = theme.textTheme.bodyMedium;
  final mutedStyle = theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant.withOpacity(0.75));
  final dateTime = meta.dateTimeText;
  final widgets = <Widget>[];

  if (dateTime.isNotEmpty) {
    widgets.add(Text('📅 $dateTime', style: baseStyle));
    widgets.add(const SizedBox(height: 4));
  }
  if (meta.plate.isNotEmpty) {
    widgets.add(Text('🚘 ${meta.plate}', style: baseStyle));
    widgets.add(const SizedBox(height: 4));
  }
  if (meta.user.isNotEmpty) {
    widgets.add(Text('👤 ${meta.user}', style: baseStyle?.copyWith(color: cs.onSurfaceVariant)));
    widgets.add(const SizedBox(height: 2));
  }
  if (meta.rawFileName.isNotEmpty) {
    widgets.add(
      Text(
        meta.rawFileName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: mutedStyle,
      ),
    );
  }

  while (widgets.isNotEmpty && widgets.last is SizedBox) {
    widgets.removeLast();
  }

  return widgets;
}

class _ImageMeta {
  final String rawFileName;
  final String date;
  final String time;
  final String plate;
  final String user;

  const _ImageMeta({
    required this.rawFileName,
    required this.date,
    required this.time,
    required this.plate,
    required this.user,
  });

  String get dateTimeText {
    if (date.isEmpty) return '';
    return time.isNotEmpty ? '$date $time' : date;
  }

  String toOverlayText() {
    final parts = <String>[];
    final dt = dateTimeText;
    if (dt.isNotEmpty) parts.add('촬영일: $dt');
    if (plate.isNotEmpty) parts.add('차량번호: $plate');
    if (user.isNotEmpty) parts.add('촬영자: $user');
    return parts.join('\n');
  }

  static _ImageMeta fromUrl(
    String url, {
    String fallbackPlateNumber = '',
  }) {
    try {
      final uri = Uri.parse(url);
      final segment = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : url.split('/').last;
      final fileName = Uri.decodeComponent(segment.split('?').first);
      return fromFileName(
        fileName,
        fallbackPlateNumber: fallbackPlateNumber,
      );
    } catch (_) {
      return _ImageMeta.empty(fallbackPlateNumber: fallbackPlateNumber);
    }
  }

  static _ImageMeta fromFileName(
    String fileName, {
    String fallbackPlateNumber = '',
  }) {
    try {
      var name = Uri.decodeComponent(fileName.trim());
      if (name.isEmpty) {
        return _ImageMeta.empty(fallbackPlateNumber: fallbackPlateNumber);
      }

      if (name.contains('?')) name = name.split('?').first;
      final raw = name;
      name = name.replaceFirst(RegExp(r'\.(jpg|jpeg|png|webp)$', caseSensitive: false), '');

      final fallbackPlate = _cleanPlate(fallbackPlateNumber);
      final parts = name.split('_').map((e) => e.trim()).toList();

      String date = '';
      String time = '';
      String plate = fallbackPlate;
      String user = '';

      if (parts.length >= 4) {
        date = _normalizeDate(parts[0]);
        time = _normalizeTime(parts[1]);
        final parsedPlate = _cleanPlate(parts[2]);
        if (parsedPlate.isNotEmpty) plate = parsedPlate;
        user = _cleanUser(parts.sublist(3).join('_'));
      }

      return _ImageMeta(
        rawFileName: raw,
        date: date,
        time: time,
        plate: plate,
        user: user,
      );
    } catch (_) {
      return _ImageMeta.empty(fallbackPlateNumber: fallbackPlateNumber);
    }
  }

  static _ImageMeta empty({String fallbackPlateNumber = ''}) {
    return _ImageMeta(
      rawFileName: '',
      date: '',
      time: '',
      plate: _cleanPlate(fallbackPlateNumber),
      user: '',
    );
  }
}

String _normalizeDate(String value) {
  final v = value.trim();
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v)) return v;
  if (RegExp(r'^\d{8}$').hasMatch(v)) {
    return '${v.substring(0, 4)}-${v.substring(4, 6)}-${v.substring(6, 8)}';
  }
  return '';
}

String _normalizeTime(String value) {
  final v = value.trim();
  if (RegExp(r'^\d{6}$').hasMatch(v)) {
    return '${v.substring(0, 2)}:${v.substring(2, 4)}:${v.substring(4, 6)}';
  }
  final millis = int.tryParse(v);
  if (millis == null || millis <= 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(millis);
  return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
}

String _cleanPlate(String value) {
  final v = value.trim();
  if (v.isEmpty) return '';
  return v;
}

String _cleanUser(String value) {
  final v = value.trim();
  if (v.isEmpty || v.toLowerCase() == 'unknown') return '';
  return v;
}

String _heroTagForUrl(String url) => 'minor_url::$url';
String _heroTagForFile(String path) => 'minor_file::$path';
