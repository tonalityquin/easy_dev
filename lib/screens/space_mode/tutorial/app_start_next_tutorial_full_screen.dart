import 'package:flutter/material.dart';

import '../../../app/di/routes.dart';
import '../../../app/tutorial/tutorial_image_split_page.dart';
import 'tutorial_start_pages.dart';

class AppStartNextTutorialFullScreen extends StatefulWidget {
  const AppStartNextTutorialFullScreen({super.key});

  @override
  State<AppStartNextTutorialFullScreen> createState() => _AppStartNextTutorialFullScreenState();
}

class _AppStartNextTutorialFullScreenState extends State<AppStartNextTutorialFullScreen> {
  final PageController _pageController = PageController();
  int _index = 0;

  List<TutorialStartPageSpec> get _pages => kAppStartFullTutorialPages;

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

  Widget _buildMissingAsset(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_not_supported_rounded, size: 44, color: cs.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(
            '이미지를 찾을 수 없습니다',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'assets/tutorial/ 폴더에 00.png~40.png가 존재하고\n'
                'pubspec.yaml에 assets/tutorial/이 등록되어 있는지 확인하세요.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget? _buildFooter(BuildContext context, TutorialStartPageSpec p) {
    final cs = Theme.of(context).colorScheme;
    final items = <Widget>[];

    if (p.bullets.isNotEmpty) {
      items.addAll(
        p.bullets.map(
              (t) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• ', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                Expanded(
                  child: Text(
                    t,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (p.warning != null && p.warning!.trim().isNotEmpty) {
      items.add(const SizedBox(height: 10));
      items.add(
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.errorContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            p.warning!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onErrorContainer),
          ),
        ),
      );
    }

    if (p.linkLabel != null && p.linkRoute != null) {
      items.add(const SizedBox(height: 10));
      items.add(
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pushNamed(p.linkRoute!),
            child: Text(p.linkLabel!),
          ),
        ),
      );
    }

    if (items.isEmpty) return null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: items,
    );
  }

  Widget _imageForPage(BuildContext context, TutorialStartPageSpec p) {
    return Image.asset(
      p.imageAsset,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stack) => _buildMissingAsset(context),
    );
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
    final progress = _pages.isEmpty ? 0.0 : (_index + 1) / _pages.length;

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
                        imageBuilder: (c) => _imageForPage(c, p),
                        zoomedImageBuilder: (c) => _imageForPage(c, p),
                        enableImageZoom: true,
                        title: p.title,
                        desc: p.desc,
                        footer: _buildFooter(context, p),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(value: progress),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${_index + 1}/${_pages.length}',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
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
