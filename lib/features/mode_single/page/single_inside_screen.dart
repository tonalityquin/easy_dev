import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../app/init/db_connection_status_section.dart';
import '../../../app/init/logout_helper.dart';
import '../../account/applications/user_state.dart';
import '../../community/page/community_stub_page.dart';
import '../../dashboard/applications/common/endtime_reminder_service.dart';
import '../../dev/debug/debug_api_logger.dart';
import '../../selector/sheets/service_bottom_sheet.dart';
import '../controllers/single_inside_controller.dart';
import 'widgets/single_inside_document_box_button_section.dart';
import 'widgets/single_inside_header_widget_section.dart';
import 'widgets/single_inside_report_button_section.dart';
import 'widgets/widgets/single_inside_punch_recorder_section.dart';

enum SingleInsideMode {
  leader,
  fieldUser,
}

const String _tSingle = 'Single';
const String _tSingleInside = 'Single/inside';
const String _tPrefs = 'prefs';
const String _tUi = 'ui';

enum _SingleInsideMenuAction {
  logout,
  settings,
}

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

Future<void> _logApiError({
  required String tag,
  required String message,
  required Object error,
  Map<String, dynamic>? extra,
  List<String>? tags,
}) async {
  try {
    await DebugApiLogger().log(
      <String, dynamic>{
        'tag': tag,
        'message': message,
        'error': error.toString(),
        if (extra != null) 'extra': extra,
      },
      level: 'error',
      tags: tags,
    );
  } catch (_) {}
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

class SingleInsideScreen extends StatefulWidget {
  const SingleInsideScreen({
    super.key,
    this.mode,
  });

  final SingleInsideMode? mode;

  @override
  State<SingleInsideScreen> createState() => _SingleInsideScreenState();
}

class _SingleInsideScreenState extends State<SingleInsideScreen> {
  final controller = SingleInsideController();

  static const String _kPelicanTagAsset = 'assets/images/pelican_text.png';
  static const double _kTagExtraHeight = 70.0;

  @override
  void initState() {
    super.initState();
    controller.initialize(context);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final userState = context.read<UserState>();

      await userState.ensureTodayClockInStatus();
      if (!mounted) return;

      if (userState.isWorking && !userState.hasClockInToday) {
        await _resetStaleWorkingState(userState);
      }
      if (!mounted) return;
    });
  }


  double _calcFooterHeight(BuildContext context) {
    final media = MediaQuery.of(context);
    final bool isShort = media.size.height < 640;
    final bool keyboardOpen = media.viewInsets.bottom > 0;
    return (isShort || keyboardOpen) ? 72 : 120;
  }

  Future<void> _resetStaleWorkingState(UserState userState) async {
    try {
      await userState.isHeWorking();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isWorking', false);

      await EndTimeReminderService.instance.cancel();
    } catch (e) {
      await _logApiError(
        tag: 'SingleInsideScreen._resetStaleWorkingState',
        message: 'stale working state 리셋 실패',
        error: e,
        tags: const <String>[_tSingle, _tSingleInside, _tPrefs],
      );
    }
  }

  Future<void> _handleLogout(BuildContext context) async {
    try {
      await LogoutHelper.logoutAndGoToLogin(
        context,
        checkWorking: false,
        delay: const Duration(milliseconds: 500),
      );
    } catch (e) {
      await _logApiError(
        tag: 'SingleInsideScreen._handleLogout',
        message: '로그아웃 처리 실패',
        error: e,
        tags: const <String>[_tSingle, _tSingleInside, _tUi],
      );
      rethrow;
    }
  }

  Future<void> _openSettings(BuildContext context) async {
    try {
      await ServiceBottomSheet.show(
        context: context,
      );
    } catch (e) {
      await _logApiError(
        tag: 'SingleInsideScreen._openSettings',
        message: '설정 바텀시트 열기 실패',
        error: e,
        tags: const <String>[_tSingle, _tSingleInside, _tUi],
      );
    }
  }

  Future<void> _handleMenuAction(
      BuildContext context,
      _SingleInsideMenuAction action,
      ) async {
    switch (action) {
      case _SingleInsideMenuAction.logout:
        await _handleLogout(context);
        break;
      case _SingleInsideMenuAction.settings:
        await _openSettings(context);
        break;
    }
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
          label: 'screen_tag: Single screen (image)',
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

  SingleInsideMode _resolveMode(UserState userState) {
    if (widget.mode != null) return widget.mode!;

    String role = '';
    final session = userState.session;
    if (session != null) {
      role = session.role.trim();
    }

    debugPrint('[SingleInsideScreen] resolved role="$role"');

    if (role == 'fieldCommon') {
      return SingleInsideMode.fieldUser;
    }

    return SingleInsideMode.leader;
  }

  Widget _buildMenu(BuildContext context, ColorScheme cs) {
    return Positioned(
      top: 16,
      right: 16,
      child: PopupMenuButton<_SingleInsideMenuAction>(
        onSelected: (value) async {
          await _handleMenuAction(context, value);
        },
        itemBuilder: (context) => [
          PopupMenuItem<_SingleInsideMenuAction>(
            value: _SingleInsideMenuAction.logout,
            child: Row(
              children: [
                Icon(Icons.logout, color: cs.error),
                const SizedBox(width: 8),
                const Text('로그아웃'),
              ],
            ),
          ),
          PopupMenuItem<_SingleInsideMenuAction>(
            value: _SingleInsideMenuAction.settings,
            child: Row(
              children: [
                Icon(Icons.settings_outlined, color: cs.primary),
                const SizedBox(width: 8),
                const Text('설정'),
              ],
            ),
          ),
        ],
        icon: const Icon(Icons.more_vert),
      ),
    );
  }

  Widget _buildContent({
    required BuildContext context,
    required SingleInsideMode mode,
    required String userId,
    required String userName,
    required String area,
    required String division,
    required double footerHeight,
  }) {
    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SingleInsideHeaderWidgetSection(),
              const SizedBox(height: 12),
              const DbConnectionStatusSection(),
              const SizedBox(height: 12),
              SingleInsidePunchRecorderSection(
                userId: userId,
                userName: userName,
                area: area,
                division: division,
              ),
              const SizedBox(height: 6),
              if (mode == SingleInsideMode.leader)
                const _CommonModeButtonGrid()
              else
                const _TeamModeButtonGrid(),
              const SizedBox(height: 1),
              Center(
                child: SizedBox(
                  height: footerHeight,
                  child: _BrandTintedLogo(
                    assetPath: 'assets/images/ParkinWorkin_text.png',
                    height: footerHeight,
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final footerHeight = _calcFooterHeight(context);

    return PopScope(
      canPop: false,
      child: Scaffold(
        bottomNavigationBar: const _SingleInsideCommunityDock(),
        body: Consumer<UserState>(
          builder: (context, userState, _) {
            final mode = _resolveMode(userState);

            final session = userState.session;
            if (session == null) {
              return Center(
                child: CircularProgressIndicator(color: cs.primary),
              );
            }

            final String userId = session.id;
            final String userName = session.displayName;
            final String area = userState.currentArea;
            final String division = userState.division;

            debugPrint(
              '[SingleInsideScreen] punchRecorder props → '
                  'userId="$userId", userName="$userName", area="$area", division="$division"',
            );

            return SafeArea(
              child: Stack(
                children: [
                  _buildScreenTag(context),
                  _buildContent(
                    context: context,
                    mode: mode,
                    userId: userId,
                    userName: userName,
                    area: area,
                    division: division,
                    footerHeight: footerHeight,
                  ),
                  _buildMenu(context, cs),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SingleInsideCommunityDock extends StatelessWidget {
  const _SingleInsideCommunityDock();

  Future<void> _openCommunity(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const CommunityStubPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      left: false,
      right: false,
      bottom: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: () => _openCommunity(context),
            icon: const Icon(Icons.groups_rounded),
            label: const Text('커뮤니티'),
            style: FilledButton.styleFrom(
              backgroundColor: cs.secondary,
              foregroundColor: cs.onSecondary,
              shape: const StadiumBorder(),
            ),
          ),
        ),
      ),
    );
  }
}

class _CommonModeButtonGrid extends StatelessWidget {
  const _CommonModeButtonGrid();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        Row(
          children: [
            Expanded(child: SingleInsideReportButtonSection()),
            SizedBox(width: 12),
            Expanded(child: SingleInsideDocumentBoxButtonSection()),
          ],
        ),
      ],
    );
  }
}

class _TeamModeButtonGrid extends StatelessWidget {
  const _TeamModeButtonGrid();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        Row(
          children: [
            Expanded(child: SingleInsideDocumentBoxButtonSection()),
          ],
        ),
      ],
    );
  }
}
