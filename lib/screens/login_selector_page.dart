import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../routes.dart';

class LoginSelectorPage extends StatefulWidget {
  const LoginSelectorPage({super.key});

  @override
  State<LoginSelectorPage> createState() => _LoginSelectorPageState();
}

class _LoginSelectorPageState extends State<LoginSelectorPage> {
  String? _savedMode; // 'service' | 'outside' | 'tablet' | null(미저장)

  @override
  void initState() {
    super.initState();
    _restoreMode();
  }

  Future<void> _restoreMode() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _savedMode = prefs.getString('mode'); // service / outside / tablet / null
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // 저장된 모드가 있으면 해당 카드만 선택 가능
    final serviceEnabled = _savedMode == null || _savedMode == 'service';
    final outsideEnabled = _savedMode == null || _savedMode == 'outside';
    final tabletEnabled = _savedMode == null || _savedMode == 'tablet';

    final List<List<Widget>> pages = [
      [
        _ServiceCard(enabled: serviceEnabled),
        _ClockCard(enabled: outsideEnabled),
      ],
      [
        _TabletCard(enabled: tabletEnabled),
        const _ParkingCard(), // ▼ 새 카드 2
      ],
      [
        const _FaqCard(), // ▼ 새 카드 1
        const _CommunityCard(), // 본사/관리자 카드는 항상 진입 가능
      ],
    ];

    return Scaffold(
      backgroundColor: Colors.white, // 전체 배경 화이트
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        title: Text(
          'Pelican Hubs',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
                color: Theme.of(context).colorScheme.onSurface,
              ),
        ),
        iconTheme: IconThemeData(color: Theme.of(context).colorScheme.onSurface),
        actionsIconTheme: IconThemeData(color: Theme.of(context).colorScheme.onSurface),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: Colors.black.withOpacity(0.06),
          ),
        ),
      ),
      body: SafeArea(
        child: Container(
          color: Colors.white, // 바디 배경 화이트
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
                    _CardsPager(pages: pages),
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
      // ▼ 하단 펠리컨 이미지
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SizedBox(
            height: 120,
            child: Image.asset('assets/images/pelican.png'),
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
  static const double _kCardHeight = 240.0; // 모든 카드 동일 높이
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

/// 헤더 영역
class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      children: [
        const _HeaderBadge(size: 64, ring: 3),
        const SizedBox(height: 12),
        Text(
          '환영합니다, 사용자님',
          style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          '화살표 버튼을 누르면 해당 페이지로 진입합니다.',
          style: text.bodyMedium?.copyWith(color: Theme.of(context).hintColor),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// 리팩토링된 헤더 배지: 검은 링 + 화이트 바디 + 글로시 + 살짝 튀어나오는 애니메이션
class _HeaderBadge extends StatelessWidget {
  const _HeaderBadge({this.size = 64, this.ring = 3});

  final double size; // 배지 지름
  final double ring; // 링(테두리) 두께

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 600),
      tween: Tween(begin: .92, end: 1),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: SizedBox(
        width: size,
        height: size,
        child: const DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black, // 검은색 링
          ),
          child: _HeaderBadgeInner(),
        ),
      ),
    );
  }
}

class _HeaderBadgeInner extends StatelessWidget {
  const _HeaderBadgeInner();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, cons) {
        return Padding(
          padding: const EdgeInsets.all(3), // 링 두께
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white, // 화이트 바디
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              children: [
                const Center(
                  child: Icon(
                    Icons.dashboard_customize_rounded,
                    color: Colors.black,
                    size: 28,
                  ),
                ),
                Positioned(
                  top: cons.maxHeight * 0.12,
                  left: cons.maxWidth * 0.22,
                  right: cons.maxWidth * 0.22,
                  child: Container(
                    height: cons.maxHeight * 0.18,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
  required VoidCallback? onTap,
  bool enabled = true,
  String? disabledHint,
}) {
  assert(title != null || titleWidget != null, 'title 또는 titleWidget 중 하나는 제공되어야 합니다.');
  final text = Theme.of(context).textTheme;

  final defaultTitle = Text(
    title ?? '',
    style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    textAlign: TextAlign.center,
  );

  final content = Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _LeadingIcon(bg: bg, icon: icon, iconColor: iconColor),
        const SizedBox(height: 12),
        titleWidget ?? defaultTitle,
        const SizedBox(height: 12),
        Tooltip(
          message: enabled ? '이동' : (disabledHint ?? '현재 저장된 모드에서만 선택할 수 있어요'),
          child: IconButton.filled(
            onPressed: enabled ? onTap : null,
            icon: const Icon(Icons.arrow_forward_rounded),
          ),
        ),
      ],
    ),
  );

  return Opacity(opacity: enabled ? 1.0 : 0.48, child: content);
}

