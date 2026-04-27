import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../application/description_models.dart';

Future<void> _showImagePreviewDialog(BuildContext context, DescriptionMediaSpec media) {
  final assetPath = media.assetPath;
  if (assetPath == null || assetPath.trim().isEmpty) {
    return Future.value();
  }

  return showGeneralDialog<void>(
    context: context,
    barrierLabel: 'image-preview',
    barrierDismissible: true,
    barrierColor: Colors.black.withOpacity(0.82),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, animation, secondaryAnimation) {
      final theme = Theme.of(context);
      final cs = theme.colorScheme;

      return SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: double.infinity,
                height: double.infinity,
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: cs.outlineVariant.withOpacity(0.34)),
                  boxShadow: [
                    BoxShadow(
                      color: cs.shadow.withOpacity(0.24),
                      blurRadius: 28,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              media.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('닫기'),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                            ),
                            child: InteractiveViewer(
                              minScale: 1,
                              maxScale: 4,
                              child: Center(
                                child: Image.asset(
                                  assetPath,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) => _MediaFallback(
                                    media: media,
                                    layout: DescriptionSectionLayout.portrait,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class DescriptionSectionCard extends StatelessWidget {
  const DescriptionSectionCard({
    super.key,
    required this.section,
    required this.pageNumber,
    required this.totalPages,
    required this.minHeight,
  });

  final DescriptionSection section;
  final int pageNumber;
  final int totalPages;
  final double minHeight;

  static const double _portraitAspectRatio = 921 / 2048;
  static const double _landscapeAspectRatio = 2048 / 1280;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.42)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.08),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              section: section,
              pageNumber: pageNumber,
              totalPages: totalPages,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: LayoutBuilder(
                builder: (context, bodyConstraints) {
                  return _buildBody(
                    context,
                    bodyConstraints.maxWidth,
                    math.max(220.0, bodyConstraints.maxHeight),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, double width, double height) {
    switch (section.layout) {
      case DescriptionSectionLayout.landscape:
        return _LandscapeLayout(
          section: section,
          viewportHeight: height,
          preferredAspectRatio: _landscapeAspectRatio,
        );
      case DescriptionSectionLayout.textOnly:
        return _TextOnlyLayout(
          section: section,
          viewportHeight: height,
        );
      case DescriptionSectionLayout.portrait:
        return _PortraitLayout(
          section: section,
          width: width,
          viewportHeight: height,
          preferredAspectRatio: _portraitAspectRatio,
        );
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.section,
    required this.pageNumber,
    required this.totalPages,
  });

  final DescriptionSection section;
  final int pageNumber;
  final int totalPages;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetaChip(label: section.chipLabel),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '${pageNumber.toString().padLeft(2, '0')} / $totalPages',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: cs.onPrimaryContainer,
            ),
          ),
        ),
      ],
    );
  }

}

class _PortraitLayout extends StatelessWidget {
  const _PortraitLayout({
    required this.section,
    required this.width,
    required this.viewportHeight,
    required this.preferredAspectRatio,
  });

  final DescriptionSection section;
  final double width;
  final double viewportHeight;
  final double preferredAspectRatio;

  @override
  Widget build(BuildContext context) {
    final useSideBySide = width >= 1040 && viewportHeight >= 560;
    final image = _MediaPanel(
      media: section.media,
      layout: section.layout,
      preferredAspectRatio: preferredAspectRatio,
      maxPanelHeight: useSideBySide
          ? math.min(viewportHeight - 8, 620.0)
          : math.min(viewportHeight * 0.44, 320.0),
    );

    if (useSideBySide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 10, child: image),
          const SizedBox(width: 16),
          Expanded(
            flex: 12,
            child: _TextPanel(
              section: section,
              compact: viewportHeight < 620,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        image,
        const SizedBox(height: 14),
        Expanded(
          child: _TextPanel(
            section: section,
            compact: width < 560 || viewportHeight < 620,
          ),
        ),
      ],
    );
  }
}

class _LandscapeLayout extends StatelessWidget {
  const _LandscapeLayout({
    required this.section,
    required this.viewportHeight,
    required this.preferredAspectRatio,
  });

  final DescriptionSection section;
  final double viewportHeight;
  final double preferredAspectRatio;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MediaPanel(
          media: section.media,
          layout: section.layout,
          preferredAspectRatio: preferredAspectRatio,
          maxPanelHeight: math.min(viewportHeight * 0.4, 300.0),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: _TextPanel(
            section: section,
            compact: viewportHeight < 560,
          ),
        ),
      ],
    );
  }
}

class _TextOnlyLayout extends StatelessWidget {
  const _TextOnlyLayout({
    required this.section,
    required this.viewportHeight,
  });

  final DescriptionSection section;
  final double viewportHeight;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: _TextPanel(
          section: section,
          compact: viewportHeight < 560,
        ),
      ),
    );
  }
}

class _MediaPanel extends StatelessWidget {
  const _MediaPanel({
    required this.media,
    required this.layout,
    required this.preferredAspectRatio,
    required this.maxPanelHeight,
  });

