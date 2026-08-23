import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/di/routes.dart';
import '../../../../app/init/app_exit_service.dart';
import '../../../../app/init/app_navigator.dart';
import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../app/utils/ops_delayed_refresh_gate.dart';
import '../../../../app/utils/snackbar_helper.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../account/applications/user_state.dart';
import '../../application/area/area_master_cache.dart';
import '../../page/sheets/head_memo.dart';
import '../../../selector/application/dev_auth.dart';
import '../../widgets/hr/attendance_calendar.dart' as hr_att;
import '../../widgets/hr/break_calendar.dart' as hr_break;
import '../../widgets/mgmt/field.dart' as mgmt;
import '../../widgets/mgmt/statistics.dart' as mgmt_stats;

class HeadHubActions {
  HeadHubActions._();

  static GlobalKey<NavigatorState> get navigatorKey => AppNavigator.key;

  static final enabled = ValueNotifier<bool>(false);

  static const _kEnabledKey = 'head_hub_actions_enabled_v1';
  static const _kBubbleXKey = 'head_hub_actions_bubble_x_v1';
  static const contactFormUrl = 'https://forms.gle/hDTkX1p6U9jMMuySA';
  static const termsOfServiceUrl =
      'https://sites.google.com/view/parkinworkin3/%ED%99%88';
  static const privacyPolicyUrl =
      'https://sites.google.com/view/parkinworkin4/%ED%99%88';
  static const _kBubbleYKey = 'head_hub_actions_bubble_y_v1';
  static const _kGameEnabledKey = 'game_quick_actions_enabled_v1';
  static const _kGameBubbleXKey = 'game_quick_actions_bubble_x_v1';
  static const _kGameBubbleYKey = 'game_quick_actions_bubble_y_v1';

  static SharedPreferences? _prefs;
  static OverlayEntry? _entry;
  static bool _initialized = false;

  static bool _closing = false;
  static bool _opening = false;

  static Future<void>? _activeSheet;

  static BuildContext? _bestContext() {
    final state = navigatorKey.currentState;
    final overlayCtx = state?.overlay?.context;
    return overlayCtx ?? state?.context;
  }

