import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';

import '../../../../app/init/app_exit_service.dart';
import '../../../../app/init/logout_helper.dart';
import '../../../../app/utils/status_dialog.dart';
import '../../../../app/models/capability.dart';
import '../../../account/applications/user_state.dart';
import '../../../calendar/presentation/headquarter_calendar_card.dart';
import '../../../dev/debug/debug_action_recorder.dart';
import '../../../headquarter/application/area/area_master_cache.dart';
import '../../../headquarter/application/fab/hub_quick_actions.dart';
import '../../widgets/widgets/info/my_info_dialog.dart';
import '../../../mode_single/application/att_brk_repository.dart';
import '../../../selector/application/dev_auth.dart';
import '../../../selector/sheets/service_bottom_sheet.dart';

enum HqDashBoardStylePreset {
  doubleLegacy,
  outlined,
}

typedef HandleWorkStatus = Future<void> Function(
  UserState userState,
  BuildContext context,
);

class CommonHqDashBoardPage extends StatefulWidget {
  const CommonHqDashBoardPage({
    super.key,
    required this.screenName,
    required this.userInfoCard,
    required this.breakButton,
    required this.onHandleWorkStatus,
    required this.stylePreset,
    this.showLogout = true,
    this.showDocumentBox = true,
  });

  final String screenName;
  final Widget userInfoCard;
  final Widget breakButton;
  final HandleWorkStatus onHandleWorkStatus;
  final HqDashBoardStylePreset stylePreset;
  final bool showLogout;
  final bool showDocumentBox;

  @override
  State<CommonHqDashBoardPage> createState() => _CommonHqDashBoardPageState();
}

class _CommonHqDashBoardPageState extends State<CommonHqDashBoardPage> {
  static const int _opsActionPageCount = 3;

  late final PageController _opsActionPageController;
  late final ScrollController _dashboardScrollController;
  final GlobalKey _dashboardViewportKey = GlobalKey();
  final GlobalKey _subscriptionHeaderKey = GlobalKey();
  final GlobalKey<_BranchSubscriptionStatusInlinePanelState>
      _subscriptionPanelKey =
      GlobalKey<_BranchSubscriptionStatusInlinePanelState>();
  int _opsActionPageIndex = 0;
  bool _subscriptionExpanded = false;
  bool _subscriptionHeaderOffscreen = false;
  bool _floatingCollapseBusy = false;
  final List<String> _opsDebugLines = <String>[];

  @override
  void initState() {
    super.initState();
    _opsActionPageController = PageController(initialPage: 1);
    _dashboardScrollController = ScrollController();
    _dashboardScrollController.addListener(_handleDashboardScroll);
  }

  @override
  void dispose() {
    _dashboardScrollController.removeListener(_handleDashboardScroll);
    _dashboardScrollController.dispose();
    _opsActionPageController.dispose();
    super.dispose();
  }

  void _handleDashboardScroll() {
    _updateFloatingCollapseVisibility();
  }

  void _handleSubscriptionExpandedChanged(bool expanded) {
    if (_subscriptionExpanded != expanded) {
      setState(() {
        _subscriptionExpanded = expanded;
        if (!expanded) {
          _subscriptionHeaderOffscreen = false;
          _floatingCollapseBusy = false;
        }
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateFloatingCollapseVisibility();
    });
  }

  void _updateFloatingCollapseVisibility() {
    if (!mounted) return;

    var headerOffscreen = false;
    if (_subscriptionExpanded && _dashboardScrollController.hasClients) {
      final headerContext = _subscriptionHeaderKey.currentContext;
      final viewportContext = _dashboardViewportKey.currentContext;
      final headerBox = headerContext?.findRenderObject();
      final viewportBox = viewportContext?.findRenderObject();

      if (headerBox is RenderBox &&
          headerBox.hasSize &&
          viewportBox is RenderBox &&
          viewportBox.hasSize) {
        final headerTop = headerBox.localToGlobal(Offset.zero).dy;
        final headerBottom = headerTop + headerBox.size.height;
        final viewportTop = viewportBox.localToGlobal(Offset.zero).dy;
        headerOffscreen = headerBottom <= viewportTop + 8;
      }
    }

    final changed = _subscriptionHeaderOffscreen != headerOffscreen;
    if (changed) {
      setState(() {
        _subscriptionHeaderOffscreen = headerOffscreen;
      });
    }

    final panelState = _subscriptionPanelKey.currentState;
    if (panelState != null) {
      final offset = _dashboardScrollController.hasClients
          ? _dashboardScrollController.offset
          : 0.0;
      panelState._updateFloatingControlDiagnostics(
        scrollOffset: offset,
        headerOffscreen: headerOffscreen,
        floatingVisible:
            _subscriptionExpanded && headerOffscreen && !_floatingCollapseBusy,
      );
    }
  }

  Future<void> _handleFloatingSubscriptionCollapse() async {
    if (_floatingCollapseBusy || !_subscriptionExpanded) return;

    final controller = _dashboardScrollController;
    final panelState = _subscriptionPanelKey.currentState;
    if (!controller.hasClients || panelState == null) return;

    final startOffset = controller.offset;
    setState(() {
      _floatingCollapseBusy = true;
    });
    _updateFloatingCollapseVisibility();

    panelState._recordSubscriptionDebug(
      'floating_collapse_pressed',
      meta: <String, Object?>{
        'scrollOffset': startOffset.toStringAsFixed(1),
        'headerOffscreen': _subscriptionHeaderOffscreen,
      },
    );
    HapticFeedback.selectionClick();

    try {
      final headerContext = _subscriptionHeaderKey.currentContext;
      final viewportContext = _dashboardViewportKey.currentContext;
      final headerBox = headerContext?.findRenderObject();
      final viewportBox = viewportContext?.findRenderObject();

      if (headerBox is RenderBox &&
          headerBox.hasSize &&
          viewportBox is RenderBox &&
          viewportBox.hasSize) {
        final headerTop = headerBox.localToGlobal(Offset.zero).dy;
        final viewportTop = viewportBox.localToGlobal(Offset.zero).dy;
        final rawTarget = controller.offset + headerTop - viewportTop - 8;
        final position = controller.position;
        final target = rawTarget
            .clamp(
              position.minScrollExtent,
              position.maxScrollExtent,
            )
            .toDouble();
        final reduceMotion =
            MediaQuery.maybeOf(context)?.disableAnimations ?? false;

        panelState._recordSubscriptionDebug(
          'collapse_anchor_scroll_start',
          meta: <String, Object?>{
            'from': controller.offset.toStringAsFixed(1),
            'to': target.toStringAsFixed(1),
            'reduceMotion': reduceMotion,
          },
        );

        if (reduceMotion) {
          controller.jumpTo(target);
        } else {
          await controller.animateTo(
            target,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          );
        }

        if (panelState.mounted) {
          panelState._recordSubscriptionDebug(
            'collapse_anchor_scroll_complete',
            meta: <String, Object?>{
              'scrollOffset': controller.offset.toStringAsFixed(1),
            },
          );
        }
      }

      if (!mounted || !panelState.mounted) return;
      panelState._collapse(
        source: 'floating_action',
        haptic: false,
      );
    } catch (error, stackTrace) {
      if (panelState.mounted) {
        panelState._recordSubscriptionDebug(
          'floating_collapse_failure',
          meta: <String, Object?>{
            'error': error,
            'stackTrace': stackTrace,
          },
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _floatingCollapseBusy = false;
          _subscriptionHeaderOffscreen = false;
        });
      }
    }
  }

  void _trace(String name, {Map<String, dynamic>? meta}) {
    DebugActionRecorder.instance.recordAction(
      name,
      route: ModalRoute.of(context)?.settings.name,
      meta: meta,
    );
  }

  Future<void> _handleLogout(BuildContext context) async {
    _trace(
      '로그아웃',
      meta: <String, dynamic>{
        'screen': widget.screenName,
        'action': 'logout',
      },
    );
    await LogoutHelper.logoutAndGoToLogin(context, useCommonUi: true);
  }

  Future<void> _openServiceSettings(BuildContext context) async {
    _trace(
      '서비스 설정 오픈',
      meta: <String, dynamic>{
        'screen': widget.screenName,
        'action': 'open_service_settings',
      },
    );

    final rootCtx = Navigator.of(context, rootNavigator: true).context;
    await ServiceBottomSheet.show(
      context: rootCtx,
    );
  }

  Future<void> _exitAppAfterClockOut(BuildContext context) async {
    try {
      if (DebugActionRecorder.instance.isRecording) {
        await DebugActionRecorder.instance.stopAndSave(
          titleOverride: 'auto:clockout_exit',
        );
      }
    } catch (_) {}

    await AppExitService.exitApp(context, useCommonUi: true);
  }

