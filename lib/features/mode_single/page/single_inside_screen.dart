import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../app/command/presentation/terminal_launcher_button.dart';
import '../../../app/init/app_exit_service.dart';
import '../../../app/init/db_connection_status_section.dart';
import '../../../app/init/logout_helper.dart';
import '../../../app/utils/developer_operation_status_dialog.dart';
import '../../../app/utils/status_dialog.dart';
import '../../../design_system/common_ui/common_adaptive_two_line_content.dart';
import '../../../shared/area_remote_settings/application/area_remote_settings_sync.dart';
import '../../account/applications/user_state.dart';
import '../../dashboard/applications/common/endtime_reminder_service.dart';
import '../../dev/debug/debug_api_logger.dart';
import '../../selector/application/dev_auth.dart';
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
  exitApp,
}

class _SingleInsideLayoutDiagnostics {
  static const int _limit = 120;
  static final List<String> _lines = <String>[];

  static void log(String message) {
    final normalized = message.trim();
    if (normalized.isEmpty) return;
    final line =
        '[SINGLE_BRANCH_LAYOUT][${DateTime.now().toIso8601String()}] $normalized';
    _lines.add(line);
    if (_lines.length > _limit) {
      _lines.removeRange(0, _lines.length - _limit);
    }
    debugPrint(line);
  }

  static String get debugPrintCode {
    if (_lines.isEmpty) {
      return 'debugPrint(${jsonEncode('[SINGLE_BRANCH_LAYOUT] 기록된 로그가 없습니다.')});';
    }
    return _lines.map((line) => 'debugPrint(${jsonEncode(line)});').join('\n');
  }

  static Future<void> showStatus(
    BuildContext context, {
    required String description,
  }) async {
    final enabled = await DevAuth.isDevModeEnabled();
    if (!enabled || !context.mounted) return;
    await StatusDialog.showSuccess(
      context,
      title: '지사 레이아웃 상태',
      description: description,
      copyText: debugPrintCode,
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: Duration.zero,
      useCommonUi: true,
      awaitManualClose: true,
    );
  }
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