/// 서비스 로그인 카드 (배경 하양, 제목 검정색)
class _ServiceCard extends StatelessWidget {
  final bool enabled;

  const _ServiceCard({this.enabled = true});

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
        icon: Icons.local_parking,
        bg: cs.primaryContainer,
        iconColor: cs.onPrimaryContainer,
        titleWidget: Text('서비스 로그인', style: titleStyle, textAlign: TextAlign.center),
        onTap: () => Navigator.of(context).pushReplacementNamed(AppRoutes.serviceLogin),
        enabled: enabled,
        disabledHint: '저장된 모드가 service일 때만 선택할 수 있어요',
      ),
    );
  }
}

/// 출퇴근 로그인 카드 (배경 #122232, '출퇴근' 흰색 + '로그인' 노란색)
class _ClockCard extends StatelessWidget {
  final bool enabled;

  const _ClockCard({this.enabled = true});

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
      surfaceTintColor: Colors.transparent,
      child: _cardBody(
        context: context,
        icon: Icons.access_time_filled_rounded,
        bg: cs.secondaryContainer,
        iconColor: cs.onSecondaryContainer,
        titleWidget: RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: base,
            children: const [
              TextSpan(text: '출퇴근 ', style: TextStyle(color: Colors.white)),
              TextSpan(text: '로그인', style: TextStyle(color: Colors.yellow)),
            ],
          ),
        ),
        onTap: () => Navigator.of(context).pushReplacementNamed(AppRoutes.outsideLogin),
        enabled: enabled,
        disabledHint: '저장된 모드가 outside일 때만 선택할 수 있어요',
      ),
    );
  }
}

/// 태블릿 로그인 카드 (서비스 카드와 동일 스타일)
class _TabletCard extends StatelessWidget {
  final bool enabled;

  const _TabletCard({this.enabled = true});

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
        enabled: enabled,
        disabledHint: '저장된 모드가 tablet일 때만 선택할 수 있어요',
      ),
    );
  }
}

/// 커뮤니티 카드 (커뮤니티/소통 허브)
class _CommunityCard extends StatelessWidget {
  const _CommunityCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: cs.tertiary, // 커뮤니티 느낌의 부드러운 톤
      child: _cardBody(
        context: context,
        icon: Icons.groups_rounded,
        // 👥 커뮤니티 아이콘
        bg: cs.tertiaryContainer,
        iconColor: cs.onTertiaryContainer,
        title: '커뮤니티',
        // 타이틀 변경
        // 임시 연결: 이후 커뮤니티 실제 화면/게임 허브로 교체 가능
        onTap: () => Navigator.of(context).pushReplacementNamed(AppRoutes.communityStub),
      ),
    );
  }
}

/// FAQ / 문의 카드 (항상 진입 가능)
class _FaqCard extends StatelessWidget {
  const _FaqCard();

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
        icon: Icons.help_center_rounded,
        bg: cs.secondaryContainer,
        iconColor: cs.onSecondaryContainer,
        titleWidget: Text('FAQ / 문의', style: titleStyle, textAlign: TextAlign.center),
        onTap: () => Navigator.of(context).pushReplacementNamed(AppRoutes.faq), // TODO: routes 등록
      ),
    );
  }
}

/// 주차 관제 시스템 카드 (항상 진입 가능)
class _ParkingCard extends StatelessWidget {
  const _ParkingCard();

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
        icon: Icons.location_city,
        // 주차 아이콘
        bg: cs.primaryContainer,
        iconColor: cs.onPrimaryContainer,
        titleWidget: Text('주차 관제 시스템(공사중)', style: titleStyle, textAlign: TextAlign.center),
        onTap: () => Navigator.of(context).pushReplacementNamed(AppRoutes.parking), // TODO: routes 등록
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
              '저장된 로그인 모드가 있으면 해당 모드만 선택할 수 있어요. (로그아웃 후, 변경 가능)',
              style: text.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