  Future<void> _handleClockOutFlow(
    BuildContext context,
    UserState userState,
  ) async {
    _trace(
      '퇴근 처리 시작',
      meta: <String, dynamic>{
        'screen': widget.screenName,
        'action': 'clockout_flow_start',
        'isWorkingBefore': userState.isWorking,
      },
    );

    await widget.onHandleWorkStatus(userState, context);

    if (!mounted) return;

    _trace(
      '퇴근 상태 반영',
      meta: <String, dynamic>{
        'screen': widget.screenName,
        'action': 'clockout_state_updated',
        'isWorkingAfter': userState.isWorking,
      },
    );

    if (!userState.isWorking) {
      final session = userState.session;
      if (session != null) {
        final now = DateTime.now();

        _trace(
          '퇴근 이벤트 기록',
          meta: <String, dynamic>{
            'screen': widget.screenName,
            'action': 'workout_event_insert_and_upload',
            'area': userState.currentArea,
            'division': userState.division,
            'at': now.toIso8601String(),
          },
        );

        await AttBrkRepository.instance.insertEventAndUpload(
          dateTime: now,
          type: AttBrkModeType.workOut,
          userId: session.id,
          userName: session.displayName,
          area: userState.currentArea,
          division: userState.division,
        );
      }

      _trace(
        '앱 종료 진행',
        meta: <String, dynamic>{
          'screen': widget.screenName,
          'action': 'exit_after_clockout',
        },
      );

      await _exitAppAfterClockOut(context);
    } else {
      _trace(
        '퇴근 처리 미완료',
        meta: <String, dynamic>{
          'screen': widget.screenName,
          'action': 'clockout_not_completed',
          'reason': 'userState.isWorking_still_true',
        },
      );
    }
  }

  Future<void> _onClockOutPressed(
    BuildContext context,
    UserState userState,
  ) async {
    _trace(
      '퇴근하기 버튼',
      meta: <String, dynamic>{
        'screen': widget.screenName,
        'action': 'clockout_tap',
        'isWorking': userState.isWorking,
      },
    );

    if (userState.isWorking) {
      _trace(
        '퇴근 다이얼로그 생략',
        meta: <String, dynamic>{
          'screen': widget.screenName,
          'action': 'clockout_dialog_skipped',
          'reason': 'immediate_clockout_required',
        },
      );
    }

    await _handleClockOutFlow(context, userState);
  }

