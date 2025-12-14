import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CardsPager extends StatefulWidget {
  final List<List<Widget>> pages;

  const CardsPager({super.key, required this.pages});

  @override
  State<CardsPager> createState() => _CardsPagerState();
}

class _CardsPagerState extends State<CardsPager> {
  static const double _gap = 16.0;
  static const double _baseCardHeight = 240.0;
  static const String _prefsKey = 'login_selector_last_page';

  late final PageController _pageCtrl;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController(initialPage: 0, viewportFraction: 1.0);
    _restoreLastPage();
  }

  Future<void> _restoreLastPage() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt(_prefsKey) ?? 0;

    final maxIndex = (widget.pages.length - 1).clamp(0, 999);
    final initial = saved.clamp(0, maxIndex).toInt();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _current = initial);
      _pageCtrl.jumpToPage(initial);
    });
  }

  Future<void> _saveLastPage(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKey, index);
  }

  void _goPrev() {
    if (!_pageCtrl.hasClients) return;
    final target = (_current - 1).clamp(0, (widget.pages.length - 1).clamp(0, 999));
    _pageCtrl.animateToPage(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _goNext() {
    if (!_pageCtrl.hasClients) return;
    final target = (_current + 1).clamp(0, (widget.pages.length - 1).clamp(0, 999));
    _pageCtrl.animateToPage(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  void didUpdateWidget(covariant CardsPager oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.pages.length != oldWidget.pages.length && _pageCtrl.hasClients) {
      final max = (widget.pages.length - 1).clamp(0, 999);
      if (_current > max) {
        setState(() => _current = max);
        _pageCtrl.jumpToPage(max);
      }
    }
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  Widget _buildDots() {
    final total = widget.pages.length;
    if (total <= 1) return const SizedBox.shrink();

    return Wrap(
      spacing: 6,
      children: List<Widget>.generate(total, (i) {
        final bool active = i == _current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: active ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: active ? Colors.black.withOpacity(0.55) : Colors.black.withOpacity(0.18),
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pages.isEmpty) return const SizedBox.shrink();

    final media = MediaQuery.of(context);
    final double cardHeight = media.size.height < 640 ? 200.0 : _baseCardHeight;

    return LayoutBuilder(
      builder: (context, cons) {
        final usable = cons.maxWidth;
        // ✅ 아주 좁은 폭에서도 음수 폭이 나오지 않도록 방어
        final double half = (((usable - _gap) / 2).clamp(0.0, double.infinity)).floorToDouble();

        final total = widget.pages.length;
        final bool canPrev = _current > 0;
        final bool canNext = _current < total - 1;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: cardHeight,
              child: PageView.builder(
                controller: _pageCtrl,
                itemCount: total,
                physics: const PageScrollPhysics(),
                onPageChanged: (i) async {
                  if (!mounted) return;
                  setState(() => _current = i);
                  await _saveLastPage(i);
                },
                itemBuilder: (context, index) {
                  final page = widget.pages[index];

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: half,
                        height: cardHeight,
                        child: page.isNotEmpty ? page[0] : const SizedBox.shrink(),
                      ),
                      const SizedBox(width: _gap),
                      SizedBox(
                        width: half,
                        height: cardHeight,
                        child: page.length > 1 ? page[1] : const SizedBox.shrink(),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: canPrev ? _goPrev : null,
                  tooltip: '이전',
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                const SizedBox(width: 6),
                _buildDots(),
                const SizedBox(width: 6),
                IconButton(
                  onPressed: canNext ? _goNext : null,
                  tooltip: '다음',
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
