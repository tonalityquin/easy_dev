import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../design_system/prompt_ui/prompt_ui_theme.dart';

@immutable
class CardsPagerPage {
  const CardsPagerPage._({
    required this.primary,
    this.secondary,
    required this.fullSpan,
  });

  final Widget primary;
  final Widget? secondary;
  final bool fullSpan;

  factory CardsPagerPage.pair({
    required Widget primary,
    Widget? secondary,
  }) {
    return CardsPagerPage._(
      primary: primary,
      secondary: secondary,
      fullSpan: false,
    );
  }

  factory CardsPagerPage.fullSpan({required Widget child}) {
    return CardsPagerPage._(
      primary: child,
      fullSpan: true,
    );
  }
}

class CardsPager extends StatefulWidget {
  const CardsPager({super.key, required this.pages});

  final List<CardsPagerPage> pages;

  @override
  State<CardsPager> createState() => _CardsPagerState();
}

class _CardsPagerState extends State<CardsPager> {
  static const double _gap = 16;
  static const double _baseCardHeight = 240;
  static const String _prefsKey = 'login_selector_last_page';

  late final PageController _pageController;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0, viewportFraction: 1);
    _restoreLastPage();
  }

  Future<void> _restoreLastPage() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt(_prefsKey) ?? 0;
    final maxIndex = (widget.pages.length - 1).clamp(0, 999).toInt();
    final initial = saved.clamp(0, maxIndex).toInt();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _current = initial);
      if (_pageController.hasClients) {
        _pageController.jumpToPage(initial);
      }
    });
  }

  Future<void> _saveLastPage(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKey, index);
  }

  Future<void> _goTo(int target) async {
    if (!_pageController.hasClients || target == _current) return;
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _pageController.jumpToPage(target);
      return;
    }
    await _pageController.animateToPage(
      target,
      duration: PromptUiMotion.component,
      curve: PromptUiMotion.enter,
    );
  }

  void _goPrev() {
    final max = (widget.pages.length - 1).clamp(0, 999).toInt();
    _goTo((_current - 1).clamp(0, max).toInt());
  }

  void _goNext() {
    final max = (widget.pages.length - 1).clamp(0, 999).toInt();
    _goTo((_current + 1).clamp(0, max).toInt());
  }

  @override
  void didUpdateWidget(covariant CardsPager oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.pages.length != oldWidget.pages.length &&
        _pageController.hasClients) {
      final max = (widget.pages.length - 1).clamp(0, 999).toInt();
      if (_current > max) {
        setState(() => _current = max);
        _pageController.jumpToPage(max);
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Widget _buildDots() {
    final total = widget.pages.length;
    if (total <= 1) return const SizedBox.shrink();

    final tokens = PromptUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Semantics(
      label: '${_current + 1} / $total 페이지',
      child: Wrap(
        spacing: 6,
        children: List<Widget>.generate(total, (index) {
          final active = index == _current;
          return AnimatedContainer(
            duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
            curve: PromptUiMotion.standard,
            width: active ? 20 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: active ? tokens.accent : tokens.borderStrong.withOpacity(0.42),
              borderRadius: BorderRadius.circular(PromptUiShapes.pill),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildPage(
    CardsPagerPage page,
    double usable,
    double cardHeight,
  ) {
    if (page.fullSpan) {
      return SizedBox(
        width: usable,
        height: cardHeight,
        child: page.primary,
      );
    }

    final half = ((usable - _gap) / 2)
        .clamp(0.0, double.infinity)
        .floorToDouble();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: half,
          height: cardHeight,
          child: page.primary,
        ),
        const SizedBox(width: _gap),
        SizedBox(
          width: half,
          height: cardHeight,
          child: page.secondary ?? const SizedBox.shrink(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pages.isEmpty) return const SizedBox.shrink();

    final media = MediaQuery.of(context);
    final cardHeight = media.size.height < 640 ? 200.0 : _baseCardHeight;

    return LayoutBuilder(
      builder: (context, constraints) {
        final total = widget.pages.length;
        final canPrev = _current > 0;
        final canNext = _current < total - 1;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: cardHeight,
              child: PageView.builder(
                controller: _pageController,
                itemCount: total,
                physics: const PageScrollPhysics(),
                onPageChanged: (index) async {
                  if (!mounted) return;
                  setState(() => _current = index);
                  await _saveLastPage(index);
                },
                itemBuilder: (context, index) {
                  return AnimatedBuilder(
                    animation: _pageController,
                    builder: (context, child) {
                      var page = _current.toDouble();
                      if (_pageController.hasClients &&
                          _pageController.position.haveDimensions) {
                        page = _pageController.page ?? _current.toDouble();
                      }
                      final distance = (page - index).abs().clamp(0.0, 1.0);
                      final opacity = media.disableAnimations
                          ? 1.0
                          : 1.0 - distance * 0.10;
                      return Opacity(opacity: opacity, child: child);
                    },
                    child: _buildPage(
                      widget.pages[index],
                      constraints.maxWidth,
                      cardHeight,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                PromptIconButton(
                  icon: Icons.chevron_left_rounded,
                  tooltip: '이전',
                  onPressed: canPrev ? _goPrev : null,
                ),
                const SizedBox(width: 8),
                _buildDots(),
                const SizedBox(width: 8),
                PromptIconButton(
                  icon: Icons.chevron_right_rounded,
                  tooltip: '다음',
                  onPressed: canNext ? _goNext : null,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
