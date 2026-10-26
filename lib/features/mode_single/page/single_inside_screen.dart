import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/command/presentation/terminal_launcher_button.dart';
import '../../../app/init/app_exit_service.dart';
import '../../../app/init/db_connection_status_section.dart';
import '../../../app/init/logout_helper.dart';
import '../../../app/init/work_status_notification.dart';
import '../../../app/models/capability.dart';
import '../../../app/theme/theme_settings_dialog.dart';
import '../../../design_system/common_ui/common_ui_components.dart';
import '../../../design_system/common_ui/common_ui_side_dock.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../../shared/area_remote_settings/application/local_area_capability_refresh.dart';
import '../../../shared/secondary/application/secondary_info.dart';
import '../../../shared/secondary/application/secondary_state.dart';
import '../../../shared/document/work_start_report/dashboard_start_report_form_page.dart';
import '../../../shared/document/user_statement/user_statement_form_page.dart';
import '../../../shared/document/backup/backup_form_page.dart';
import '../../../shared/secondary/side_docks/secondary_side_dock.dart';
import '../../account/applications/user_state.dart';
import '../../community/page/faq_side_dock.dart';
import '../../dev/application/area_state.dart';
import '../../headquarter/application/headquarter_support_actions.dart';
import '../../selector/dialogs/update_dialog.dart';
import '../../attendance/application/common_attendance_service.dart';
import '../../dev/debug/debug_api_logger.dart';
import '../application/single_inside_diagnostics.dart';
import '../application/single_operational_data_sync_workflow.dart';
import '../controllers/single_inside_controller.dart';
import 'sheets/report/widgets/single_inside_end_report_form_page.dart';
import '../application/single_attendance_submission_summary_service.dart';
import 'side_docks/single_inside_attendance_submit_side_dock.dart';
import 'side_docks/single_inside_parking_side_dock.dart';
import 'side_docks/single_inside_side_dock.dart';
import 'side_docks/single_inside_work_rules_side_dock.dart';
import 'side_docks/single_inside_work_schedule_side_dock.dart';
import 'side_docks/single_inside_work_manual_side_dock.dart';
import 'widgets/single_inside_punch_recorder_content_surface.dart';
import 'widgets/single_inside_spatial_dot_map.dart';

enum SingleInsideMode {
  leader,
  fieldUser,
}

enum SingleInsideContentDockContent {
  workSchedule,
  parkingArea,
  workRules,
  workManual,
  workStartReport,
  workEndReport,
  statementForm,
  leaveApplication,
  faq,
  commuteSubmit,
  restTimeSubmit,
}

