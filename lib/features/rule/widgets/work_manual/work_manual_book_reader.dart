import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../domain/models/rule_model.dart';
import 'work_manual_page_card.dart';

class WorkManualBookDiagnostics {
  const WorkManualBookDiagnostics({
    required this.pageCount,
    required this.activePage,
    required this.activePageId,
    required this.pageTextLength,
    required this.pageViewportWidth,
    required this.pageViewportHeight,
    required this.textScale,
    required this.compact,
    required this.internalScroll,
  });

  final int pageCount;
  final int activePage;
  final String activePageId;
  final int pageTextLength;
  final double pageViewportWidth;
  final double pageViewportHeight;
  final double textScale;
  final bool compact;
  final bool internalScroll;
}

class WorkManualBookReader extends StatefulWidget {
  const WorkManualBookReader({
    super.key,
    required this.pages,
    this.updatedAt,
    this.onDebug,
    this.onDiagnosticsChanged,
    this.maxPageWidth = 720,
  });

  final List<RuleManualPage> pages;
  final DateTime? updatedAt;
  final ValueChanged<String>? onDebug;
  final ValueChanged<WorkManualBookDiagnostics>? onDiagnosticsChanged;
  final double maxPageWidth;

  @override
  State<WorkManualBookReader> createState() => _WorkManualBookReaderState();
}

class _WorkManualBookReaderState extends State<WorkManualBookReader> {
  late final PageController _pageController;
  int _activePage = 0;
  String? _lastDiagnosticsSignature;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void didUpdateWidget(covariant WorkManualBookReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_pageSignature(oldWidget.pages) != _pageSignature(widget.pages)) {
      _activePage = 0;
      _lastDiagnosticsSignature = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_pageController.hasClients) return;
        _pageController.jumpToPage(0);
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String _pageSignature(List<RuleManualPage> pages) {
    return normalizeRuleManualPagesForStorage(pages)
        .map((page) => '${page.id}:${page.order}:${page.content.length}')
        .join('|');
  }

