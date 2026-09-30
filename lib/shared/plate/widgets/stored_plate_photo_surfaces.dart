import 'package:flutter/material.dart';

import '../../../design_system/common_ui/common_ui_theme.dart';
import '../editor/domain/stored_plate_photo.dart';

class StoredPlatePhotoListSurface extends StatelessWidget {
  const StoredPlatePhotoListSurface({
    super.key,
    required this.photos,
    required this.onSelect,
    this.onThumbnailRequested,
  });

  final List<StoredPlatePhoto> photos;
  final ValueChanged<int> onSelect;
  final ValueChanged<StoredPlatePhoto>? onThumbnailRequested;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(CommonUiShapes.card),
        border: Border.all(color: tokens.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: photos.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          color: tokens.borderSubtle,
        ),
        itemBuilder: (context, index) {
          final photo = photos[index];
          if (onThumbnailRequested != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              onThumbnailRequested?.call(photo);
            });
          }
          return Material(
            color: tokens.transparent,
            child: InkWell(
              onTap: () => onSelect(index),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ThumbnailBox(photo: photo),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _AssetBadge(
                            label: photo.hasThumbnail
                                ? 'THUMBNAIL'
                                : 'THUMBNAIL 없음',
                            active: photo.hasThumbnail,
                          ),
                          const SizedBox(height: 8),
                          _MetadataRows(metadata: photo.metadata),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Padding(
                      padding: const EdgeInsets.only(top: 32),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: tokens.iconSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class StoredPlatePhotoThumbnailPreviewSurface extends StatefulWidget {
  const StoredPlatePhotoThumbnailPreviewSurface({
    super.key,
    required this.photos,
    required this.initialIndex,
    required this.onBack,
    required this.onOpenDisplay,
    this.onPageChanged,
    this.onThumbnailRequested,
    this.trailing,
  });

  final List<StoredPlatePhoto> photos;
  final int initialIndex;
  final VoidCallback onBack;
  final ValueChanged<int> onOpenDisplay;
  final ValueChanged<int>? onPageChanged;
  final ValueChanged<StoredPlatePhoto>? onThumbnailRequested;
  final Widget? trailing;

  @override
  State<StoredPlatePhotoThumbnailPreviewSurface> createState() =>
      _StoredPlatePhotoThumbnailPreviewSurfaceState();
}

class _StoredPlatePhotoThumbnailPreviewSurfaceState
    extends State<StoredPlatePhotoThumbnailPreviewSurface> {
  late final PageController _controller;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.photos.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.photos.length - 1).toInt();
    _controller = PageController(initialPage: _currentIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.photos.isEmpty) return;
      widget.onThumbnailRequested?.call(widget.photos[_currentIndex]);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handlePageChanged(int index) {
    if (index < 0 || index >= widget.photos.length) return;
    setState(() => _currentIndex = index);
    widget.onThumbnailRequested?.call(widget.photos[index]);
    widget.onPageChanged?.call(index);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    if (widget.photos.isEmpty) {
      return Center(
        child: Text(
          '표시할 사진이 없습니다.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: tokens.textSecondary,
              ),
        ),
      );
    }
    final current = widget.photos[_currentIndex];
    return Container(
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
                IconButton(
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: tokens.iconPrimary,
                ),
                const SizedBox(width: 4),
                _AssetBadge(
                  label: current.hasThumbnail ? 'THUMBNAIL' : 'THUMBNAIL 없음',
                  active: current.hasThumbnail,
                ),
                const Spacer(),
                Text(
                  '${_currentIndex + 1} / ${widget.photos.length}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                if (widget.trailing != null) ...[
                  const SizedBox(width: 6),
                  widget.trailing!,
                ],
              ],
            ),
          ),
          Divider(height: 1, color: tokens.borderSubtle),
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.photos.length,
              onPageChanged: _handlePageChanged,
              itemBuilder: (context, index) {
                final photo = widget.photos[index];
                return Padding(
                  padding: const EdgeInsets.all(10),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onDoubleTap: () => widget.onOpenDisplay(index),
                    child: _NetworkPhotoImage(
                      url: photo.gridThumbnailUrl,
                      filterQuality: FilterQuality.low,
                      cacheWidth: 800,
                    ),
                  ),
                );
              },
            ),
          ),
          Divider(height: 1, color: tokens.borderSubtle),
          Container(
            width: double.infinity,
            color: tokens.surfaceRaised,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: _MetadataRows(metadata: current.metadata),
          ),
        ],
      ),
    );
  }
}

class _ThumbnailBox extends StatelessWidget {
  const _ThumbnailBox({required this.photo});

  final StoredPlatePhoto photo;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final url = photo.gridThumbnailUrl;
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: tokens.surfaceOverlay,
        borderRadius: BorderRadius.circular(CommonUiShapes.control),
        border: Border.all(color: tokens.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: url == null
          ? Center(
              child: Icon(
                Icons.image_outlined,
                size: 34,
                color: tokens.iconSecondary,
              ),
            )
          : Image.network(
              url,
              fit: BoxFit.cover,
              cacheWidth: 400,
              filterQuality: FilterQuality.low,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: tokens.accent,
                    ),
                  ),
                );
              },
              errorBuilder: (_, __, ___) => Center(
                child: Icon(
                  Icons.broken_image_rounded,
                  size: 30,
                  color: tokens.danger,
                ),
              ),
            ),
    );
  }
}

class _NetworkPhotoImage extends StatelessWidget {
  const _NetworkPhotoImage({
    required this.url,
    required this.filterQuality,
    this.cacheWidth,
  });

  final String? url;
  final FilterQuality filterQuality;
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    if (url == null || url!.trim().isEmpty) {
      return Center(
        child: Icon(
          Icons.image_outlined,
          size: 44,
          color: tokens.iconSecondary,
        ),
      );
    }
    return Image.network(
      url!,
      fit: BoxFit.contain,
      cacheWidth: cacheWidth,
      filterQuality: filterQuality,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Center(
          child: CircularProgressIndicator(color: tokens.accent),
        );
      },
      errorBuilder: (_, __, ___) => Center(
        child: Icon(
          Icons.broken_image_rounded,
          size: 44,
          color: tokens.danger,
        ),
      ),
    );
  }
}

class _AssetBadge extends StatelessWidget {
  const _AssetBadge({
    required this.label,
    required this.active,
  });

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: active ? tokens.accentContainer : tokens.surfaceOverlay,
        borderRadius: BorderRadius.circular(CommonUiShapes.pill),
        border: Border.all(
          color: active ? tokens.accent.withOpacity(.45) : tokens.borderSubtle,
        ),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: active ? tokens.onAccentContainer : tokens.textSecondary,
              fontWeight: FontWeight.w900,
              letterSpacing: .3,
            ),
      ),
    );
  }
}

class _MetadataRows extends StatelessWidget {
  const _MetadataRows({required this.metadata});

  final StoredPlatePhotoMetadata metadata;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MetadataRow(label: '촬영일', value: metadata.capturedDate),
        const SizedBox(height: 4),
        _MetadataRow(label: '촬영 시간', value: metadata.capturedTime),
        const SizedBox(height: 4),
        _MetadataRow(label: '차량번호', value: metadata.plateNumber),
        const SizedBox(height: 4),
        _MetadataRow(label: '촬영자', value: metadata.capturedBy),
      ],
    );
  }
}

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final shown = value.trim().isEmpty ? '-' : value.trim();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 62,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            shown,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
      ],
    );
  }
}
