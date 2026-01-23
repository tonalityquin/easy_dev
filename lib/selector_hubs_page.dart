import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'routes.dart';

// snackbar helper
import 'utils/snackbar_helper.dart';

// 패키지 분리된 섹션들
import 'screens/hubs_mode/dev_package/debug_package/debug_bottom_sheet.dart';
import 'selector_hubs_package/dev_auth.dart';
import 'selector_hubs_package/cards.dart';
import 'selector_hubs_package/cards_pager.dart';
import 'selector_hubs_package/header.dart';
import 'selector_hubs_package/update_alert_bar.dart';
import 'selector_hubs_package/dev_login_bottom_sheet.dart';
import 'selector_hubs_package/update_bottom_sheet.dart';

class SelectorHubsPage extends StatefulWidget {
  const SelectorHubsPage({super.key});

  @override
  State<SelectorHubsPage> createState() => _SelectorHubsPageState();
}

class _SelectorHubsPageState extends State<SelectorHubsPage> {
  String? _savedMode; // 'tablet' | 'single' | 'double' | 'triple' | 'minor' | null
  bool _devAuthorized = false;

  @override
  void initState() {
    super.initState();
    _restorePrefs();
  }

  Future<void> _restorePrefs() async {
    final pref = await DevAuth.restorePrefs();
    if (!mounted) return;

    // ✅ 레거시(service 모드) 저장값 감지: 서비스 로그인 폐기 이후에도 허브가 잠기지 않도록 안내
    final wasService = (pref.savedMode ?? '').trim().toLowerCase() == 'service';

    setState(() {
      _savedMode = pref.savedMode;
      _devAuthorized = pref.devAuthorized;
    });

    if (wasService) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showSelectedSnackbar(context, '서비스 로그인은 종료되었습니다. 다른 모드를 선택해 주세요.');
      });
    }
  }

  Future<void> _setDevAuthorized(bool value) async {
    await DevAuth.setDevAuthorized(value);
    if (mounted) setState(() => _devAuthorized = value);
  }

  Future<void> _resetDevAuth() async {
    await DevAuth.resetDevAuth();
    if (mounted) setState(() => _devAuthorized = false);
  }

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
            await _setDevAuthorized(true);
            if (mounted) {
              Navigator.of(ctx).pop();
              showSuccessSnackbar(
                context,
                '개발자 인증 완료. 이제 개발 메뉴를 사용할 수 있습니다.',
              );
            }
          },
          onReset: () async {
            await _resetDevAuth();
            if (mounted) {
              Navigator.of(ctx).pop();
              showSelectedSnackbar(context, '개발자 인증이 초기화되었습니다.');
            }
          },
        ),
      ),
    );
  }

  Future<void> _handleUpdateTap(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const FractionallySizedBox(
        heightFactor: 1,
        child: UpdateBottomSheet(),
      ),
    );
  }

  Future<void> _handleLogsTap(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const DebugBottomSheet(),
    );
  }

  String? _normalizeMode(String? raw) {
    if (raw == null) return null;
    final v = raw.trim().toLowerCase();
    if (v.isEmpty) return null;

    // 리네이밍/하위호환: 기존 값도 수용
    switch (v) {
      case 'service':
        return null; // 서비스 로그인 폐기: 저장값이 service면 모드 제한 해제
      case 'tablet':
        return 'tablet';
      case 'single':
      case 'simple':
        return 'single';
      case 'double':
      case 'lite':
      case 'light':
        return 'double';
      case 'triple':
      case 'normal':
        return 'triple';
      default:
        return v; // 알 수 없는 값은 그대로(방어 로직에서 전체 허용)
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = _normalizeMode(_savedMode);

    final bool singleEnabled;
    final bool tabletEnabled;
    final bool doubleEnabled;
    final bool tripleEnabled;
    final bool minorEnabled;

    if (mode == null) {
      singleEnabled = true;
      tabletEnabled = true;
      doubleEnabled = true;
      tripleEnabled = true;
      minorEnabled = true;
    } else if (mode == 'single') {
      singleEnabled = true;
      tabletEnabled = false;
      doubleEnabled = false;
      tripleEnabled = false;
      minorEnabled = false;
    } else if (mode == 'tablet') {
      singleEnabled = false;
      tabletEnabled = true;
      doubleEnabled = false;
      tripleEnabled = false;
      minorEnabled = false;
    } else if (mode == 'double') {
      singleEnabled = false;
      tabletEnabled = false;
      doubleEnabled = true;
      tripleEnabled = false;
      minorEnabled = false;
    } else if (mode == 'triple') {
      // ✅ WorkFlow B 로그인 후: triple만 허용 (다른 WorkFlow 로그인 카드 비활성화)
      singleEnabled = false;
      tabletEnabled = false;
      doubleEnabled = false;
      tripleEnabled = true;
      minorEnabled = false;
    } else if (mode == 'minor') {
      // ✅ WorkFlow C 로그인 후: minor만 허용 (다른 WorkFlow 로그인 카드 비활성화)
      singleEnabled = false;
      tabletEnabled = false;
      doubleEnabled = false;
      tripleEnabled = false;
      minorEnabled = true;
    } else {
      // 예기치 못한 값이 들어온 경우: 방어적으로 모두 허용
      singleEnabled = true;
      tabletEnabled = true;
      doubleEnabled = true;
      tripleEnabled = true;
      minorEnabled = true;
    }

    // ✅ 요청하신 카드 배열 순서(페이지/좌우)를 그대로 반영
    final List<List<Widget>> pages = [
      // 1) WorkFlow A(더블) / WorkFlow B(트리플)
      [
        DoubleLoginCard(enabled: doubleEnabled),
        TripleLoginCard(enabled: tripleEnabled),
      ],

      // 2) WorkFlow C(마이너) / WorkFlow D(싱글)
      [
        MinorLoginCard(enabled: minorEnabled),
        SingleLoginCard(enabled: singleEnabled),
      ],

      // 3) 태블릿 로그인 / 본사
      [
        TabletCard(enabled: tabletEnabled),
        const HeadquarterCard(),
      ],

      // 4) 커뮤니티 / FAQ
      [
        const CommunityCard(),
        const FaqCard(),
      ],

      // 5) 개발자 전용: Practice Space + 개발 (동일 화면)
      //    - Practice Space는 개발자 인증 후에만 노출
      if (_devAuthorized)
        [
          const ParkingCard(),
          DevCard(
            onTap: () => Navigator.of(context).pushReplacementNamed(AppRoutes.devStub),
          ),
        ],
    ];

    final media = MediaQuery.of(context);
    final bool isShort = media.size.height < 640;
    final bool keyboardOpen = media.viewInsets.bottom > 0;
    final double footerHeight = (isShort || keyboardOpen) ? 72 : 120;
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {},
      child: Scaffold(
        backgroundColor: Colors.white,
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Header(),
                    const SizedBox(height: 24),
                    CardsPager(pages: pages),
                    const SizedBox(height: 16),
                    UpdateAlertBar(
                      onTapUpdate: () => _handleUpdateTap(context),
                      onTapLogs: () => _handleLogsTap(context),
                      background: cs.primary,
                      foreground: cs.onPrimary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: AnimatedOpacity(
          opacity: keyboardOpen ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 160),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: footerHeight,
              child: Center(
                child: Semantics(
                  button: true,
                  label: '개발자 로그인',
                  hint: '개발자 전용 로그인 시트를 엽니다',
                  child: Tooltip(
                    message: '개발자 로그인',
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
          ),
        ),
      ),
    );
  }
}
