import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../states/user/user_state.dart';
import '../../../utils/init/logout_helper.dart';
import '../../../services/endtime_reminder_service.dart';
import 'commute_inside_package/minor_commute_in_controller.dart';
import 'commute_inside_package/widgets/minor_commute_in_work_button_widget.dart';
import 'commute_inside_package/widgets/minor_commute_in_info_card_widget.dart';
import 'commute_inside_package/widgets/minor_commute_in_header_widget.dart';

/// ─────────────────────────────────────────────────────────────
/// ✅ 로고(PNG) 가독성 보장 유틸 (파일 내부 로컬 정의)
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

  final Color? preferredColor;
  final Color? fallbackColor;
  final double minContrast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

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

class MinorCommuteInScreen extends StatefulWidget {
  const MinorCommuteInScreen({super.key});

  @override
  State<MinorCommuteInScreen> createState() => _MinorCommuteInScreenState();
}

class _MinorCommuteInScreenState extends State<MinorCommuteInScreen> {
  final controller = MinorCommuteInController();
  bool _isLoading = false;

  // ✅ (변경) 상단 screen tag 이미지
  static const String _kPelicanTagAsset = 'assets/images/pelican_text.png';
  static const double _kTagExtraHeight = 70.0;

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
    await userState.isHeWorking(); // true → false

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

  Widget _buildScreenTag(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final base = theme.textTheme.labelSmall ??
        const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        );

    final fontSize = (base.fontSize ?? 11).toDouble();
    final tagImageHeight = fontSize + _kTagExtraHeight;

    final tagPreferredTint = cs.onSurfaceVariant.withOpacity(0.80);

    return Positioned(
      top: 12,
      left: 12,
      child: IgnorePointer(
        child: Semantics(
          label: 'screen_tag: minor commute screen',
          child: ExcludeSemantics(
            child: _BrandTintedLogo(
              assetPath: _kPelicanTagAsset,
              height: tagImageHeight,
              preferredColor: tagPreferredTint,
              fallbackColor: cs.onBackground,
              minContrast: 3.0,
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
                  _buildScreenTag(context),

                  SingleChildScrollView(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            const MinorCommuteInHeaderWidget(),
                            const MinorCommuteInInfoCardWidget(),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: MinorCommuteInWorkButtonWidget(
                                controller: controller,
                                onLoadingChanged: (value) {
                                  setState(() => _isLoading = value);
                                },
                              ),
                            ),
                            const SizedBox(height: 8),

                            // ✅ (변경) 하단 텍스트 로고 tint 적용
                            Center(
                              child: SizedBox(
                                height: 80,
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
                        if (value == 'logout') _handleLogout(context);
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
