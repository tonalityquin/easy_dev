import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../states/user/user_state.dart';
import '../../../utils/init/logout_helper.dart';
import '../../../services/endtime_reminder_service.dart';
import 'commute_inside_package/double_commute_in_controller.dart';
import 'commute_inside_package/widgets/double_commute_in_work_button_widget.dart';
import 'commute_inside_package/widgets/double_commute_in_info_card_widget.dart';
import 'commute_inside_package/widgets/double_commute_in_header_widget.dart';

/// ─────────────────────────────────────────────────────────────
/// ✅ 로고(PNG) 가독성 보장 유틸
///
/// - 단색/검정 고정 PNG가 다크/브랜드 배경에서 안 보이는 문제를 방지:
///   알파(투명도)를 마스크로 사용해 tint.
/// - preferred가 배경과 대비가 부족하면 fallback으로 자동 폴백.
///
/// NOTE: 로고/큰 텍스트는 minContrast=3.0 기준을 기본으로 둡니다.
double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final l1 = la >= lb ? la : lb;
  final l2 = la >= lb ? lb : la;
  return (l1 + 0.05) / (l2 + 0.05);
}

Color _resolveLogoTint({
  required Color background,
  required Color preferred,
  required Color fallback,
  double minContrast = 3.0,
}) {
  if (_contrastRatio(preferred, background) >= minContrast) return preferred;
  return fallback;
}

/// ✅ 단색(검정 고정) PNG 로고를 테마에 맞춰 tint 하는 위젯
class _BrandTintedLogo extends StatelessWidget {
  const _BrandTintedLogo({
    required this.assetPath,
    required this.height,
    this.preferredColor,
    this.fallbackColor,
    this.minContrast = 3.0,
  });

  final String assetPath;
  final double height;

  /// (선택) 기본은 cs.primary
  final Color? preferredColor;

  /// (선택) 기본은 cs.onBackground
  final Color? fallbackColor;

  final double minContrast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // ✅ 실제 화면 배경에 가장 근접한 scaffoldBackgroundColor를 기준으로 대비 판단
    final bg = theme.scaffoldBackgroundColor;

    final preferred = preferredColor ?? cs.primary;
    final fallback = fallbackColor ?? cs.onBackground;

    final tint = _resolveLogoTint(
      background: bg,
      preferred: preferred,
      fallback: fallback,
      minContrast: minContrast,
    );

    return Image.asset(
      assetPath,
      fit: BoxFit.contain,
      height: height,
      color: tint,
      colorBlendMode: BlendMode.srcIn,
    );
  }
}

class DoubleCommuteInScreen extends StatefulWidget {
  const DoubleCommuteInScreen({super.key});

  @override
  State<DoubleCommuteInScreen> createState() => _DoubleCommuteInScreenState();
}

class _DoubleCommuteInScreenState extends State<DoubleCommuteInScreen> {
  final controller = DoubleCommuteInController();

  bool _isLoading = false;

  // ✅ (변경) screen tag 텍스트 대신 표시할 “첨부 이미지” 에셋 경로
  static const String _kPelicanTagAsset = 'assets/images/pelican_text.png';

  // ✅ (신규) “보이는 크기만” 키우는 스케일 (레이아웃 높이에는 거의 영향 없음)
  static const double _kTagScale = 3.0;

  @override
  void initState() {
    super.initState();
    controller.initialize(context);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      final userState = context.read<UserState>();

      await userState.ensureTodayClockInStatus();
      if (!mounted) return;

      if (userState.isWorking && !userState.hasClockInToday) {
        await _resetStaleWorkingState(userState);
      }
      if (!mounted) return;

      if (userState.isWorking) {
        controller.redirectIfWorking(context, userState);
      }
    });
  }

  Future<void> _resetStaleWorkingState(UserState userState) async {
    await userState.isHeWorking();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isWorking', false);

    await EndTimeReminderService.instance.cancel();
  }

  Future<void> _handleLogout(BuildContext context) async {
    await LogoutHelper.logoutAndGoToLogin(
      context,
      checkWorking: false,
      delay: const Duration(milliseconds: 500),
    );
  }

  TextStyle _screenTagStyle(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.labelSmall;

    return (base ??
        const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ))
        .copyWith(
      color: cs.onSurfaceVariant.withOpacity(0.80),
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    );
  }

  /// ✅ (변경) 기존 텍스트 tag → pelican_text.png
  /// - 레이아웃 점유 높이: fontSize + 3.0 (고정)
  /// - 보이는 크기: Transform.scale 로 확대 (세로 길이 영향 최소화)
  Widget _buildScreenTag(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final style = _screenTagStyle(context);
    final fontSize = (style.fontSize ?? 11.0).toDouble();

    // ✅ 레이아웃 점유 높이(=텍스트 1줄 체감치)
    final tagLayoutHeight = fontSize + 3.0;

    // ✅ 기존 텍스트 색감(onSurfaceVariant 0.80)으로 이미지 tint
    final tagPreferredTint = cs.onSurfaceVariant.withOpacity(0.80);

    return Positioned(
      top: 12,
      left: 12,
      child: IgnorePointer(
        child: Semantics(
          label: 'screen_tag: WorkFlow A commute screen',
          child: ExcludeSemantics(
            child: SizedBox(
              height: tagLayoutHeight, // ✅ 레이아웃 높이 고정
              child: Align(
                alignment: Alignment.centerLeft,
                child: Transform.scale(
                  scale: _kTagScale, // ✅ 여기만 조절하면 “보이는 크기”가 변함
                  alignment: Alignment.centerLeft,
                  child: _BrandTintedLogo(
                    assetPath: _kPelicanTagAsset,
                    height: tagLayoutHeight,
                    preferredColor: tagPreferredTint,
                    fallbackColor: cs.onBackground,
                    minContrast: 3.0,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Consumer<UserState>(
          builder: (context, userState, _) {
            return SafeArea(
              child: Stack(
                children: [
                  // ✅ (변경) screen tag 텍스트 → pelican_text.png
                  _buildScreenTag(context),

                  SingleChildScrollView(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            const DoubleCommuteInHeaderWidget(),
                            const DoubleCommuteInInfoCardWidget(),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: DoubleCommuteInWorkButtonWidget(
                                controller: controller,
                                onLoadingChanged: (value) {
                                  setState(() {
                                    _isLoading = value;
                                  });
                                },
                              ),
                            ),
                            const SizedBox(height: 8),
                            Center(
                              child: SizedBox(
                                height: 80,
                                // ✅ (변경) 하단 텍스트 로고도 tint 적용
                                child: _BrandTintedLogo(
                                  assetPath: 'assets/images/ParkinWorkin_text.png',
                                  height: 80,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  Positioned(
                    top: 16,
                    right: 16,
                    child: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'logout') {
                          _handleLogout(context);
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'logout',
                          child: Row(
                            children: [
                              Icon(Icons.logout, color: cs.error),
                              const SizedBox(width: 8),
                              const Text('로그아웃'),
                            ],
                          ),
                        ),
                      ],
                      icon: const Icon(Icons.more_vert),
                    ),
                  ),

                  if (_isLoading || userState.isWorking)
                    Positioned.fill(
                      child: AbsorbPointer(
                        absorbing: true,
                        child: Container(
                          color: cs.scrim.withOpacity(0.35),
                          child: Center(
                            child: CircularProgressIndicator(color: cs.primary),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
