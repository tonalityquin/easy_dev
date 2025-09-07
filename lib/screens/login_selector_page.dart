import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../routes.dart';

class LoginSelectorPage extends StatelessWidget {
  const LoginSelectorPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // ✅ 페이지(공간) 단위로 명시적 그룹 구성
    // 1페이지: 서비스 + 출퇴근
    // 2페이지: 태블릿 + 본사/관리자
    final List<List<Widget>> pages = const [
      [_ServiceCard(), _ClockCard()],
      [_TabletCard(), _HeadquarterCard()],
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('로그인 방식 선택'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [cs.surface, cs.surfaceVariant.withOpacity(0.6)],
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Header(),
                    const SizedBox(height: 24),
                    _CardsPager(pages: pages), // ← 두 장씩 스와이프(고정 크기, 페이지 기억)
                    const SizedBox(height: 16),
                    _HintBanner(
                      color: cs.secondaryContainer,
                      iconColor: cs.onSecondaryContainer,
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

/// 두 장씩 보여주는 스와이프 페이저 (카드 크기 고정, 명시적 그룹 사용, 마지막 페이지 기억)
class _CardsPager extends StatefulWidget {
  final List<List<Widget>> pages;

  const _CardsPager({required this.pages});

  @override
  State<_CardsPager> createState() => _CardsPagerState();
}

class _CardsPagerState extends State<_CardsPager> {
  static const double _gap = 16.0;
  static const double _kCardHeight = 240.0; // ✅ 모든 카드 동일 높이
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
    // 현재 페이지 수에 맞춰 보정
    _initialPage = saved.clamp(0, (widget.pages.length - 1).clamp(0, 999)).toInt();
    // 첫 프레임 이후 점프해 깜빡임 최소화
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
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pages.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, cons) {
        final usable = cons.maxWidth;
        final half = ((usable - _gap) / 2).floorToDouble(); // 반폭 고정

        return SizedBox(
          height: _kCardHeight, // 페이지 높이 = 카드 높이
          child: PageView.builder(
            controller: _pageCtrl,
            itemCount: widget.pages.length,
            onPageChanged: (i) => _saveLastPage(i),
            itemBuilder: (context, index) {
              final page = widget.pages[index];
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: half,
                    height: _kCardHeight,
                    child: page.isNotEmpty ? page[0] : const SizedBox.shrink(),
                  ),
                  const SizedBox(width: _gap),
                  SizedBox(
                    width: half,
                    height: _kCardHeight,
                    child: page.length > 1 ? page[1] : const SizedBox.shrink(),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// 상단 타이틀 + 서브텍스트
class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.primaryContainer.withOpacity(0.7),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.login_rounded, color: cs.onPrimaryContainer, size: 28),
        ),
        const SizedBox(height: 12),
        Text(
          '어떤 방식으로 로그인할까요?',
          style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          '서비스용/태블릿용 화면 중에서 선택해 주세요.',
          style: text.bodyMedium?.copyWith(color: Theme.of(context).hintColor),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// 공통 바디: 아이콘 → 타이틀 → 화살표 버튼
Widget _cardBody({
  required BuildContext context,
  required IconData icon,
  required Color bg,
  required Color iconColor,
  String? title, // 기존과의 호환
  Widget? titleWidget, // 커스텀 타이틀 위젯
  required VoidCallback onTap,
}) {
  assert(title != null || titleWidget != null, 'title 또는 titleWidget 중 하나는 제공되어야 합니다.');
  final text = Theme.of(context).textTheme;

  final defaultTitle = Text(
    title ?? '',
    style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    textAlign: TextAlign.center,
  );

  return Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _LeadingIcon(bg: bg, icon: icon, iconColor: iconColor),
        const SizedBox(height: 12),
        titleWidget ?? defaultTitle,
        const SizedBox(height: 12),
        IconButton.filled(
          onPressed: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          icon: const Icon(Icons.arrow_forward_rounded),
          tooltip: '이동',
        ),
      ],
    ),
  );
}

/// 서비스 로그인 카드 (배경 하양, 제목 검정색)
class _ServiceCard extends StatelessWidget {
  const _ServiceCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final titleStyle =
    Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: Colors.black);

    return Card(
      color: Colors.white,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: cs.primary,
      child: _cardBody(
        context: context,
        icon: Icons.build_rounded,
        bg: cs.primaryContainer,
        iconColor: cs.onPrimaryContainer,
        titleWidget: Text('서비스 로그인', style: titleStyle, textAlign: TextAlign.center),
        onTap: () => Navigator.of(context).pushReplacementNamed(AppRoutes.serviceLogin),
      ),
    );
  }
}

/// 출퇴근 로그인 카드 (배경 #122232, '출퇴근' 흰색 + '로그인' 노란색)
class _ClockCard extends StatelessWidget {
  const _ClockCard();

  static const Color _clockBg = Color(0xFF122232); // R=18, G=34, B=50

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: Colors.white,
    );

    return Card(
      color: _clockBg,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: Colors.transparent, // 정확한 색 유지
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _LeadingIcon(
              bg: cs.secondaryContainer,
              icon: Icons.access_time_filled_rounded,
              iconColor: cs.onSecondaryContainer,
            ),
            const SizedBox(height: 12),
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: base,
                children: const [
                  TextSpan(text: '출퇴근 ', style: TextStyle(color: Colors.white)),
                  TextSpan(text: '로그인', style: TextStyle(color: Colors.yellow)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            IconButton.filled(
              onPressed: () {
                HapticFeedback.selectionClick();
                Navigator.of(context).pushReplacementNamed(AppRoutes.outsideLogin);
                },
              icon: const Icon(Icons.arrow_forward_rounded),
              tooltip: '이동',
            ),
          ],
        ),
      ),
    );
  }
}

/// 태블릿 로그인 카드 (서비스 카드와 동일 스타일)
class _TabletCard extends StatelessWidget {
  const _TabletCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final titleStyle =
    Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: Colors.black);

    return Card(
      color: Colors.white,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: cs.primary,
      child: _cardBody(
        context: context,
        icon: Icons.tablet_mac_rounded,
        bg: cs.tertiaryContainer,
        iconColor: cs.onTertiaryContainer,
        titleWidget: Text('태블릿 로그인', style: titleStyle, textAlign: TextAlign.center),
        onTap: () => Navigator.of(context).pushReplacementNamed(AppRoutes.tabletLogin),
      ),
    );
  }
}

/// 본사/관리 카드 (기본 테마)
class _HeadquarterCard extends StatelessWidget {
  const _HeadquarterCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: cs.primary,
      child: _cardBody(
        context: context,
        icon: Icons.business_rounded,
        bg: cs.primaryContainer,
        iconColor: cs.onPrimaryContainer,
        title: '본사 / 관리자',
        onTap: () => Navigator.of(context).pushReplacementNamed(AppRoutes.headquarterPage),
      ),
    );
  }
}

/// 카드 상단 원형 아이콘
class _LeadingIcon extends StatelessWidget {
  final Color bg;
  final IconData icon;
  final Color iconColor;

  const _LeadingIcon({required this.bg, required this.icon, required this.iconColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Icon(icon, color: iconColor, size: 28),
    );
  }
}

/// 하단 힌트 배너
class _HintBanner extends StatelessWidget {
  final Color color;
  final Color iconColor;

  const _HintBanner({required this.color, required this.iconColor});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '언제든지 설정/메뉴에서 로그인 방식을 변경할 수 있어요.',
              style: text.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