  String _formatUpdatedAt(DateTime? value) {
    if (value == null) return '-';
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}.${two(local.month)}.${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  Future<void> _goToPage(int target, int pageCount, String source) async {
    if (pageCount <= 1) return;
    final next = target.clamp(0, pageCount - 1).toInt();
    if (next == _activePage) return;
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    widget.onDebug?.call(
      'work_manual_page_change_requested from=${_activePage + 1} to=${next + 1} pageCount=$pageCount source=$source storageMode=structured_pages',
    );
    if (!_pageController.hasClients) return;
    if (reduceMotion) {
      _pageController.jumpToPage(next);
    } else {
      await _pageController.animateToPage(
        next,
        duration: CommonUiMotion.overlay,
        curve: CommonUiMotion.enter,
      );
    }
  }

  void _handlePageChanged(int index, List<RuleManualPage> pages) {
    if (index == _activePage) return;
    final previous = _activePage;
    setState(() => _activePage = index);
    final page = index < pages.length ? pages[index] : null;
    widget.onDebug?.call(
      'work_manual_page_changed from=${previous + 1} to=${index + 1} pageCount=${pages.length} pageId=${page?.id ?? '-'} pageTextLength=${page?.content.length ?? 0} source=page_view storageMode=structured_pages',
    );
  }

  void _emitDiagnostics({
    required List<RuleManualPage> pages,
    required double width,
    required double height,
    required double textScale,
    required bool compact,
  }) {
    if (pages.isEmpty) return;
    final active = _activePage.clamp(0, pages.length - 1).toInt();
    final page = pages[active];
    final signature = [
      pages.length,
      active,
      page.id,
      page.content.length,
      width.toStringAsFixed(1),
      height.toStringAsFixed(1),
      textScale.toStringAsFixed(2),
      compact,
    ].join(':');
    if (_lastDiagnosticsSignature == signature) return;
    _lastDiagnosticsSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _lastDiagnosticsSignature != signature) return;
      widget.onDiagnosticsChanged?.call(
        WorkManualBookDiagnostics(
          pageCount: pages.length,
          activePage: active + 1,
          activePageId: page.id,
          pageTextLength: page.content.length,
          pageViewportWidth: width,
          pageViewportHeight: height,
          textScale: textScale,
          compact: compact,
          internalScroll: true,
        ),
      );
      widget.onDebug?.call(
        'work_manual_pages_ready storageMode=structured_pages pageCount=${pages.length} activePage=${active + 1} activePageId=${page.id} pageTextLength=${page.content.length} pageViewportWidth=${width.toStringAsFixed(1)} pageViewportHeight=${height.toStringAsFixed(1)} textScale=${textScale.toStringAsFixed(2)} compact=$compact pageAxis=horizontal pageInternalScroll=true renderMode=structured_horizontal_book autoPagination=false autoNumbering=false preserveBlankLines=true',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final reduceMotion = media.disableAnimations;
    final pages = normalizeRuleManualPagesForStorage(widget.pages);

    if (pages.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420 || constraints.maxHeight < 560;
        final horizontalPadding = compact ? 6.0 : 12.0;
        final footerHeight = compact ? 48.0 : 54.0;
        final metaHeight = widget.updatedAt == null ? 0.0 : (compact ? 24.0 : 28.0);
        final pageRegionHeight = math.max(
          1.0,
          constraints.maxHeight - footerHeight - metaHeight - 14,
        );
        final pageWidth = math.max(
          1.0,
          math.min(
            widget.maxPageWidth,
            constraints.maxWidth - horizontalPadding * 2,
          ),
        );
        final pageHeight = pageRegionHeight;
        final safeActive = _activePage.clamp(0, pages.length - 1).toInt();
        if (safeActive != _activePage) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _activePage = safeActive);
            if (_pageController.hasClients) {
              _pageController.jumpToPage(safeActive);
            }
          });
        }
        _emitDiagnostics(
          pages: pages,
          width: pageWidth,
          height: pageHeight,
          textScale: media.textScaler.scale(1),
          compact: compact,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.updatedAt != null) ...[
              SizedBox(
                height: metaHeight,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '마지막 수정 ${_formatUpdatedAt(widget.updatedAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: tokens.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Expanded(
              child: Center(
                child: SizedBox(
                  width: pageWidth,
                  height: pageHeight,
                  child: CommonAnimatedReveal(
                    duration:
                        reduceMotion ? Duration.zero : CommonUiMotion.component,
                    offset: const Offset(0, .025),
                    child: PageView.builder(
                      controller: _pageController,
                      scrollDirection: Axis.horizontal,
                      physics: const PageScrollPhysics(),
                      clipBehavior: Clip.none,
                      itemCount: pages.length,
                      onPageChanged: (index) => _handlePageChanged(index, pages),
                      itemBuilder: (context, index) {
                        final page = pages[index];
                        return Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: compact ? 2 : 4,
                          ),
                          child: WorkManualPageCard(
                            key: ValueKey<String>(
                              'manual_page_${page.id}_${page.order}_${pages.length}',
                            ),
                            text: page.content,
                            pageNumber: index + 1,
                            totalPages: pages.length,
                            compact: compact,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: footerHeight,
              child: Row(
                children: [
                  Expanded(
                    child: CommonButton(
                      label: '이전',
                      icon: Icons.chevron_left_rounded,
                      semanticsLabel: '이전 페이지',
                      onPressed: safeActive <= 0
                          ? null
                          : () => _goToPage(
                                safeActive - 1,
                                pages.length,
                                'previous_button',
                              ),
                      variant: CommonButtonVariant.secondary,
                      haptic: CommonHaptic.none,
                      minHeight: compact ? 42 : 46,
                      expand: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  AnimatedSwitcher(
                    duration:
                        reduceMotion ? Duration.zero : CommonUiMotion.selection,
                    switchInCurve: CommonUiMotion.enter,
                    switchOutCurve: CommonUiMotion.exit,
                    transitionBuilder: (child, animation) {
                      if (reduceMotion) return child;
                      final curved = CurvedAnimation(
                        parent: animation,
                        curve: CommonUiMotion.enter,
                        reverseCurve: CommonUiMotion.exit,
                      );
                      return FadeTransition(
                        opacity: curved,
                        child: ScaleTransition(
                          scale: Tween<double>(begin: .94, end: 1).animate(curved),
                          child: child,
                        ),
                      );
                    },
                    child: Text(
                      '${safeActive + 1} / ${pages.length}',
                      key: ValueKey<String>(
                        'manual_footer_${safeActive + 1}_${pages.length}',
                      ),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: CommonButton(
                      label: '다음',
                      icon: Icons.chevron_right_rounded,
                      semanticsLabel: '다음 페이지',
                      onPressed: safeActive >= pages.length - 1
                          ? null
                          : () => _goToPage(
                                safeActive + 1,
                                pages.length,
                                'next_button',
                              ),
                      haptic: CommonHaptic.none,
                      minHeight: compact ? 42 : 46,
                      expand: true,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