  static Future<void> closeAnySheet() async {
    if (_closing) return;
    _closing = true;
    try {
      final ctx = _bestContext();
      if (ctx == null) return;

      final tracked = _activeSheet;
      if (tracked != null) {
        Navigator.of(ctx).maybePop();
        try {
          await tracked;
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 16));
        return;
      }

      final popped = await Navigator.of(ctx).maybePop();
      if (popped) {
        await Future<void>.delayed(const Duration(milliseconds: 220));
      }
    } finally {
      _closing = false;
    }
  }

  static Future<T?> openSheetExclusively<T>(
    Future<T?> Function(BuildContext ctx) openFn, {
    BuildContext? context,
  }) async {
    if (_opening) return null;
    _opening = true;
    try {
      await closeAnySheet();
      final ctx = context ?? _bestContext();
      if (ctx == null) return null;

      final Future<T?> fut = openFn(ctx);

      final Future<void> tracked = fut.then<void>((_) {});
      _activeSheet = tracked;

      try {
        final T? result = await fut;
        return result;
      } finally {
        _activeSheet = null;
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
    } finally {
      _opening = false;
    }
  }

  static Future<void> init() async {
    if (_initialized) return;
    _prefs ??= await SharedPreferences.getInstance();
    enabled.value = _prefs!.getBool(_kEnabledKey) ?? false;

    enabled.addListener(() {
      _prefs?.setBool(_kEnabledKey, enabled.value);
      if (enabled.value) {
        _showOverlay();
      } else {
        _hideOverlay();
      }
    });
    _initialized = true;
  }

  static Future<void> mountIfNeeded() async {
    if (!_initialized || _prefs == null) {
      await init();
    }
    if (enabled.value) _showOverlay();
  }

  static void setEnabled(bool value) => enabled.value = value;

  static void toggle() => enabled.value = !enabled.value;

  static Future<bool> _openExternalPage({
    required String url,
    required String failureMessage,
    BuildContext? context,
  }) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;

    var opened = false;

    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }

    if (!opened) {
      try {
        opened = await launchUrl(uri, mode: LaunchMode.platformDefault);
      } catch (_) {
        opened = false;
      }
    }

    if (!opened) {
      final ctx = context ?? _bestContext();
      if (ctx != null && ctx.mounted) {
        showFailedSnackbar(
          ctx,
          failureMessage,
          useCommonUi: true,
        );
      }
    }

    return opened;
  }

  static Future<bool> openTermsOfService([BuildContext? context]) {
    return _openExternalPage(
      url: termsOfServiceUrl,
      failureMessage: '이용약관 화면을 열 수 없습니다.',
      context: context,
    );
  }

  static Future<bool> openPrivacyPolicy([BuildContext? context]) {
    return _openExternalPage(
      url: privacyPolicyUrl,
      failureMessage: '개인정보보호처리방침 화면을 열 수 없습니다.',
      context: context,
    );
  }

  static Future<bool> openContactForm([BuildContext? context]) {
    return _openExternalPage(
      url: contactFormUrl,
      failureMessage: '문의하기 화면을 열 수 없습니다.',
      context: context,
    );
  }

  static Future<void> refreshAreaMaster([
    BuildContext? context,
  ]) async {
    final ctx = context ?? _bestContext();
    if (ctx == null) return;

    final userState = ctx.read<UserState>();
    final division = userState.division.trim();
    final currentArea = userState.currentArea.trim();
    final trace = await DeveloperOperationTrace.start(
      context: ctx,
      title: '본사 데이터 내려받기',
      initialMessage: '본사 다운로드 Snapshot 요청을 확인하고 있습니다.',
      useCommonUi: true,
      developerModeMessage: '개발자 모드 ON: debugPrint 코드를 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF',
    );

    if (division.isEmpty) {
      const failureMessage = '회사 정보가 없어 본사 데이터를 내려받을 수 없습니다.';
      await trace.fail(failureMessage);
      if (!trace.developerMode && ctx.mounted) {
        showFailedSnackbar(ctx, failureMessage, useCommonUi: true);
      }
      return;
    }

    if (currentArea.isEmpty) {
      const failureMessage = '현재 지역 정보가 없어 본사 데이터를 내려받을 수 없습니다.';
      await trace.fail(failureMessage);
      if (!trace.developerMode && ctx.mounted) {
        showFailedSnackbar(ctx, failureMessage, useCommonUi: true);
      }
      return;
    }

    trace.log('회사 정보를 확인했습니다: $division', progress: 0.05);
    trace.log('현재 로그인 지역을 확인했습니다: $currentArea', progress: 0.09);
    trace.log('내려받기 실행 게이트를 확인하고 있습니다.', progress: 0.14);

    final shouldRefresh = await OpsDelayedRefreshGate.waitIfNeeded(
      context: ctx,
      title: '본사 데이터 내려받기',
      message: '본사 데이터를 내려받기 전 요청을 준비하고 있습니다.',
      useCommonUi: true,
    );
    if (!shouldRefresh) {
      trace.log('사용자가 본사 데이터 내려받기를 취소했습니다.');
      return;
    }

    try {
      trace.log(
        'Firebase 데이터를 다운로드한 뒤 하나의 SQLite Snapshot으로 저장합니다.',
        progress: 0.2,
      );
      final snapshot = await AreaMasterCache.refreshDivision(
        division,
        requiredArea: currentArea,
        onLog: trace.log,
        progressStart: 0.22,
        progressEnd: 0.76,
      );
      trace.log(
        'SQLite Snapshot 저장을 확인했습니다: areas=${snapshot.items.length}, downloadedAt=${snapshot.refreshedAtIso}',
        progress: 0.8,
      );

      AreaMasterItem? currentItem;
      for (final item in snapshot.items) {
        if (item.name.trim() == currentArea) {
          currentItem = item;
          break;
        }
      }
      if (currentItem == null) {
        throw StateError(
          '다운로드 Snapshot에서 현재 지역을 찾을 수 없습니다: $currentArea',
        );
      }
      trace.log(
        '현재 지역 연결 데이터는 SharedPreferences에 복제하지 않고 SQLite Snapshot만 사용합니다: emailPresent=${currentItem.email.trim().isNotEmpty}, invitePresent=${currentItem.invite.trim().isNotEmpty}, communicationPresent=${currentItem.communication.trim().isNotEmpty}',
        progress: 0.9,
      );
      trace.log(
        '기존 Snapshot row 전량 삭제, 0건 검증, 신규 전량 INSERT와 commit을 완료했습니다.',
        progress: 0.99,
      );

      if (trace.developerMode) {
        await trace.succeed(
          '본사 데이터 내려받기가 완료되었습니다. 개발자 모드에서는 앱을 종료하지 않습니다.',
        );
        return;
      }

      await trace.succeed('본사 데이터 내려받기가 완료되었습니다.');
      if (!ctx.mounted) return;

      await showCommonDialog<void>(
        context: ctx,
        barrierDismissible: false,
        builder: (dialogContext) {
          final tokens = CommonUiTheme.of(dialogContext);
          final text = Theme.of(dialogContext).textTheme;
          final reduceMotion =
              MediaQuery.maybeOf(dialogContext)?.disableAnimations ?? false;
          final content = ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: tokens.successContainer,
                        borderRadius:
                            BorderRadius.circular(CommonUiShapes.control),
                      ),
                      child: Icon(
                        Icons.download_done_rounded,
                        color: tokens.onSuccessContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '본사 데이터 내려받기 완료',
                        style: text.titleMedium?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: tokens.surfaceOverlay,
                    borderRadius:
                        BorderRadius.circular(CommonUiShapes.control),
                    border: Border.all(color: tokens.borderSubtle),
                  ),
                  child: Text(
                    '${snapshot.items.length}개 지역 정보를 SQLite Snapshot으로 저장했습니다.\n\n'
                    '기준 시각: ${snapshot.refreshedAtIso}\n\n'
                    '현재 지역($currentArea)의 email · invite · communication도 SQLite Snapshot에 포함되며 SharedPreferences에는 복제하지 않습니다.\n\n'
                    '변경 사항 적용을 위해 앱을 종료합니다. 앱을 다시 실행해 주세요.',
                    style: text.bodyMedium?.copyWith(
                      color: tokens.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                CommonButton(
                  label: '확인 및 종료',
                  icon: Icons.power_settings_new_rounded,
                  expand: true,
                  haptic: CommonHaptic.selection,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            ),
          );

          if (reduceMotion) return content;

          return TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: CommonUiMotion.layout,
            curve: CommonUiMotion.enter,
            child: content,
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, 12 * (1 - value)),
                  child: Transform.scale(
                    scale: 0.98 + (0.02 * value),
                    child: child,
                  ),
                ),
              );
            },
          );
        },
      );

      final exitContext = _bestContext();
      if (exitContext == null || !exitContext.mounted) return;
      await AppExitService.exitApp(exitContext, useCommonUi: true);
    } catch (error, stackTrace) {
      const failureMessage = '본사 데이터 내려받기에 실패했습니다.';
      await trace.fail(
        failureMessage,
        error: error,
        stackTrace: stackTrace,
      );
      if (!trace.developerMode && ctx.mounted) {
        showFailedSnackbar(ctx, failureMessage, useCommonUi: true);
      }
    }
  }

  static Offset _restorePos() {
    final dx = _prefs?.getDouble(_kBubbleXKey) ?? 12.0;
    final dy = _prefs?.getDouble(_kBubbleYKey) ?? 200.0;
    return Offset(dx, dy);
  }

  static Future<void> _savePos(Offset pos) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setDouble(_kBubbleXKey, pos.dx);
    await _prefs!.setDouble(_kBubbleYKey, pos.dy);
  }

  static void _showOverlay() {
    if (_entry != null) return;
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showOverlay());
      return;
    }
    _entry = OverlayEntry(
      builder: (context) => CommonUiScope(
        child: Material(
          type: MaterialType.transparency,
          child: _HubBubble(
            initialPos: _restorePos(),
            onPosSave: _savePos,
          ),
        ),
      ),
    );
    overlay.insert(_entry!);
  }

  static void _hideOverlay() {
    _entry?.remove();
    _entry = null;
  }
}