const String _tSingle = 'Single';
const String _tSingleInside = 'Single/inside';
const String _tPrefs = 'prefs';
const String _tUi = 'ui';

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
}) {
  if (_contrastRatio(preferred, background) >= 3.0) return preferred;
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
  });

  final String assetPath;
  final double height;
  final Color? preferredColor;
  final Color? fallbackColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bg = theme.scaffoldBackgroundColor;
    final preferred = preferredColor ?? cs.primary;
    final fallback = fallbackColor ?? cs.onSurface;
    final tint = _resolveLogoTint(
      background: bg,
      preferred: preferred,
      fallback: fallback,
    );

    return Image.asset(
      assetPath,
      fit: BoxFit.contain,
      height: height,
      color: tint,
      colorBlendMode: BlendMode.srcIn,
      filterQuality: FilterQuality.high,
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

class _SingleInsideScreenState extends State<SingleInsideScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final SingleInsideController controller = SingleInsideController();
  final SingleInsideSpatialDotMapController _parkingSpatialController =
      SingleInsideSpatialDotMapController();
  late final AnimationController _contentDockController;
  late final Animation<double> _contentDockProgress;
  String _lastModeSignature = '';
  String _lastUserSignature = '';
  int _scheduleRevision = 0;
  int _spatialRefreshRevision = 0;
  int _ruleRefreshRevision = 0;
  int _hotKeyRefreshRevision = 0;
  static const Duration _contentDockSwitchDuration = Duration(milliseconds: 230);

  bool _dashboardActionRunning = false;
  final Set<SingleInsideContentDockContent> _mountedContentDocks =
      <SingleInsideContentDockContent>{};
  bool _contentDockCloseEnabled = true;
  bool _parkingDetailOpen = false;
  double _lastRailWidth = 56;
  double _lastWorkspaceWidth = 0;
  double _lastContentDockWidth = 0;
  String _lastDashboardLayoutSignature = '';
  SingleInsideContentDockContent? _contentDockContent;
  bool _notificationRevealPending = false;
  bool _notificationRevealFrameScheduled = false;
  String? _pendingNotificationTapId;
  String _lastConsumedNotificationTapId = '-';
  DateTime? _notificationVisibleFrameAt;
  int _notificationTapConsumeCount = 0;
  int _lastHandledNotificationTapRevision = 0;
  int _notificationRevealCount = 0;
  String _lastNotificationTapSource = '-';
  String _lastNotificationTapEvent = '-';
  DateTime? _lastNotificationTapAt;
  DateTime? _lastNotificationRevealAt;
  bool _pendingNotificationDeveloperStatus = false;
  bool _initialWorkspaceRevealCompleted = false;

  bool get _contentDockOpen => _contentDockContent != null;

  @override
  void initState() {
    super.initState();
    _contentDockController = AnimationController(
      vsync: this,
      duration: CommonUiMotion.layout,
      reverseDuration: CommonUiMotion.overlay,
    );
    _contentDockProgress = CurvedAnimation(
      parent: _contentDockController,
      curve: CommonUiMotion.enter,
      reverseCurve: CommonUiMotion.exit,
    );
    WidgetsBinding.instance.addObserver(this);
    final initialTapRevision =
        WorkStatusNotificationController.notificationTapRevision.value;
    final initialPendingTap =
        WorkStatusNotificationController.pendingNotificationTap;
    if (initialPendingTap != null &&
        initialPendingTap.source == 'notification_body') {
      _lastHandledNotificationTapRevision =
          initialTapRevision > 0 ? initialTapRevision - 1 : 0;
      _pendingNotificationTapId = initialPendingTap.id;
      _lastNotificationTapSource = initialPendingTap.source;
      _lastNotificationTapEvent = initialPendingTap.event;
      _lastNotificationTapAt = initialPendingTap.tappedAt;
    } else {
      _lastHandledNotificationTapRevision = initialTapRevision;
    }
    WorkStatusNotificationController.notificationTapRevision.addListener(
      _handleNotificationTapRevision,
    );
    SingleInsideDiagnostics.log(
      'screen',
      'init notificationTapRevision=$initialTapRevision pendingTapId=${initialPendingTap?.id ?? '-'} workspace=punchRecorder contentDock=${_contentDockContent?.name ?? 'closed'} notificationRevealPending=$_notificationRevealPending',
    );
    controller.initialize(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_restorePendingNotificationTapAfterMount());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final userState = context.read<UserState>();
      await userState.ensureTodayClockInStatus();
      if (!mounted) return;
      SingleInsideDiagnostics.log(
        'attendance',
        'clock_state isWorking=${userState.isWorking} hasClockInToday=${userState.hasClockInToday}',
      );
      if (userState.isWorking && !userState.hasClockInToday) {
        await _resetStaleWorkingState();
      }
    });
  }

  @override
  void dispose() {
    WorkStatusNotificationController.notificationTapRevision.removeListener(
      _handleNotificationTapRevision,
    );
    WidgetsBinding.instance.removeObserver(this);
    _contentDockController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    setState(() => _hotKeyRefreshRevision++);
    SingleInsideDiagnostics.log(
      'hotkey',
      'refresh_requested source=app_resumed revision=$_hotKeyRefreshRevision',
    );
    if (_notificationRevealPending) {
      _scheduleNotificationRevealAfterVisibleFrame(source: 'app_resumed');
      return;
    }
  }

  Future<void> _restorePendingNotificationTapAfterMount() async {
    await WorkStatusNotificationController.restorePendingNotificationTap(
      source: 'single_screen_mount',
    );
    if (!mounted) return;
    _handleNotificationTapRevision();
    if (_notificationRevealPending) {
      _scheduleNotificationRevealAfterVisibleFrame(
        source: 'single_screen_mount',
      );
    }
  }

  void _handleNotificationTapRevision() {
    if (!mounted) return;
    final revision =
        WorkStatusNotificationController.notificationTapRevision.value;
    final pendingTap = WorkStatusNotificationController.pendingNotificationTap;
    if (revision <= _lastHandledNotificationTapRevision) return;
    _lastHandledNotificationTapRevision = revision;
    if (pendingTap == null) {
      SingleInsideDiagnostics.log(
        'workspace',
        'notification_tap_revision_without_pending revision=$revision active=punchRecorder',
      );
      return;
    }
    _lastNotificationTapSource = pendingTap.source;
    _lastNotificationTapEvent = pendingTap.event;
    _lastNotificationTapAt = pendingTap.tappedAt;
    if (pendingTap.source != 'notification_body') {
      SingleInsideDiagnostics.log(
        'workspace',
        'notification_tap_ignored tapId=${pendingTap.id} source=${pendingTap.source} event=${pendingTap.event} revision=$revision active=punchRecorder',
      );
      return;
    }
    if (_notificationRevealPending &&
        _pendingNotificationTapId == pendingTap.id) {
      SingleInsideDiagnostics.log(
        'workspace',
        'notification_tap_duplicate_ignored tapId=${pendingTap.id} revision=$revision active=punchRecorder',
      );
      return;
    }
    _revealPunchRecorderFromNotification(
      revision: revision,
      tap: pendingTap,
    );
  }

  void _revealPunchRecorderFromNotification({
    required int revision,
    required WorkStatusNotificationTap tap,
  }) {
    if (!mounted) return;
    final now = DateTime.now();
    setState(() {
      _notificationRevealPending = true;
      _pendingNotificationTapId = tap.id;
      _notificationVisibleFrameAt = null;
      _notificationRevealCount++;
      _lastNotificationRevealAt = now;
      _pendingNotificationDeveloperStatus = true;
    });
    SingleInsideDiagnostics.log(
      'workspace',
      'notification_punch_reveal tapId=${tap.id} source=${tap.source} event=${tap.event} tapRevision=$revision home=punchRecorder tappedAt=${tap.tappedAt.toIso8601String()} revealAt=${now.toIso8601String()}',
    );
    if (_contentDockOpen || _contentDockController.value > 0) {
      unawaited(
        _setContentDock(
          null,
          source: 'notification_punch_reveal',
        ),
      );
    }
    _scheduleNotificationRevealAfterVisibleFrame(source: 'notification_tap');
  }

  void _scheduleNotificationRevealAfterVisibleFrame({required String source}) {
    if (!mounted || !_notificationRevealPending) return;
    if (_notificationRevealFrameScheduled) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != AppLifecycleState.resumed) {
      SingleInsideDiagnostics.log(
        'punch_content',
        'notification_reveal_deferred source=$source reason=lifecycle state=${lifecycle?.name ?? '-'} tapId=${_pendingNotificationTapId ?? '-'}',
      );
      return;
    }
    _notificationRevealFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notificationRevealFrameScheduled = false;
      if (!mounted ||
          !_notificationRevealPending ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      final now = DateTime.now();
      final tapId = _pendingNotificationTapId;
      final showDeveloperStatus = _pendingNotificationDeveloperStatus;
      setState(() {
        _notificationRevealPending = false;
        _notificationVisibleFrameAt = now;
        _pendingNotificationDeveloperStatus = false;
      });
      SingleInsideDiagnostics.log(
        'punch_content',
        'notification_reveal_committed source=$source tapId=${tapId ?? '-'} visibleFrameAt=${now.toIso8601String()} home=punchRecorder',
      );
      if (tapId != null && tapId.isNotEmpty) {
        unawaited(
          _consumePendingNotificationTap(
            tapId: tapId,
            source: 'notification_visible_frame',
          ),
        );
      }
      if (showDeveloperStatus) {
        unawaited(
          _showDeveloperStatus(
            title: 'Single 알림 복귀 상태',
            description: '알림 복귀 및 출퇴근 기록기 표시 상태',
          ),
        );
      }
    });
  }

  Future<void> _consumePendingNotificationTap({
    required String tapId,
    required String source,
  }) async {
    await WorkStatusNotificationController.consumePendingNotificationTap(
      tapId: tapId,
      source: source,
    );
    if (!mounted) return;
    setState(() {
      _pendingNotificationTapId = null;
      _lastConsumedNotificationTapId = tapId;
      _notificationTapConsumeCount++;
    });
    SingleInsideDiagnostics.log(
      'workspace',
      'notification_tap_consumed tapId=$tapId source=$source count=$_notificationTapConsumeCount',
    );
  }

  void _completeInitialWorkspaceReveal({required bool reduceMotion}) {
    if (_initialWorkspaceRevealCompleted || !mounted) return;
    setState(() => _initialWorkspaceRevealCompleted = true);
    SingleInsideDiagnostics.log(
      'screen',
      'initial_workspace_reveal_completed reduceMotion=$reduceMotion rulesAutoOpen=false contentDockDefault=closed',
    );
  }

  Future<void> _setContentDock(
    SingleInsideContentDockContent? next, {
    required String source,
    bool force = false,
  }) async {
    if (!mounted) return;
    final current = _contentDockContent;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    if (!force && !_contentDockCloseEnabled && next != current) {
      SingleInsideDiagnostics.log(
        'content_dock',
        'transition_blocked source=$source current=${current?.name ?? 'closed'} next=${next?.name ?? 'closed'} closeEnabled=$_contentDockCloseEnabled',
      );
      return;
    }

    if (next == null) {
      if (current == null && _contentDockController.value <= .001) {
        SingleInsideDiagnostics.log(
          'content_dock',
          'close_ignored source=$source progress=${_contentDockController.value.toStringAsFixed(3)}',
        );
        return;
      }
      if (_parkingSpatialController.detailOpen) {
        await _parkingSpatialController.closeDetail(
          source: '${source}_before_dock_close',
        );
        if (!mounted) return;
      }
      SingleInsideDiagnostics.log(
        'content_dock',
        'animation_started action=close content=${current?.name ?? 'none'} source=$source reduceMotion=$reduceMotion closeEnabled=$_contentDockCloseEnabled railWidth=${_lastRailWidth.toStringAsFixed(1)} workspaceWidth=${_lastWorkspaceWidth.toStringAsFixed(1)} dockWidth=${_lastContentDockWidth.toStringAsFixed(1)} progress=${_contentDockController.value.toStringAsFixed(3)}',
      );
      if (reduceMotion) {
        _contentDockController.value = 0;
      } else {
        try {
          await _contentDockController.reverse().orCancel;
        } on TickerCanceled {
          return;
        }
      }
      if (!mounted) return;
      setState(() {
        _contentDockContent = null;
        _contentDockCloseEnabled = true;
        _hotKeyRefreshRevision++;
      });
      SingleInsideDiagnostics.log(
        'content_dock',
        'animation_completed action=close content=${current?.name ?? 'none'} source=$source progress=${_contentDockController.value.toStringAsFixed(3)} workspaceOffset=${(-_lastRailWidth * _contentDockController.value).toStringAsFixed(1)}',
      );
      return;
    }

    if (current == next && (_contentDockController.value - 1).abs() < .001) {
      SingleInsideDiagnostics.log(
        'content_dock',
        'open_ignored content=${next.name} source=$source progress=${_contentDockController.value.toStringAsFixed(3)}',
      );
      return;
    }

    if (current != null && current != next && _contentDockController.value > .001) {
      if (_parkingSpatialController.detailOpen) {
        await _parkingSpatialController.closeDetail(
          source: '${source}_before_content_switch',
        );
        if (!mounted) return;
      }
      setState(() {
        _contentDockContent = next;
        _mountedContentDocks.add(next);
        _contentDockCloseEnabled = true;
        _hotKeyRefreshRevision++;
      });
      SingleInsideDiagnostics.log(
        'content_dock',
        'content_switched from=${current.name} to=${next.name} source=$source motionMs=${reduceMotion ? 0 : _contentDockSwitchDuration.inMilliseconds} progress=${_contentDockController.value.toStringAsFixed(3)}',
      );
      return;
    }

    setState(() {
      _contentDockContent = next;
      _mountedContentDocks.add(next);
      _contentDockCloseEnabled = true;
    });
    SingleInsideDiagnostics.log(
      'content_dock',
      'animation_started action=open content=${next.name} source=$source reduceMotion=$reduceMotion railWidth=${_lastRailWidth.toStringAsFixed(1)} workspaceWidth=${_lastWorkspaceWidth.toStringAsFixed(1)} dockWidth=${_lastContentDockWidth.toStringAsFixed(1)} progress=${_contentDockController.value.toStringAsFixed(3)}',
    );
    if (reduceMotion) {
      _contentDockController.value = 1;
    } else {
      try {
        await _contentDockController.forward().orCancel;
      } on TickerCanceled {
        return;
      }
    }
    if (!mounted) return;
    SingleInsideDiagnostics.log(
      'content_dock',
      'animation_completed action=open content=${next.name} source=$source progress=${_contentDockController.value.toStringAsFixed(3)} workspaceOffset=${(-_lastRailWidth * _contentDockController.value).toStringAsFixed(1)}',
    );
  }

  void _setContentDockCloseEnabled(bool enabled, {required String source}) {
    if (!mounted || _contentDockCloseEnabled == enabled) return;
    setState(() => _contentDockCloseEnabled = enabled);
    SingleInsideDiagnostics.log(
      'content_dock',
      'close_enabled_changed enabled=$enabled source=$source content=${_contentDockContent?.name ?? 'closed'}',
    );
  }

  void _setContentDockCloseEnabledFor(
    SingleInsideContentDockContent content,
    bool enabled, {
    required String source,
  }) {
    if (_contentDockContent != content) {
      SingleInsideDiagnostics.log(
        'content_dock',
        'close_enabled_ignored enabled=$enabled source=$source owner=${content.name} active=${_contentDockContent?.name ?? 'closed'}',
      );
      return;
    }
    _setContentDockCloseEnabled(enabled, source: source);
  }

  void _handleParkingDetailStateChanged(bool open) {
    if (_parkingDetailOpen == open || !mounted) return;
    setState(() => _parkingDetailOpen = open);
    SingleInsideDiagnostics.log(
      'content_dock',
      'parking_detail_state open=$open content=${_contentDockContent?.name ?? 'closed'}',
    );
  }

  void _handleSystemBack() {
    if (_parkingSpatialController.detailOpen || _parkingDetailOpen) {
      unawaited(
        _parkingSpatialController.closeDetail(source: 'system_back'),
      );
      return;
    }
    if (_contentDockOpen || _contentDockController.value > .001) {
      if (!_contentDockCloseEnabled) {
        SingleInsideDiagnostics.log(
          'content_dock',
          'system_back_blocked content=${_contentDockContent?.name ?? 'closed'} closeEnabled=false',
        );
        return;
      }
      unawaited(
        _setContentDock(
          null,
          source: 'system_back',
        ),
      );
      return;
    }
    SingleInsideDiagnostics.log(
      'workspace',
      'system_back_at_home home=punchRecorder',
    );
  }

  Future<void> _resetStaleWorkingState() async {
    try {
      SingleInsideDiagnostics.log('attendance', 'stale_reset_start');
      await CommonAttendanceService.resetStaleWorkingState(
        context,
        source: 'single_inside_stale_guard',
        modeKey: 'single',
      );
      SingleInsideDiagnostics.log('attendance', 'stale_reset_complete');
    } catch (error, stackTrace) {
      SingleInsideDiagnostics.log(
        'attendance',
        'stale_reset_failure error=$error stack=$stackTrace',
      );
      await _logApiError(
        tag: 'SingleInsideScreen._resetStaleWorkingState',
        message: 'stale working state 리셋 실패',
        error: error,
        tags: const <String>[_tSingle, _tSingleInside, _tPrefs],
      );
    }
  }

  Future<void> _handleLogout(BuildContext context) async {
    try {
      SingleInsideDiagnostics.log('account', 'logout_start');
      await LogoutHelper.logoutAndGoToLogin(
        context,
        checkWorking: false,
        delay: const Duration(milliseconds: 500),
      );
    } catch (error, stackTrace) {
      SingleInsideDiagnostics.log(
        'account',
        'logout_failure error=$error stack=$stackTrace',
      );
      await _logApiError(
        tag: 'SingleInsideScreen._handleLogout',
        message: '로그아웃 처리 실패',
        error: error,
        tags: const <String>[_tSingle, _tSingleInside, _tUi],
      );
      rethrow;
    }
  }

  Future<void> _handleAppExit(BuildContext context) async {
    try {
      SingleInsideDiagnostics.log('system', 'app_exit_start');
      await AppExitService.exitApp(context);
    } catch (error, stackTrace) {
      SingleInsideDiagnostics.log(
        'system',
        'app_exit_failure error=$error stack=$stackTrace',
      );
      await _logApiError(
        tag: 'SingleInsideScreen._handleAppExit',
        message: '앱 종료 처리 실패',
        error: error,
        tags: const <String>[_tSingle, _tSingleInside, _tUi],
      );
      rethrow;
    }
  }

  Future<void> _showDeveloperStatus({
    String title = 'Single 상태',
    String description = 'Single UI 및 SQLite 공간 상태 로그',
  }) async {
    final media = MediaQuery.maybeOf(context);
    final userState = context.read<UserState>();
    final areaState = context.read<AreaState>();
    final secondaryState = context.read<SecondaryState>();
    final operationsVisible =
        secondaryState.hasPermission('single.operations.enter') &&
            secondaryState.canAccess(Section.user);
    SingleInsideDiagnostics.log(
      'status',
      'snapshot viewport=${media?.size.width.toStringAsFixed(1)}x${media?.size.height.toStringAsFixed(1)} permissionCount=${userState.permissionKeys.length} area=${userState.currentArea} division=${userState.division} areaStateCapabilities=${LocalAreaCapabilityRefresh.keys(areaState.capabilitiesOfCurrentArea)} locationAccess=${secondaryState.canAccess(Section.location)} locationAccessReason=${secondaryState.accessDebugReason(Section.location)} operationsVisible=$operationsVisible scheduleRevision=$_scheduleRevision spatialRevision=$_spatialRefreshRevision ruleRevision=$_ruleRefreshRevision hotKeyRevision=$_hotKeyRefreshRevision dashboardMode=compact_only railWidth=${_lastRailWidth.toStringAsFixed(1)} workspaceWidth=${_lastWorkspaceWidth.toStringAsFixed(1)} contentDockWidth=${_lastContentDockWidth.toStringAsFixed(1)} contentDock=${_contentDockContent?.name ?? 'closed'} contentDockProgress=${_contentDockController.value.toStringAsFixed(3)} contentDockCloseEnabled=$_contentDockCloseEnabled mountedContentDocks=${_mountedContentDocks.map((item) => item.name).join(',')} parkingDetailOpen=$_parkingDetailOpen parkingControllerDetailOpen=${_parkingSpatialController.detailOpen} dashboardActionRunning=$_dashboardActionRunning workspaceContent=punchRecorder punchContentPlacement=workspace_home workspaceBackPolicy=detail_then_content_dock_then_punch scheduleSaveMode=explicit notificationRevealPending=$_notificationRevealPending notificationRevealFrameScheduled=$_notificationRevealFrameScheduled pendingNotificationTapId=${_pendingNotificationTapId ?? '-'} lastConsumedNotificationTapId=$_lastConsumedNotificationTapId notificationVisibleFrameAt=${_notificationVisibleFrameAt?.toIso8601String() ?? '-'} notificationTapConsumeCount=$_notificationTapConsumeCount notificationTapRevision=${WorkStatusNotificationController.notificationTapRevision.value} workStatusLastNotificationTapId=${WorkStatusNotificationController.lastNotificationTapId} workStatusPendingNotificationTapId=${WorkStatusNotificationController.pendingNotificationTap?.id ?? '-'} workStatusPendingNotificationTapAt=${WorkStatusNotificationController.pendingNotificationTap?.tappedAt.toIso8601String() ?? '-'} lastHandledNotificationTapRevision=$_lastHandledNotificationTapRevision notificationRevealCount=$_notificationRevealCount lastNotificationTapSource=$_lastNotificationTapSource lastNotificationTapEvent=$_lastNotificationTapEvent lastNotificationTapAt=${_lastNotificationTapAt?.toIso8601String() ?? '-'} lastNotificationRevealAt=${_lastNotificationRevealAt?.toIso8601String() ?? '-'} pendingNotificationDeveloperStatus=$_pendingNotificationDeveloperStatus initialRevealCompleted=$_initialWorkspaceRevealCompleted rulesAutoOpen=false auxiliaryPresentation=embedded_content_side_dock',
    );
    await SingleInsideDiagnostics.showStatus(
      context,
      title: title,
      description: description,
    );
  }

  SingleInsideMode _resolveMode(UserState userState) {
    if (widget.mode != null) return widget.mode!;
    final canManage = userState.hasPermission('single.operations.enter');
    final mode = canManage
        ? SingleInsideMode.leader
        : SingleInsideMode.fieldUser;
    final signature = 'operationsAllowed=$canManage mode=${mode.name}';
    if (_lastModeSignature != signature) {
      _lastModeSignature = signature;
      SingleInsideDiagnostics.log('screen', 'mode_resolved $signature');
    }
    return mode;
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return AppBar(
      titleSpacing: NavigationToolbar.kMiddleSpacing,
      leadingWidth: 48,
      leading: const SizedBox.shrink(),
      title: const TerminalLauncherButton(source: 'single_branch'),
      centerTitle: true,
      backgroundColor: tokens.surface,
      foregroundColor: tokens.textPrimary,
      elevation: 0,
      surfaceTintColor: tokens.transparent,
      shadowColor: tokens.transparent,
      toolbarHeight: kToolbarHeight,
      shape: Border(bottom: BorderSide(color: tokens.borderSubtle)),
      flexibleSpace: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            IgnorePointer(
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12, top: 4),
                  child: Semantics(
                    label: 'Single',
                    child: ExcludeSemantics(
                      child: CommonAnimatedReveal(
                        offset: const Offset(-0.035, 0),
                        child: _BrandTintedLogo(
                          assetPath: 'assets/images/pelican_text.png',
                          height: 54,
                          preferredColor: tokens.accent,
                          fallbackColor: tokens.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            IgnorePointer(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(
                    right: 12,
                    top: 4,
                    bottom: 4,
                  ),
                  child: SizedBox(
                    height: kToolbarHeight - 8,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: 116,
                          maxHeight: kToolbarHeight - 8,
                        ),
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: DbConnectionStatusAppBarSection(
                            liveLabel: 'live DB',
                            storageLabel: '스토리지 DB',
                            spacing: 4,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  SingleInsideContentDockContent? _contentDockTargetForRequest(
    SingleInsideDockRequest request,
  ) {
    switch (request) {
      case SingleInsideDockRequest.workSchedule:
        return SingleInsideContentDockContent.workSchedule;
      case SingleInsideDockRequest.parkingArea:
        return SingleInsideContentDockContent.parkingArea;
      case SingleInsideDockRequest.workRules:
        return SingleInsideContentDockContent.workRules;
      case SingleInsideDockRequest.workManual:
        return SingleInsideContentDockContent.workManual;
      case SingleInsideDockRequest.workStartReport:
        return SingleInsideContentDockContent.workStartReport;
      case SingleInsideDockRequest.workEndReport:
        return SingleInsideContentDockContent.workEndReport;
      case SingleInsideDockRequest.statementForm:
        return SingleInsideContentDockContent.statementForm;
      case SingleInsideDockRequest.leaveApplication:
        return SingleInsideContentDockContent.leaveApplication;
      case SingleInsideDockRequest.faq:
        return SingleInsideContentDockContent.faq;
      case SingleInsideDockRequest.commuteSubmit:
        return SingleInsideContentDockContent.commuteSubmit;
      case SingleInsideDockRequest.restTimeSubmit:
        return SingleInsideContentDockContent.restTimeSubmit;
      case SingleInsideDockRequest.update:
      case SingleInsideDockRequest.terms:
      case SingleInsideDockRequest.privacy:
      case SingleInsideDockRequest.operations:
      case SingleInsideDockRequest.operationalSync:
      case SingleInsideDockRequest.theme:
      case SingleInsideDockRequest.logout:
      case SingleInsideDockRequest.exitApp:
        return null;
    }
  }

  SingleInsideDockRequest? get _selectedDockRequest {
    switch (_contentDockContent) {
      case SingleInsideContentDockContent.workSchedule:
        return SingleInsideDockRequest.workSchedule;
      case SingleInsideContentDockContent.parkingArea:
        return SingleInsideDockRequest.parkingArea;
      case SingleInsideContentDockContent.workRules:
        return SingleInsideDockRequest.workRules;
      case SingleInsideContentDockContent.workManual:
        return SingleInsideDockRequest.workManual;
      case SingleInsideContentDockContent.workStartReport:
        return SingleInsideDockRequest.workStartReport;
      case SingleInsideContentDockContent.workEndReport:
        return SingleInsideDockRequest.workEndReport;
      case SingleInsideContentDockContent.statementForm:
        return SingleInsideDockRequest.statementForm;
      case SingleInsideContentDockContent.leaveApplication:
        return SingleInsideDockRequest.leaveApplication;
      case SingleInsideContentDockContent.faq:
        return SingleInsideDockRequest.faq;
      case SingleInsideContentDockContent.commuteSubmit:
        return SingleInsideDockRequest.commuteSubmit;
      case SingleInsideContentDockContent.restTimeSubmit:
        return SingleInsideDockRequest.restTimeSubmit;
      case null:
        return null;
    }
  }

  Future<void> _dispatchDashboardRequest(
    SingleInsideDockRequest request,
    String source,
  ) async {
    if (_dashboardActionRunning || !mounted) return;
    setState(() => _dashboardActionRunning = true);
    try {
      await HapticFeedback.selectionClick();
      if (!mounted) return;
      final contentTarget = _contentDockTargetForRequest(request);
      SingleInsideDiagnostics.log(
        'dashboard',
        'action_selected request=${request.name} source=$source dashboardMode=compact_only railWidth=${_lastRailWidth.toStringAsFixed(1)} workspaceWidth=${_lastWorkspaceWidth.toStringAsFixed(1)} contentDockWidth=${_lastContentDockWidth.toStringAsFixed(1)} contentDock=${_contentDockContent?.name ?? 'closed'} contentDockProgress=${_contentDockController.value.toStringAsFixed(3)} contentDockCloseEnabled=$_contentDockCloseEnabled parkingDetailOpen=$_parkingDetailOpen workspaceContent=punchRecorder target=${contentTarget?.name ?? 'action'}',
      );
      if (contentTarget == null &&
          (_contentDockOpen || _contentDockController.value > .001)) {
        await _setContentDock(
          null,
          source: 'before_${request.name}',
        );
        if (!mounted || _contentDockOpen || _contentDockController.value > .001) {
          return;
        }
      }
      await _handleDockRequest(request, source: source);
    } finally {
      if (mounted) {
        setState(() => _dashboardActionRunning = false);
      }
    }
  }

  Future<void> _handleDockRequest(
    SingleInsideDockRequest request, {
    required String source,
  }) async {
    SingleInsideDiagnostics.log(
      'menu',
      'handle_request request=${request.name} source=$source',
    );
    final contentTarget = _contentDockTargetForRequest(request);
    if (contentTarget != null) {
      if (_contentDockContent == contentTarget &&
          _contentDockController.value > .001) {
        await _setContentDock(null, source: source);
        return;
      }
      await _setContentDock(contentTarget, source: source);
      return;
    }

    switch (request) {
      case SingleInsideDockRequest.update:
        SingleInsideDiagnostics.log(
          'support',
          'update_dialog_open source=$source',
        );
        await showUpdateDialog(
          context,
          source: 'single_mini_side_dock',
        );
        SingleInsideDiagnostics.log(
          'support',
          'update_dialog_closed source=$source',
        );
        break;
      case SingleInsideDockRequest.terms:
        final termsOpened =
            await HeadquarterSupportActions.openTermsOfService(context);
        SingleInsideDiagnostics.log(
          'support',
          'external_result id=terms opened=$termsOpened source=$source',
        );
        break;
      case SingleInsideDockRequest.privacy:
        final privacyOpened =
            await HeadquarterSupportActions.openPrivacyPolicy(context);
        SingleInsideDiagnostics.log(
          'support',
          'external_result id=privacy opened=$privacyOpened source=$source',
        );
        break;
      case SingleInsideDockRequest.operations:
        await _openOperations(context);
        break;
      case SingleInsideDockRequest.operationalSync:
        await _runSingleOperationalSync();
        break;
      case SingleInsideDockRequest.theme:
        SingleInsideDiagnostics.log(
          'theme',
          'settings_open source=$source',
        );
        await showCommonThemeSettingsDialog(
          context: context,
          source: 'single_mini_side_dock',
        );
        SingleInsideDiagnostics.log(
          'theme',
          'settings_closed source=$source',
        );
        break;
      case SingleInsideDockRequest.logout:
        await _handleLogout(context);
        break;
      case SingleInsideDockRequest.exitApp:
        await _handleAppExit(context);
        break;
      case SingleInsideDockRequest.workSchedule:
      case SingleInsideDockRequest.parkingArea:
      case SingleInsideDockRequest.workRules:
      case SingleInsideDockRequest.workManual:
      case SingleInsideDockRequest.workStartReport:
      case SingleInsideDockRequest.workEndReport:
      case SingleInsideDockRequest.statementForm:
      case SingleInsideDockRequest.leaveApplication:
      case SingleInsideDockRequest.faq:
      case SingleInsideDockRequest.commuteSubmit:
      case SingleInsideDockRequest.restTimeSubmit:
        break;
    }
  }

  Future<void> _openOperations(BuildContext context) async {
    final userState = context.read<UserState>();
    final state = context.read<SecondaryState>();
    final roleAllowed = state.hasPermission('single.operations.enter');
    final sectionAllowed = state.canAccess(Section.user);
    final allowed = roleAllowed && sectionAllowed;
    SingleInsideDiagnostics.log(
      'work',
      'open target=user_management allowed=$allowed permissionCount=${userState.permissionKeys.length} roleAllowed=$roleAllowed sectionAllowed=$sectionAllowed reason=${state.accessDebugReason(Section.user)}',
    );
    if (!allowed) return;
    await showSecondarySideDock<void>(
      context: context,
      barrierLabel: '운영 관리',
      initialSection: Section.user,
    );
    SingleInsideDiagnostics.log('work', 'closed target=user_management');
  }

  Future<void> _runSingleOperationalSync() async {
    SingleInsideDiagnostics.log(
      'data',
      'operational_sync_start implementation=single_independent',
    );
    final result = await SingleOperationalDataSyncWorkflow.runCurrentArea(
      context: context,
      useCommonUi: true,
    );
    SingleInsideDiagnostics.log(
      'data',
      'operational_sync_result implementation=single_independent result=${result.name}',
    );
    if (result == SingleOperationalDataSyncResult.completed && mounted) {
      setState(() {
        _spatialRefreshRevision++;
        _ruleRefreshRevision++;
        _hotKeyRefreshRevision++;
      });
    }
  }

  void _handleScheduleChanged() {
    if (!mounted) return;
    setState(() => _scheduleRevision++);
    SingleInsideDiagnostics.log(
      'schedule',
      'changed revision=$_scheduleRevision',
    );
  }

  void _handleHotKeyDataChanged(String source) {
    if (!mounted) return;
    setState(() => _hotKeyRefreshRevision++);
    SingleInsideDiagnostics.log(
      'hotkey',
      'refresh_requested source=$source revision=$_hotKeyRefreshRevision',
    );
  }

  @override
  Widget build(BuildContext context) {
    return CommonUiScope(
      child: Builder(
        builder: (context) {
          final tokens = CommonUiTheme.of(context);
          final reduceMotion =
              MediaQuery.maybeOf(context)?.disableAnimations ?? false;
          return PopScope(
            canPop: false,
            onPopInvoked: (didPop) {
              if (didPop) return;
              _handleSystemBack();
            },
            child: Scaffold(
              backgroundColor: tokens.canvas,
              appBar: _buildAppBar(context),
              body: Consumer3<UserState, SecondaryState, AreaState>(
                builder: (context, userState, secondaryState, areaState, _) {
                  final mode = _resolveMode(userState);
                  final session = userState.session;
                  if (session == null) {
                    return Center(
                      child: CircularProgressIndicator(color: tokens.accent),
                    );
                  }


                  final roleAllowed =
                      secondaryState.hasPermission('single.operations.enter');
                  final sectionAllowed =
                      secondaryState.canAccess(Section.user);
                  final showOperations = roleAllowed && sectionAllowed;
                  final areaStateDivision = areaState.currentDivision.trim();
                  final currentDivision = areaStateDivision.isNotEmpty
                      ? areaStateDivision
                      : userState.division.trim();
                  final areaStateArea = areaState.currentArea.trim();
                  final currentArea = areaStateArea.isNotEmpty
                      ? areaStateArea
                      : userState.currentArea.trim();
                  final userSignature =
                      'userId=${session.id} userName=${session.displayName} area=$currentArea division=$currentDivision mode=${mode.name} permissionCount=${userState.permissionKeys.length} operationsVisible=$showOperations roleAllowed=$roleAllowed secondaryUserAccess=$sectionAllowed';
                  if (_lastUserSignature != userSignature) {
                    _lastUserSignature = userSignature;
                    SingleInsideDiagnostics.log('screen', userSignature);
                  }

                  final content = LayoutBuilder(
                    builder: (context, constraints) {
                      final bodyWidth = constraints.maxWidth;
                      final bodyHeight = constraints.maxHeight;
                      final railWidth = bodyHeight < 600
                          ? 48.0
                          : bodyHeight < 720
                              ? 52.0
                              : 56.0;
                      final workspaceWidth = bodyWidth - railWidth;
                      final contentDockWidth = workspaceWidth <= 360
                          ? workspaceWidth
                          : workspaceWidth < 560
                              ? workspaceWidth * .78
                              : (workspaceWidth * .44)
                                  .clamp(360.0, 420.0)
                                  .toDouble();
                      _lastRailWidth = railWidth;
                      _lastWorkspaceWidth = workspaceWidth;
                      _lastContentDockWidth = contentDockWidth;
                      final dashboardLayoutSignature =
                          '${bodyWidth.toStringAsFixed(1)}|${bodyHeight.toStringAsFixed(1)}|${railWidth.toStringAsFixed(1)}|${workspaceWidth.toStringAsFixed(1)}|${contentDockWidth.toStringAsFixed(1)}|compact_only';
                      if (_lastDashboardLayoutSignature !=
                          dashboardLayoutSignature) {
                        _lastDashboardLayoutSignature =
                            dashboardLayoutSignature;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted ||
                              _lastDashboardLayoutSignature !=
                                  dashboardLayoutSignature) {
                            return;
                          }
                          SingleInsideDiagnostics.log(
                            'dashboard',
                            'layout mode=compact_only railWidth=${railWidth.toStringAsFixed(1)} workspaceWidth=${workspaceWidth.toStringAsFixed(1)} contentDockWidth=${contentDockWidth.toStringAsFixed(1)} bodyWidth=${bodyWidth.toStringAsFixed(1)} contentDockEmbedded=true contentDock=${_contentDockContent?.name ?? 'closed'} workspaceResize=false workspaceClip=true scrim=false rulesPlacement=content_side_dock parkingDetailPresentation=embedded',
                          );
                        });
                      }

                      final workspace = SingleInsidePunchRecorderContentSurface(
                        key: ValueKey<String>(
                          'single_punch_content_${session.id}_${currentArea}_$currentDivision',
                        ),
                        userId: session.id,
                        userName: session.displayName,
                        area: currentArea,
                        division: currentDivision,
                        scheduleRevision: _scheduleRevision,
                        hotKeyRefreshRevision: _hotKeyRefreshRevision,
                        allowReports: mode == SingleInsideMode.leader,
                        onHotKeyRequest: _dispatchDashboardRequest,
                        onDeveloperStatus: () => _showDeveloperStatus(),
                      );

                      bool dockMounted(SingleInsideContentDockContent content) =>
                          _mountedContentDocks.contains(content);

                      void closeDock(String source) {
                        unawaited(_setContentDock(null, source: source));
                      }

                      final workScheduleDock =
                          dockMounted(SingleInsideContentDockContent.workSchedule)
                              ? SingleInsideWorkScheduleSideDock(
                                  key: ValueKey<String>(
                                    'single_work_schedule_dock_${session.id}_$currentArea',
                                  ),
                                  area: currentArea,
                                  scheduleRevision: _scheduleRevision,
                                  onChanged: _handleScheduleChanged,
                                  onClose: () => closeDock(
                                    'work_schedule_dock_close_button',
                                  ),
                                  onDeveloperStatus: () => _showDeveloperStatus(
                                    title: 'Single 근무 일정 상태',
                                    description: '근무 일정 Side Dock 및 저장 상태 로그',
                                  ),
                                  closeEnabled: _contentDockCloseEnabled,
                                  onCloseEnabledChanged: (enabled) =>
                                      _setContentDockCloseEnabledFor(
                                    SingleInsideContentDockContent.workSchedule,
                                    enabled,
                                    source: 'work_schedule',
                                  ),
                                )
                              : const SizedBox.shrink();

                      final parkingDock =
                          dockMounted(SingleInsideContentDockContent.parkingArea)
                              ? SingleInsideParkingSideDock(
                                  key: ValueKey<String>(
                                    'single_parking_dock_${session.id}_$currentArea',
                                  ),
                                  area: currentArea,
                                  refreshRevision: _spatialRefreshRevision,
                                  controller: _parkingSpatialController,
                                  onDetailStateChanged:
                                      _handleParkingDetailStateChanged,
                                  onClose: () => closeDock(
                                    'parking_dock_close_button',
                                  ),
                                  onDeveloperStatus: () => _showDeveloperStatus(
                                    title: 'Single 주차 구역 상태',
                                    description:
                                        '주차 구역 Side Dock 및 공간 상태 로그',
                                  ),
                                )
                              : const SizedBox.shrink();

                      final workRulesDock =
                          dockMounted(SingleInsideContentDockContent.workRules)
                              ? SingleInsideWorkRulesSideDock(
                                  key: ValueKey<String>(
                                    'single_work_rules_dock_${session.id}_${currentArea}_$currentDivision',
                                  ),
                                  division: currentDivision,
                                  area: currentArea,
                                  capabilityEnabled: areaState
                                      .capabilitiesOfCurrentArea
                                      .contains(Capability.rule),
                                  refreshRevision: _ruleRefreshRevision,
                                  onClose: () => closeDock(
                                    'work_rules_dock_close_button',
                                  ),
                                  onDeveloperStatus: () => _showDeveloperStatus(
                                    title: 'Single 업무 규칙 상태',
                                    description:
                                        '업무 규칙 Side Dock 및 데이터 상태 로그',
                                  ),
                                )
                              : const SizedBox.shrink();

                      final workManualDock =
                          dockMounted(SingleInsideContentDockContent.workManual)
                              ? SingleInsideWorkManualSideDock(
                                  key: ValueKey<String>(
                                    'single_work_manual_dock_${session.id}_${currentArea}_$currentDivision',
                                  ),
                                  division: currentDivision,
                                  area: currentArea,
                                  capabilityEnabled: areaState
                                      .capabilitiesOfCurrentArea
                                      .contains(Capability.rule),
                                  refreshRevision: _ruleRefreshRevision,
                                  onClose: () => closeDock(
                                    'work_manual_dock_close_button',
                                  ),
                                  onDeveloperStatus: () => _showDeveloperStatus(
                                    title: 'Single 업무 메뉴얼 상태',
                                    description:
                                        '업무 메뉴얼 Side Dock 및 데이터 상태 로그',
                                  ),
                                )
                              : const SizedBox.shrink();

                      final workStartReportDock = dockMounted(
                        SingleInsideContentDockContent.workStartReport,
                      )
                          ? DashboardStartReportSideDock(
                              key: ValueKey<String>(
                                'single_start_report_dock_${session.id}_$currentArea',
                              ),
                              onClose: () => closeDock(
                                'work_start_report_close_button',
                              ),
                              onCloseEnabledChanged: (enabled) =>
                                  _setContentDockCloseEnabledFor(
                                SingleInsideContentDockContent.workStartReport,
                                enabled,
                                source: 'work_start_report',
                              ),
                            )
                          : const SizedBox.shrink();

                      final workEndReportDock = dockMounted(
                        SingleInsideContentDockContent.workEndReport,
                      )
                          ? SingleInsideEndReportSideDock(
                              key: ValueKey<String>(
                                'single_end_report_dock_${session.id}_$currentArea',
                              ),
                              onClose: () => closeDock(
                                'work_end_report_close_button',
                              ),
                              onCloseEnabledChanged: (enabled) =>
                                  _setContentDockCloseEnabledFor(
                                SingleInsideContentDockContent.workEndReport,
                                enabled,
                                source: 'work_end_report',
                              ),
                            )
                          : const SizedBox.shrink();

                      final statementDock = dockMounted(
                        SingleInsideContentDockContent.statementForm,
                      )
                          ? UserStatementSideDock(
                              key: ValueKey<String>(
                                'single_statement_dock_${session.id}_$currentArea',
                              ),
                              onClose: () => closeDock(
                                'statement_form_close_button',
                              ),
                              onCloseEnabledChanged: (enabled) =>
                                  _setContentDockCloseEnabledFor(
                                SingleInsideContentDockContent.statementForm,
                                enabled,
                                source: 'statement_form',
                              ),
                            )
                          : const SizedBox.shrink();

                      final leaveApplicationDock = dockMounted(
                        SingleInsideContentDockContent.leaveApplication,
                      )
                          ? BackupApplicationSideDock(
                              key: ValueKey<String>(
                                'single_leave_application_dock_${session.id}_$currentArea',
                              ),
                              onClose: () => closeDock(
                                'leave_application_close_button',
                              ),
                              onCloseEnabledChanged: (enabled) =>
                                  _setContentDockCloseEnabledFor(
                                SingleInsideContentDockContent.leaveApplication,
                                enabled,
                                source: 'leave_application',
                              ),
                            )
                          : const SizedBox.shrink();

                      final faqDock =
                          dockMounted(SingleInsideContentDockContent.faq)
                              ? FaqSideDockContent(
                                  key: const ValueKey<String>(
                                    'single_faq_content_dock',
                                  ),
                                  side: CommonSideDockSide.right,
                                  source: 'single_embedded_content_dock',
                                  onClose: () => closeDock(
                                    'faq_close_button',
                                  ),
                                )
                              : const SizedBox.shrink();

                      final commuteSubmitDock = dockMounted(
                        SingleInsideContentDockContent.commuteSubmit,
                      )
                          ? SingleInsideAttendanceSubmitSideDock(
                              key: ValueKey<String>(
                                'single_commute_submit_dock_${session.id}_$currentArea',
                              ),
                              kind: SingleAttendanceSubmissionKind.commute,
                              area: currentArea,
                              refreshRevision: _hotKeyRefreshRevision,
                              onClose: () => closeDock(
                                'commute_submit_close_button',
                              ),
                              onCloseEnabledChanged: (enabled) =>
                                  _setContentDockCloseEnabledFor(
                                SingleInsideContentDockContent.commuteSubmit,
                                enabled,
                                source: 'commute_submit',
                              ),
                              onSubmitted: () => _handleHotKeyDataChanged(
                                'commute_submit_complete',
                              ),
                              onDeveloperStatus: () => _showDeveloperStatus(
                                title: 'Single 출퇴근 제출 상태',
                                description: '출퇴근 제출 Side Dock 및 로컬 기록 상태 로그',
                              ),
                            )
                          : const SizedBox.shrink();

                      final restTimeSubmitDock = dockMounted(
                        SingleInsideContentDockContent.restTimeSubmit,
                      )
                          ? SingleInsideAttendanceSubmitSideDock(
                              key: ValueKey<String>(
                                'single_rest_submit_dock_${session.id}_$currentArea',
                              ),
                              kind: SingleAttendanceSubmissionKind.restTime,
                              area: currentArea,
                              refreshRevision: _hotKeyRefreshRevision,
                              onClose: () => closeDock(
                                'rest_submit_close_button',
                              ),
                              onCloseEnabledChanged: (enabled) =>
                                  _setContentDockCloseEnabledFor(
                                SingleInsideContentDockContent.restTimeSubmit,
                                enabled,
                                source: 'rest_submit',
                              ),
                              onSubmitted: () => _handleHotKeyDataChanged(
                                'rest_submit_complete',
                              ),
                              onDeveloperStatus: () => _showDeveloperStatus(
                                title: 'Single 휴게 제출 상태',
                                description: '휴게 제출 Side Dock 및 로컬 기록 상태 로그',
                              ),
                            )
                          : const SizedBox.shrink();

                      final contentDock = DecoratedBox(
                        decoration: BoxDecoration(
                          color: tokens.surface.withOpacity(
                            tokens.isDark ? .94 : .97,
                          ),
                          border: Border(
                            left: BorderSide(color: tokens.borderSubtle),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: tokens.shadow.withOpacity(.14),
                              blurRadius: 22,
                              offset: const Offset(-8, 0),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: _SingleInsideContentDockSwitcher(
                            active: _contentDockContent,
                            duration: reduceMotion
                                ? Duration.zero
                                : _contentDockSwitchDuration,
                            children: <SingleInsideContentDockContent, Widget>{
                              SingleInsideContentDockContent.workSchedule:
                                  workScheduleDock,
                              SingleInsideContentDockContent.parkingArea:
                                  parkingDock,
                              SingleInsideContentDockContent.workRules:
                                  workRulesDock,
                              SingleInsideContentDockContent.workManual:
                                  workManualDock,
                              SingleInsideContentDockContent.workStartReport:
                                  workStartReportDock,
                              SingleInsideContentDockContent.workEndReport:
                                  workEndReportDock,
                              SingleInsideContentDockContent.statementForm:
                                  statementDock,
                              SingleInsideContentDockContent.leaveApplication:
                                  leaveApplicationDock,
                              SingleInsideContentDockContent.faq: faqDock,
                              SingleInsideContentDockContent.commuteSubmit:
                                  commuteSubmitDock,
                              SingleInsideContentDockContent.restTimeSubmit:
                                  restTimeSubmitDock,
                            },
                          ),
                        ),
                      );

                      final dashboard = SafeArea(
                        top: false,
                        left: false,
                        child: SingleInsideDashboardRail(
                          width: railWidth,
                          showReport: mode == SingleInsideMode.leader,
                          showOperations: showOperations,
                          enabled: !_dashboardActionRunning &&
                              _contentDockCloseEnabled,
                          onDeveloperStatus: () => _showDeveloperStatus(),
                          onRequest: _dispatchDashboardRequest,
                          selectedRequest: _selectedDockRequest,
                        ),
                      );

                      return ClipRect(
                        child: AnimatedBuilder(
                          animation: _contentDockProgress,
                          builder: (context, _) {
                            final progress = _contentDockProgress.value
                                .clamp(0.0, 1.0)
                                .toDouble();
                            final workspaceBlocked = progress > .001;
                            final contentDockInteractive = _contentDockOpen &&
                                !_contentDockController.isAnimating &&
                                progress >= .999;
                            return Stack(
                              clipBehavior: Clip.hardEdge,
                              children: [
                                Positioned(
                                  left: 0,
                                  top: 0,
                                  bottom: 0,
                                  width: workspaceWidth,
                                  child: Transform.translate(
                                    offset: Offset(-railWidth * progress, 0),
                                    child: ExcludeSemantics(
                                      excluding: workspaceBlocked,
                                      child: IgnorePointer(
                                        ignoring: workspaceBlocked,
                                        child: workspace,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: railWidth,
                                  top: 0,
                                  bottom: 0,
                                  width: contentDockWidth,
                                  child: Transform.translate(
                                    offset: Offset(
                                      contentDockWidth * (1 - progress),
                                      0,
                                    ),
                                    child: ExcludeSemantics(
                                      excluding: progress <= .001,
                                      child: IgnorePointer(
                                        ignoring: !contentDockInteractive,
                                        child: TickerMode(
                                          enabled: progress > .001,
                                          child: contentDock,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  bottom: 0,
                                  width: railWidth,
                                  child: dashboard,
                                ),
                              ],
                            );
                          },
                        ),
                      );
                    },
                  );

                  if (reduceMotion) {
                    if (!_initialWorkspaceRevealCompleted) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        _completeInitialWorkspaceReveal(reduceMotion: true);
                      });
                    }
                    return content;
                  }
                  return TweenAnimationBuilder<double>(
                    key: ValueKey<String>(
                      'single_workspace_${session.id}_$currentArea',
                    ),
                    tween: Tween<double>(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    onEnd: () =>
                        _completeInitialWorkspaceReveal(reduceMotion: false),
                    child: content,
                    builder: (context, value, child) {
                      return Opacity(
                        opacity: value,
                        child: Transform.translate(
                          offset: Offset(0, 10 * (1 - value)),
                          child: child,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SingleInsideContentDockSwitcher extends StatelessWidget {
  const _SingleInsideContentDockSwitcher({
    required this.active,
    required this.duration,
    required this.children,
  });

  final SingleInsideContentDockContent? active;
  final Duration duration;
  final Map<SingleInsideContentDockContent, Widget> children;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final entry in children.entries)
          _SingleInsideContentDockLayer(
            active: active == entry.key,
            duration: duration,
            child: entry.value,
          ),
      ],
    );
  }
}

class _SingleInsideContentDockLayer extends StatelessWidget {
  const _SingleInsideContentDockLayer({
    required this.active,
    required this.duration,
    required this.child,
  });

  final bool active;
  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      excluding: !active,
      child: IgnorePointer(
        ignoring: !active,
        child: AnimatedOpacity(
          opacity: active ? 1 : 0,
          duration: duration,
          curve: Curves.easeOutCubic,
          child: AnimatedSlide(
            offset: active ? Offset.zero : const Offset(.035, 0),
            duration: duration,
            curve: Curves.easeOutCubic,
            child: AnimatedScale(
              scale: active ? 1 : .992,
              duration: duration,
              curve: Curves.easeOutCubic,
              child: TickerMode(
                enabled: active,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