  Widget _dialogPanel({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tokens.accentContainer,
                  borderRadius: BorderRadius.circular(CommonUiShapes.control),
                  border: Border.all(color: tokens.borderSubtle),
                ),
                child: Icon(icon, color: tokens.onAccentContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: tokens.textPrimary,
                    letterSpacing: -.2,
                  ),
                ),
              ),
              CommonIconButton(
                icon: Icons.close_rounded,
                tooltip: '닫기',
                onPressed: () => Navigator.of(context).pop(),
                haptic: CommonHaptic.selection,
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Future<void> _openWorkActionsDialog(
    BuildContext context,
    UserState userState,
  ) async {
    final tokens = CommonUiTheme.of(context);

    await showCommonDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return _dialogPanel(
          context: dialogContext,
          title: '근무 액션',
          icon: Icons.work_history_rounded,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: double.infinity, child: widget.breakButton),
              const SizedBox(height: 8),
              _OpsHqActionTile(
                label: '퇴근하기',
                icon: Icons.exit_to_app_rounded,
                color: tokens.danger,
                danger: true,
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  _onClockOutPressed(context, userState);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _toggleHeadHubQuickButton() async {
    await HeadHubActions.init();
    HeadHubActions.toggle();
    HapticFeedback.selectionClick();
  }

  Future<void> _openMyInfo(BuildContext context) async {
    await showMyInfoDialog(
      context: context,
      source: MyInfoEntrySource.hqDashboard,
    );
  }

  String _opsDebugMessage({
    required String label,
    required String action,
  }) {
    final now = DateTime.now().toIso8601String();
    return '[HQ_DASHBOARD] timestamp=$now screen=${widget.screenName} '
        'page=${_opsActionPageIndex + 1}/$_opsActionPageCount '
        'label=$label action=$action';
  }

  void _recordOpsDebug(String message) {
    _opsDebugLines.add(message);
    if (_opsDebugLines.length > 120) {
      _opsDebugLines.removeRange(0, _opsDebugLines.length - 120);
    }
    debugPrint(message);
  }

  Future<void> _runOpsAction(
    BuildContext context, {
    required String label,
    required String action,
    required Future<void> Function() operation,
  }) async {
    final message = _opsDebugMessage(label: label, action: action);
    _recordOpsDebug('$message phase=start');
    _trace(
      '본사 대시보드 액션',
      meta: <String, dynamic>{
        'screen': widget.screenName,
        'page': _opsActionPageIndex + 1,
        'label': label,
        'action': action,
      },
    );
    try {
      await operation();
      _recordOpsDebug('$message phase=complete');
    } catch (error, stackTrace) {
      _recordOpsDebug(
        '$message phase=failure error=$error\n'
        'StackTrace:\n$stackTrace',
      );
      rethrow;
    }
  }

  Future<void> _showOpsDebugStatus(
    BuildContext context, {
    required String label,
    required String action,
  }) async {
    final developerMode = await DevAuth.isDevModeEnabled();
    if (!developerMode || !mounted || !context.mounted) return;

    final message = _opsDebugMessage(label: label, action: action);
    _recordOpsDebug('$message phase=status_open');
    final snapshot = List<String>.of(_opsDebugLines);
    final code = snapshot
        .map((line) => 'debugPrint(${jsonEncode(line)});')
        .join('\n');
    HapticFeedback.mediumImpact();

    await StatusDialog.showSuccess(
      context,
      title: '개발자 상태',
      description: '$label 액션 디버그 코드를 복사할 수 있습니다.',
      copyText: code,
      copyButtonLabel: 'debugPrint 복사',
      visibleDuration: const Duration(seconds: 30),
      useCommonUi: true,
    );
  }

  String _modeLabel() {
    final screen = widget.screenName.toLowerCase();
    if (screen.contains('minor')) return '확장형';
    if (screen.contains('triple')) return '기본형';
    if (screen.contains('double') || screen.contains('lite')) return '경량형';
    return '경량형';
  }

  String _safe(String value, {String fallback = '-'}) {
    final v = value.trim();
    return v.isEmpty ? fallback : v;
  }

  void _onOpsActionPageChanged(int page) {
    final int logicalPage;
    if (page == 0) {
      logicalPage = _opsActionPageCount - 1;
    } else if (page == _opsActionPageCount + 1) {
      logicalPage = 0;
    } else {
      logicalPage = page - 1;
    }

    if (_opsActionPageIndex != logicalPage) {
      HapticFeedback.selectionClick();
      setState(() {
        _opsActionPageIndex = logicalPage;
      });
    }

    if (page == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_opsActionPageController.hasClients) return;
        _opsActionPageController.jumpToPage(_opsActionPageCount);
      });
      return;
    }

    if (page == _opsActionPageCount + 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_opsActionPageController.hasClients) return;
        _opsActionPageController.jumpToPage(1);
      });
    }
  }

  int _logicalOpsActionPage(int page) {
    if (page == 0) return _opsActionPageCount - 1;
    if (page == _opsActionPageCount + 1) return 0;
    return page - 1;
  }

  Widget _buildOpsActionPage(
    BuildContext context,
    UserState userState,
    int page,
  ) {
    final tokens = CommonUiTheme.of(context);

    switch (page) {
      case 0:
        return Row(
          children: [
            Expanded(
              child: _OpsHqCarouselButton(
                label: '내정보',
                icon: Icons.person_rounded,
                color: tokens.info,
                onTap: () => _runOpsAction(
                  context,
                  label: '내정보',
                  action: 'open_my_info',
                  operation: () => _openMyInfo(context),
                ),
                onLongPress: () => _showOpsDebugStatus(
                  context,
                  label: '내정보',
                  action: 'open_my_info',
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _OpsHqCarouselButton(
                label: '근무액션',
                icon: Icons.work_history_rounded,
                color: tokens.info,
                onTap: () => _runOpsAction(
                  context,
                  label: '근무액션',
                  action: 'open_work_actions',
                  operation: () => _openWorkActionsDialog(context, userState),
                ),
                onLongPress: () => _showOpsDebugStatus(
                  context,
                  label: '근무액션',
                  action: 'open_work_actions',
                ),
              ),
            ),
          ],
        );
      case 1:
        return Row(
          children: [
            Expanded(
              child: ValueListenableBuilder<bool>(
                valueListenable: HeadHubActions.enabled,
                builder: (context, enabled, _) {
                  return _OpsHqCarouselButton(
                    label: '퀵버튼',
                    icon: Icons.lightbulb_rounded,
                    color: enabled ? tokens.warning : tokens.iconDisabled,
                    leading: _OpsHqQuickButtonIndicator(enabled: enabled),
                    onTap: () => _runOpsAction(
                      context,
                      label: '퀵버튼',
                      action: enabled
                          ? 'disable_head_hub_quick_button'
                          : 'enable_head_hub_quick_button',
                      operation: _toggleHeadHubQuickButton,
                    ),
                    onLongPress: () => _showOpsDebugStatus(
                      context,
                      label: '퀵버튼',
                      action: enabled
                          ? 'disable_head_hub_quick_button'
                          : 'enable_head_hub_quick_button',
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _OpsHqCarouselButton(
                label: '다운받기',
                icon: Icons.download_rounded,
                color: tokens.info,
                onTap: () => _runOpsAction(
                  context,
                  label: '다운받기',
                  action: 'refresh_area_master',
                  operation: () => HeadHubActions.refreshAreaMaster(context),
                ),
                onLongPress: () => _showOpsDebugStatus(
                  context,
                  label: '다운받기',
                  action: 'refresh_area_master',
                ),
              ),
            ),
          ],
        );
      case 2:
      default:
        return Row(
          children: [
            Expanded(
              child: _OpsHqCarouselButton(
                label: '환경설정',
                icon: Icons.settings_rounded,
                color: tokens.accent,
                onTap: () => _runOpsAction(
                  context,
                  label: '환경설정',
                  action: 'open_service_settings',
                  operation: () => _openServiceSettings(context),
                ),
                onLongPress: () => _showOpsDebugStatus(
                  context,
                  label: '환경설정',
                  action: 'open_service_settings',
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _OpsHqCarouselButton(
                label: '로그아웃',
                icon: Icons.logout_rounded,
                color: tokens.danger,
                onTap: widget.showLogout
                    ? () => _runOpsAction(
                          context,
                          label: '로그아웃',
                          action: 'logout',
                          operation: () => _handleLogout(context),
                        )
                    : null,
                onLongPress: widget.showLogout
                    ? () => _showOpsDebugStatus(
                          context,
                          label: '로그아웃',
                          action: 'logout',
                        )
                    : null,
              ),
            ),
          ],
        );
    }
  }

  Widget _buildAnimatedOpsActionPage(
    BuildContext context, {
    required int page,
    required Widget child,
  }) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return child;

    return AnimatedBuilder(
      animation: _opsActionPageController,
      child: child,
      builder: (context, staticChild) {
        var currentPage = 1.0;
        if (_opsActionPageController.hasClients &&
            _opsActionPageController.position.hasContentDimensions) {
          currentPage = _opsActionPageController.page ?? 1.0;
        }
        final distance = (currentPage - page).abs().clamp(0.0, 1.0).toDouble();
        final visibility = 1.0 - distance;
        final opacity = 0.78 + (0.22 * visibility);
        final scale = 0.97 + (0.03 * visibility);
        final offsetY = 5.0 * distance;

        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, offsetY),
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.center,
              child: staticChild,
            ),
          ),
        );
      },
    );
  }

  Widget _buildOpsActionCarousel(
    BuildContext context,
    UserState userState,
  ) {
    return Column(
      children: [
        SizedBox(
          height: 60,
          child: PageView.builder(
            controller: _opsActionPageController,
            itemCount: _opsActionPageCount + 2,
            onPageChanged: _onOpsActionPageChanged,
            itemBuilder: (context, page) {
              final child = _buildOpsActionPage(
                context,
                userState,
                _logicalOpsActionPage(page),
              );
              return _buildAnimatedOpsActionPage(
                context,
                page: page,
                child: child,
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        _OpsHqPageDots(
          count: _opsActionPageCount,
          currentIndex: _opsActionPageIndex,
        ),
      ],
    );
  }

  Widget _buildOpsHeader(
    BuildContext context,
    UserState userState,
  ) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final name = _safe(userState.name);
    final position = _safe(userState.position);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tokens.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: tokens.shadow,
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: tokens.accentContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.apartment_rounded,
                    color: tokens.onAccentContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '본사 대시보드',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: (textTheme.titleLarge ??
                                    const TextStyle(fontSize: 22))
                                .copyWith(
                              color: tokens.textPrimary,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _OpsHqBadge(
                          label: _modeLabel(),
                          color: tokens.accentContainer,
                          foreground: tokens.onAccentContainer,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _OpsHqHeaderPill(
                            icon: Icons.person_rounded, text: name),
                        _OpsHqHeaderPill(
                            icon: Icons.badge_rounded, text: position),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildOpsActionCarousel(context, userState),
        ],
      ),
    );
  }

  Widget _buildMenuPanel(BuildContext context, UserState userState) {
    return _OpsHqPanel(
      title: '업무 메뉴',
      icon: Icons.dashboard_customize_rounded,
      child: _BranchSubscriptionStatusInlinePanel(
        key: _subscriptionPanelKey,
        screenName: widget.screenName,
        division: userState.division.trim(),
        headerKey: _subscriptionHeaderKey,
        onExpandedChanged: _handleSubscriptionExpandedChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    final showFloatingCollapse = _subscriptionExpanded &&
        _subscriptionHeaderOffscreen &&
        !_floatingCollapseBusy;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Scaffold(
      backgroundColor: tokens.canvas,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: AnimatedSwitcher(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 180),
        reverseDuration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 150),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: .96, end: 1).animate(curved),
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, .16),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            ),
          );
        },
        child: showFloatingCollapse
            ? _SubscriptionCollapseFloatingAction(
                key: const ValueKey<String>('subscription_collapse_floating'),
                onPressed: _handleFloatingSubscriptionCollapse,
                onLongPress: () {
                  final state = _subscriptionPanelKey.currentState;
                  if (state != null) {
                    state._showSubscriptionDebugStatus(state.context);
                  }
                },
              )
            : const SizedBox.shrink(
                key: ValueKey<String>('subscription_collapse_hidden'),
              ),
      ),
      body: SafeArea(
        bottom: false,
        child: Consumer<UserState>(
          builder: (context, userState, _) {
            return CustomScrollView(
              key: _dashboardViewportKey,
              controller: _dashboardScrollController,
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 18 + bottomInset),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate(
                      [
                        CommonAnimatedReveal(
                          child: _buildOpsHeader(context, userState),
                        ),
                        const SizedBox(height: 12),
                        CommonAnimatedReveal(
                          delay: const Duration(milliseconds: 70),
                          child: _buildMenuPanel(context, userState),
                        ),
                        const SizedBox(height: 18),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}


class _SubscriptionCollapseFloatingAction extends StatelessWidget {
  const _SubscriptionCollapseFloatingAction({
    super.key,
    required this.onPressed,
    required this.onLongPress,
  });

  final VoidCallback onPressed;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Semantics(
      button: true,
      label: '지사 별 구독 현황 접기',
      child: Tooltip(
        message: '지사 별 구독 현황 접기',
        child: Material(
          color: tokens.surfaceRaised,
          elevation: 4,
          shadowColor: tokens.shadow,
          borderRadius: BorderRadius.circular(CommonUiShapes.pill),
          child: InkWell(
            onTap: onPressed,
            onLongPress: onLongPress,
            borderRadius: BorderRadius.circular(CommonUiShapes.pill),
            overlayColor: WidgetStatePropertyAll(
              tokens.accent.withOpacity(.08),
            ),
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(CommonUiShapes.pill),
                border: Border.all(color: tokens.borderSubtle),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.keyboard_arrow_up_rounded,
                    size: 19,
                    color: tokens.accent,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '접기',
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OpsHqBadge extends StatelessWidget {
  const _OpsHqBadge({
    required this.label,
    required this.color,
    required this.foreground,
  });

  final String label;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: foreground,
          fontWeight: FontWeight.w900,
          fontSize: 12,
          letterSpacing: -.1,
        ),
      ),
    );
  }
}

class _OpsHqHeaderPill extends StatelessWidget {
  const _OpsHqHeaderPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 170),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: tokens.surfaceOverlay,
        borderRadius: BorderRadius.circular(CommonUiShapes.pill),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: tokens.iconSecondary),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OpsHqQuickButtonIndicator extends StatefulWidget {
  const _OpsHqQuickButtonIndicator({required this.enabled});

  final bool enabled;

  @override
  State<_OpsHqQuickButtonIndicator> createState() =>
      _OpsHqQuickButtonIndicatorState();
}

class _OpsHqQuickButtonIndicatorState extends State<_OpsHqQuickButtonIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    );
    _pulse = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
    if (widget.enabled) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _OpsHqQuickButtonIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      _syncAnimation();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  void _syncAnimation() {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (widget.enabled && !reduceMotion) {
      if (!_controller.isAnimating) {
        _controller.repeat(reverse: true);
      }
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final value = widget.enabled && !reduceMotion ? _pulse.value : 0.0;
        final color = widget.enabled ? tokens.warning : tokens.iconDisabled;

        return AnimatedContainer(
          duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
          curve: CommonUiMotion.standard,
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: widget.enabled
                ? tokens.warningContainer
                : tokens.surfaceDisabled,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: widget.enabled
                  ? tokens.warning.withOpacity(.62)
                  : tokens.borderSubtle,
            ),
            boxShadow: widget.enabled
                ? [
                    BoxShadow(
                      color: tokens.warning.withOpacity(.12 + (value * .12)),
                      blurRadius: 6 + (value * 6),
                      spreadRadius: value,
                    ),
                  ]
                : const [],
          ),
          child: Center(
            child: AnimatedScale(
              scale: widget.enabled ? 1 + (value * .08) : 1,
              duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
              curve: CommonUiMotion.enter,
              child: AnimatedSwitcher(
                duration:
                    reduceMotion ? Duration.zero : CommonUiMotion.selection,
                transitionBuilder: (child, animation) {
                  return ScaleTransition(
                    scale: animation,
                    child: FadeTransition(opacity: animation, child: child),
                  );
                },
                child: Icon(
                  widget.enabled
                      ? Icons.lightbulb_rounded
                      : Icons.lightbulb_outline_rounded,
                  key: ValueKey<bool>(widget.enabled),
                  color: color,
                  size: 19,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OpsHqCarouselButton extends StatefulWidget {
  const _OpsHqCarouselButton({
    required this.label,
    required this.icon,
    required this.color,
    this.leading,
    this.onTap,
    this.onLongPress,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Widget? leading;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<_OpsHqCarouselButton> createState() => _OpsHqCarouselButtonState();
}

class _OpsHqCarouselButtonState extends State<_OpsHqCarouselButton> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final enabled = widget.onTap != null;
    final background = !enabled
        ? tokens.surfaceDisabled
        : _pressed || _hovered
            ? tokens.surfaceSelected
            : tokens.surfaceOverlay;
    final foreground = enabled ? tokens.textPrimary : tokens.textDisabled;
    final iconColor = enabled ? widget.color : tokens.iconDisabled;

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
        curve: CommonUiMotion.standard,
        height: 60,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(CommonUiShapes.button),
          border: Border.all(
            color: _focused ? tokens.focusRing : tokens.borderSubtle,
            width: _focused ? 2 : 1,
          ),
          boxShadow: _hovered && enabled
              ? [
                  BoxShadow(
                    color: tokens.shadow,
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ]
              : const [],
        ),
        child: Material(
          color: tokens.transparent,
          borderRadius: BorderRadius.circular(CommonUiShapes.button),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            onHighlightChanged: (value) {
              if (_pressed == value) return;
              setState(() => _pressed = value);
            },
            onHover: (value) {
              if (_hovered == value) return;
              setState(() => _hovered = value);
            },
            onFocusChange: (value) {
              if (_focused == value) return;
              setState(() => _focused = value);
            },
            borderRadius: BorderRadius.circular(CommonUiShapes.button),
            overlayColor: WidgetStatePropertyAll(
              tokens.accent.withOpacity(_pressed ? .12 : .06),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: AnimatedScale(
                scale: _pressed && enabled ? .98 : 1,
                duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
                curve: CommonUiMotion.enter,
                child: Row(
                  children: [
                    widget.leading ??
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: enabled
                                ? widget.color.withOpacity(.14)
                                : tokens.surfaceDisabled,
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                              color: enabled
                                  ? widget.color.withOpacity(.34)
                                  : tokens.borderSubtle,
                            ),
                          ),
                          child: Icon(widget.icon, color: iconColor, size: 19),
                        ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.15,
                        ),
                      ),
                    ),
                    if (enabled) ...[
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: tokens.iconSecondary,
                        size: 17,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OpsHqPageDots extends StatelessWidget {
  const _OpsHqPageDots({
    required this.count,
    required this.currentIndex,
  });

  final int count;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final active = index == currentIndex;
        return AnimatedContainer(
          duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
          curve: CommonUiMotion.enter,
          width: active ? 8 : 6,
          height: active ? 8 : 6,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? tokens.accent : tokens.borderStrong,
          ),
        );
      }),
    );
  }
}

class _OpsHqPanel extends StatelessWidget {
  const _OpsHqPanel({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tokens.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: tokens.shadow.withOpacity(tokens.isDark ? .22 : .08),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: tokens.accentContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: tokens.onAccentContainer, size: 17),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _OpsHqActionTile extends StatefulWidget {
  const _OpsHqActionTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool danger;

  @override
  State<_OpsHqActionTile> createState() => _OpsHqActionTileState();
}

class _OpsHqActionTileState extends State<_OpsHqActionTile> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final enabled = widget.onTap != null;
    final effectiveColor = enabled ? widget.color : tokens.iconDisabled;
    final background = !enabled
        ? tokens.surfaceDisabled
        : _pressed || _hovered
            ? tokens.surfaceSelected
            : tokens.surface;
    final foreground = !enabled
        ? tokens.textDisabled
        : widget.danger
            ? tokens.danger
            : tokens.textPrimary;

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
        curve: CommonUiMotion.standard,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(CommonUiShapes.button),
          border: Border.all(
            color: _focused
                ? tokens.focusRing
                : widget.danger
                    ? tokens.danger.withOpacity(enabled ? .52 : .22)
                    : tokens.borderSubtle,
            width: _focused ? 2 : 1,
          ),
          boxShadow: _hovered && enabled
              ? [
                  BoxShadow(
                    color: tokens.shadow,
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ]
              : const [],
        ),
        child: Material(
          color: tokens.transparent,
          borderRadius: BorderRadius.circular(CommonUiShapes.button),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            onHighlightChanged: (value) {
              if (_pressed == value) return;
              setState(() => _pressed = value);
            },
            onHover: (value) {
              if (_hovered == value) return;
              setState(() => _hovered = value);
            },
            onFocusChange: (value) {
              if (_focused == value) return;
              setState(() => _focused = value);
            },
            overlayColor: WidgetStatePropertyAll(
              effectiveColor.withOpacity(_pressed ? .12 : .06),
            ),
            borderRadius: BorderRadius.circular(CommonUiShapes.button),
            child: SizedBox(
              height: 58,
              child: AnimatedScale(
                scale: _pressed && enabled ? .98 : 1,
                duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
                curve: CommonUiMotion.enter,
                child: Row(
                  children: [
                    Container(
                      width: 5,
                      decoration: BoxDecoration(
                        color: effectiveColor,
                        borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(CommonUiShapes.button),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: effectiveColor.withOpacity(.12),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: effectiveColor.withOpacity(.30),
                        ),
                      ),
                      child: Icon(
                        widget.icon,
                        color: effectiveColor,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.1,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: enabled
                            ? tokens.iconSecondary
                            : tokens.iconDisabled,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _DashboardMenuTone {
  primary,
  secondary,
  tertiary,
  neutral,
}

class HqDashBoardButtonStyles {
  static ButtonStyle clockOut(
    BuildContext context,
    HqDashBoardStylePreset preset,
  ) {
    final cs = Theme.of(context).colorScheme;

    switch (preset) {
      case HqDashBoardStylePreset.doubleLegacy:
        return ElevatedButton.styleFrom(
          backgroundColor: cs.surface,
          foregroundColor: cs.error,
          minimumSize: const Size.fromHeight(56),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          elevation: 0,
          side: BorderSide(color: cs.error.withOpacity(0.65), width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ).copyWith(
          overlayColor: MaterialStateProperty.resolveWith<Color?>(
            (states) => states.contains(MaterialState.pressed)
                ? cs.error.withOpacity(0.10)
                : null,
          ),
        );

      case HqDashBoardStylePreset.outlined:
        return ElevatedButton.styleFrom(
          backgroundColor: cs.errorContainer,
          foregroundColor: cs.onErrorContainer,
          minimumSize: const Size.fromHeight(56),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          elevation: 0,
          side: BorderSide(color: cs.error.withOpacity(0.16), width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ).copyWith(
          overlayColor: MaterialStateProperty.resolveWith<Color?>(
            (states) => states.contains(MaterialState.pressed)
                ? cs.error.withOpacity(0.08)
                : null,
          ),
        );
    }
  }

  static ButtonStyle menuTile(
    BuildContext context,
    _DashboardMenuTone tone,
    HqDashBoardStylePreset preset,
  ) {
    switch (preset) {
      case HqDashBoardStylePreset.doubleLegacy:
        return _legacyMenuTile(context, tone);
      case HqDashBoardStylePreset.outlined:
        return _tonalMenuTile(context, tone);
    }
  }

  static ButtonStyle utilityAccent(
    BuildContext context,
    HqDashBoardStylePreset preset,
  ) {
    final cs = Theme.of(context).colorScheme;

    switch (preset) {
      case HqDashBoardStylePreset.doubleLegacy:
        return ElevatedButton.styleFrom(
          backgroundColor: cs.surface,
          foregroundColor: cs.primary,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          elevation: 0,
          side: BorderSide(color: cs.primary.withOpacity(0.75), width: 1.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ).copyWith(
          overlayColor: MaterialStateProperty.resolveWith<Color?>(
            (states) => states.contains(MaterialState.pressed)
                ? cs.primary.withOpacity(0.08)
                : null,
          ),
        );

      case HqDashBoardStylePreset.outlined:
        return ElevatedButton.styleFrom(
          backgroundColor: cs.primaryContainer,
          foregroundColor: cs.onPrimaryContainer,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          elevation: 0,
          side: BorderSide(color: cs.primary.withOpacity(0.14), width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ).copyWith(
          overlayColor: MaterialStateProperty.resolveWith<Color?>(
            (states) => states.contains(MaterialState.pressed)
                ? cs.primary.withOpacity(0.08)
                : null,
          ),
        );
    }
  }

  static ButtonStyle utilityNeutral(
    BuildContext context,
    HqDashBoardStylePreset preset,
  ) {
    final cs = Theme.of(context).colorScheme;
    final overlay = preset == HqDashBoardStylePreset.doubleLegacy ? 0.14 : 0.10;
    final borderOpacity =
        preset == HqDashBoardStylePreset.doubleLegacy ? 0.24 : 0.18;

    return ElevatedButton.styleFrom(
      backgroundColor: cs.surface,
      foregroundColor: cs.onSurface,
      minimumSize: const Size.fromHeight(52),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      elevation: 0,
      side: BorderSide(color: cs.outline.withOpacity(borderOpacity), width: 1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    ).copyWith(
      overlayColor: MaterialStateProperty.resolveWith<Color?>(
        (states) => states.contains(MaterialState.pressed)
            ? cs.onSurface.withOpacity(overlay)
            : null,
      ),
    );
  }

  static ButtonStyle _legacyMenuTile(
    BuildContext context,
    _DashboardMenuTone tone,
  ) {
    final cs = Theme.of(context).colorScheme;

    late final Color fg;
    late final Color border;

    switch (tone) {
      case _DashboardMenuTone.primary:
        fg = cs.primary;
        border = cs.primary.withOpacity(0.35);
        break;
      case _DashboardMenuTone.secondary:
        fg = cs.secondary;
        border = cs.secondary.withOpacity(0.35);
        break;
      case _DashboardMenuTone.tertiary:
        fg = cs.tertiary;
        border = cs.tertiary.withOpacity(0.35);
        break;
      case _DashboardMenuTone.neutral:
        fg = cs.onSurface;
        border = cs.outline.withOpacity(0.20);
        break;
    }

    return ElevatedButton.styleFrom(
      backgroundColor: cs.surface,
      foregroundColor: fg,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      side: BorderSide(color: border, width: 1.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
    ).copyWith(
      overlayColor: MaterialStateProperty.resolveWith<Color?>(
        (states) => states.contains(MaterialState.pressed)
            ? fg.withOpacity(0.08)
            : null,
      ),
    );
  }

  static ButtonStyle _tonalMenuTile(
    BuildContext context,
    _DashboardMenuTone tone,
  ) {
    final cs = Theme.of(context).colorScheme;

    late final Color bg;
    late final Color fg;

    switch (tone) {
      case _DashboardMenuTone.primary:
        bg = cs.primaryContainer;
        fg = cs.onPrimaryContainer;
        break;
      case _DashboardMenuTone.secondary:
        bg = cs.secondaryContainer;
        fg = cs.onSecondaryContainer;
        break;
      case _DashboardMenuTone.tertiary:
        bg = cs.tertiaryContainer;
        fg = cs.onTertiaryContainer;
        break;
      case _DashboardMenuTone.neutral:
        bg = cs.surfaceVariant;
        fg = cs.onSurfaceVariant;
        break;
    }

    return ElevatedButton.styleFrom(
      backgroundColor: bg,
      foregroundColor: fg,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      side: BorderSide(color: fg.withOpacity(0.10), width: 1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
    ).copyWith(
      overlayColor: MaterialStateProperty.resolveWith<Color?>(
        (states) => states.contains(MaterialState.pressed)
            ? fg.withOpacity(0.08)
            : null,
      ),
    );
  }
}

class _BranchSubscriptionStatusInlinePanel extends StatefulWidget {
  const _BranchSubscriptionStatusInlinePanel({
    super.key,
    required this.screenName,
    required this.division,
    required this.headerKey,
    required this.onExpandedChanged,
  });

  final String screenName;
  final String division;
  final GlobalKey headerKey;
  final ValueChanged<bool> onExpandedChanged;

  @override
  State<_BranchSubscriptionStatusInlinePanel> createState() =>
      _BranchSubscriptionStatusInlinePanelState();
}

class _BranchSubscriptionStatusInlinePanelState
    extends State<_BranchSubscriptionStatusInlinePanel> {
  Future<_BranchSubscriptionStatusViewData>? _future;
  bool _hasRequestedLoad = false;
  bool _expanded = false;
  int _cachedAreaCount = 0;
  String _areaMasterRefreshedAtIso = '';
  List<_BranchSubscriptionStatusArea> _lastLoadedAreas =
      const <_BranchSubscriptionStatusArea>[];
  double _lastSubscriptionAvailableWidth = 0;
  int _lastSubscriptionColumns = 0;
  bool _lastSubscriptionCompactList = false;
  double _lastDashboardScrollOffset = 0;
  bool _lastHeaderOffscreen = false;
  bool _lastFloatingCollapseVisible = false;
  final List<String> _subscriptionDebugLines = <String>[];

  @override
  void initState() {
    super.initState();
    _restoreAreaMasterMeta();
  }

  @override
  void didUpdateWidget(covariant _BranchSubscriptionStatusInlinePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.division != widget.division) {
      _future = null;
      _hasRequestedLoad = false;
      _expanded = false;
      _cachedAreaCount = 0;
      _areaMasterRefreshedAtIso = '';
      _lastLoadedAreas = const <_BranchSubscriptionStatusArea>[];
      _lastSubscriptionAvailableWidth = 0;
      _lastSubscriptionColumns = 0;
      _lastSubscriptionCompactList = false;
      _lastDashboardScrollOffset = 0;
      _lastHeaderOffscreen = false;
      _lastFloatingCollapseVisible = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onExpandedChanged(false);
      });
      _recordSubscriptionDebug(
        'division_changed',
        meta: <String, Object?>{
          'from': oldWidget.division.trim(),
          'to': widget.division.trim(),
        },
      );
      _restoreAreaMasterMeta();
    }
  }

  String _subscriptionDebugMessage(
    String event, {
    Map<String, Object?> meta = const <String, Object?>{},
  }) {
    final division = widget.division.trim();
    final fields = <String>[
      '[HQ_SUBSCRIPTION]',
      'timestamp=${DateTime.now().toIso8601String()}',
      'screen=${widget.screenName}',
      'division=${division.isEmpty ? '-' : division}',
      'event=$event',
      ...meta.entries.map((entry) => '${entry.key}=${entry.value}'),
    ];
    return fields.join(' ');
  }

  void _recordSubscriptionDebug(
    String event, {
    Map<String, Object?> meta = const <String, Object?>{},
  }) {
    final message = _subscriptionDebugMessage(event, meta: meta);
    _subscriptionDebugLines.add(message);
    if (_subscriptionDebugLines.length > 120) {
      _subscriptionDebugLines.removeRange(
        0,
        _subscriptionDebugLines.length - 120,
      );
    }
    debugPrint(message);
  }

  Future<void> _showSubscriptionDebugStatus(BuildContext context) async {
    final developerMode = await DevAuth.isDevModeEnabled();
    if (!developerMode || !mounted || !context.mounted) return;

    final screenWidth = MediaQuery.sizeOf(context).width;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final availableWidth = _lastSubscriptionAvailableWidth;
    final compactList = _lastSubscriptionCompactList;
    final layoutColumns = _lastSubscriptionColumns;
    final layout = availableWidth > 0 && layoutColumns > 0
        ? (compactList ? 'compact_list' : 'grid')
        : 'unmeasured';

    _recordSubscriptionDebug(
      'status_open',
      meta: <String, Object?>{
        'expanded': _expanded,
        'cachedAreaCount': _cachedAreaCount,
        'loadedAreaCount': _lastLoadedAreas.length,
        'areaMasterRefreshedAt':
            _formatAreaMasterRefreshAt(_areaMasterRefreshedAtIso),
        'layout': layout,
        'columns': layoutColumns,
        'screenWidth': screenWidth.toStringAsFixed(1),
        'availableWidth': availableWidth > 0
            ? availableWidth.toStringAsFixed(1)
            : '-',
        'reduceMotion': reduceMotion,
        'scrollOffset': _lastDashboardScrollOffset.toStringAsFixed(1),
        'headerOffscreen': _lastHeaderOffscreen,
        'floatingCollapseVisible': _lastFloatingCollapseVisible,
        'floatingAlignment': 'center',
      },
    );

    final snapshot = <String>[
      ..._subscriptionDebugLines,
      _subscriptionDebugMessage(
        'status_snapshot',
        meta: <String, Object?>{
          'expanded': _expanded,
          'hasRequestedLoad': _hasRequestedLoad,
          'cachedAreaCount': _cachedAreaCount,
          'loadedAreaCount': _lastLoadedAreas.length,
          'areaMasterRefreshedAtIso':
              _areaMasterRefreshedAtIso.trim().isEmpty
                  ? '-'
                  : _areaMasterRefreshedAtIso.trim(),
          'layout': layout,
          'columns': layoutColumns,
          'screenWidth': screenWidth.toStringAsFixed(1),
          'availableWidth': availableWidth > 0
              ? availableWidth.toStringAsFixed(1)
              : '-',
          'reduceMotion': reduceMotion,
          'scrollOffset': _lastDashboardScrollOffset.toStringAsFixed(1),
          'headerOffscreen': _lastHeaderOffscreen,
          'floatingCollapseVisible': _lastFloatingCollapseVisible,
        'floatingAlignment': 'center',
        },
      ),
      for (final area in _lastLoadedAreas)
        _subscriptionDebugMessage(
          'area_snapshot',
          meta: <String, Object?>{
            'area': area.areaName,
            'modes': area.visibleModes.isEmpty
                ? '-'
                : area.visibleModes.join(','),
            'allowedCapabilityCount': area.allowedCapabilityCount,
            'capabilities': _capabilityDisplayOrder
                .map(
                  (item) =>
                      '${item.label}:${area.capabilities.contains(item) ? 'on' : 'off'}',
                )
                .join(','),
          },
        ),
    ];
    final code = snapshot
        .map((line) => 'debugPrint(${jsonEncode(line)});')
        .join('\n');

    HapticFeedback.mediumImpact();
    await StatusDialog.showSuccess(
      context,
      title: '지사 별 구독 현황 상태',
      description: '현재 구독 현황의 debugPrint 코드를 복사할 수 있습니다.',
      copyText: code,
      copyButtonLabel: 'debugPrint 복사',
      visibleDuration: const Duration(seconds: 30),
      useCommonUi: true,
    );
  }

  void _handleSubscriptionLayoutMetrics(
    double availableWidth,
    int columns,
    bool compactList,
  ) {
    final widthChanged =
        (_lastSubscriptionAvailableWidth - availableWidth).abs() >= .5;
    final columnsChanged = _lastSubscriptionColumns != columns;
    final compactChanged = _lastSubscriptionCompactList != compactList;
    _lastSubscriptionAvailableWidth = availableWidth;
    _lastSubscriptionColumns = columns;
    _lastSubscriptionCompactList = compactList;
    if (!widthChanged && !columnsChanged && !compactChanged) return;
    _recordSubscriptionDebug(
      'layout_metrics',
      meta: <String, Object?>{
        'availableWidth': availableWidth.toStringAsFixed(1),
        'layout': compactList ? 'compact_list' : 'grid',
        'columns': columns,
      },
    );
  }

  void _updateFloatingControlDiagnostics({
    required double scrollOffset,
    required bool headerOffscreen,
    required bool floatingVisible,
  }) {
    final visibilityChanged =
        _lastFloatingCollapseVisible != floatingVisible;
    _lastDashboardScrollOffset = scrollOffset;
    _lastHeaderOffscreen = headerOffscreen;
    _lastFloatingCollapseVisible = floatingVisible;
    if (!visibilityChanged) return;
    _recordSubscriptionDebug(
      floatingVisible
          ? 'floating_collapse_visible'
          : 'floating_collapse_hidden',
      meta: <String, Object?>{
        'scrollOffset': scrollOffset.toStringAsFixed(1),
        'headerOffscreen': headerOffscreen,
        'alignment': 'center',
      },
    );
  }

  List<AreaMasterItem> _filterBranchItems({
    required List<AreaMasterItem> items,
    required String division,
  }) {
    final normalizedDivision = division.trim();
    final byName = <String, AreaMasterItem>{};

    for (final item in items) {
      final name = item.name.trim();
      if (name.isEmpty) continue;
      if (item.isHeadquarter) continue;
      if (name == normalizedDivision) continue;
      byName[name] = item;
    }

    final filtered = byName.values.toList(growable: false);
    filtered.sort((a, b) => a.name.compareTo(b.name));
    return filtered;
  }

  Future<void> _restoreAreaMasterMeta() async {
    final division = widget.division.trim();
    if (division.isEmpty) {
      _recordSubscriptionDebug('meta_restore_skipped_empty_division');
      return;
    }

    _recordSubscriptionDebug('meta_restore_start');
    try {
      final snapshot = await AreaMasterCache.readSnapshot(division);
      final branchItems = snapshot == null
          ? const <AreaMasterItem>[]
          : _filterBranchItems(
              items: snapshot.items,
              division: division,
            );

      if (!mounted) return;

      setState(() {
        _cachedAreaCount = branchItems.length;
        _areaMasterRefreshedAtIso = snapshot?.refreshedAtIso ?? '';
      });
      _recordSubscriptionDebug(
        'meta_restore_complete',
        meta: <String, Object?>{
          'hasCache': snapshot != null,
          'areaCount': branchItems.length,
          'refreshedAt': snapshot?.refreshedAtIso ?? '-',
        },
      );
    } catch (error, stackTrace) {
      _recordSubscriptionDebug(
        'meta_restore_failure',
        meta: <String, Object?>{
          'error': error,
          'stackTrace': stackTrace,
        },
      );
    }
  }

  _BranchSubscriptionStatusArea _buildArea(AreaMasterItem item) {
    final normalizedModes = item.modes
        .map((mode) => mode.trim().toLowerCase())
        .where((mode) => mode.isNotEmpty)
        .toSet()
        .toList(growable: false);
    normalizedModes.sort();

    return _BranchSubscriptionStatusArea(
      areaName: item.name.trim(),
      modes: List<String>.unmodifiable(normalizedModes),
      capabilities: Set<Capability>.unmodifiable(item.capabilities),
    );
  }

  Future<_BranchSubscriptionStatusViewData> _load() async {
    final division = widget.division.trim();

    if (division.isEmpty) {
      return const _BranchSubscriptionStatusViewData(
        division: '',
        areas: <_BranchSubscriptionStatusArea>[],
        hasAreaMasterCache: false,
        areaMasterRefreshedAtIso: '',
      );
    }

    final snapshot = await AreaMasterCache.readSnapshot(division);
    if (snapshot == null) {
      return _BranchSubscriptionStatusViewData(
        division: division,
        areas: const <_BranchSubscriptionStatusArea>[],
        hasAreaMasterCache: false,
        areaMasterRefreshedAtIso: '',
      );
    }

    final branchItems = _filterBranchItems(
      items: snapshot.items,
      division: division,
    );

    final areas = branchItems
        .map(_buildArea)
        .toList(growable: false);

    return _BranchSubscriptionStatusViewData(
      division: division,
      areas: areas,
      hasAreaMasterCache: true,
      areaMasterRefreshedAtIso: snapshot.refreshedAtIso,
    );
  }

  Future<_BranchSubscriptionStatusViewData> _loadAndSyncMeta() async {
    _recordSubscriptionDebug('load_start');
    try {
      final data = await _load();
      if (!mounted) return data;
      setState(() {
        _cachedAreaCount = data.areas.length;
        _areaMasterRefreshedAtIso = data.areaMasterRefreshedAtIso;
        _lastLoadedAreas = data.areas;
      });
      _recordSubscriptionDebug(
        'load_complete',
        meta: <String, Object?>{
          'hasCache': data.hasAreaMasterCache,
          'areaCount': data.areas.length,
          'refreshedAt': data.areaMasterRefreshedAtIso.isEmpty
              ? '-'
              : data.areaMasterRefreshedAtIso,
        },
      );
      return data;
    } catch (error, stackTrace) {
      _recordSubscriptionDebug(
        'load_failure',
        meta: <String, Object?>{
          'error': error,
          'stackTrace': stackTrace,
        },
      );
      rethrow;
    }
  }

  void _toggleExpanded() {
    final next = !_expanded;
    _recordSubscriptionDebug(
      'toggle',
      meta: <String, Object?>{'expanded': next},
    );
    setState(() {
      _expanded = next;
      if (next) {
        _hasRequestedLoad = true;
        _future = _loadAndSyncMeta();
      }
    });
    widget.onExpandedChanged(next);
    HapticFeedback.selectionClick();
  }

  void _collapse({
    String source = 'inline_button',
    bool haptic = true,
  }) {
    if (!_expanded) return;
    _recordSubscriptionDebug(
      'collapse',
      meta: <String, Object?>{
        'expanded': false,
        'source': source,
      },
    );
    setState(() {
      _expanded = false;
    });
    widget.onExpandedChanged(false);
    if (haptic) HapticFeedback.selectionClick();
    if (source == 'floating_action') {
      _recordSubscriptionDebug(
        'floating_collapse_complete',
        meta: <String, Object?>{
          'scrollOffset': _lastDashboardScrollOffset.toStringAsFixed(1),
        },
      );
    }
  }

  Widget _buildTopBar(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final statusLabel = _expanded ? '접기' : '펼치기';
    final statusIcon = _expanded
        ? Icons.keyboard_arrow_up_rounded
        : Icons.keyboard_arrow_down_rounded;

    return Semantics(
      key: widget.headerKey,
      button: true,
      label: '지사 별 구독 현황 $statusLabel',
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
        curve: CommonUiMotion.standard,
        decoration: BoxDecoration(
          color: _expanded ? tokens.surfaceSelected : tokens.surfaceOverlay,
          borderRadius: BorderRadius.circular(CommonUiShapes.card),
          border: Border.all(
            color: _expanded ? tokens.accent : tokens.borderSubtle,
          ),
        ),
        child: Material(
          color: tokens.transparent,
          borderRadius: BorderRadius.circular(CommonUiShapes.card),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _toggleExpanded,
            onLongPress: () => _showSubscriptionDebugStatus(context),
            borderRadius: BorderRadius.circular(CommonUiShapes.card),
            overlayColor: WidgetStatePropertyAll(
              tokens.accent.withOpacity(.08),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration:
                        reduceMotion ? Duration.zero : CommonUiMotion.selection,
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _expanded ? tokens.accent : tokens.accentContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.domain_rounded,
                      color: _expanded
                          ? tokens.onAccent
                          : tokens.onAccentContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '지사 별 구독 현황',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: (textTheme.titleMedium ??
                                  const TextStyle(fontSize: 16))
                              .copyWith(
                            fontWeight: FontWeight.w900,
                            color: tokens.textPrimary,
                            letterSpacing: -.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '마스터 ${_formatAreaMasterRefreshAt(_areaMasterRefreshedAtIso)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: tokens.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _BranchHeaderPill(
                    icon: Icons.sd_storage_rounded,
                    label: '$_cachedAreaCount',
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: tokens.surface,
                      borderRadius: BorderRadius.circular(CommonUiShapes.pill),
                      border: Border.all(color: tokens.borderSubtle),
                    ),
                    child: AnimatedSwitcher(
                      duration: reduceMotion
                          ? Duration.zero
                          : CommonUiMotion.selection,
                      transitionBuilder: (child, animation) {
                        return ScaleTransition(
                          scale: animation,
                          child: FadeTransition(
                            opacity: animation,
                            child: child,
                          ),
                        );
                      },
                      child: Icon(
                        statusIcon,
                        key: ValueKey<bool>(_expanded),
                        size: 22,
                        color: tokens.iconSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: _BranchStateCard(
        icon: Icons.storage_rounded,
        label: '구독 현황을 불러오는 중입니다.',
        loading: true,
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: _BranchStateCard(
        icon: Icons.error_outline_rounded,
        label: '구독 현황을 불러오지 못했습니다.',
        description: '상단 다운받기 후 다시 확인하세요.',
      ),
    );
  }

  Widget _buildEmptyDivisionState(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: _BranchStateCard(
        icon: Icons.badge_outlined,
        label: 'division 정보가 없습니다.',
      ),
    );
  }

  Widget _buildLoadedState(
    BuildContext context,
    _BranchSubscriptionStatusViewData data,
  ) {
    if (!data.hasAreaMasterCache) {
      return const _BranchStateCard(
        icon: Icons.cloud_download_outlined,
        label: '저장된 지역 마스터가 없습니다.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _BranchSubscriptionLegend(),
        const SizedBox(height: 12),
        data.areas.isEmpty
            ? const _BranchStateCard(
                icon: Icons.location_off_rounded,
                label: '표시할 지사 지역이 없습니다.',
              )
            : _BranchSectionFrame(
                title: '지사',
                child: _BranchAreaCollection(
                  areas: data.areas,
                  onLayoutMetrics: _handleSubscriptionLayoutMetrics,
                ),
              ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    if (!_hasRequestedLoad || _future == null) {
      return const _BranchGuideCard();
    }

    return FutureBuilder<_BranchSubscriptionStatusViewData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _buildLoadingState(context);
        }

        if (snapshot.hasError) {
          return _buildErrorState(context);
        }

        final data = snapshot.data ??
            const _BranchSubscriptionStatusViewData(
              division: '',
              areas: <_BranchSubscriptionStatusArea>[],
              hasAreaMasterCache: false,
              areaMasterRefreshedAtIso: '',
            );

        if (data.division.isEmpty) {
          return _buildEmptyDivisionState(context);
        }

        return _buildLoadedState(context, data);
      },
    );
  }

  Widget _buildExpandedContent(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedSize(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: _expanded
          ? Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AnimatedSwitcher(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: KeyedSubtree(
                      key: ValueKey<Future<_BranchSubscriptionStatusViewData>?>(
                        _future,
                      ),
                      child: _buildBody(context),
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTopBar(context),
        _buildExpandedContent(context),
        const SizedBox(height: 12),
        const HeadquarterCalendarCard(useCommonUi: true),
      ],
    );
  }
}

class _BranchHeaderPill extends StatelessWidget {
  const _BranchHeaderPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(CommonUiShapes.pill),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: tokens.iconSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _BranchSectionFrame extends StatelessWidget {
  const _BranchSectionFrame({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.domain_rounded,
                    color: cs.onPrimaryContainer, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _BranchSubscriptionLegend extends StatelessWidget {
  const _BranchSubscriptionLegend();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 400;
        final modeItems = <Widget>[
          for (final mode in const <String>['single', 'double', 'triple', 'minor'])
            _BranchModeLegendItem(
              icon: _modeIcon(mode),
              label: _modeLabel(mode),
              compact: compact,
            ),
        ];
        final capabilityItems = <Widget>[
          for (final capability in _capabilityDisplayOrder)
            _BranchCapabilityLegendItem(
              icon: _capabilityIcon(capability),
              label: capability.label,
              compact: compact,
            ),
          _BranchCapabilityStateLegend(
            allowed: true,
            label: '허용',
            compact: compact,
          ),
          _BranchCapabilityStateLegend(
            allowed: false,
            label: '비허용',
            compact: compact,
          ),
        ];

        return Container(
          padding: EdgeInsets.all(compact ? 9 : 10),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: cs.outlineVariant.withOpacity(.55),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: compact ? 5 : 7,
                runSpacing: compact ? 5 : 7,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: modeItems,
              ),
              SizedBox(height: compact ? 6 : 8),
              Wrap(
                spacing: compact ? 5 : 7,
                runSpacing: compact ? 5 : 7,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: capabilityItems,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BranchModeLegendItem extends StatelessWidget {
  const _BranchModeLegendItem({
    required this.icon,
    required this.label,
    required this.compact,
  });

  final IconData icon;
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Semantics(
      label: label,
      child: Container(
        height: compact ? 30 : 34,
        padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 9),
        decoration: BoxDecoration(
          color: cs.primaryContainer.withOpacity(.62),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: cs.primary.withOpacity(.24),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: compact ? 14 : 16,
              color: cs.onPrimaryContainer,
            ),
            SizedBox(width: compact ? 4 : 6),
            Text(
              label,
              style: TextStyle(
                color: cs.onPrimaryContainer,
                fontWeight: FontWeight.w800,
                fontSize: compact ? 11 : 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BranchCapabilityLegendItem extends StatelessWidget {
  const _BranchCapabilityLegendItem({
    required this.icon,
    required this.label,
    required this.compact,
  });

  final IconData icon;
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Semantics(
      label: label,
      child: Container(
        height: compact ? 30 : 34,
        padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 9),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(.62),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: cs.outlineVariant.withOpacity(.55),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: compact ? 14 : 16,
              color: cs.onSurfaceVariant,
            ),
            SizedBox(width: compact ? 4 : 6),
            Text(
              label,
              style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.w800,
                fontSize: compact ? 11 : 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BranchCapabilityStateLegend extends StatelessWidget {
  const _BranchCapabilityStateLegend({
    required this.allowed,
    required this.label,
    required this.compact,
  });

  final bool allowed;
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final color = allowed ? tokens.success : tokens.danger;
    final background =
        allowed ? tokens.successContainer : tokens.dangerContainer;

    return Semantics(
      label: label,
      child: Container(
        height: compact ? 30 : 34,
        padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 9),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: color.withOpacity(.50)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              allowed ? Icons.check_circle_rounded : Icons.cancel_rounded,
              size: compact ? 14 : 16,
              color: color,
            ),
            SizedBox(width: compact ? 4 : 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: compact ? 11 : 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BranchGuideCard extends StatelessWidget {
  const _BranchGuideCard();

  @override
  Widget build(BuildContext context) {
    return const _BranchSubscriptionLegend();
  }
}

class _BranchStateCard extends StatelessWidget {
  const _BranchStateCard({
    required this.icon,
    required this.label,
    this.description,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final String? description;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: cs.outlineVariant.withOpacity(0.55),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(15),
            ),
            child: loading
                ? Padding(
                    padding: const EdgeInsets.all(11),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: cs.onPrimaryContainer,
                    ),
                  )
                : Icon(icon, color: cs.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: (tt.titleMedium ?? const TextStyle(fontSize: 16))
                      .copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (description != null && description!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BranchSubscriptionStatusViewData {
  const _BranchSubscriptionStatusViewData({
    required this.division,
    required this.areas,
    required this.hasAreaMasterCache,
    required this.areaMasterRefreshedAtIso,
  });

  final String division;
  final List<_BranchSubscriptionStatusArea> areas;
  final bool hasAreaMasterCache;
  final String areaMasterRefreshedAtIso;
}

class _BranchSubscriptionStatusArea {
  const _BranchSubscriptionStatusArea({
    required this.areaName,
    required this.modes,
    required this.capabilities,
  });

  final String areaName;
  final List<String> modes;
  final CapSet capabilities;

  List<String> get visibleModes =>
      modes.where((mode) => mode != 'record').toList(growable: false);

  int get allowedCapabilityCount => _capabilityDisplayOrder
      .where(capabilities.contains)
      .length;
}

int _subscriptionGridColumnsForAvailableWidth(double width) {
  const minCardWidth = 196.0;
  const gap = 8.0;
  final raw = ((width + gap) / (minCardWidth + gap)).floor();
  if (raw < 1) return 1;
  if (raw > 4) return 4;
  return raw;
}

String _formatAreaMasterRefreshAt(String iso) {
  final raw = iso.trim();
  if (raw.isEmpty) return '-';
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return '-';
  final local = parsed.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$month.$day $hour:$minute';
}

const List<Capability> _capabilityDisplayOrder = <Capability>[
  Capability.location,
  Capability.sector,
  Capability.tablet,
  Capability.monthly,
  Capability.bill,
  Capability.record,
];

IconData _capabilityIcon(Capability capability) {
  switch (capability) {
    case Capability.location:
      return Icons.location_on_rounded;
    case Capability.sector:
      return Icons.hub_rounded;
    case Capability.tablet:
      return Icons.tablet_mac_rounded;
    case Capability.monthly:
      return Icons.calendar_month_rounded;
    case Capability.bill:
      return Icons.receipt_long_rounded;
    case Capability.record:
      return Icons.record_voice_over_rounded;
  }
}

IconData _modeIcon(String mode) {
  switch (mode.trim().toLowerCase()) {
    case 'single':
      return Icons.looks_one_rounded;
    case 'double':
      return Icons.filter_2_rounded;
    case 'triple':
      return Icons.filter_3_rounded;
    case 'minor':
      return Icons.account_tree_rounded;
    default:
      return Icons.extension_rounded;
  }
}

String _modeLabel(String mode) {
  switch (mode.trim().toLowerCase()) {
    case 'single':
      return '싱글 모드';
    case 'double':
      return '더블 모드';
    case 'triple':
      return '트리플 모드';
    case 'minor':
      return '마이너 모드';
    default:
      return mode.trim();
  }
}

class _BranchAreaCollection extends StatelessWidget {
  const _BranchAreaCollection({
    required this.areas,
    required this.onLayoutMetrics,
  });

  final List<_BranchSubscriptionStatusArea> areas;
  final void Function(double availableWidth, int columns, bool compactList)
      onLayoutMetrics;

  int _delayFor(int index) {
    if (index <= 0) return 0;
    if (index == 1) return 25;
    if (index == 2) return 50;
    return 75;
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final columns =
            _subscriptionGridColumnsForAvailableWidth(availableWidth);
        final compactList = columns == 1;
        onLayoutMetrics(availableWidth, columns, compactList);

        if (compactList) {
          return AnimatedSize(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Column(
              children: List<Widget>.generate(
                areas.length,
                (index) {
                  final area = areas[index];
                  return Column(
                    children: [
                      CommonAnimatedReveal(
                        key: ValueKey<String>(
                          'subscription-area-compact-${area.areaName}',
                        ),
                        delay: reduceMotion
                            ? Duration.zero
                            : Duration(milliseconds: _delayFor(index)),
                        offset: const Offset(0, .018),
                        child: _BranchAreaCompactRow(item: area),
                      ),
                      if (index != areas.length - 1)
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withOpacity(.45),
                        ),
                    ],
                  );
                },
                growable: false,
              ),
            ),
          );
        }

        return AnimatedSize(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: areas.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              mainAxisExtent: 132,
            ),
            itemBuilder: (context, index) {
              final area = areas[index];
              return CommonAnimatedReveal(
                key: ValueKey<String>(
                  'subscription-area-grid-${area.areaName}',
                ),
                delay: reduceMotion
                    ? Duration.zero
                    : Duration(milliseconds: _delayFor(index)),
                offset: const Offset(0, .018),
                child: _BranchAreaGridCard(item: area),
              );
            },
          ),
        );
      },
    );
  }
}

class _BranchAreaCompactRow extends StatelessWidget {
  const _BranchAreaCompactRow({required this.item});

  final _BranchSubscriptionStatusArea item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Semantics(
      container: true,
      label:
          '${item.areaName}, 모드 ${item.visibleModes.length}개, 기능 ${item.allowedCapabilityCount}/${_capabilityDisplayOrder.length}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    Icons.store_mall_directory_rounded,
                    size: 15,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Tooltip(
                    message: item.areaName,
                    child: Text(
                      item.areaName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _BranchCapabilitySummaryPill(item: item),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 4,
                  child: _BranchModeStrip(
                    modes: item.visibleModes,
                    iconSize: 22,
                    alignment: WrapAlignment.start,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 6,
                  child: _BranchCapabilityStrip(
                    capabilities: item.capabilities,
                    iconSize: 20,
                    alignment: WrapAlignment.start,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BranchAreaGridCard extends StatelessWidget {
  const _BranchAreaGridCard({required this.item});

  final _BranchSubscriptionStatusArea item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Semantics(
      container: true,
      label:
          '${item.areaName}, 모드 ${item.visibleModes.length}개, 기능 ${item.allowedCapabilityCount}/${_capabilityDisplayOrder.length}',
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: cs.outlineVariant.withOpacity(.55),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.store_mall_directory_rounded,
                    size: 14,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Tooltip(
                    message: item.areaName,
                    child: Text(
                      item.areaName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _BranchCapabilitySummaryPill(item: item),
              ],
            ),
            const SizedBox(height: 6),
            _BranchModeStrip(
              modes: item.visibleModes,
              iconSize: 22,
              alignment: WrapAlignment.start,
            ),
            const SizedBox(height: 6),
            _BranchCapabilityStrip(
              capabilities: item.capabilities,
              iconSize: 20,
              alignment: WrapAlignment.start,
            ),
          ],
        ),
      ),
    );
  }
}

class _BranchCapabilitySummaryPill extends StatelessWidget {
  const _BranchCapabilitySummaryPill({required this.item});

  final _BranchSubscriptionStatusArea item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final allowed = item.allowedCapabilityCount;
    final total = _capabilityDisplayOrder.length;

    return Semantics(
      label: '기능 $total개 중 $allowed개 허용',
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.primaryContainer.withOpacity(.72),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: cs.primary.withOpacity(.24),
          ),
        ),
        child: Text(
          '$allowed/$total',
          style: TextStyle(
            color: cs.onPrimaryContainer,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _BranchModeStrip extends StatelessWidget {
  const _BranchModeStrip({
    required this.modes,
    required this.iconSize,
    this.alignment = WrapAlignment.start,
  });

  final List<String> modes;
  final double iconSize;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    if (modes.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Icon(
          Icons.remove_rounded,
          size: iconSize,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Wrap(
      alignment: alignment,
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final mode in modes)
          _AllowedModeIcon(
            icon: _modeIcon(mode),
            label: _modeLabel(mode),
            size: iconSize,
            iconSize: iconSize <= 22 ? 13 : 15,
          ),
      ],
    );
  }
}

class _BranchCapabilityStrip extends StatelessWidget {
  const _BranchCapabilityStrip({
    required this.capabilities,
    required this.iconSize,
    this.alignment = WrapAlignment.end,
  });

  final CapSet capabilities;
  final double iconSize;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: alignment,
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final capability in _capabilityDisplayOrder)
          _CapabilityStatusIcon(
            icon: _capabilityIcon(capability),
            label: capability.label,
            allowed: capabilities.contains(capability),
            size: iconSize,
            iconSize: iconSize <= 20 ? 12 : 14,
          ),
      ],
    );
  }
}

class _AllowedModeIcon extends StatelessWidget {
  const _AllowedModeIcon({
    required this.icon,
    required this.label,
    this.size = 28,
    this.iconSize = 16,
  });

  final IconData icon;
  final String label;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Semantics(
      label: '$label 허용',
      child: Tooltip(
        message: '$label · 허용',
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: cs.primaryContainer.withOpacity(.72),
            borderRadius: BorderRadius.circular(size <= 22 ? 6 : 8),
            border: Border.all(
              color: cs.primary.withOpacity(.30),
            ),
          ),
          child: Icon(
            icon,
            size: iconSize,
            color: cs.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}

class _CapabilityStatusIcon extends StatelessWidget {
  const _CapabilityStatusIcon({
    required this.icon,
    required this.label,
    required this.allowed,
    this.size = 28,
    this.iconSize = 16,
  });

  final IconData icon;
  final String label;
  final bool allowed;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final color = allowed ? tokens.success : tokens.danger;
    final background =
        allowed ? tokens.successContainer : tokens.dangerContainer;
    final status = allowed ? '허용' : '비허용';
    final markerSize = size <= 20 ? 4.5 : 6.0;

    return Semantics(
      label: '$label $status',
      child: Tooltip(
        message: '$label · $status',
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(size <= 20 ? 6 : 8),
            border: Border.all(
              color: color.withOpacity(.55),
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(
                icon,
                size: iconSize,
                color: color,
              ),
              if (!allowed)
                Positioned(
                  right: size <= 20 ? 1.5 : 2,
                  bottom: size <= 20 ? 1.5 : 2,
                  child: Container(
                    width: markerSize,
                    height: markerSize,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