class _HubBubble extends StatefulWidget {
  final Offset initialPos;
  final Future<void> Function(Offset) onPosSave;

  const _HubBubble({required this.initialPos, required this.onPosSave});

  @override
  State<_HubBubble> createState() => _HubBubbleState();
}

class _HubBubbleState extends State<_HubBubble> {
  static const double _handleTouchWidth = 44;
  static const double _handleVisualWidth = 18;
  static const double _handleHeight = 56;
  static const double _gameTouchWidth = 34;
  static const double _gameHeight = 64;
  static const double _bubbleGap = 12;

  late Offset _pos;
  bool _clampedOnce = false;

  _HeadQuickActionsRoute? _panelRoute;

  bool get _expanded => _panelRoute != null;

  bool _developerMode = false;
  bool _disposing = false;
  final List<String> _debugLines = <String>[];

  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _pos = widget.initialPos;
    _recordDebug('initialized navigation=popup_route');
    _refreshDeveloperMode();
  }

  void _recordDebug(String message) {
    final line = '[HeadQuickActions] $message';
    _debugLines.add(line);
    if (_debugLines.length > 120) {
      _debugLines.removeRange(0, _debugLines.length - 120);
    }
    debugPrint(line);
  }

  Future<void> _showDeveloperStatus() async {
    if (!_developerMode || !mounted) return;
    HapticFeedback.mediumImpact();
    final configuredActions = _buildActions(context, CommonUiTheme.of(context));
    final configuredActionIds =
        configuredActions.map((action) => action.id).join('>');
    final visibleActions = configuredActions
        .where((action) => !action.hiddenUntilExactQuery)
        .toList(growable: false);
    final sectionSummary = _QuickActionCategoryUi.mainCategories
        .map((category) {
          final ids = visibleActions
              .where((action) => action.category == category)
              .map((action) => action.id)
              .join(',');
          return '${category.label}:$ids';
        })
        .join('|');
    _recordDebug(
      'developer_status_open expanded=$_expanded position=${_pos.dx.toStringAsFixed(1)},${_pos.dy.toStringAsFixed(1)}',
    );
    _recordDebug(
      'developer_status_actions count=${configuredActions.length} ids=$configuredActionIds',
    );
    _recordDebug(
      'developer_status_sections layout=vertical_headers indent=10 sections=$sectionSummary',
    );
    final panelRoute = _panelRoute;
    _recordDebug(
      'developer_status_back_policy navigation=popup_route routeActive=${panelRoute != null} routeCurrent=${panelRoute?.isCurrent ?? false}',
    );
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '빠른 실행 상태',
      initialMessage: '빠른 실행 상태를 수집하고 있습니다.',
      useCommonUi: true,
      developerModeMessage: '개발자 모드 ON: debugPrint 코드를 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF',
    );
    if (!trace.developerMode) return;
    final media = MediaQuery.maybeOf(context);
    trace.log(
      'expanded=$_expanded, reduceMotion=${media?.disableAnimations ?? false}, debugLines=${_debugLines.length}',
      progress: 0.25,
    );
    trace.log(
      'position=${_pos.dx.toStringAsFixed(1)},${_pos.dy.toStringAsFixed(1)}, developerMode=$_developerMode',
      progress: 0.45,
    );
    trace.log(
      'layout=vertical_headers, indent=10, sections=$sectionSummary',
      progress: 0.52,
    );
    trace.log(
      'work=memo operations=field,attendance,break,statistics support=faq,terms,privacy,contact thirdParty=moved_to_dashboard',
      progress: 0.58,
    );
    trace.log(
      'backPolicy=popup_route_first, panelRouteActive=${panelRoute != null}, panelRouteCurrent=${panelRoute?.isCurrent ?? false}, closeSources=handle,scrim,action,system_back',
      progress: 0.68,
    );
    final snapshot = List<String>.of(_debugLines);
    if (snapshot.isEmpty) {
      trace.log('기록된 빠른 실행 로그가 없습니다.', progress: 0.75);
    } else {
      for (var i = 0; i < snapshot.length; i++) {
        trace.log(
          snapshot[i],
          progress: 0.45 + ((i + 1) / snapshot.length) * 0.45,
        );
      }
    }
    await trace.succeed('빠른 실행 상태 수집이 완료되었습니다.');
  }

  Future<void> _refreshDeveloperMode() async {
    final enabled = await DevAuth.isDeveloperLoggedIn();
    if (!mounted) return;
    _recordDebug('developer_mode=$enabled');
    if (_developerMode == enabled) return;
    setState(() => _developerMode = enabled);
  }

  @override
  void dispose() {
    _disposing = true;
    final route = _panelRoute;
    if (route != null) {
      route.markCloseSource('overlay_dispose');
      final navigator = route.navigator;
      if (navigator != null) {
        navigator.removeRoute(route);
      }
      _panelRoute = null;
    }
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _openMenu({
    required String source,
    bool haptic = false,
  }) async {
    if (_panelRoute != null || !mounted) return;
    final navigator = HeadHubActions.navigatorKey.currentState;
    if (navigator == null) {
      _recordDebug('quick_route_push_failed source=$source reason=navigator_unavailable');
      return;
    }
    await _refreshDeveloperMode();
    if (!mounted || _panelRoute != null) return;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _searchCtrl.clear();
    if (haptic) {
      HapticFeedback.lightImpact();
    }
    final actions = _buildActions(context, CommonUiTheme.of(context));
    late final _HeadQuickActionsRoute route;
    route = _HeadQuickActionsRoute(
      reduceMotion: reduceMotion,
      builder: (routeContext, animation) {
        return _HeadQuickActionsRoutePanel(
          animation: animation,
          initialPos: _pos,
          actions: actions,
          controller: _searchCtrl,
          focusNode: _searchFocus,
          developerMode: _developerMode,
          clampPosition: _clampToScreen,
          onPositionChanged: (position) {
            _pos = position;
          },
          onPositionSave: (position) async {
            _pos = position;
            await widget.onPosSave(position);
            _recordDebug(
              'position_saved x=${position.dx.toStringAsFixed(1)} y=${position.dy.toStringAsFixed(1)} source=panel_route',
            );
          },
          onSelect: _handleActionTap,
          onCloseRequest: (closeSource, closeHaptic) {
            return _closeMenu(
              source: closeSource,
              haptic: closeHaptic,
            );
          },
          onDeveloperStatus: _showDeveloperStatus,
        );
      },
      onDidPop: (closeSource) {
        _searchFocus.unfocus();
        if (closeSource == 'system_back') {
          _recordDebug('back_requested panelRouteActive=true');
        }
        _recordDebug('quick_route_pop source=$closeSource');
        if (closeSource == 'system_back') {
          _recordDebug('back_consumed route=quick_actions');
        }
      },
      onDisposed: (closeSource) {
        if (_panelRoute == route) {
          _panelRoute = null;
        }
        if (mounted && !_disposing) {
          setState(() {});
          _recordDebug('quick_route_closed source=$closeSource');
        }
      },
    );
    _panelRoute = route;
    setState(() {});
    _recordDebug(
      'quick_route_push source=$source reduceMotion=$reduceMotion actions=${actions.length}',
    );
    unawaited(
      navigator.push<void>(route).catchError((Object error, StackTrace stackTrace) {
        _recordDebug(
          'quick_route_failure source=$source error=$error\nStackTrace:\n$stackTrace',
        );
        if (_panelRoute == route) {
          _panelRoute = null;
          if (mounted) setState(() {});
        }
      }),
    );
  }

  Future<void> _closeMenu({
    required String source,
    bool haptic = false,
  }) async {
    final route = _panelRoute;
    if (route == null || !mounted) return;
    _searchFocus.unfocus();
    if (haptic) {
      HapticFeedback.lightImpact();
    }
    _recordDebug(
      'menu_close source=$source navigation=popup_route reduceMotion=${route.reduceMotion} routeCurrent=${route.isCurrent}',
    );
    final requested = route.requestClose(source);
    if (!requested) {
      _recordDebug(
        'menu_close_deferred source=$source routeCurrent=${route.isCurrent}',
      );
      return;
    }
    await route.dismissed;
    if (mounted) {
      _recordDebug('menu_closed source=$source navigation=popup_route');
    }
  }

  Future<void> _toggleMenu() async {
    if (_expanded) {
      await _closeMenu(source: 'handle', haptic: true);
    } else {
      await _openMenu(source: 'handle', haptic: true);
    }
  }

  Future<void> _handleActionTap(_DockAction action) async {
    HapticFeedback.selectionClick();
    _recordDebug('action_start id=${action.id}');
    try {
      await action.onTap();
      _recordDebug('action_complete id=${action.id}');
    } catch (error, stackTrace) {
      _recordDebug(
        'action_failure id=${action.id} error=$error\n'
        'StackTrace:\n$stackTrace',
      );
      rethrow;
    }
  }

  List<_DockAction> _buildActions(
    BuildContext actionContext,
    CommonUiTokens tokens,
  ) {
    Future<void> closeMenu() {
      return _closeMenu(source: 'action');
    }

    Future<T?> openCommonSheet<T>(
      Future<T?> Function(BuildContext context) open,
    ) {
      return HeadHubActions.openSheetExclusively<T>(
        open,
        context: actionContext,
      );
    }

    return <_DockAction>[
      _DockAction(
        id: 'memo',
        category: _QuickActionCategory.work,
        icon: Icons.sticky_note_2_rounded,
        label: '메모',
        description: '플로팅 버블에서 기록을 관리합니다.',
        color: tokens.infoContainer,
        foreground: tokens.onInfoContainer,
        onTap: () async {
          await closeMenu();
          await openCommonSheet<void>(
            (sheetContext) => HeadMemo.openPanel(
              context: sheetContext,
              useCommonUi: true,
            ),
          );
        },
      ),
      _DockAction(
        id: 'field',
        category: _QuickActionCategory.operations,
        icon: Icons.map_rounded,
        label: '근무지 현황',
        description: '사업부별 지역과 근무 인원을 확인합니다.',
        color: tokens.accentContainer,
        foreground: tokens.onAccentContainer,
        onTap: () async {
          await closeMenu();
          await openCommonSheet<dynamic>(
            (sheetContext) => mgmt.Field.showAsBottomSheet(
              sheetContext,
              useCommonUi: true,
            ),
          );
        },
      ),
      _DockAction(
        id: 'attendance',
        category: _QuickActionCategory.operations,
        icon: Icons.how_to_reg_rounded,
        label: '출·퇴근',
        description: '직원별 출퇴근 기록을 관리합니다.',
        color: tokens.infoContainer,
        foreground: tokens.onInfoContainer,
        onTap: () async {
          await closeMenu();
          await openCommonSheet<dynamic>(
            (sheetContext) => hr_att.AttendanceCalendar.showAsBottomSheet(
              sheetContext,
              useCommonUi: true,
            ),
          );
        },
      ),
      _DockAction(
        id: 'break',
        category: _QuickActionCategory.operations,
        icon: Icons.free_breakfast_rounded,
        label: '휴게 관리',
        description: '직원별 휴게시간을 관리합니다.',
        color: tokens.warningContainer,
        foreground: tokens.onWarningContainer,
        onTap: () async {
          await closeMenu();
          await openCommonSheet<dynamic>(
            (sheetContext) => hr_break.BreakCalendar.showAsBottomSheet(
              sheetContext,
              useCommonUi: true,
            ),
          );
        },
      ),
      _DockAction(
        id: 'statistics',
        category: _QuickActionCategory.operations,
        icon: Icons.stacked_line_chart_rounded,
        label: '통계 비교',
        description: '입·출차와 정산 추이를 비교합니다.',
        color: tokens.accentContainer,
        foreground: tokens.onAccentContainer,
        onTap: () async {
          await closeMenu();
          await openCommonSheet<dynamic>(
            (sheetContext) => mgmt_stats.Statistics.showAsBottomSheet(
              sheetContext,
              useCommonUi: true,
            ),
          );
        },
      ),
      _DockAction(
        id: 'faq',
        category: _QuickActionCategory.support,
        icon: Icons.help_center_rounded,
        label: 'FAQ',
        description: '자주 묻는 질문을 확인합니다.',
        color: tokens.surfaceSelected,
        foreground: tokens.textPrimary,
        onTap: () async {
          await closeMenu();
          await HeadHubActions.closeAnySheet();
          await HeadHubActions.navigatorKey.currentState
              ?.pushNamed(AppRoutes.faq);
        },
      ),
      _DockAction(
        id: 'terms',
        category: _QuickActionCategory.support,
        icon: Icons.description_rounded,
        label: '이용약관',
        description: '서비스 이용약관을 확인합니다.',
        color: tokens.surfaceSelected,
        foreground: tokens.textPrimary,
        onTap: () async {
          await closeMenu();
          await HeadHubActions.closeAnySheet();
          final opened =
              await HeadHubActions.openTermsOfService(actionContext);
          _recordDebug('external_result id=terms opened=$opened');
        },
      ),
      _DockAction(
        id: 'privacy',
        category: _QuickActionCategory.support,
        icon: Icons.privacy_tip_rounded,
        label: '개인정보보호처리방침',
        description: '개인정보 처리 기준을 확인합니다.',
        color: tokens.infoContainer,
        foreground: tokens.onInfoContainer,
        onTap: () async {
          await closeMenu();
          await HeadHubActions.closeAnySheet();
          final opened = await HeadHubActions.openPrivacyPolicy(actionContext);
          _recordDebug('external_result id=privacy opened=$opened');
        },
      ),
      _DockAction(
        id: 'contact',
        category: _QuickActionCategory.support,
        icon: Icons.contact_support_rounded,
        label: '문의하기',
        description: '이슈와 오류를 문의합니다.',
        color: tokens.dangerContainer,
        foreground: tokens.onDangerContainer,
        onTap: () async {
          await closeMenu();
          await HeadHubActions.closeAnySheet();
          final opened = await HeadHubActions.openContactForm(actionContext);
          _recordDebug('external_result id=contact opened=$opened');
        },
      ),
      if (_developerMode)
        _DockAction(
          id: 'notensystem',
          category: _QuickActionCategory.developer,
          icon: Icons.auto_stories_rounded,
          label: 'notensystem',
          description: '소설 설계 및 집필 스튜디오',
          color: tokens.infoContainer,
          foreground: tokens.onInfoContainer,
          hiddenUntilExactQuery: true,
          onTap: () async {
            await closeMenu();
            await HeadHubActions.navigatorKey.currentState
                ?.pushNamed(AppRoutes.noteSystem);
          },
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final screen = media?.size ?? Size.zero;
    final bottomInset = media?.padding.bottom ?? 0;
    final keyboardInset = media?.viewInsets.bottom ?? 0;

    if (!_clampedOnce && screen != Size.zero) {
      _clampedOnce = true;
      _pos = _clampToScreen(_pos, screen, bottomInset + keyboardInset);
    }

    final dockRight = screen == Size.zero
        ? true
        : (_pos.dx + _handleTouchWidth / 2) >= screen.width / 2;
    final handleX = screen == Size.zero
        ? _pos.dx
        : (dockRight ? (screen.width - _handleTouchWidth) : 0.0);

    return Stack(
      children: [
        Positioned(
          left: handleX,
          top: _pos.dy,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _toggleMenu,
            onLongPress: _developerMode ? _showDeveloperStatus : null,
            onPanUpdate: _expanded
                ? null
                : (d) {
                    if (screen == Size.zero) return;
                    setState(() {
                      final next =
                          Offset(_pos.dx + d.delta.dx, _pos.dy + d.delta.dy);
                      _pos = _clampToScreen(
                        next,
                        screen,
                        bottomInset + keyboardInset,
                      );
                    });
                  },
            onPanEnd: _expanded
                ? null
                : (_) async {
                    if (screen == Size.zero) return;
                    setState(() {
                      _pos = _clampToScreen(
                        _pos,
                        screen,
                        bottomInset + keyboardInset,
                      );
                    });
                    await widget.onPosSave(_pos);
                    _recordDebug(
                      'position_saved x=${_pos.dx.toStringAsFixed(1)} y=${_pos.dy.toStringAsFixed(1)} source=handle_overlay',
                    );
                  },
            child: SizedBox(
              width: _handleTouchWidth,
              height: _handleHeight,
              child: Align(
                alignment:
                    dockRight ? Alignment.centerRight : Alignment.centerLeft,
                child: _EdgeHandle(
                  width: _handleVisualWidth,
                  height: _handleHeight,
                  dockRight: dockRight,
                  expanded: _expanded,
                  progress: _expanded ? 1 : 0,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Offset _clampToScreen(Offset raw, Size screen, double bottomInset) {
    final wantsRight = (raw.dx + _handleTouchWidth / 2) >= screen.width / 2;
    final snappedX = wantsRight ? (screen.width - _handleTouchWidth) : 0.0;

    final maxY = (screen.height - _handleHeight - bottomInset).clamp(0.0, double.infinity).toDouble();
    final dy = raw.dy.clamp(0.0, maxY).toDouble();
    return _avoidGameOverlap(Offset(snappedX, dy), screen, bottomInset);
  }

  Rect? _gameBubbleRect(Size screen, double bottomInset) {
    final prefs = HeadHubActions._prefs;
    if (prefs?.getBool(HeadHubActions._kGameEnabledKey) != true) return null;
    final rawDx = prefs?.getDouble(HeadHubActions._kGameBubbleXKey) ?? 100000.0;
    final rawDy = prefs?.getDouble(HeadHubActions._kGameBubbleYKey) ?? 272.0;
    final right = (rawDx + _gameTouchWidth / 2) >= screen.width / 2;
    final x = right ? screen.width - _gameTouchWidth : 0.0;
    final maxY = (screen.height - _gameHeight - bottomInset).clamp(0.0, double.infinity).toDouble();
    final y = rawDy.clamp(0.0, maxY).toDouble();
    return Rect.fromLTWH(x, y, _gameTouchWidth, _gameHeight);
  }

  Offset _avoidGameOverlap(Offset pos, Size screen, double bottomInset) {
    final game = _gameBubbleRect(screen, bottomInset);
    if (game == null) return pos;
    final mine = Rect.fromLTWH(pos.dx, pos.dy, _handleTouchWidth, _handleHeight);
    if (!mine.overlaps(game)) return pos;

    final maxY = (screen.height - _handleHeight - bottomInset).clamp(0.0, double.infinity).toDouble();
    final above = (game.top - _bubbleGap - _handleHeight).clamp(0.0, maxY).toDouble();
    final aboveRect = Rect.fromLTWH(pos.dx, above, _handleTouchWidth, _handleHeight);
    if (!aboveRect.overlaps(game)) return Offset(pos.dx, above);

    final below = (game.bottom + _bubbleGap).clamp(0.0, maxY).toDouble();
    final belowRect = Rect.fromLTWH(pos.dx, below, _handleTouchWidth, _handleHeight);
    if (!belowRect.overlaps(game)) return Offset(pos.dx, below);

    return Offset(pos.dx, 0.0);
  }
}

class _HeadQuickActionsRoute extends PopupRoute<void> {
  _HeadQuickActionsRoute({
    required this.reduceMotion,
    required this.builder,
    required this.onDidPop,
    required this.onDisposed,
  });

  final bool reduceMotion;
  final Widget Function(BuildContext context, Animation<double> animation)
      builder;
  final ValueChanged<String> onDidPop;
  final ValueChanged<String> onDisposed;
  final Completer<void> _dismissedCompleter = Completer<void>();

  String? _closeSource;
  String? _resolvedCloseSource;
  bool _didPop = false;

  Future<void> get dismissed => _dismissedCompleter.future;

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => '빠른 실행';

  @override
  Duration get transitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 240);

  @override
  Duration get reverseTransitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 240);

  void markCloseSource(String source) {
    if (_didPop) return;
    _closeSource = source;
  }

  bool requestClose(String source) {
    if (_didPop || !isCurrent) return false;
    _closeSource = source;
    navigator?.pop();
    return true;
  }

  @override
  bool didPop(void result) {
    final popped = super.didPop(result);
    if (!popped) return false;
    _didPop = true;
    _resolvedCloseSource = _closeSource ?? 'system_back';
    onDidPop(_resolvedCloseSource!);
    return true;
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final panelAnimation = CurvedAnimation(
      parent: animation,
      curve: const SpringCurve(),
      reverseCurve: Curves.easeInCubic,
    );
    return CommonUiScope(
      child: Material(
        type: MaterialType.transparency,
        child: builder(context, panelAnimation),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }

  @override
  void dispose() {
    final source = _resolvedCloseSource ?? _closeSource ?? 'route_dispose';
    if (!_dismissedCompleter.isCompleted) {
      _dismissedCompleter.complete();
    }
    onDisposed(source);
    super.dispose();
  }
}

class _HeadQuickActionsRoutePanel extends StatefulWidget {
  const _HeadQuickActionsRoutePanel({
    required this.animation,
    required this.initialPos,
    required this.actions,
    required this.controller,
    required this.focusNode,
    required this.developerMode,
    required this.clampPosition,
    required this.onPositionChanged,
    required this.onPositionSave,
    required this.onSelect,
    required this.onCloseRequest,
    required this.onDeveloperStatus,
  });

  final Animation<double> animation;
  final Offset initialPos;
  final List<_DockAction> actions;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool developerMode;
  final Offset Function(Offset raw, Size screen, double bottomInset)
      clampPosition;
  final ValueChanged<Offset> onPositionChanged;
  final Future<void> Function(Offset position) onPositionSave;
  final Future<void> Function(_DockAction action) onSelect;
  final Future<void> Function(String source, bool haptic) onCloseRequest;
  final Future<void> Function() onDeveloperStatus;

  @override
  State<_HeadQuickActionsRoutePanel> createState() =>
      _HeadQuickActionsRoutePanelState();
}

class _HeadQuickActionsRoutePanelState
    extends State<_HeadQuickActionsRoutePanel> {
  static const double _handleTouchWidth = 44;
  static const double _handleVisualWidth = 18;
  static const double _handleHeight = 56;
  static const double _dockRadius = 18;

  late Offset _pos;

  @override
  void initState() {
    super.initState();
    _pos = widget.initialPos;
    widget.controller.addListener(_handleSearchChanged);
  }

  void _handleSearchChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleSearchChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.animation,
      builder: (context, _) {
        final media = MediaQuery.maybeOf(context);
        final screen = media?.size ?? Size.zero;
        final bottomInset = media?.padding.bottom ?? 0;
        final keyboardInset = media?.viewInsets.bottom ?? 0;
        final tokens = CommonUiTheme.of(context);
        final progress = widget.animation.value.clamp(0.0, 1.0).toDouble();

        if (screen != Size.zero) {
          final clamped = widget.clampPosition(
            _pos,
            screen,
            bottomInset + keyboardInset,
          );
          if (clamped != _pos) {
            _pos = clamped;
            widget.onPositionChanged(_pos);
          }
        }

        final dockRight = screen == Size.zero
            ? true
            : (_pos.dx + _handleTouchWidth / 2) >= screen.width / 2;
        final maxDockWidth =
            (screen.width * 0.92).clamp(240.0, double.infinity);
        final dockWidth = math.min(360.0, maxDockWidth);
        final dockBorderRadius = dockRight
            ? const BorderRadius.only(
                topLeft: Radius.circular(_dockRadius),
                bottomLeft: Radius.circular(_dockRadius),
              )
            : const BorderRadius.only(
                topRight: Radius.circular(_dockRadius),
                bottomRight: Radius.circular(_dockRadius),
              );
        final slideDistance = dockWidth + _handleTouchWidth + 24;
        final slideX = dockRight
            ? slideDistance * (1 - progress)
            : -slideDistance * (1 - progress);
        final handleX = screen == Size.zero
            ? _pos.dx
            : (dockRight ? screen.width - _handleTouchWidth : 0.0);

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => widget.onCloseRequest('scrim', true),
                behavior: HitTestBehavior.opaque,
                child: ColoredBox(
                  color: tokens.scrim.withOpacity(0.22 * progress),
                ),
              ),
            ),
            Positioned(
              top: 0,
              bottom: 0,
              left: dockRight ? null : 0,
              right: dockRight ? 0 : null,
              child: Transform.translate(
                offset: Offset(slideX, 0),
                child: Opacity(
                  opacity: progress,
                  child: _GlassDock(
                    width: dockWidth,
                    height: screen.height,
                    borderRadius: dockBorderRadius,
                    child: SafeArea(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: keyboardInset),
                        child: _CommandPaletteDock(
                          actions: widget.actions,
                          controller: widget.controller,
                          focusNode: widget.focusNode,
                          onSelect: widget.onSelect,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: handleX,
              top: _pos.dy,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => widget.onCloseRequest('handle', true),
                onLongPress:
                    widget.developerMode ? widget.onDeveloperStatus : null,
                onPanUpdate: (details) {
                  if (screen == Size.zero) return;
                  setState(() {
                    final next = Offset(
                      _pos.dx + details.delta.dx,
                      _pos.dy + details.delta.dy,
                    );
                    _pos = widget.clampPosition(
                      next,
                      screen,
                      bottomInset + keyboardInset,
                    );
                    widget.onPositionChanged(_pos);
                  });
                },
                onPanEnd: (_) async {
                  if (screen == Size.zero) return;
                  setState(() {
                    _pos = widget.clampPosition(
                      _pos,
                      screen,
                      bottomInset + keyboardInset,
                    );
                    widget.onPositionChanged(_pos);
                  });
                  await widget.onPositionSave(_pos);
                },
                child: SizedBox(
                  width: _handleTouchWidth,
                  height: _handleHeight,
                  child: Align(
                    alignment: dockRight
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: _EdgeHandle(
                      width: _handleVisualWidth,
                      height: _handleHeight,
                      dockRight: dockRight,
                      expanded: true,
                      progress: progress,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

enum _QuickActionCategory {
  work,
  operations,
  support,
  developer,
}

extension _QuickActionCategoryUi on _QuickActionCategory {
  static const List<_QuickActionCategory> mainCategories = <_QuickActionCategory>[
    _QuickActionCategory.work,
    _QuickActionCategory.operations,
    _QuickActionCategory.support,
  ];

  String get label {
    switch (this) {
      case _QuickActionCategory.work:
        return '업무';
      case _QuickActionCategory.operations:
        return '운영';
      case _QuickActionCategory.support:
        return '지원';
      case _QuickActionCategory.developer:
        return '개발자';
    }
  }
}

class _CommandPaletteDock extends StatelessWidget {
  final List<_DockAction> actions;
  final TextEditingController controller;
  final FocusNode focusNode;
  final Future<void> Function(_DockAction action) onSelect;

  const _CommandPaletteDock({
    required this.actions,
    required this.controller,
    required this.focusNode,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final queryRaw = controller.text.trim();
    final query = _normalize(queryRaw);

    final filtered = query.isEmpty
        ? actions
            .where((action) => !action.hiddenUntilExactQuery)
            .toList(growable: false)
        : actions.where((action) {
            if (action.hiddenUntilExactQuery) {
              return query == _normalize(action.id) ||
                  query == _normalize(action.label);
            }
            return _normalize(action.searchText).contains(query);
          }).toList(growable: false);

    final titleText = query.isEmpty ? '빠른 실행' : '검색 결과';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          titleText,
          style: text.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        _SearchField(
          controller: controller,
          focusNode: focusNode,
          onSubmit: () async {
            if (filtered.isNotEmpty) {
              await onSelect(filtered.first);
            }
          },
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _PaletteList(
            query: query,
            items: filtered,
            onSelect: onSelect,
          ),
        ),
      ],
    );
  }

  static String _normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final Future<void> Function() onSubmit;

  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final border = cs.outlineVariant.withOpacity(0.85);
    final fill = cs.surface.withOpacity(0.55);

    return Container(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => onSubmit(),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final hasText = value.text.trim().isNotEmpty;
              if (!hasText) return const SizedBox.shrink();
              return IconButton(
                onPressed: () => controller.clear(),
                icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
                tooltip: '지우기',
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PaletteList extends StatelessWidget {
  final String query;
  final List<_DockAction> items;
  final Future<void> Function(_DockAction action) onSelect;

  const _PaletteList({
    required this.query,
    required this.items,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (query.isNotEmpty && items.isEmpty) {
      return Center(
        child: Text(
          '검색 결과가 없습니다.',
          style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }

    if (query.isNotEmpty) {
      return ListView.separated(
        padding: EdgeInsets.zero,
        physics: const ClampingScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          return _StaggeredReveal(
            key: ValueKey<String>('search_${items[index].id}'),
            order: index,
            child: _PaletteTile(
              action: items[index],
              onSelect: onSelect,
            ),
          );
        },
      );
    }

    final children = <Widget>[];
    var revealOrder = 0;

    for (final category in _QuickActionCategoryUi.mainCategories) {
      final sectionItems = items
          .where((action) => action.category == category)
          .toList(growable: false);
      if (sectionItems.isEmpty) continue;

      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 14));
      }

      children.add(
        _StaggeredReveal(
          key: ValueKey<String>('header_${category.name}'),
          order: revealOrder++,
          offsetY: 6,
          child: _PaletteSectionHeader(label: category.label),
        ),
      );
      children.add(const SizedBox(height: 8));

      for (var index = 0; index < sectionItems.length; index++) {
        final action = sectionItems[index];
        children.add(
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: _StaggeredReveal(
              key: ValueKey<String>('section_${category.name}_${action.id}'),
              order: revealOrder++,
              child: _PaletteTile(
                action: action,
                onSelect: onSelect,
              ),
            ),
          ),
        );
        if (index != sectionItems.length - 1) {
          children.add(const SizedBox(height: 10));
        }
      }
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 4),
      physics: const ClampingScrollPhysics(),
      children: children,
    );
  }
}

class _PaletteSectionHeader extends StatelessWidget {
  const _PaletteSectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;

    return Semantics(
      header: true,
      label: label,
      child: Padding(
        padding: const EdgeInsets.only(left: 2, right: 4),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 16,
              decoration: BoxDecoration(
                color: tokens.accent,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: text.labelLarge?.copyWith(
                color: tokens.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StaggeredReveal extends StatelessWidget {
  const _StaggeredReveal({
    super.key,
    required this.order,
    required this.child,
    this.offsetY = 9,
  });

  final int order;
  final Widget child;
  final double offsetY;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return child;

    final delayMs = math.min(order, 10) * 22;
    const motionMs = 190;
    final totalMs = delayMs + motionMs;
    final start = delayMs / totalMs;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: totalMs),
      builder: (context, value, animatedChild) {
        final normalized = value <= start
            ? 0.0
            : ((value - start) / (1 - start)).clamp(0.0, 1.0).toDouble();
        final motion = Curves.easeOutCubic.transform(normalized);
        return Opacity(
          opacity: motion,
          child: Transform.translate(
            offset: Offset(0, offsetY * (1 - motion)),
            child: animatedChild,
          ),
        );
      },
      child: child,
    );
  }
}

class _PaletteTile extends StatelessWidget {
  final _DockAction action;
  final Future<void> Function(_DockAction action) onSelect;

  const _PaletteTile({required this.action, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;

    final border = tokens.borderSubtle;
    final bg = tokens.surface;

    return Semantics(
      button: true,
      label: action.label,
      child: Material(
        color: tokens.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => onSelect(action),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: border, width: 1),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: action.color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: tokens.shadow,
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Icon(action.icon, color: action.foreground, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        action.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleSmall?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                      if ((action.description ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          action.description!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(
                            color: tokens.textSecondary,
                            height: 1.15,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: tokens.iconSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DockAction {
  final String id;
  final _QuickActionCategory category;
  final IconData icon;
  final String label;
  final String? description;
  final Color color;
  final Color foreground;
  final bool hiddenUntilExactQuery;
  final Future<void> Function() onTap;

  _DockAction({
    required this.id,
    required this.category,
    required this.icon,
    required this.label,
    required this.description,
    required this.color,
    required this.foreground,
    this.hiddenUntilExactQuery = false,
    required this.onTap,
  });

  String get searchText =>
      [id, category.label, label, description].whereType<String>().join(' ');
}

class _EdgeHandle extends StatelessWidget {
  final double width;
  final double height;
  final bool dockRight;
  final bool expanded;
  final double progress;

  const _EdgeHandle({
    required this.width,
    required this.height,
    required this.dockRight,
    required this.expanded,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final t = Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));
    final bg0 = Color.alphaBlend(
        cs.primaryContainer.withOpacity(0.55 + 0.10 * t), cs.surface);
    final bg1 = Color.alphaBlend(
        cs.secondaryContainer.withOpacity(0.35 + 0.10 * t), cs.surface);
    final border = cs.outlineVariant.withOpacity(0.85);

    IconData icon;
    if (dockRight) {
      icon =
          expanded ? Icons.chevron_right_rounded : Icons.chevron_left_rounded;
    } else {
      icon =
          expanded ? Icons.chevron_left_rounded : Icons.chevron_right_rounded;
    }

    return Semantics(
      button: true,
      label: expanded ? '빠른 실행 닫기' : '빠른 실행 열기',
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [bg0, bg1],
          ),
          border: Border.all(color: border, width: 1),
          boxShadow: [
            BoxShadow(
              blurRadius: 16,
              offset: const Offset(0, 6),
              color: cs.shadow.withOpacity(0.22),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: cs.onSurface.withOpacity(0.92)),
            const SizedBox(height: 8),
            _GripDots(color: cs.onSurfaceVariant.withOpacity(0.55)),
          ],
        ),
      ),
    );
  }
}

class _GripDots extends StatelessWidget {
  final Color color;

  const _GripDots({required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Dot(color: color),
        const SizedBox(height: 4),
        _Dot(color: color),
        const SizedBox(height: 4),
        _Dot(color: color),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;

  const _Dot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3.5,
      height: 3.5,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _GlassDock extends StatelessWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;
  final Widget child;

  const _GlassDock({
    required this.width,
    required this.height,
    required this.borderRadius,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: width,
          height: height,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            color: tokens.surface.withOpacity(tokens.isDark ? 0.86 : 0.90),
            border: Border.all(color: tokens.borderSubtle, width: 1),
            boxShadow: [
              BoxShadow(
                blurRadius: 16,
                color: tokens.shadow,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class SpringCurve extends Curve {
  const SpringCurve();

  @override
  double transform(double t) {
    final e = math.exp(-6 * t);
    final c = math.cos(10 * t);
    final y = 1 - e * c;
    return y.clamp(0.0, 1.0);
  }
}