  Future<void> _handleAppExit(BuildContext context) async {
    try {
      await AppExitService.exitApp(context);
    } catch (e) {
      await _logApiError(
        tag: 'SingleInsideScreen._handleAppExit',
        message: '앱 종료 처리 실패',
        error: e,
        tags: const <String>[_tSingle, _tSingleInside, _tUi],
      );
      rethrow;
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
      case _SingleInsideMenuAction.exitApp:
        await _handleAppExit(context);
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

  Widget _buildTerminalLauncher(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Positioned(
      top: 16,
      left: 0,
      right: 0,
      child: TweenAnimationBuilder<double>(
        duration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        tween: Tween<double>(begin: 0, end: 1),
        builder: (context, value, child) {
          return Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, (1 - value) * -6),
              child: child,
            ),
          );
        },
        child: const Align(
          alignment: Alignment.topCenter,
          child: TerminalLauncherButton(source: 'single_branch'),
        ),
      ),
    );
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
            value: _SingleInsideMenuAction.exitApp,
            child: Row(
              children: [
                Icon(Icons.power_settings_new_rounded, color: cs.error),
                const SizedBox(width: 8),
                const Text('앱 종료'),
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
          padding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
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
        bottomNavigationBar: const _SingleInsideDataDownloadDock(),
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
                  _buildContent(
                    context: context,
                    mode: mode,
                    userId: userId,
                    userName: userName,
                    area: area,
                    division: division,
                    footerHeight: footerHeight,
                  ),
                  _buildScreenTag(context),
                  _buildTerminalLauncher(context),
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

enum _SingleInsideDataDownloadState {
  idle,
  loading,
  success,
  failure,
}

class _SingleInsideDataDownloadDock extends StatefulWidget {
  const _SingleInsideDataDownloadDock();

  @override
  State<_SingleInsideDataDownloadDock> createState() =>
      _SingleInsideDataDownloadDockState();
}

class _SingleInsideDataDownloadDockState
    extends State<_SingleInsideDataDownloadDock> {
  _SingleInsideDataDownloadState _state = _SingleInsideDataDownloadState.idle;
  Timer? _feedbackTimer;
  String _lastLayoutSignature = '';

  bool get _busy => _state == _SingleInsideDataDownloadState.loading;

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    super.dispose();
  }

  void _setStateSafe(_SingleInsideDataDownloadState value) {
    if (!mounted) return;
    if (_state != value) {
      _SingleInsideLayoutDiagnostics.log(
        'download_dock_state previous=${_state.name} next=${value.name}',
      );
    }
    setState(() => _state = value);
  }

  void _scheduleIdle() {
    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(const Duration(milliseconds: 1600), () {
      _setStateSafe(_SingleInsideDataDownloadState.idle);
    });
  }

  Future<void> _download() async {
    if (_busy) return;

    _feedbackTimer?.cancel();
    _setStateSafe(_SingleInsideDataDownloadState.loading);
    HapticFeedback.selectionClick();

    DeveloperOperationTrace? trace;
    try {
      final userState = context.read<UserState>();
      final division = userState.division.trim();
      final area = userState.currentArea.trim();

      trace = await DeveloperOperationTrace.start(
        context: context,
        title: '다운로드 데이터 확인',
        initialMessage: '현재 지역의 SQLite Snapshot 연결 데이터를 확인하고 있습니다.',
        useCommonUi: true,
        developerModeMessage: '개발자 모드 ON: debugPrint 코드를 복사할 수 있습니다.',
        standardModeMessage: '개발자 모드 OFF',
      );

      trace.log(
        'singleModePolicy=sqlite_snapshot_read_only firebaseRead=false sharedPreferencesRead=false',
        progress: 0.04,
      );
      trace.log(
        '현재 로그인 범위를 확인했습니다: divisionPresent=${division.isNotEmpty}, areaPresent=${area.isNotEmpty}',
        progress: 0.07,
      );

      final result = await AreaRemoteSettingsSync.sync(
        division: division,
        area: area,
        onLog: trace.log,
        progressStart: 0.1,
        progressEnd: 0.94,
      );

      trace.log(
        'SQLite Snapshot 연결 데이터 확인 결과: availableCount=${result.availableCount} emailAvailable=${result.emailAvailable} inviteAvailable=${result.inviteAvailable} communicationAvailable=${result.communicationAvailable}',
        progress: 0.97,
      );
      await trace.succeed('현재 지역의 SQLite Snapshot 확인이 완료되었습니다.');

      if (!mounted) return;
      _setStateSafe(_SingleInsideDataDownloadState.success);
      HapticFeedback.lightImpact();

      if (!trace.developerMode) {
        await StatusDialog.showSuccess(
          context,
          title: '다운로드 데이터 확인 완료',
          description:
              '현재 지역(${result.area})의 본사 다운로드 SQLite Snapshot을 확인했습니다.\nFirebase와 SharedPreferences는 조회하거나 갱신하지 않았습니다.\n${result.summary}',
          useCommonUi: true,
        );
      }

      _scheduleIdle();
    } catch (error, stackTrace) {
      debugPrint('[SingleInsideDataDownload] failure: $error');
      final activeTrace = trace;
      if (activeTrace != null) {
        await activeTrace.fail(
          '현재 지역의 SQLite Snapshot 확인에 실패했습니다.',
          error: error,
          stackTrace: stackTrace,
        );
      }

      if (!mounted) return;
      _setStateSafe(_SingleInsideDataDownloadState.failure);
      HapticFeedback.mediumImpact();

      if (activeTrace == null || !activeTrace.developerMode) {
        await StatusDialog.showFailure(
          context,
          title: '다운로드 데이터 확인 실패',
          description:
              '현재 지역의 본사 다운로드 SQLite Snapshot을 확인하지 못했습니다.',
          useCommonUi: true,
        );
      }

      _scheduleIdle();
    }
  }

  Color _background(ColorScheme cs) {
    switch (_state) {
      case _SingleInsideDataDownloadState.idle:
        return cs.secondaryContainer;
      case _SingleInsideDataDownloadState.loading:
        return cs.primaryContainer;
      case _SingleInsideDataDownloadState.success:
        return cs.tertiaryContainer;
      case _SingleInsideDataDownloadState.failure:
        return cs.errorContainer;
    }
  }

  Color _foreground(ColorScheme cs) {
    switch (_state) {
      case _SingleInsideDataDownloadState.idle:
        return cs.onSecondaryContainer;
      case _SingleInsideDataDownloadState.loading:
        return cs.onPrimaryContainer;
      case _SingleInsideDataDownloadState.success:
        return cs.onTertiaryContainer;
      case _SingleInsideDataDownloadState.failure:
        return cs.onErrorContainer;
    }
  }

  String get _title {
    switch (_state) {
      case _SingleInsideDataDownloadState.idle:
        return '다운로드 데이터 확인';
      case _SingleInsideDataDownloadState.loading:
        return 'SQLite Snapshot 확인 중';
      case _SingleInsideDataDownloadState.success:
        return '다운로드 데이터 확인 완료';
      case _SingleInsideDataDownloadState.failure:
        return '다시 확인';
    }
  }

  String get _subtitle {
    switch (_state) {
      case _SingleInsideDataDownloadState.idle:
        return '본사 내려받기 SQLite Snapshot만 사용';
      case _SingleInsideDataDownloadState.loading:
        return '현재 지역의 저장된 연결 정보를 확인합니다';
      case _SingleInsideDataDownloadState.success:
        return 'Firebase · SharedPreferences 접근 없음';
      case _SingleInsideDataDownloadState.failure:
        return '본사 내려받기 후 다시 확인할 수 있습니다';
    }
  }

  Widget _leadingIcon({
    required Color foreground,
    required bool reduceMotion,
  }) {
    if (_state == _SingleInsideDataDownloadState.loading && !reduceMotion) {
      return SizedBox(
        key: const ValueKey<String>('loading'),
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2.2,
          color: foreground,
        ),
      );
    }

    final icon = switch (_state) {
      _SingleInsideDataDownloadState.idle => Icons.cloud_download_rounded,
      _SingleInsideDataDownloadState.loading => Icons.sync_rounded,
      _SingleInsideDataDownloadState.success => Icons.cloud_done_rounded,
      _SingleInsideDataDownloadState.failure => Icons.refresh_rounded,
    };

    return Icon(
      icon,
      key: ValueKey<_SingleInsideDataDownloadState>(_state),
      size: 22,
      color: foreground,
    );
  }

  Future<void> _showLayoutDeveloperStatus() async {
    final media = MediaQuery.maybeOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    _SingleInsideLayoutDiagnostics.log(
      'status_dialog state=${_state.name} viewport=${media?.size.width.toStringAsFixed(1)}x${media?.size.height.toStringAsFixed(1)} textScale=${textScale.toStringAsFixed(2)} minHeight=64.0',
    );
    await _SingleInsideLayoutDiagnostics.showStatus(
      context,
      description:
          'Single 지사 다운로드 Dock의 반응형 높이, TextScaler, 현재 상태 debugPrint 코드를 복사할 수 있습니다.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final motion =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 200);
    final background = _background(cs);
    final foreground = _foreground(cs);
    final media = MediaQuery.maybeOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final layoutSignature =
        'state=${_state.name} viewport=${media?.size.width.toStringAsFixed(1)}x${media?.size.height.toStringAsFixed(1)} textScale=${textScale.toStringAsFixed(2)} minHeight=64.0 paddingY=8.0';
    if (_lastLayoutSignature != layoutSignature) {
      _lastLayoutSignature = layoutSignature;
      _SingleInsideLayoutDiagnostics.log(layoutSignature);
    }

    final dock = SafeArea(
      top: false,
      left: false,
      right: false,
      bottom: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: AnimatedSize(
          duration: motion,
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: AnimatedContainer(
            duration: motion,
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minHeight: 64),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: foreground.withOpacity(0.14),
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: _busy ? null : _download,
                onLongPress: _showLayoutDeveloperStatus,
                borderRadius: BorderRadius.circular(22),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: motion,
                        curve: Curves.easeOutCubic,
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: foreground.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        alignment: Alignment.center,
                        child: AnimatedSwitcher(
                          duration: motion,
                          switchInCurve: Curves.linear,
                          switchOutCurve: Curves.linear,
                          transitionBuilder: (child, animation) {
                            final fadeAnimation = CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                              reverseCurve: Curves.easeInCubic,
                            );
                            final scaleAnimation = Tween<double>(
                              begin: 0.86,
                              end: 1,
                            ).animate(
                              CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutBack,
                                reverseCurve: Curves.easeInCubic,
                              ),
                            );
                            return FadeTransition(
                              opacity: fadeAnimation,
                              child: ScaleTransition(
                                scale: scaleAnimation,
                                child: child,
                              ),
                            );
                          },
                          child: _leadingIcon(
                            foreground: foreground,
                            reduceMotion: reduceMotion,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: motion,
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0, 0.08),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: CommonAdaptiveTwoLineContent(
                            key: ValueKey<_SingleInsideDataDownloadState>(
                              _state,
                            ),
                            gap: 2,
                            title: Text(
                              _title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: foreground,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              _subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: foreground.withOpacity(0.78),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedRotation(
                        turns: _state == _SingleInsideDataDownloadState.failure
                            ? -0.08
                            : 0,
                        duration: motion,
                        curve: Curves.easeOutCubic,
                        child: Icon(
                          _state == _SingleInsideDataDownloadState.success
                              ? Icons.check_rounded
                              : Icons.chevron_right_rounded,
                          color: foreground.withOpacity(_busy ? 0.45 : 0.82),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (reduceMotion) {
      return Semantics(
        button: true,
        enabled: !_busy,
        label: '다운로드 데이터 확인',
        child: dock,
      );
    }

    return Semantics(
      button: true,
      enabled: !_busy,
      label: '다운로드 데이터 확인',
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        child: dock,
        builder: (context, value, child) {
          return Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, 8 * (1 - value)),
              child: child,
            ),
          );
        },
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
