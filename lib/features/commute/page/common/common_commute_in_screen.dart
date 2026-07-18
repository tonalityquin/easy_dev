import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/di/routes.dart';
import '../../../../app/init/app_exit_service.dart';
import '../../../../app/init/db_connection_status_section.dart';
import '../../../../app/init/logout_helper.dart';
import '../../../../app/utils/status_dialog.dart';
import '../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../../account/applications/user_state.dart';
import '../../../dashboard/applications/common/endtime_reminder_service.dart';
import '../../controllers/common_commute_in_controller.dart';
import '../../utils/common_brand_tinted_logo.dart';
import '../../utils/commute_mode_spec.dart';
import '../widgets/common_commute_in_header_widget.dart';
import '../widgets/common_commute_in_info_card_widget.dart';
import '../widgets/common_commute_in_work_button_widget.dart';

class CommonCommuteInScreen extends StatefulWidget {
  const CommonCommuteInScreen({
    super.key,
    required this.spec,
  });

  final CommuteModeSpec spec;

  @override
  State<CommonCommuteInScreen> createState() => _CommonCommuteInScreenState();
}

class _CommonCommuteInScreenState extends State<CommonCommuteInScreen> {
  late final CommonCommuteInController controller =
      CommonCommuteInController(spec: widget.spec);

  bool _isLoading = false;

  static const String _pelicanTagAsset = 'assets/images/pelican_text.png';

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
    await prefs.setBool(kIsWorkingPrefsKey, false);

