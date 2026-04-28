import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/di/routes.dart';
import '../../../../app/init/logout_helper.dart';
import '../../../../services/endtime_reminder_service.dart';
import '../../../../utils/db_connection_status_section.dart';
import '../../../../widgets/dialog/status_dialog_package/status_dialog.dart';
import '../../../account/applications/user_state.dart';
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
    );
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
    );
  }

  double _calcFooterHeight(BuildContext context) {
    final media = MediaQuery.of(context);
    final isShort = media.size.height < 640;
    final keyboardOpen = media.viewInsets.bottom > 0;
    return (isShort || keyboardOpen) ? 72 : 120;
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
          label: widget.spec.screenTagLabel,
          child: ExcludeSemantics(
            child: CommonBrandTintedLogo(
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

  Widget _buildContent(BuildContext context, double footerHeight) {
    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const CommonCommuteInHeaderWidget(),
              const SizedBox(height: 10),
              const DbConnectionStatusSection(),
              const SizedBox(height: 10),
              const CommonCommuteInInfoCardWidget(),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: CommonCommuteInWorkButtonWidget(
                  controller: controller,
                  spec: widget.spec,
                  onLoadingChanged: (value) {
                    setState(() => _isLoading = value);
                  },
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: SizedBox(
                  height: footerHeight,
                  child: CommonBrandTintedLogo(
                    assetPath: 'assets/images/ParkinWorkin_text.png',
                    height: footerHeight,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenu(BuildContext context, ColorScheme cs) {
    return Positioned(
      top: 16,
      right: 16,
      child: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'selector') _goToSelector(context);
          if (value == 'clock_in_issue') _resolveClockInIssue(context);
          if (value == 'logout') _handleLogout(context);
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'selector',
            child: Row(
              children: [
                Icon(Icons.grid_view_rounded, color: cs.primary),
                const SizedBox(width: 8),
                const Text('모드 선택(Selector)'),
              ],
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'clock_in_issue',
            child: Row(
              children: [
                Icon(Icons.build_circle_outlined, color: cs.secondary),
                const SizedBox(width: 8),
                const Text('출근 이슈 해결'),
              ],
            ),
          ),
          const PopupMenuDivider(),
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
    );
  }

  Widget _buildBlockingOverlay(ColorScheme cs) {
    return Positioned.fill(
      child: AbsorbPointer(
        absorbing: true,
        child: Container(
          color: cs.scrim.withOpacity(0.35),
          child: Center(
            child: CircularProgressIndicator(color: cs.primary),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Consumer<UserState>(
          builder: (context, userState, _) {
            final cs = Theme.of(context).colorScheme;
            final footerHeight = _calcFooterHeight(context);
            final isBlocking = _isLoading || userState.isWorking;

            return SafeArea(
              child: Stack(
                children: [
                  _buildScreenTag(context),
                  _buildContent(context, footerHeight),
                  _buildMenu(context, cs),
                  if (isBlocking) _buildBlockingOverlay(cs),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
