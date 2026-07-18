import 'package:flutter/material.dart';

import '../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../application/description_models.dart';

class DescriptionNavigationPanel extends StatelessWidget {
  const DescriptionNavigationPanel({
    super.key,
    required this.book,
    required this.activeSectionId,
    required this.onTapSection,
  });

  final DescriptionBook book;
  final String activeSectionId;
  final ValueChanged<String> onTapSection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = PromptUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(
          right: BorderSide(color: tokens.borderSubtle),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: tokens.accentContainer,
                      borderRadius:
                          BorderRadius.circular(PromptUiShapes.control),
                      border: Border.all(
                        color: tokens.accent.withOpacity(
                          tokens.isDark ? 0.58 : 0.38,
                        ),
                      ),
                    ),
                    child: Icon(
                      Icons.auto_stories_rounded,
                      size: 22,
                      color: tokens.onAccentContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          book.title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          book.subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: tokens.textSecondary,
                            fontWeight: FontWeight.w500,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _TopChip(label: '${book.totalSections}페이지'),
                  _TopChip(label: '가로 ${book.landscapeSectionCount}'),
                  _TopChip(label: '텍스트 ${book.textOnlySectionCount}'),
                ],
              ),
              const SizedBox(height: 16),
              Divider(height: 1, color: tokens.borderSubtle),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (var index = 0;
                        index < book.chapters.length;
                        index++)
                      PromptAnimatedReveal(
                        delay: reduceMotion
                            ? Duration.zero
                            : Duration(milliseconds: 28 * index),
                        offset: const Offset(-0.025, 0),
                        child: _ChapterGroup(
                          chapter: book.chapters[index],
                          activeSectionId: activeSectionId,
                          onTapSection: onTapSection,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopChip extends StatelessWidget {
  const _TopChip({required this.label});

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

class _ChapterGroup extends StatelessWidget {
  const _ChapterGroup({
    required this.chapter,
    required this.activeSectionId,
    required this.onTapSection,
  });

  final DescriptionChapter chapter;
  final String activeSectionId;
  final ValueChanged<String> onTapSection;

  @override
  Widget build(BuildContext context) {
    final isActiveChapter =
        chapter.sections.any((section) => section.id == activeSectionId);

    if (!chapter.hasChildren && chapter.sections.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _NavTile(
          label: chapter.title,
          subtitle: chapter.summary,
          selected: isActiveChapter,
          badge: chapter.sections.length.toString(),
          onTap: () => onTapSection(chapter.primarySectionId),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ChapterHeader(
            chapter: chapter,
            selected: isActiveChapter,
            onTap: () => onTapSection(chapter.primarySectionId),
          ),
          const SizedBox(height: 6),
          for (final section in chapter.sections)
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 6),
              child: _NavTile(
                label: section.tocTitle ?? section.title,
                selected: section.id == activeSectionId,
                dense: true,
                badge: section.layout == DescriptionSectionLayout.landscape
                    ? '가로'
                    : section.layout == DescriptionSectionLayout.textOnly
                        ? '텍스트'
                        : null,
                onTap: () => onTapSection(section.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChapterHeader extends StatefulWidget {
  const _ChapterHeader({
    required this.chapter,
    required this.selected,
    required this.onTap,
  });

  final DescriptionChapter chapter;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ChapterHeader> createState() => _ChapterHeaderState();
}

class _ChapterHeaderState extends State<_ChapterHeader> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = PromptUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final active = widget.selected;
    final background = active
        ? tokens.surfaceSelected
        : _hovered
            ? tokens.surfaceOverlay
            : tokens.transparent;
    final border = _focused
        ? tokens.focusRing
        : active
            ? tokens.accent.withOpacity(tokens.isDark ? 0.66 : 0.46)
            : tokens.transparent;

    return Semantics(
      button: true,
      selected: active,
      label: widget.chapter.title,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
        curve: PromptUiMotion.standard,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(PromptUiShapes.card),
          border: Border.all(color: border),
        ),
        child: Material(
          color: tokens.transparent,
          borderRadius: BorderRadius.circular(PromptUiShapes.card),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            onHover: (value) => setState(() => _hovered = value),
            onFocusChange: (value) => setState(() => _focused = value),
            onHighlightChanged: (value) => setState(() => _pressed = value),
            borderRadius: BorderRadius.circular(PromptUiShapes.card),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: AnimatedScale(
                scale: _pressed ? 0.985 : 1,
                duration:
                    reduceMotion ? Duration.zero : PromptUiMotion.press,
                curve: PromptUiMotion.enter,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.chapter.title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: active
                                  ? tokens.onAccentContainer
                                  : tokens.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.chapter.summary,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: active
                                  ? tokens.onAccentContainer.withOpacity(0.82)
                                  : tokens.textSecondary,
                              fontWeight: FontWeight.w500,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _CountBadge(
                      label: '${widget.chapter.sections.length}',
                      selected: active,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavTile extends StatefulWidget {
  const _NavTile({
    required this.label,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.badge,
    this.dense = false,
  });

  final String label;
  final String? subtitle;
  final String? badge;
  final bool selected;
  final bool dense;
  final VoidCallback onTap;

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = PromptUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final background = widget.selected
        ? tokens.surfaceSelected
        : _hovered || _pressed
            ? tokens.surfaceOverlay
            : tokens.transparent;
    final border = _focused
        ? tokens.focusRing
        : widget.selected
            ? tokens.accent.withOpacity(tokens.isDark ? 0.66 : 0.46)
            : tokens.borderSubtle;

    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.label,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
        curve: PromptUiMotion.standard,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(PromptUiShapes.button),
          color: background,
          border: Border.all(color: border),
        ),
        child: Material(
          color: tokens.transparent,
          borderRadius: BorderRadius.circular(PromptUiShapes.button),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: BorderRadius.circular(PromptUiShapes.button),
            onTap: widget.onTap,
            onHover: (value) => setState(() => _hovered = value),
            onFocusChange: (value) => setState(() => _focused = value),
            onHighlightChanged: (value) => setState(() => _pressed = value),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: widget.dense ? 12 : 14,
                vertical: widget.dense ? 10 : 12,
              ),
              child: AnimatedScale(
                scale: _pressed ? 0.985 : 1,
                duration:
                    reduceMotion ? Duration.zero : PromptUiMotion.press,
                curve: PromptUiMotion.enter,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.selected) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.check_circle_rounded,
                          size: 18,
                          color: tokens.accentPressed,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.label,
                            style: (widget.dense
                                    ? theme.textTheme.bodyMedium
                                    : theme.textTheme.titleSmall)
                                ?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: widget.selected
                                  ? tokens.onAccentContainer
                                  : tokens.textPrimary,
                            ),
                          ),
                          if (widget.subtitle != null &&
                              widget.subtitle!.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              widget.subtitle!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: widget.selected
                                    ? tokens.onAccentContainer.withOpacity(0.82)
                                    : tokens.textSecondary,
                                fontWeight: FontWeight.w500,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (widget.badge != null) ...[
                      const SizedBox(width: 8),
                      _CountBadge(
                        label: widget.badge!,
                        selected: widget.selected,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({
    required this.label,
    required this.selected,
  });

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = PromptUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return AnimatedContainer(
      duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(PromptUiShapes.pill),
        color: selected ? tokens.accent : tokens.surfaceOverlay,
        border: Border.all(
          color: selected ? tokens.accent : tokens.borderSubtle,
        ),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: selected ? tokens.onAccent : tokens.textPrimary,
        ),
      ),
    );
  }
}
