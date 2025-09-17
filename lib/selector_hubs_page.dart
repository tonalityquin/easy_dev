// lib/screens/selector_hubs_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../routes.dart';

class SelectorHubsPage extends StatefulWidget {
  const SelectorHubsPage({super.key});

  @override
  State<SelectorHubsPage> createState() => _SelectorHubsPageState();
}

class _SelectorHubsPageState extends State<SelectorHubsPage> {
  String? _savedMode; // 'service' | 'tablet' | null(미저장)
  bool _devAuthorized = false; // ✅ 개발자 전용 로그인 성공 여부 (영구 저장)

  static const _prefsKeyMode = 'mode';
  static const _prefsKeyDevAuth = 'dev_auth';
  static const _prefsKeyDevId = 'dev_id';
  static const _prefsKeyDevPw = 'dev_pw';

  @override
  void initState() {
    super.initState();
    _restorePrefs();
  }

  Future<void> _restorePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _savedMode = prefs.getString(_prefsKeyMode); // service / outside / tablet / null
      _devAuthorized = prefs.getBool(_prefsKeyDevAuth) ?? false;
    });
  }

  Future<void> _setDevAuthorized(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyDevAuth, value);
    setState(() => _devAuthorized = value);
  }

  Future<void> _setDevCredentials(String id, String pw) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyDevId, id);
    await prefs.setString(_prefsKeyDevPw, pw);
  }

  Future<void> _resetDevAuthAndCreds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyDevId);
    await prefs.remove(_prefsKeyDevPw);
    await prefs.setBool(_prefsKeyDevAuth, false);
    setState(() => _devAuthorized = false);
  }

  /// ✅ 하단 펠리컨 이미지를 눌렀을 때 전용 로그인 BottomSheet 열기
  Future<void> _handlePelicanTap(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 1,
        child: DevLoginBottomSheet(
          onSuccess: (id, pw) async {
            await _setDevCredentials(id, pw);
            await _setDevAuthorized(true);
            if (mounted) {
              Navigator.of(ctx).pop(); // 시트 닫기
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('개발자 인증 완료. 이제 개발/주차 카드를 눌러 진입할 수 있습니다.')),
              );
            }
          },
          onReset: () async {
            await _resetDevAuthAndCreds();
            if (mounted) {
              Navigator.of(ctx).pop(); // 시트 닫기
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('개발자 인증이 초기화되었습니다.')),
              );
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 저장된 모드가 있으면 해당 카드만 선택 가능
    final serviceEnabled = _savedMode == null || _savedMode == 'service';
    final tabletEnabled = _savedMode == null || _savedMode == 'tablet';

    // ✅ 개발/주차 카드는 _devAuthorized 이전에는 생성 자체를 생략
    final List<List<Widget>> pages = [
      [
        _ServiceCard(enabled: serviceEnabled),
        _TabletCard(enabled: tabletEnabled),
      ],
      [
        _HeadquarterCard(enabled: serviceEnabled), // ✅ 본사도 service 모드에서만
        const _FaqCard(),
      ],
      [
        const _CommunityCard(),
        if (_devAuthorized) const _ParkingCard(), // ✅ 현재 위치 유지 + 개발 인증 시에만 노출
      ],
      if (_devAuthorized)
        [
          _DevCard(
            onTap: () => Navigator.of(context).pushReplacementNamed(AppRoutes.devStub),
          ),
        ],
    ];

    // ▶︎ 화면/키보드 상황에 따른 하단 이미지 높이/표시 제어
    final media = MediaQuery.of(context);
    final bool isShort = media.size.height < 640;
    final bool keyboardOpen = media.viewInsets.bottom > 0;
    final double footerHeight = (isShort || keyboardOpen) ? 72 : 120;
    const double footerBottomPadding = 8;

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
        child: Stack(
          children: [
            // ▼ 본문(스크롤 가능) — 하단에 이미지 높이만큼 여백을 추가하여 겹침 방지
            SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                24,
                24,
                24,
                24 + footerHeight + footerBottomPadding,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 880),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Header(),
                      const SizedBox(height: 24),
                      _CardsPager(pages: pages),
                      const SizedBox(height: 16),
                      const _HintBanner(
                        color: Colors.green, // 배경 초록
                        iconColor: Colors.white, // 아이콘 흰색
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ▼ 하단 펠리컨 이미지(탭 가능, 로그인 시트 트리거)
            Positioned(
              left: 0,
              right: 0,
              bottom: footerBottomPadding,
              child: AnimatedOpacity(
                opacity: keyboardOpen ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 160),
                child: SizedBox(
                  height: footerHeight,
                  child: Center(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _handlePelicanTap(context),
                      child: Image.asset(
                        'assets/images/pelican.png',
                        fit: BoxFit.contain,
                        height: footerHeight,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      // ❌ 기존 bottomNavigationBar 제거 (Stack으로 대체)
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
          '환영합니다',
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

/// 공통 바디: 아이콘 → 타이틀 → 화살표 버튼
/// - 카드 본문 탭 시 네비게이션 + 살짝 축소 애니메이션(내비 이전 유지시간 보장)
Widget _cardBody({
  required BuildContext context,
  required IconData icon,
  required Color bg, // 아이콘 배지 배경
  required Color iconColor, // 아이콘 색
  Color? buttonBg, // 이동 버튼 배경
  Color? buttonFg, // 이동 버튼 아이콘 색
  String? title, // 기존과의 호환
  Widget? titleWidget, // 커스텀 타이틀 위젯
  required VoidCallback? onTap,
  bool enabled = true,
  String? disabledHint,
}) {
  assert(title != null || titleWidget != null, 'title 또는 titleWidget 중 하나는 제공되어야 합니다.');
  return _CardBody(
    icon: icon,
    bg: bg,
    iconColor: iconColor,
    buttonBg: buttonBg,
    buttonFg: buttonFg,
    title: title,
    titleWidget: titleWidget,
    onTap: onTap,
    enabled: enabled,
    disabledHint: disabledHint,
  );
}

class _CardBody extends StatefulWidget {
  const _CardBody({
    required this.icon,
    required this.bg,
    required this.iconColor,
    this.buttonBg,
    this.buttonFg,
    this.title,
    this.titleWidget,
    required this.onTap,
    this.enabled = true,
    this.disabledHint,
  });

  final IconData icon;
  final Color bg;
  final Color iconColor;
  final Color? buttonBg;
  final Color? buttonFg;
  final String? title;
  final Widget? titleWidget;
  final VoidCallback? onTap;
  final bool enabled;
  final String? disabledHint;

  @override
  State<_CardBody> createState() => _CardBodyState();
}

class _CardBodyState extends State<_CardBody> {
  static const _pressScale = 0.96; // 조금 더 눈에 띄게
  static const _duration = Duration(milliseconds: 160);
  static const _frame = Duration(milliseconds: 16);

  bool _pressed = false;
  bool _animating = false;

  Future<void> _animateThenNavigate() async {
    if (!widget.enabled || widget.onTap == null || _animating) return;
    _animating = true;

    // 1) 축소 시작 (그림이 한 프레임이라도 그려지도록 짧은 대기)
    setState(() => _pressed = true);
    await Future<void>.delayed(_frame);

    // 2) 축소 상태를 유지해 사용자가 체감할 시간 확보
    await Future<void>.delayed(_duration);

    // 3) (옵션) 가벼운 햅틱 피드백
    HapticFeedback.selectionClick();

    // 4) 내비게이션
    widget.onTap!.call();

    _animating = false;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    final defaultTitle = Text(
      widget.title ?? '',
      style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      textAlign: TextAlign.center,
    );

    final content = Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _LeadingIcon(bg: widget.bg, icon: widget.icon, iconColor: widget.iconColor),
          const SizedBox(height: 12),
          widget.titleWidget ?? defaultTitle,
          const SizedBox(height: 12),
          Tooltip(
            message: widget.enabled ? '이동' : (widget.disabledHint ?? '현재 저장된 모드에서만 선택할 수 있어요'),
            child: IconButton.filled(
              // 버튼도 동일 애니메이션 후 이동
              onPressed: widget.enabled ? () => _animateThenNavigate() : null,
              style: IconButton.styleFrom(
                backgroundColor: widget.buttonBg ?? Theme.of(context).colorScheme.primary,
                foregroundColor: widget.buttonFg ?? Theme.of(context).colorScheme.onPrimary,
              ),
              icon: const Icon(Icons.arrow_forward_rounded),
            ),
          ),
        ],
      ),
    );

    return Opacity(
      opacity: widget.enabled ? 1.0 : 0.48,
      child: AnimatedScale(
        scale: _pressed ? _pressScale : 1.0,
        duration: _duration,
        curve: Curves.easeOut,
        child: InkWell(
          onTap: widget.enabled ? _animateThenNavigate : null,
          child: content,
        ),
      ),
    );
  }
}

/// 서비스 로그인 카드 — Deep Blue 팔레트
class _ServiceCard extends StatelessWidget {
  final bool enabled;

  const _ServiceCard({this.enabled = true});

  static const Color _base = Color(0xFF0D47A1);
  static const Color _dark = Color(0xFF09367D);
  static const Color _light = Color(0xFF5472D3);

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: _dark);

    return Card(
      color: Colors.white,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: _light,
      child: _cardBody(
        context: context,
        icon: Icons.local_parking,
        bg: _base,
        iconColor: Colors.white,
        titleWidget: Text('서비스 로그인', style: titleStyle, textAlign: TextAlign.center),
        buttonBg: _base,
        buttonFg: Colors.white,
        onTap: () => Navigator.of(context).pushReplacementNamed(AppRoutes.serviceLogin),
        enabled: enabled,
        disabledHint: '저장된 모드가 service일 때만 선택할 수 있어요',
      ),
    );
  }
}

/// 태블릿 로그인 카드 — Cyan 팔레트
class _TabletCard extends StatelessWidget {
  final bool enabled;

  const _TabletCard({this.enabled = true});

  static const Color _base = Color(0xFF00ACC1);
  static const Color _dark = Color(0xFF00838F);
  static const Color _light = Color(0xFF4DD0E1);

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: _dark);

    return Card(
      color: Colors.white,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: _light,
      child: _cardBody(
        context: context,
        icon: Icons.tablet_mac_rounded,
        bg: _base,
        iconColor: Colors.white,
        titleWidget: Text('태블릿 로그인', style: titleStyle, textAlign: TextAlign.center),
        buttonBg: _base,
        buttonFg: Colors.white,
        onTap: () => Navigator.of(context).pushReplacementNamed(AppRoutes.tabletLogin),
        enabled: enabled,
        disabledHint: '저장된 모드가 tablet일 때만 선택할 수 있어요',
      ),
    );
  }
}

