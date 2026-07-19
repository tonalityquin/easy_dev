import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';

Future<void> inputShowFullScreenImageViewer(
  BuildContext context,
  List<XFile> images,
  int initialIndex,
) {
  return showPromptOverlayDialog<void>(
    context: context,
    builder: (dialogContext) => _PromptImageViewer(
      itemCount: images.length,
      initialIndex: initialIndex,
      imageBuilder: (index) => Image.file(
        File(images[index].path),
        fit: BoxFit.contain,
      ),
      tagBuilder: (index) => images[index].path,
      metadataBuilder: (index) => _parseMetadataFromFileName(
        File(images[index].path).uri.pathSegments.last,
      ),
      fileExistenceCheck: (index) => File(images[index].path).exists(),
    ),
  );
}

Future<void> showFullScreenImageViewerFromUrls(
  BuildContext context,
  List<String> imageUrls,
  int initialIndex,
) {
  return showPromptOverlayDialog<void>(
    context: context,
    builder: (dialogContext) => _PromptImageViewer(
      itemCount: imageUrls.length,
      initialIndex: initialIndex,
      imageBuilder: (index) => Image.network(
        imageUrls[index],
        fit: BoxFit.contain,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              color: PromptUiTheme.of(context).accent,
            ),
          );
        },
        errorBuilder: (_, __, ___) => Center(
          child: Icon(
            Icons.broken_image_rounded,
            color: PromptUiTheme.of(dialogContext).danger,
            size: 42,
          ),
        ),
      ),
      tagBuilder: (index) => imageUrls[index],
      metadataBuilder: (index) => _parseMetadataFromFileName(
        Uri.parse(imageUrls[index]).pathSegments.last,
      ),
    ),
  );
}

class _PromptImageViewer extends StatefulWidget {
  const _PromptImageViewer({
    required this.itemCount,
    required this.initialIndex,
    required this.imageBuilder,
    required this.tagBuilder,
    required this.metadataBuilder,
    this.fileExistenceCheck,
  });

  final int itemCount;
  final int initialIndex;
  final Widget Function(int index) imageBuilder;
  final String Function(int index) tagBuilder;
  final String Function(int index) metadataBuilder;
  final Future<bool> Function(int index)? fileExistenceCheck;

  @override
  State<_PromptImageViewer> createState() => _PromptImageViewerState();
}

class _PromptImageViewerState extends State<_PromptImageViewer> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final size = MediaQuery.sizeOf(context);
    return SizedBox(
      width: size.width,
      height: size.height,
      child: Material(
        color: tokens.canvas,
        child: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: widget.itemCount,
              onPageChanged: (value) => setState(() => _index = value),
              itemBuilder: (context, index) {
                final metadata = widget.metadataBuilder(index);
                final image = InteractiveViewer(
                  minScale: .8,
                  maxScale: 4,
                  child: widget.fileExistenceCheck == null
                      ? widget.imageBuilder(index)
                      : FutureBuilder<bool>(
                          future: widget.fileExistenceCheck!(index),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState !=
                                ConnectionState.done) {
                              return Center(
                                child: CircularProgressIndicator(
                                  color: tokens.accent,
                                ),
                              );
                            }
                            if (snapshot.hasError || !(snapshot.data ?? false)) {
                              return Center(
                                child: Icon(
                                  Icons.broken_image_rounded,
                                  color: tokens.danger,
                                  size: 42,
                                ),
                              );
                            }
                            return widget.imageBuilder(index);
                          },
                        ),
                );
                return Stack(
                  children: [
                    Center(
                      child: Hero(
                        tag: widget.tagBuilder(index),
                        child: image,
                      ),
                    ),
                    if (metadata.isNotEmpty)
                      Positioned(
                        left: 18,
                        right: 18,
                        bottom: 24,
                        child: PromptAnimatedReveal(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              color: tokens.surfaceRaised,
                              borderRadius:
                                  BorderRadius.circular(PromptUiShapes.control),
                              border: Border.all(color: tokens.borderSubtle),
                              boxShadow: [
                                BoxShadow(
                                  color: tokens.shadow,
                                  blurRadius: 14,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Text(
                              metadata,
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: tokens.textPrimary,
                                    height: 1.4,
                                  ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: tokens.surfaceRaised,
                  borderRadius: BorderRadius.circular(PromptUiShapes.pill),
                  border: Border.all(color: tokens.borderSubtle),
                ),
                child: Text(
                  '${_index + 1} / ${widget.itemCount}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: PromptIconButton(
                icon: Icons.close_rounded,
                tooltip: '닫기',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _parseMetadataFromFileName(String fileName) {
  try {
    final name = fileName.replaceAll('.jpg', '');
    final parts = name.split('_');
    if (parts.length < 4) return '';
    final date = parts[0];
    final time = parts[1];
    final plate = parts[2];
    final user = parts.sublist(3).join('_');
    final timeText = time.length == 6
        ? '${time.substring(0, 2)}:${time.substring(2, 4)}:${time.substring(4, 6)}'
        : (() {
            final millis = int.tryParse(time);
            if (millis == null) return '';
            final dateTime = DateTime.fromMillisecondsSinceEpoch(millis);
            return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
          })();
    return timeText.isEmpty
        ? ''
        : '촬영일: $date $timeText\n차량번호: $plate\n촬영자: $user';
  } catch (_) {
    return '';
  }
}