  final DescriptionMediaSpec media;
  final DescriptionSectionLayout layout;
  final double preferredAspectRatio;
  final double maxPanelHeight;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final minHeight = layout == DescriptionSectionLayout.landscape ? 160.0 : 200.0;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.36)),
      ),
      padding: const EdgeInsets.all(10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final resolvedHeight = math.max(
            minHeight,
            math.min(maxPanelHeight, constraints.maxWidth / preferredAspectRatio),
          );
          final resolvedWidth = math.min(
            constraints.maxWidth,
            resolvedHeight * preferredAspectRatio,
          );

          final hasAsset = media.assetPath != null && media.assetPath!.trim().isNotEmpty;
          final mediaWidget = hasAsset
              ? Material(
                  color: cs.surface,
                  child: InkWell(
                    onTap: () => _showImagePreviewDialog(context, media),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.asset(
                          media.assetPath!,
                          fit: BoxFit.contain,
                          alignment: Alignment.topCenter,
                          errorBuilder: (context, error, stackTrace) => _MediaFallback(
                            media: media,
                            layout: layout,
                          ),
                        ),
                        Positioned(
                          right: 12,
                          top: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.52),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '확대',
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : _MediaFallback(
                  media: media,
                  layout: layout,
                );

          return Center(
            child: SizedBox(
              width: resolvedWidth,
              height: resolvedHeight,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: mediaWidget,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MediaFallback extends StatelessWidget {
  const _MediaFallback({
    required this.media,
    required this.layout,
  });

  final DescriptionMediaSpec media;
  final DescriptionSectionLayout layout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 240 || constraints.maxWidth < 260;
        final tiny = constraints.maxHeight < 180 || constraints.maxWidth < 220;
        final iconBox = tiny ? 48.0 : compact ? 60.0 : 76.0;
        final iconSize = tiny ? 24.0 : compact ? 30.0 : 36.0;
        final outerPadding = tiny ? 12.0 : compact ? 16.0 : 24.0;

        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                cs.surfaceContainerHigh,
                cs.primaryContainer.withOpacity(0.55),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(outerPadding),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: iconBox,
                      height: iconBox,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: cs.surface.withOpacity(0.58),
                      ),
                      child: Icon(
                        media.icon,
                        size: iconSize,
                        color: cs.onSurface,
                      ),
                    ),
                    SizedBox(height: tiny ? 10 : 14),
                    Text(
                      media.title,
                      textAlign: TextAlign.center,
                      maxLines: tiny ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                        fontSize: tiny ? 15 : compact ? 18 : 22,
                      ),
                    ),
                    SizedBox(height: tiny ? 6 : 8),
                    Text(
                      media.caption,
                      textAlign: TextAlign.center,
                      maxLines: tiny ? 2 : compact ? 3 : 4,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                        fontSize: tiny ? 11 : compact ? 12 : 14,
                      ),
                    ),
                    if (!tiny && (media.slotName ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: cs.surface.withOpacity(0.72),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
                        ),
                        child: Text(
                          media.slotName!,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TextPanel extends StatelessWidget {
  const _TextPanel({
    required this.section,
    required this.compact,
  });

  final DescriptionSection section;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final veryCompact = constraints.maxHeight < 280 || constraints.maxWidth < 340;
        final tight = constraints.maxHeight < 360 || constraints.maxWidth < 420;
        final bodyPadding = veryCompact ? 14.0 : compact || tight ? 18.0 : 24.0;
        final titleStyle = theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w900,
          height: 1.15,
          fontSize: veryCompact ? 22 : tight ? 24 : 28,
        );
        final summaryStyle = theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: cs.onSurfaceVariant,
          height: 1.45,
          fontSize: veryCompact ? 14 : tight ? 15 : 17,
        );
        final paragraphStyle = theme.textTheme.bodyLarge?.copyWith(
          height: 1.6,
          fontWeight: FontWeight.w500,
          color: cs.onSurface,
          fontSize: veryCompact ? 13 : tight ? 14 : 15,
        );
        final summaryLines = veryCompact ? 2 : tight ? 3 : 4;
        final paragraphLines = veryCompact ? 2 : tight ? 3 : 4;
        final visibleParagraphs = constraints.maxHeight < 340 ? 1 : math.min(3, section.paragraphs.length);

        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.34)),
          ),
          padding: EdgeInsets.all(bodyPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Text(
                section.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              ),
              SizedBox(height: veryCompact ? 8 : 10),
              Text(
                section.summary,
                maxLines: summaryLines,
                overflow: TextOverflow.ellipsis,
                style: summaryStyle,
              ),
              SizedBox(height: veryCompact ? 10 : 14),
              for (final paragraph in section.paragraphs.take(visibleParagraphs)) ...[
                Text(
                  paragraph,
                  maxLines: paragraphLines,
                  overflow: TextOverflow.ellipsis,
                  style: paragraphStyle,
                ),
                SizedBox(height: veryCompact ? 8 : 10),
              ],
              const Spacer(),
            ],
          ),
        );
      },
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: cs.onSurface,
        ),
      ),
    );
  }
}