/// 커뮤니티 카드 — Teal 팔레트
class _CommunityCard extends StatelessWidget {
  const _CommunityCard();

  static const Color _base = Color(0xFF26A69A);
  static const Color _dark = Color(0xFF1E8077);
  static const Color _light = Color(0xFF64D8CB);

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: _dark);

    return Card(
      color: Colors.white,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: _light,
      child: _cardBody(
        context: context,
        icon: Icons.groups_rounded,
        bg: _base,
        iconColor: Colors.white,
        titleWidget: Text('커뮤니티', style: titleStyle, textAlign: TextAlign.center),
        buttonBg: _base,
        buttonFg: Colors.white,
        onTap: () => Navigator.of(context).pushReplacementNamed(AppRoutes.communityStub),
      ),
    );
  }
}

/// FAQ / 문의 카드 — Indigo 팔레트
class _FaqCard extends StatelessWidget {
  const _FaqCard();

  static const Color _base = Color(0xFF3949AB);
  static const Color _dark = Color(0xFF283593);
  static const Color _light = Color(0xFF7986CB);

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: _dark);

    return Card(
      color: Colors.white,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: _light,
      child: _cardBody(
        context: context,
        icon: Icons.help_center_rounded,
        bg: _base,
        iconColor: Colors.white,
        titleWidget: Text('FAQ / 문의', style: titleStyle, textAlign: TextAlign.center),
        buttonBg: _base,
        buttonFg: Colors.white,
        onTap: () => Navigator.of(context).pushReplacementNamed(AppRoutes.faq),
      ),
    );
  }
}

