import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../application/description_content.dart';
import '../application/description_models.dart';
import 'widgets/description_navigation_panel.dart';
import 'widgets/description_section_card.dart';

class DescriptionPage extends StatefulWidget {
  const DescriptionPage({super.key});

  @override
  State<DescriptionPage> createState() => _DescriptionPageState();
}

class _DescriptionPageState extends State<DescriptionPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final DescriptionBook _book = parkinWorkinDescriptionBook;
  late final PageController _pageController = PageController();
  int _activeIndex = 0;

  String get _activeSectionId {
    if (_book.sections.isEmpty) {
      return '';
    }
    final safeIndex = math.min(math.max(_activeIndex, 0), _book.sections.length - 1);
    return _book.sections[safeIndex].id;
  }

  DescriptionSection? get _currentSection {
    if (_book.sections.isEmpty) {
      return null;
    }
    final safeIndex = math.min(math.max(_activeIndex, 0), _book.sections.length - 1);
    return _book.sections[safeIndex];
  }

  DescriptionChapter? get _currentChapter {
    final section = _currentSection;
    if (section == null) {
      return null;
    }
    return _book.chapterForSection(section.id);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _jumpToSection(String sectionId) async {
    final index = _book.indexOfSection(sectionId);
    if (index < 0) {
      return;
    }

    if (_activeIndex != index) {
      setState(() => _activeIndex = index);
    }

    if (!_pageController.hasClients) {
      return;
    }

    await _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final media = MediaQuery.of(context);
    final wide = media.size.width >= 1180;
    final currentSection = _currentSection;
    final currentChapter = _currentChapter;
    final currentIndex = currentSection == null ? -1 : _book.indexOfSection(currentSection.id);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _book.title,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 2),
            Text(
              currentSection == null
                  ? _book.subtitle
                  : '${currentChapter?.title ?? ''} · ${currentSection.title} · ${(currentIndex + 1).toString().padLeft(2, '0')} / ${_book.totalSections}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          if (!wide)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: TextButton(
                  onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                  child: Text(
                    '목차',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: cs.primary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      endDrawer: wide
          ? null
          : Drawer(
              width: 336,
              child: DescriptionNavigationPanel(
                book: _book,
                activeSectionId: _activeSectionId,
                onTapSection: (sectionId) async {
                  Navigator.of(context).pop();
                  await _jumpToSection(sectionId);
                },
              ),
            ),
      body: Row(
        children: [
          if (wide)
            SizedBox(
              width: 336,
              child: DescriptionNavigationPanel(
                book: _book,
                activeSectionId: _activeSectionId,
                onTapSection: _jumpToSection,
              ),
            ),
          Expanded(
            child: Column(
              children: [
                if (!wide && currentSection != null)
                  _CurrentLocationBar(
                    chapterTitle: currentChapter?.title ?? '',
                    sectionTitle: currentSection.title,
                    pageLabel: '${(currentIndex + 1).toString().padLeft(2, '0')} / ${_book.totalSections}',
                  ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final horizontalPadding = wide ? 24.0 : media.size.width < 420 ? 12.0 : 16.0;
                      final verticalPadding = wide ? 24.0 : media.size.height < 760 ? 12.0 : 16.0;
                      final cardHeight = math.max(
                        320.0,
                        constraints.maxHeight - (verticalPadding * 2),
                      );

                      return PageView.builder(
                        controller: _pageController,
                        scrollDirection: Axis.vertical,
                        physics: const PageScrollPhysics(),
                        itemCount: _book.totalSections,
                        onPageChanged: (index) {
                          if (_activeIndex != index) {
                            setState(() => _activeIndex = index);
                          }
                        },
                        itemBuilder: (context, index) {
                          final section = _book.sections[index];
                          return Padding(
                            padding: EdgeInsets.fromLTRB(
                              horizontalPadding,
                              verticalPadding,
                              horizontalPadding,
                              verticalPadding,
                            ),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 1280),
                                child: SizedBox(
                                  height: cardHeight,
                                  child: DescriptionSectionCard(
                                    section: section,
                                    pageNumber: index + 1,
                                    totalPages: _book.totalSections,
                                    minHeight: cardHeight,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CurrentLocationBar extends StatelessWidget {
  const _CurrentLocationBar({
    required this.chapterTitle,
    required this.sectionTitle,
    required this.pageLabel,
  });

  final String chapterTitle;
  final String sectionTitle;
  final String pageLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.45)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  chapterTitle,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sectionTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Text(
            pageLabel,
            style: theme.textTheme.labelLarge?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
