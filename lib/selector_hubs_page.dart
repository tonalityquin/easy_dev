// lib/screens/selector_hubs_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'routes.dart';

// snackbar helper
import '../utils/snackbar_helper.dart';

// 패키지 분리된 섹션들
import 'screens/dev_package/debug_package/debug_bottom_sheet.dart';
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
  String? _savedMode; // 'service' | 'tablet' | null
  bool _devAuthorized = false;

  @override
  void initState() {
    super.initState();
    _restorePrefs();
  }

  Future<void> _restorePrefs() async {
    final pref = await DevAuth.restorePrefs();
    if (!mounted) return;
    setState(() {
      _savedMode = pref.savedMode;
      _devAuthorized = pref.devAuthorized;
    });
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
              // 🔁 문구 수정: 오프라인 서비스는 인증 없이도 진입 가능하므로 문구에서 제외
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

  @override
  Widget build(BuildContext context) {
    final serviceEnabled = _savedMode == null || _savedMode == 'service';
    final tabletEnabled = _savedMode == null || _savedMode == 'tablet';

    final List<List<Widget>> pages = [
      [
        ServiceCard(enabled: serviceEnabled),
        TabletCard(enabled: tabletEnabled),
      ],
      [
        const HeadquarterCard(),
        const FaqCard(),
      ],
      // ✅ 변경: 개발자 인증 여부와 무관하게 오프라인 서비스 카드를 항상 표시
      [
        const CommunityCard(),
        const ParkingCard(),
      ],
      // 개발자 메뉴는 기존과 동일 — 인증된 경우에만 표시
      if (_devAuthorized)
        [
          DevCard(onTap: () => Navigator.of(context).pushReplacementNamed(AppRoutes.devStub)),
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
            child: Container(height: 1, color: Colors.black.withOpacity(0.06)),
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
                      onTapLogs: () => _handleLogsTap(context), // 🔥 새로 추가될 함수
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
