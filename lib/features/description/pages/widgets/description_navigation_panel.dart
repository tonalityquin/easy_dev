import 'package:flutter/material.dart';

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
    final cs = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(
          right: BorderSide(color: cs.outlineVariant.withOpacity(0.45)),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                book.title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                book.subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  height: 1.45,
                ),
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
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (final chapter in book.chapters)
                      _ChapterGroup(
                        chapter: chapter,
                        activeSectionId: activeSectionId,
                        onTapSection: onTapSection,
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isActiveChapter = chapter.sections.any((section) => section.id == activeSectionId);

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
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => onTapSection(chapter.primarySectionId),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: isActiveChapter ? cs.primaryContainer.withOpacity(0.75) : Colors.transparent,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          chapter.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: isActiveChapter ? cs.onPrimaryContainer : cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          chapter.summary,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _CountBadge(
                    label: '${chapter.sections.length}',
                    selected: isActiveChapter,
                  ),
                ],
              ),
            ),
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

class _NavTile extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(
            horizontal: dense ? 12 : 14,
            vertical: dense ? 10 : 12,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: selected ? cs.primaryContainer : Colors.transparent,
            border: Border.all(
              color: selected
                  ? cs.primary.withOpacity(0.28)
                  : cs.outlineVariant.withOpacity(0.45),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: (dense ? theme.textTheme.bodyMedium : theme.textTheme.titleSmall)?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: selected ? cs.onPrimaryContainer : cs.onSurface,
                      ),
                    ),
                    if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 8),
                _CountBadge(label: badge!, selected: selected),
              ],
            ],
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
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: selected ? cs.primary : cs.surfaceContainerHighest,
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w900,
          color: selected ? cs.onPrimary : cs.onSurface,
        ),
      ),
    );
  }
}
