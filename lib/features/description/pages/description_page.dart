import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../design_system/prompt_ui/prompt_ui_theme.dart';
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
    final safeIndex = math.min(
      math.max(_activeIndex, 0),
      _book.sections.length - 1,
    );
    return _book.sections[safeIndex].id;
  }

  DescriptionSection? get _currentSection {
    if (_book.sections.isEmpty) {
      return null;
    }
    final safeIndex = math.min(
      math.max(_activeIndex, 0),
      _book.sections.length - 1,
    );
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

    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _pageController.jumpToPage(index);
      return;
    }

    await _pageController.animateToPage(
      index,
      duration: PromptUiMotion.overlay,
      curve: PromptUiMotion.enter,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PromptUiScope(
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final tokens = PromptUiTheme.of(context);
          final media = MediaQuery.of(context);
          final wide = media.size.width >= 1180;
          final reduceMotion = media.disableAnimations;
          final currentSection = _currentSection;
          final currentChapter = _currentChapter;
          final currentIndex = currentSection == null
              ? -1
              : _book.indexOfSection(currentSection.id);
          final overlayStyle = SystemUiOverlayStyle(
            statusBarColor: tokens.transparent,
            statusBarIconBrightness:
                tokens.isDark ? Brightness.light : Brightness.dark,
            statusBarBrightness:
                tokens.isDark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: tokens.surface,
            systemNavigationBarIconBrightness:
                tokens.isDark ? Brightness.light : Brightness.dark,
            systemNavigationBarDividerColor: tokens.borderSubtle,
          );

          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: overlayStyle,
            child: Scaffold(
              key: _scaffoldKey,
              backgroundColor: tokens.canvas,
              appBar: AppBar(
                backgroundColor: tokens.surface,
                foregroundColor: tokens.textPrimary,
                surfaceTintColor: tokens.transparent,
                elevation: 0,
                scrolledUnderElevation: 0,
                systemOverlayStyle: overlayStyle,
                titleSpacing: 0,
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _book.title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    AnimatedSwitcher(
                      duration: reduceMotion
                          ? Duration.zero
                          : PromptUiMotion.selection,
                      switchInCurve: PromptUiMotion.enter,
                      switchOutCurve: PromptUiMotion.exit,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.14),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: Text(
                        currentSection == null
                            ? _book.subtitle
                            : '${currentChapter?.title ?? ''} · ${currentSection.title} · ${(currentIndex + 1).toString().padLeft(2, '0')} / ${_book.totalSections}',
                        key: ValueKey<String>(_activeSectionId),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: tokens.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                actions: [
                  if (!wide)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Center(
                        child: PromptButton(
                          label: '목차',
                          icon: Icons.list_alt_rounded,
                          variant: PromptButtonVariant.tertiary,
                          minHeight: 42,
                          haptic: PromptHaptic.selection,
                          onPressed: () =>
                              _scaffoldKey.currentState?.openEndDrawer(),
                        ),
                      ),
                    ),
                ],
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(1),
                  child: Container(
                    height: 1,
                    color: tokens.borderSubtle,
                  ),
                ),
              ),
              endDrawer: wide
                  ? null
                  : Drawer(
                      width: 336,
                      backgroundColor: tokens.surface,
                      surfaceTintColor: tokens.transparent,
                      child: DescriptionNavigationPanel(
                        book: _book,
                        activeSectionId: _activeSectionId,
                        onTapSection: (sectionId) async {
                          Navigator.of(context).pop();
                          await _jumpToSection(sectionId);
                        },
                      ),
                    ),
              body: SafeArea(
                top: false,
                bottom: false,
                child: Row(
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
                            AnimatedSwitcher(
                              duration: reduceMotion
                                  ? Duration.zero
                                  : PromptUiMotion.selection,
                              switchInCurve: PromptUiMotion.enter,
                              switchOutCurve: PromptUiMotion.exit,
                              child: _CurrentLocationBar(
                                key: ValueKey<String>(currentSection.id),
                                chapterTitle: currentChapter?.title ?? '',
                                sectionTitle: currentSection.title,
                                pageLabel:
                                    '${(currentIndex + 1).toString().padLeft(2, '0')} / ${_book.totalSections}',
                              ),
                            ),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final horizontalPadding = wide
                                    ? 24.0
                                    : media.size.width < 420
                                        ? 12.0
                                        : 16.0;
                                final verticalPadding = wide
                                    ? 24.0
                                    : media.size.height < 760
                                        ? 12.0
                                        : 16.0;
                                final cardHeight = math.max(
                                  320.0,
                                  constraints.maxHeight -
                                      (verticalPadding * 2),
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
                                          constraints: const BoxConstraints(
                                            maxWidth: 1280,
                                          ),
                                          child: SizedBox(
                                            height: cardHeight,
                                            child: PromptAnimatedReveal(
                                              key: ValueKey<String>(
                                                'description-${section.id}',
                                              ),
                                              duration:
                                                  PromptUiMotion.component,
                                              offset: const Offset(0, 0.025),
                                              child: DescriptionSectionCard(
                                                section: section,
                                                pageNumber: index + 1,
                                                totalPages:
                                                    _book.totalSections,
                                                minHeight: cardHeight,
                                              ),
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
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CurrentLocationBar extends StatelessWidget {
  const _CurrentLocationBar({
    super.key,
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
    final tokens = PromptUiTheme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(
          bottom: BorderSide(color: tokens.borderSubtle),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: tokens.accentContainer,
                borderRadius: BorderRadius.circular(PromptUiShapes.control),
                border: Border.all(
                  color: tokens.accent.withOpacity(
                    tokens.isDark ? 0.58 : 0.38,
                  ),
                ),
              ),
              child: Icon(
                Icons.menu_book_rounded,
                size: 20,
                color: tokens.onAccentContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    chapterTitle,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: tokens.accentPressed,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sectionTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 7,
              ),
              decoration: BoxDecoration(
                color: tokens.surfaceOverlay,
                borderRadius: BorderRadius.circular(PromptUiShapes.pill),
                border: Border.all(color: tokens.borderSubtle),
              ),
              child: Text(
                pageLabel,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