/// 본사 카드 — Blue 팔레트
class _HeadquarterCard extends StatelessWidget {
  const _HeadquarterCard({this.enabled = true});

  final bool enabled;

  static const Color _base = Color(0xFF1E88E5);
  static const Color _dark = Color(0xFF1565C0);
  static const Color _light = Color(0xFF64B5F6);

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: _dark);

    return Card(
      color: Colors.white,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: _light,
      child: _cardBody(
        context: context,
        icon: Icons.apartment_rounded,
        bg: _base,
        iconColor: Colors.white,
        titleWidget: Text('본사', style: titleStyle, textAlign: TextAlign.center),
        buttonBg: _base,
        buttonFg: Colors.white,
        enabled: enabled,
        disabledHint: '저장된 모드가 service일 때만 선택할 수 있어요',
        onTap: () {
          // ✅ 본사도 서비스 로그인 검증을 동일하게 거친다
          Navigator.of(context).pushReplacementNamed(
            AppRoutes.serviceLogin,
            arguments: {
              'redirectAfterLogin': AppRoutes.headStub, // 로그인 성공 후 본사(Stub)로 이동
              'requiredMode': 'service',
            },
          );
        },
      ),
    );
  }
}

/// 개발 카드 — Deep Purple 팔레트 (인증 후에만 보임)
class _DevCard extends StatelessWidget {
  const _DevCard({required this.onTap});