    await EndTimeReminderService.instance.cancel();
  }

  Future<void> _handleLogout(BuildContext context) async {
    await LogoutHelper.logoutAndGoToLogin(
      context,
      checkWorking: false,
      delay: const Duration(milliseconds: 500),
      usePromptUi: true,
    );
  }

  Future<void> _handleAppExit(BuildContext context) async {
    await AppExitService.exitApp(context, usePromptUi: true);
  }

  Future<void> _goToSelector(BuildContext context) async {
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.selector,
      (route) => false,
    );
  }

  Future<void> _resolveClockInIssue(BuildContext context) async {
    final userState = context.read<UserState>();
    await userState.clearClockInIssueFlag();
    if (!mounted) return;
    await StatusDialog.showSuccess(
      context,
      title: '출근 이슈 해결 완료',
      usePromptUi: true,
    );
  }

  double _footerHeight(BuildContext context) {
    final media = MediaQuery.of(context);
    final compact = media.size.height < 680;
    final keyboardOpen = media.viewInsets.bottom > 0;
    if (keyboardOpen) return 0;
    return compact ? 58 : 76;
  }

  SystemUiOverlayStyle _systemUiStyle(PromptUiTokens tokens) {
    final brightness = tokens.isDark ? Brightness.light : Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: tokens.canvas,
      statusBarIconBrightness: brightness,
      statusBarBrightness: tokens.isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: tokens.surface,
      systemNavigationBarIconBrightness: brightness,
      systemNavigationBarDividerColor: tokens.borderSubtle,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
    );
  }

  Widget _buildBackground(PromptUiTokens tokens) {
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(color: tokens.canvas),
          child: Stack(
            children: [
              Positioned(
                top: -90,
                right: -72,
                child: Container(
                  width: 230,
                  height: 230,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tokens.accentContainer.withOpacity(
                      tokens.isDark ? 0.28 : 0.48,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 54,
                left: -88,
                child: Container(
                  width: 210,
                  height: 210,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tokens.surfaceOverlay.withOpacity(
                      tokens.isDark ? 0.42 : 0.70,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScreenTag(BuildContext context, PromptUiTokens tokens) {
    return Semantics(
      label: widget.spec.screenTagLabel,
      image: true,
      child: ExcludeSemantics(
        child: AnimatedContainer(
          duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
              ? Duration.zero
              : PromptUiMotion.selection,
          width: 116,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(PromptUiShapes.control),
            border: Border.all(color: tokens.borderSubtle),
          ),
          child: CommonBrandTintedLogo(
            assetPath: _pelicanTagAsset,
            height: 30,
            preferredColor: tokens.iconSecondary,
            fallbackColor: tokens.textPrimary,
            minContrast: 3,
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _menuItem({
    required PromptUiTokens tokens,
    required String value,
    required IconData icon,
    required String label,
    bool destructive = false,
  }) {
    final foreground = destructive ? tokens.danger : tokens.textPrimary;
    final iconColor = destructive ? tokens.danger : tokens.accent;
    return PopupMenuItem<String>(
      value: value,
      height: 52,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: destructive
                  ? tokens.dangerContainer
                  : tokens.accentContainer,
              borderRadius: BorderRadius.circular(PromptUiShapes.control),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenu(BuildContext context, PromptUiTokens tokens) {
    return PopupMenuButton<String>(
      tooltip: '메뉴',
      color: tokens.surfaceRaised,
      elevation: 0,
      offset: const Offset(0, 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PromptUiShapes.card),
        side: BorderSide(color: tokens.borderSubtle),
      ),
      onSelected: (value) {
        switch (value) {
          case 'selector':
            _goToSelector(context);
            break;
          case 'clock_in_issue':
            _resolveClockInIssue(context);
            break;
          case 'exit_app':
            _handleAppExit(context);
            break;
          case 'logout':
            _handleLogout(context);
            break;
        }
      },
      itemBuilder: (context) => [
        _menuItem(
          tokens: tokens,
          value: 'selector',
          icon: Icons.grid_view_rounded,
          label: '모드 선택(Selector)',
        ),
        const PopupMenuDivider(height: 1),
        _menuItem(
          tokens: tokens,
          value: 'clock_in_issue',
          icon: Icons.build_circle_outlined,
          label: '출근 이슈 해결',
        ),
        const PopupMenuDivider(height: 1),
        _menuItem(
          tokens: tokens,
          value: 'exit_app',
          icon: Icons.power_settings_new_rounded,
          label: '앱 종료',
          destructive: true,
        ),
        _menuItem(
          tokens: tokens,
          value: 'logout',
          icon: Icons.logout_rounded,
          label: '로그아웃',
          destructive: true,
        ),
      ],
      child: Semantics(
        button: true,
        label: '메뉴',
        child: AnimatedContainer(
          duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
              ? Duration.zero
              : PromptUiMotion.selection,
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(PromptUiShapes.control),
            border: Border.all(color: tokens.borderSubtle),
          ),
          child: Icon(
            Icons.more_horiz_rounded,
            color: tokens.iconPrimary,
            size: 24,
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, PromptUiTokens tokens) {
    return PromptAnimatedReveal(
      duration: PromptUiMotion.component,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildScreenTag(context, tokens),
          _buildMenu(context, tokens),
        ],
      ),
    );
  }

  Widget _buildConnectionPanel(
    BuildContext context,
    PromptUiTokens tokens,
  ) {
    return PromptAnimatedReveal(
      delay: const Duration(milliseconds: 80),
      child: AnimatedContainer(
        duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
            ? Duration.zero
            : PromptUiMotion.component,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(PromptUiShapes.card),
          border: Border.all(color: tokens.borderSubtle),
        ),
        child: const DbConnectionStatusSection(usePromptUi: true),
      ),
    );
  }

  Widget _buildFooterLogo(
    BuildContext context,
    PromptUiTokens tokens,
    double footerHeight,
  ) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedSize(
      duration: reduceMotion ? Duration.zero : PromptUiMotion.layout,
      curve: PromptUiMotion.standard,
      child: footerHeight == 0
          ? const SizedBox.shrink()
          : PromptAnimatedReveal(
              delay: const Duration(milliseconds: 260),
              child: SizedBox(
                height: footerHeight,
                child: Center(
                  child: CommonBrandTintedLogo(
                    assetPath: 'assets/images/ParkinWorkin_text.png',
                    height: footerHeight,
                    preferredColor: tokens.accent,
                    fallbackColor: tokens.textPrimary,
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    PromptUiTokens tokens,
    double footerHeight,
  ) {
    final media = MediaQuery.of(context);
    final horizontalPadding = media.size.width >= 720 ? 32.0 : 18.0;
    final bottomPadding = media.viewPadding.bottom + 20;

    return Positioned.fill(
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          14,
          horizontalPadding,
          bottomPadding,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              children: [
                _buildTopBar(context, tokens),
                const SizedBox(height: 12),
                const CommonCommuteInHeaderWidget(),
                const SizedBox(height: 12),
                _buildConnectionPanel(context, tokens),
                const SizedBox(height: 14),
                const PromptAnimatedReveal(
                  delay: Duration(milliseconds: 140),
                  child: CommonCommuteInInfoCardWidget(),
                ),
                const SizedBox(height: 14),
                PromptAnimatedReveal(
                  delay: const Duration(milliseconds: 200),
                  child: CommonCommuteInWorkButtonWidget(
                    controller: controller,
                    spec: widget.spec,
                    onLoadingChanged: (value) {
                      if (!mounted || _isLoading == value) return;
                      setState(() => _isLoading = value);
                    },
                  ),
                ),
                const SizedBox(height: 12),
                _buildFooterLogo(
                  context,
                  tokens,
                  footerHeight,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBlockingOverlay(
    BuildContext context,
    PromptUiTokens tokens,
    bool isBlocking,
  ) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Positioned.fill(
      child: AnimatedSwitcher(
        duration: reduceMotion ? Duration.zero : PromptUiMotion.overlay,
        switchInCurve: PromptUiMotion.enter,
        switchOutCurve: PromptUiMotion.exit,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.98, end: 1).animate(animation),
              child: child,
            ),
          );
        },
        child: isBlocking
            ? AbsorbPointer(
                key: const ValueKey<String>('blocking'),
                absorbing: true,
                child: ColoredBox(
                  color: tokens.scrim,
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 290),
                      margin: const EdgeInsets.symmetric(horizontal: 28),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: tokens.surfaceRaised,
                        borderRadius:
                            BorderRadius.circular(PromptUiShapes.dialog),
                        border: Border.all(color: tokens.borderSubtle),
                        boxShadow: [
                          BoxShadow(
                            color: tokens.shadow,
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: tokens.accentContainer,
                              borderRadius: BorderRadius.circular(
                                PromptUiShapes.control,
                              ),
                            ),
                            child: Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: tokens.accent,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Flexible(
                            child: Text(
                              '출근 정보를 확인하고 있습니다',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: tokens.textPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            : const SizedBox.shrink(
                key: ValueKey<String>('idle'),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PromptUiScope(
      child: Builder(
        builder: (context) {
          final tokens = PromptUiTheme.of(context);
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: _systemUiStyle(tokens),
            child: PopScope(
              canPop: false,
              child: Scaffold(
                backgroundColor: tokens.canvas,
                body: Consumer<UserState>(
                  builder: (context, userState, _) {
                    final footerHeight = _footerHeight(context);
                    final isBlocking = _isLoading || userState.isWorking;

                    return SafeArea(
                      bottom: false,
                      child: Stack(
                        children: [
                          _buildBackground(tokens),
                          _buildContent(context, tokens, footerHeight),
                          _buildBlockingOverlay(
                            context,
                            tokens,
                            isBlocking,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
