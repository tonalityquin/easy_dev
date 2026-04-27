import 'package:flutter/material.dart';
import '../../../app/di/routes.dart';
import '../../../widgets/tutorial/tutorial_image_split_page.dart';

class AppStartNextTutorialQuickScreen extends StatefulWidget {
  const AppStartNextTutorialQuickScreen({super.key});

  @override
  State<AppStartNextTutorialQuickScreen> createState() => _AppStartNextTutorialQuickScreenState();
}

class _AppStartNextTutorialQuickScreenState extends State<AppStartNextTutorialQuickScreen> {
  final PageController _pageController = PageController();
  int _index = 0;

  final List<_PageData> _pages = const [
    _PageData(
      icon: Icons.flash_on_rounded,
      title: '단축 튜토리얼',
      desc: '이미 사용해 본 사용자용 핵심 변경점만 안내합니다.',
    ),
    _PageData(
      icon: Icons.layers_rounded,
      title: '빠른 조작',
      desc: '오버레이/단축 동작과 권장 설정만 빠르게 확인하세요.',
    ),
    _PageData(
      icon: Icons.check_rounded,
      title: '다음 단계',
      desc: '마지막 확인으로 이동합니다.',
    ),
  ];

  void _skipToEnd() {
    _pageController.animateToPage(
      _pages.length - 1,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  void _next() {
    if (_index >= _pages.length - 1) return;
    _pageController.nextPage(duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
  }

  void _prev() {
    if (_index <= 0) return;
    _pageController.previousPage(duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
  }

  void _finish() {
    Navigator.of(context).pushReplacementNamed(AppRoutes.appStartFinish);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isLast = _index == _pages.length - 1;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Selector 화면 안내'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            children: [
              Expanded(
                child: Card(
                  elevation: 1,
                  clipBehavior: Clip.antiAlias,
                  child: PageView.builder(
                    controller: _pageController,
                    onPageChanged: (idx) => setState(() => _index = idx),
                    itemCount: _pages.length,
                    itemBuilder: (context, idx) {
                      final p = _pages[idx];
                      return TutorialImageSplitPage(
                        imageBuilder: (c) => Icon(p.icon, size: 140, color: cs.primary),
                        enableImageZoom: false,
                        title: p.title,
                        desc: p.desc,
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pages.length, (i) {
                  final selected = i == _index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: selected ? 18 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: selected ? cs.primary : cs.outlineVariant,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: _index == 0 ? null : _prev,
                    child: const Text('이전'),
                  ),
                  TextButton(
                    onPressed: isLast ? null : _skipToEnd,
                    child: const Text('건너뛰기'),
                  ),
                  const Spacer(),
                  if (!isLast)
                    FilledButton(onPressed: _next, child: const Text('다음'))
                  else
                    FilledButton.icon(
                      onPressed: _finish,
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: const Text('확인으로'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageData {
  final IconData icon;
  final String title;
  final String desc;

  const _PageData({
    required this.icon,
    required this.title,
    required this.desc,
  });
}