  final VoidCallback onTap;

  static const Color _base = Color(0xFF6A1B9A);
  static const Color _dark = Color(0xFF4A148C);
  static const Color _light = Color(0xFFCE93D8);

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: _dark);

    return Card(
      color: Colors.white,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: _light,
      child: _cardBody(
        context: context,
        icon: Icons.developer_mode_rounded,
        bg: _base,
        iconColor: Colors.white,
        titleWidget: Text('개발', style: titleStyle, textAlign: TextAlign.center),
        buttonBg: _base,
        buttonFg: Colors.white,
        onTap: onTap,
      ),
    );
  }
}

/// 주차 관제 시스템 카드 — Deep Orange 팔레트(개발 인증 후에만 보임: 현재 위치 유지)
class _ParkingCard extends StatelessWidget {
  const _ParkingCard();

  static const Color _base = Color(0xFFF4511E);
  static const Color _dark = Color(0xFFD84315);
  static const Color _light = Color(0xFFFFAB91);

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: _dark);

    return Card(
      color: Colors.white,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: _light,
      child: _cardBody(
        context: context,
        icon: Icons.location_city,
        bg: _base,
        iconColor: Colors.white,
        titleWidget: Text('오프라인 서비스', style: titleStyle, textAlign: TextAlign.center),
        buttonBg: _base,
        buttonFg: Colors.white,
        onTap: () => Navigator.of(context).pushReplacementNamed(AppRoutes.parking),
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
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '저장된 로그인 모드가 있으면 해당 모드만 선택할 수 있어요. (로그아웃 후, 변경 가능)',
              style: text.bodySmall?.copyWith(
                color: Colors.white, // 흰색
                fontWeight: FontWeight.w700, // 진하게
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ============================
/// Developer-only Login BottomSheet (EN)
/// ============================
class DevLoginBottomSheet extends StatefulWidget {
  const DevLoginBottomSheet({
    super.key,
    required this.onSuccess,
    required this.onReset,
  });

  final Future<void> Function(String id, String pw) onSuccess;
  final Future<void> Function() onReset;

  @override
  State<DevLoginBottomSheet> createState() => _DevLoginBottomSheetState();
}

class _DevLoginBottomSheetState extends State<DevLoginBottomSheet> {
  final _idCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscure = true;
  String? _error;

  static const _hardId = 'facere';
  static const _hardPw = '1868';

  @override
  void dispose() {
    _idCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final id = _idCtrl.text.trim();
    final pw = _pwCtrl.text.trim();

    if (id == _hardId && pw == _hardPw) {
      HapticFeedback.selectionClick();
      await widget.onSuccess(id, pw);
    } else {
      setState(() => _error = 'Invalid ID or password.');
      HapticFeedback.vibrate();
    }
  }

  Future<void> _reset() async {
    await widget.onReset(); // ✅ prefs 초기화 + 카드 숨김
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    final effectiveHeight = screenHeight - bottomInset;

    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        // keep keyboard inset so content stays visible
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SizedBox(
          height: effectiveHeight,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 16),
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text(
                  'Developer Login',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Enter your developer credentials. Once verified, access will persist across app restarts.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ),
                const SizedBox(height: 12),

                // ⬇️ 버튼을 "더 위"로: 하단 고정 영역 제거하고 폼 바로 아래 배치
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _idCtrl,
                            decoration: const InputDecoration(
                              labelText: 'ID', // no hint
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _pwCtrl,
                            obscureText: _obscure,
                            decoration: InputDecoration(
                              labelText: 'Password', // no hint
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                onPressed: () => setState(() => _obscure = !_obscure),
                                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                                tooltip: _obscure ? 'Show' : 'Hide',
                              ),
                            ),
                            onFieldSubmitted: (_) => _submit(),
                          ),

                          const SizedBox(height: 12),
                          if (_error != null)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: cs.errorContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: cs.onErrorContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),

                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: const StadiumBorder(),
                                  ),
                                  child: const Text('Cancel'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _submit,
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: const StadiumBorder(),
                                  ),
                                  icon: const Icon(Icons.login),
                                  label: const Text(
                                    'Log in',
                                    style: TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          // ⬇️ 초기화(Reset) 버튼 추가 — prefs의 dev_auth/dev_id/dev_pw 초기화 + 카드 숨김
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: _reset,
                              icon: const Icon(Icons.restart_alt),
                              label: const Text('Reset'), // '초기화'
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                              ),
                            ),
                          ),

                          // ⬇️ 여백을 조금 둬서 실제 하단과 간격 확보(버튼이 더 위에 보이도록)
                          const SizedBox(height: 48),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
