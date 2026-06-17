import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../../../shared/page/modify/application/modify_plate_service.dart';

class TripleDepartureCompletedPlateImageDialog extends StatelessWidget {
  final String plateNumber;

  const TripleDepartureCompletedPlateImageDialog({
    super.key,
    required this.plateNumber,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        centerTitle: true,
        title: const Text('저장된 사진 목록'),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: Border(
          bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.85), width: 1),
        ),
      ),
      body: FutureBuilder<List<String>>(
        future: ModifyPlateService.listPlateImages(
          context: context,
          plateNumber: plateNumber,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
              ),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                '이미지 불러오기 실패',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
          }

          final urls = (snapshot.data ?? <String>[]).where((e) => e.trim().isNotEmpty).toList();

          if (urls.isEmpty) {
            return Center(
              child: Text(
                '저장된 이미지가 없습니다.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
          }

          return ListView.builder(
            itemCount: urls.length,
            itemBuilder: (context, index) {
              final url = urls[index];
              final meta = _PlateImageMeta.fromUrl(
                url,
                fallbackPlateNumber: plateNumber,
              );
              final infoLines = _buildInfoLines(context, meta);

              return InkWell(
                onTap: () => modifyshowFullScreenImageViewer(
                  context,
                  urls,
                  index,
                  isUrlList: true,
                  fallbackPlateNumber: plateNumber,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
                  child: Row(
                    children: [
                      Container(
                        width: MediaQuery.of(context).size.width * 0.2,
                        height: 80,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
                          color: cs.surfaceContainerLow,
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: Image.network(
                          url,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(Icons.broken_image, color: cs.error),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: infoLines,
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
    );
  }
}

void modifyshowFullScreenImageViewer(
  BuildContext context,
  List<dynamic> images,
  int initialIndex, {
  bool isUrlList = false,
  String fallbackPlateNumber = '',
}) {
  final cs = Theme.of(context).colorScheme;

  showDialog(
    context: context,
    useSafeArea: true,
    barrierDismissible: true,
    builder: (_) {
      return Dialog(
        backgroundColor: cs.scrim,
        insetPadding: EdgeInsets.zero,
        child: SafeArea(
          child: Stack(
            children: [
              PageView.builder(
                controller: PageController(initialPage: initialIndex),
                itemCount: images.length,
                itemBuilder: (context, index) {
                  final image = images[index];
                  final tag = isUrlList ? image : (image as XFile).path;
                  final metadata = isUrlList
                      ? _metadataFromUrl(
                          image,
                          fallbackPlateNumber: fallbackPlateNumber,
                        )
                      : _metadataFromFileName(
                          File(image.path).uri.pathSegments.last,
                          fallbackPlateNumber: fallbackPlateNumber,
                        );

                  return Stack(
                    children: [
                      Center(
                        child: Hero(
                          tag: tag,
                          child: InteractiveViewer(
                            minScale: 0.8,
                            maxScale: 4.0,
                            child: isUrlList
                                ? Image.network(
                                    image,
                                    fit: BoxFit.contain,
                                    loadingBuilder: (context, child, progress) {
                                      if (progress == null) return child;
                                      return Center(
                                        child: CircularProgressIndicator(
                                          valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                                        ),
                                      );
                                    },
                                    errorBuilder: (_, __, ___) => Icon(Icons.error, color: cs.error),
                                  )
                                : FutureBuilder<bool>(
                                    future: File(image.path).exists(),
                                    builder: (context, snapshot) {
                                      if (snapshot.connectionState != ConnectionState.done) {
                                        return Center(
                                          child: CircularProgressIndicator(
                                            valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                                          ),
                                        );
                                      }
                                      if (snapshot.hasError || !(snapshot.data ?? false)) {
                                        return Center(
                                          child: Icon(Icons.broken_image, color: cs.error),
                                        );
                                      }
                                      return Image.file(
                                        File(image.path),
                                        fit: BoxFit.contain,
                                      );
                                    },
                                  ),
                          ),
                        ),
                      ),
                      if (metadata.isNotEmpty)
                        Positioned(
                          bottom: 30,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: cs.scrim.withOpacity(0.65),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
                              ),
                              child: Text(
                                metadata,
                                style: TextStyle(
                                  color: cs.inverseSurface,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
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
                  padding: const EdgeInsets.all(16),
                  child: IconButton(
                    icon: Icon(Icons.close, color: Theme.of(context).colorScheme.inverseSurface, size: 30),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: '닫기',
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

List<Widget> _buildInfoLines(BuildContext context, _PlateImageMeta meta) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final baseStyle = theme.textTheme.bodyMedium?.copyWith(
        color: cs.onSurface,
        fontWeight: FontWeight.w700,
      ) ??
      TextStyle(
        fontSize: 14,
        color: cs.onSurface,
        fontWeight: FontWeight.w700,
      );
  final mutedStyle = baseStyle.copyWith(color: cs.onSurfaceVariant);
  final dateTime = meta.dateTimeText;
  final widgets = <Widget>[];

  if (dateTime.isNotEmpty) {
    widgets.add(Text('📅 $dateTime', style: baseStyle));
  }
  if (meta.plate.isNotEmpty) {
    widgets.add(Text('🚘 ${meta.plate}', style: baseStyle));
  }
  if (meta.user.isNotEmpty) {
    widgets.add(Text('👤 ${meta.user}', style: mutedStyle));
  }

  return widgets;
}

String _metadataFromUrl(
  String url, {
  String fallbackPlateNumber = '',
}) {
  return _PlateImageMeta.fromUrl(
    url,
    fallbackPlateNumber: fallbackPlateNumber,
  ).toOverlayText();
}

String _metadataFromFileName(
  String fileName, {
  String fallbackPlateNumber = '',
}) {
  return _PlateImageMeta.fromFileName(
    fileName,
    fallbackPlateNumber: fallbackPlateNumber,
  ).toOverlayText();
}

class _PlateImageMeta {
  final String rawFileName;
  final String date;
  final String time;
  final String plate;
  final String user;

  const _PlateImageMeta({
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

  static _PlateImageMeta fromUrl(
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
      return _PlateImageMeta.empty(fallbackPlateNumber: fallbackPlateNumber);
    }
  }

  static _PlateImageMeta fromFileName(
    String fileName, {
    String fallbackPlateNumber = '',
  }) {
    try {
      var name = Uri.decodeComponent(fileName.trim());
      if (name.isEmpty) {
        return _PlateImageMeta.empty(fallbackPlateNumber: fallbackPlateNumber);
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

      return _PlateImageMeta(
        rawFileName: raw,
        date: date,
        time: time,
        plate: plate,
        user: user,
      );
    } catch (_) {
      return _PlateImageMeta.empty(fallbackPlateNumber: fallbackPlateNumber);
    }
  }

  static _PlateImageMeta empty({String fallbackPlateNumber = ''}) {
    return _PlateImageMeta(
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
