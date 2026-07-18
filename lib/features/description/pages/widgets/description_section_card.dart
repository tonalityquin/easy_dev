import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../application/description_models.dart';

Future<void> _showImagePreviewDialog(
  BuildContext context,
  DescriptionMediaSpec media,
) {
  final assetPath = media.assetPath;
  if (assetPath == null || assetPath.trim().isEmpty) {
    return Future.value();
  }

  final tokens = PromptUiTheme.of(context);
  final reduceMotion =
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  return showGeneralDialog<void>(
    context: context,
    barrierLabel: '이미지 미리보기 닫기',
    barrierDismissible: true,
    barrierColor: tokens.scrim,
    transitionDuration:
        reduceMotion ? Duration.zero : PromptUiMotion.component,
    pageBuilder: (context, animation, secondaryAnimation) {
      return PromptUiScope(
        child: Builder(
          builder: (context) {
            final theme = Theme.of(context);
            final dialogTokens = PromptUiTheme.of(context);

            return SafeArea(
              minimum: const EdgeInsets.all(12),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 1400,
                    maxHeight: 1000,
                  ),
                  child: Material(
                    color: dialogTokens.transparent,
                    child: Container(
                      width: double.infinity,
                      height: double.infinity,
                      decoration: BoxDecoration(
                        color: dialogTokens.surfaceRaised,
                        borderRadius:
                            BorderRadius.circular(PromptUiShapes.dialog),
                        border: Border.all(
                          color: dialogTokens.borderSubtle,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: dialogTokens.shadow,
                            blurRadius: 28,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius:
                            BorderRadius.circular(PromptUiShapes.dialog),
                        child: Column(
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: dialogTokens.surface,
                                border: Border(
                                  bottom: BorderSide(
                                    color: dialogTokens.borderSubtle,
                                  ),
                                ),
                              ),
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 12, 12, 12),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: dialogTokens.accentContainer,
                                        borderRadius: BorderRadius.circular(
                                          PromptUiShapes.control,
                                        ),
                                        border: Border.all(
                                          color: dialogTokens.accent.withOpacity(
                                            dialogTokens.isDark ? 0.58 : 0.38,
                                          ),
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.image_search_rounded,
                                        size: 22,
                                        color:
                                            dialogTokens.onAccentContainer,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        media.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.titleLarge
                                            ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: dialogTokens.textPrimary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    PromptIconButton(
                                      icon: Icons.close_rounded,
                                      tooltip: '닫기',
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                      haptic: PromptHaptic.selection,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                    PromptUiShapes.card,
                                  ),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: dialogTokens.surfaceOverlay,
                                      border: Border.all(
                                        color: dialogTokens.borderSubtle,
                                      ),
                                    ),
                                    child: InteractiveViewer(
                                      minScale: 1,
                                      maxScale: 4,
                                      child: Center(
                                        child: Image.asset(
                                          assetPath,
                                          fit: BoxFit.contain,
                                          errorBuilder:
                                              (context, error, stackTrace) =>
                                                  _MediaFallback(
                                            media: media,
                                            layout:
                                                DescriptionSectionLayout.portrait,
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
              ),
            );
          },
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: PromptUiMotion.enter,
        reverseCurve: PromptUiMotion.exit,
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
    final tokens = PromptUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return AnimatedContainer(
      duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
      curve: PromptUiMotion.standard,
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: tokens.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: tokens.shadow,
            blurRadius: tokens.isDark ? 18 : 24,
            offset: const Offset(0, 10),
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
    final tokens = PromptUiTheme.of(context);

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
            color: tokens.accentContainer,
            borderRadius: BorderRadius.circular(PromptUiShapes.pill),
            border: Border.all(
              color: tokens.accent.withOpacity(
                tokens.isDark ? 0.62 : 0.42,
              ),
            ),
          ),
          child: Text(
            '${pageNumber.toString().padLeft(2, '0')} / $totalPages',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: tokens.onAccentContainer,
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
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final useSideBySide = width >= 1040 && viewportHeight >= 560;
    final image = PromptAnimatedReveal(
      duration: PromptUiMotion.component,
      offset: const Offset(-0.025, 0),
      child: _MediaPanel(
        media: section.media,
        layout: section.layout,
        preferredAspectRatio: preferredAspectRatio,
        maxPanelHeight: useSideBySide
            ? math.min(viewportHeight - 8, 620.0)
            : math.min(
                viewportHeight * (viewportHeight < 620 ? 0.34 : 0.44),
                viewportHeight < 620 ? 240.0 : 320.0,
              ),
      ),
    );
    final text = PromptAnimatedReveal(
      delay: reduceMotion ? Duration.zero : const Duration(milliseconds: 50),
      duration: PromptUiMotion.component,
      offset: const Offset(0.025, 0),
      child: _TextPanel(
        section: section,
        compact: width < 560 || viewportHeight < 620,
      ),
    );

    if (useSideBySide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 10, child: image),
          const SizedBox(width: 16),
          Expanded(
            flex: 12,
            child: text,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        image,
        const SizedBox(height: 14),
        Expanded(child: text),
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
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PromptAnimatedReveal(
          child: _MediaPanel(
            media: section.media,
            layout: section.layout,
            preferredAspectRatio: preferredAspectRatio,
            maxPanelHeight: math.min(viewportHeight * 0.4, 300.0),
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: PromptAnimatedReveal(
            delay:
                reduceMotion ? Duration.zero : const Duration(milliseconds: 50),
            child: _TextPanel(
              section: section,
              compact: viewportHeight < 560,
            ),
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
        child: PromptAnimatedReveal(
          child: _TextPanel(
            section: section,
            compact: viewportHeight < 560,
          ),
        ),
      ),
    );
  }
}

class _MediaPanel extends StatefulWidget {
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
  State<_MediaPanel> createState() => _MediaPanelState();
}

class _MediaPanelState extends State<_MediaPanel> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = PromptUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final minHeight = widget.layout == DescriptionSectionLayout.landscape
        ? 160.0
        : 200.0;
    final hasAsset = widget.media.assetPath != null &&
        widget.media.assetPath!.trim().isNotEmpty;
    final borderColor = _focused
        ? tokens.focusRing
        : _hovered
            ? tokens.borderStrong
            : tokens.borderSubtle;

    return AnimatedContainer(
      duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
      curve: PromptUiMotion.standard,
      decoration: BoxDecoration(
        color: tokens.surfaceOverlay,
        borderRadius: BorderRadius.circular(PromptUiShapes.sheet),
        border: Border.all(color: borderColor),
        boxShadow: [
          if (_hovered && hasAsset)
            BoxShadow(
              color: tokens.shadow,
              blurRadius: 16,
              offset: const Offset(0, 7),
            ),
        ],
      ),
      padding: const EdgeInsets.all(10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final resolvedHeight = math.max(
            minHeight,
            math.min(
              widget.maxPanelHeight,
              constraints.maxWidth / widget.preferredAspectRatio,
            ),
          );
          final resolvedWidth = math.min(
            constraints.maxWidth,
            resolvedHeight * widget.preferredAspectRatio,
          );

          final mediaWidget = hasAsset
              ? Semantics(
                  button: true,
                  label: '${widget.media.title} 이미지 확대',
                  child: Tooltip(
                    message: '이미지 확대',
                    child: Material(
                      color: tokens.surface,
                      borderRadius:
                          BorderRadius.circular(PromptUiShapes.card),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () =>
                            _showImagePreviewDialog(context, widget.media),
                        onHover: (value) => setState(() => _hovered = value),
                        onFocusChange: (value) =>
                            setState(() => _focused = value),
                        onHighlightChanged: (value) =>
                            setState(() => _pressed = value),
                        borderRadius:
                            BorderRadius.circular(PromptUiShapes.card),
                        child: AnimatedScale(
                          scale: _pressed ? 0.99 : 1,
                          duration: reduceMotion
                              ? Duration.zero
                              : PromptUiMotion.press,
                          curve: PromptUiMotion.enter,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.asset(
                                widget.media.assetPath!,
                                fit: BoxFit.contain,
                                alignment: Alignment.topCenter,
                                errorBuilder:
                                    (context, error, stackTrace) =>
                                        _MediaFallback(
                                  media: widget.media,
                                  layout: widget.layout,
                                ),
                              ),
                              Positioned(
                                right: 12,
                                top: 12,
                                child: AnimatedContainer(
                                  duration: reduceMotion
                                      ? Duration.zero
                                      : PromptUiMotion.selection,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _hovered
                                        ? tokens.accentContainer
                                        : tokens.surfaceRaised.withOpacity(0.94),
                                    borderRadius: BorderRadius.circular(
                                      PromptUiShapes.pill,
                                    ),
                                    border: Border.all(
                                      color: _hovered
                                          ? tokens.accent
                                          : tokens.borderSubtle,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: tokens.shadow,
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.zoom_in_rounded,
                                        size: 16,
                                        color: _hovered
                                            ? tokens.onAccentContainer
                                            : tokens.iconPrimary,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '확대',
                                        style: theme.textTheme.labelLarge
                                            ?.copyWith(
                                          color: _hovered
                                              ? tokens.onAccentContainer
                                              : tokens.textPrimary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              : _MediaFallback(
                  media: widget.media,
                  layout: widget.layout,
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
    final tokens = PromptUiTheme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxHeight < 240 || constraints.maxWidth < 260;
        final tiny = constraints.maxHeight < 180 || constraints.maxWidth < 220;
        final iconBox = tiny
            ? 48.0
            : compact
                ? 60.0
                : 76.0;
        final iconSize = tiny
            ? 24.0
            : compact
                ? 30.0
                : 36.0;
        final outerPadding = tiny
            ? 12.0
            : compact
                ? 16.0
                : 24.0;

        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                tokens.surfaceOverlay,
                tokens.accentContainer,
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
                        color: tokens.surfaceRaised.withOpacity(0.88),
                        border: Border.all(color: tokens.borderSubtle),
                      ),
                      child: Icon(
                        media.icon,
                        size: iconSize,
                        color: tokens.accentPressed,
                      ),
                    ),
                    SizedBox(height: tiny ? 10 : 14),
                    Text(
                      media.title,
                      textAlign: TextAlign.center,
                      maxLines: tiny ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: tokens.textPrimary,
                        fontSize: tiny
                            ? 15
                            : compact
                                ? 18
                                : 22,
                      ),
                    ),
                    SizedBox(height: tiny ? 6 : 8),
                    Text(
                      media.caption,
                      textAlign: TextAlign.center,
                      maxLines: tiny
                          ? 2
                          : compact
                              ? 3
                              : 4,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: tokens.textSecondary,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                        fontSize: tiny
                            ? 11
                            : compact
                                ? 12
                                : 14,
                      ),
                    ),
                    if (!tiny &&
                        (media.slotName ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.surfaceRaised.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(
                            PromptUiShapes.pill,
                          ),
                          border: Border.all(color: tokens.borderSubtle),
                        ),
                        child: Text(
                          media.slotName!,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: tokens.textPrimary,
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

class _TextPanel extends StatefulWidget {
  const _TextPanel({
    required this.section,
    required this.compact,
  });

  final DescriptionSection section;
  final bool compact;

  @override
  State<_TextPanel> createState() => _TextPanelState();
}

class _TextPanelState extends State<_TextPanel> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void didUpdateWidget(covariant _TextPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section.id != widget.section.id &&
        _scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = PromptUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return LayoutBuilder(
      builder: (context, constraints) {
        final veryCompact =
            constraints.maxHeight < 280 || constraints.maxWidth < 340;
        final tight =
            constraints.maxHeight < 360 || constraints.maxWidth < 420;
        final bodyPadding = veryCompact
            ? 14.0
            : widget.compact || tight
                ? 18.0
                : 24.0;
        final titleStyle = theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: tokens.textPrimary,
          height: 1.2,
          fontSize: veryCompact
              ? 22
              : tight
                  ? 24
                  : 28,
        );
        final summaryStyle = theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: tokens.textSecondary,
          height: 1.45,
          fontSize: veryCompact
              ? 14
              : tight
                  ? 15
                  : 17,
        );
        final paragraphStyle = theme.textTheme.bodyLarge?.copyWith(
          height: 1.6,
          fontWeight: FontWeight.w400,
          color: tokens.textPrimary,
          fontSize: veryCompact
              ? 13
              : tight
                  ? 14
                  : 15,
        );
        final bulletStyle = theme.textTheme.bodyLarge?.copyWith(
          height: 1.5,
          fontWeight: FontWeight.w500,
          color: tokens.textPrimary,
          fontSize: veryCompact
              ? 13
              : tight
                  ? 14
                  : 15,
        );
        final bulletDotStyle = bulletStyle?.copyWith(
          color: tokens.accentPressed,
          fontWeight: FontWeight.w700,
        );

        return AnimatedContainer(
          duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
          curve: PromptUiMotion.standard,
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(PromptUiShapes.sheet),
            border: Border.all(color: tokens.borderSubtle),
          ),
          padding: EdgeInsets.all(bodyPadding),
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility:
                constraints.maxHeight >= 320 && constraints.maxWidth >= 340,
            child: SingleChildScrollView(
              controller: _scrollController,
              primary: false,
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.only(right: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.section.title,
                    style: titleStyle,
                  ),
                  SizedBox(height: veryCompact ? 8 : 10),
                  Text(
                    widget.section.summary,
                    style: summaryStyle,
                  ),
                  if (widget.section.paragraphs.isNotEmpty) ...[
                    SizedBox(height: veryCompact ? 10 : 14),
                    for (final paragraph in widget.section.paragraphs) ...[
                      Text(
                        paragraph,
                        style: paragraphStyle,
                      ),
                      SizedBox(height: veryCompact ? 8 : 10),
                    ],
                  ],
                  if (widget.section.bullets.isNotEmpty) ...[
                    SizedBox(height: veryCompact ? 4 : 8),
                    for (final bullet in widget.section.bullets) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: EdgeInsets.only(
                              top: veryCompact ? 0 : 1,
                            ),
                            child: Text(
                              '• ',
                              style: bulletDotStyle,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              bullet,
                              style: bulletStyle,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: veryCompact ? 6 : 8),
                    ],
                  ],
                ],
              ),
            ),
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
    final tokens = PromptUiTheme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.surfaceOverlay,
        borderRadius: BorderRadius.circular(PromptUiShapes.pill),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: tokens.textPrimary,
        ),
      ),
    );
  }
}
