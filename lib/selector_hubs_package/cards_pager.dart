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
  int _initialPage = 0;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController(initialPage: 0, viewportFraction: 1.0);
    _restoreLastPage();
  }

  Future<void> _restoreLastPage() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt(_prefsKey) ?? 0;
    _initialPage = saved.clamp(0, (widget.pages.length - 1).clamp(0, 999)).toInt();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pageCtrl.jumpToPage(_initialPage);
    });
  }

  Future<void> _saveLastPage(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKey, index);
  }

  @override
  void didUpdateWidget(covariant CardsPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pages.length != oldWidget.pages.length && _pageCtrl.hasClients) {
      final curr = _pageCtrl.page?.round() ?? 0;
      final max = (widget.pages.length - 1).clamp(0, 999);
      if (curr > max) _pageCtrl.jumpToPage(max);
    }
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pages.isEmpty) return const SizedBox.shrink();
    final media = MediaQuery.of(context);
    final double cardHeight = media.size.height < 640 ? 200.0 : _baseCardHeight;

    return LayoutBuilder(
      builder: (context, cons) {
        final usable = cons.maxWidth;
        final half = ((usable - _gap) / 2).floorToDouble();

        return SizedBox(
          height: cardHeight,
          child: PageView.builder(
            controller: _pageCtrl,
            itemCount: widget.pages.length,
            onPageChanged: (i) => _saveLastPage(i),
            itemBuilder: (context, index) {
              final page = widget.pages[index];
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(width: half, height: cardHeight, child: page.isNotEmpty ? page[0] : const SizedBox.shrink()),
                  const SizedBox(width: _gap),
                  SizedBox(width: half, height: cardHeight, child: page.length > 1 ? page[1] : const SizedBox.shrink()),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
