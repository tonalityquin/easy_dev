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
import '../../../../app/utils/ops_delayed_refresh_gate.dart';
import '../../../../app/utils/snackbar_helper.dart';
import '../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../../account/applications/user_state.dart';
import '../../../chat/application/chat_area_key.dart';
import '../../../chat/presentation/area_chat_panel.dart';
import '../../application/area/area_master_cache.dart';
import '../../page/sheets/company_calendar_page.dart';
import '../../page/sheets/head_memo.dart';
import '../../page/sheets/head_tutorials.dart';
import '../../page/sheets/roadmap_bottom_sheet.dart';
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

  static BuildContext? currentContext() => _bestContext();

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

  static Future<bool> openContactForm([BuildContext? context]) async {
    final uri = Uri.tryParse(contactFormUrl.trim());
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
          '문의하기 화면을 열 수 없습니다.',
          usePromptUi: true,
        );
      }
    }

    return opened;
  }


  static Future<void> openHeadquarterChat([BuildContext? context]) async {
    final ctx = context ?? _bestContext();
    if (ctx == null) return;

    await openSheetExclusively<void>(
      (sheetContext) {
        return AreaChatPanel.showSheet(
          context: sheetContext,
          areaName: headquarterChatAreaName,
          usePromptUi: true,
        );
      },
      context: ctx,
    );
  }

  static Future<void> refreshAreaMaster([
    BuildContext? context,
  ]) async {
    final ctx = context ?? _bestContext();
    if (ctx == null) return;

    final division = ctx.read<UserState>().division.trim();
    if (division.isEmpty) return;

    final shouldRefresh = await OpsDelayedRefreshGate.waitIfNeeded(
      context: ctx,
      title: '지역 마스터 갱신',
      message: '지역 마스터를 갱신하기 전 요청을 준비하고 있습니다.',
      usePromptUi: true,
    );
    if (!shouldRefresh) return;

    try {
      final snapshot = await AreaMasterCache.refreshDivision(division);
      if (!ctx.mounted) return;

      await showPromptDialog<void>(
        context: ctx,
        barrierDismissible: false,
        builder: (dialogContext) {
          final tokens = PromptUiTheme.of(dialogContext);
          final text = Theme.of(dialogContext).textTheme;
          return ConstrainedBox(
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
                            BorderRadius.circular(PromptUiShapes.control),
                      ),
                      child: Icon(
                        Icons.cloud_done_rounded,
                        color: tokens.onSuccessContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '지역 마스터 갱신 완료',
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
                        BorderRadius.circular(PromptUiShapes.control),
                    border: Border.all(color: tokens.borderSubtle),
                  ),
                  child: Text(
                    '기존 지역 마스터를 삭제하고 '
                    '${snapshot.items.length}개 지역 정보를 새로 저장했습니다.\n\n'
                    '변경 사항 적용을 위해 앱을 종료합니다. '
                    '앱을 다시 실행해 주세요.',
                    style: text.bodyMedium?.copyWith(
                      color: tokens.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                PromptButton(
                  label: '확인 및 종료',
                  icon: Icons.power_settings_new_rounded,
                  expand: true,
                  haptic: PromptHaptic.selection,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            ),
          );
        },
      );

      final exitContext = _bestContext();
      if (exitContext == null || !exitContext.mounted) return;
      await AppExitService.exitApp(exitContext, usePromptUi: true);
    } catch (_) {
      if (!ctx.mounted) return;
      showFailedSnackbar(
        ctx,
        '지역 마스터 갱신에 실패했습니다.',
        usePromptUi: true,
      );
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
      builder: (context) => PromptUiScope(
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

class _HubBubbleState extends State<_HubBubble>
    with SingleTickerProviderStateMixin {
  static const double _handleTouchWidth = 44;
  static const double _handleVisualWidth = 18;
  static const double _handleHeight = 56;
  static const double _dockRadius = 18;
  static const double _gameTouchWidth = 34;
  static const double _gameHeight = 64;
  static const double _bubbleGap = 12;

  late Offset _pos;
  bool _clampedOnce = false;

  late final AnimationController _ctrl;
  late final Animation<double> _t;

  bool get _expanded => _ctrl.value > 0.001;

  bool _developerMode = false;

  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _pos = widget.initialPos;
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _t = CurvedAnimation(
      parent: _ctrl,
      curve: const SpringCurve(),
      reverseCurve: Curves.easeInCubic,
    )..addListener(() => setState(() {}));
    _searchCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _refreshDeveloperMode();
  }

  Future<void> _refreshDeveloperMode() async {
    final enabled = await DevAuth.isDeveloperLoggedIn();
    if (!mounted) return;
    if (_developerMode == enabled) return;
    setState(() => _developerMode = enabled);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _toggleMenu() {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_expanded) {
      _searchFocus.unfocus();
      if (reduceMotion) {
        _ctrl.value = 0;
      } else {
        _ctrl.reverse();
      }
    } else {
      _refreshDeveloperMode();
      _searchCtrl.clear();
      if (reduceMotion) {
        _ctrl.value = 1;
      } else {
        _ctrl.forward();
      }
    }
    HapticFeedback.lightImpact();
  }

  Future<void> _handleActionTap(_DockAction action) async {
    HapticFeedback.selectionClick();
    await action.onTap();
  }

  List<_DockAction> _buildActions(
    BuildContext actionContext,
    PromptUiTokens tokens,
  ) {
    Future<void> closeMenu() async {
      if (!_expanded) return;
      _searchFocus.unfocus();
      final reduceMotion =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      if (reduceMotion) {
        _ctrl.value = 0;
      } else {
        await _ctrl.reverse();
      }
    }

    Future<T?> openPromptSheet<T>(
      Future<T?> Function(BuildContext context) open,
    ) {
      return HeadHubActions.openSheetExclusively<T>(
        open,
        context: actionContext,
      );
    }

    return <_DockAction>[
      _DockAction(
        id: 'headquarter_chat',
        icon: Icons.forum_rounded,
        label: '본사 채팅',
        description: '본사 전용 텍스트 채팅',
        color: tokens.accentContainer,
        foreground: tokens.onAccentContainer,
        onTap: () async {
          await closeMenu();
          await HeadHubActions.openHeadquarterChat(actionContext);
        },
      ),
      _DockAction(
        id: 'memo',
        icon: Icons.sticky_note_2_rounded,
        label: '메모',
        description: '플로팅 버블에서 기록을 관리합니다.',
        color: tokens.infoContainer,
        foreground: tokens.onInfoContainer,
        onTap: () async {
          await closeMenu();
          await openPromptSheet<void>(
            (sheetContext) => HeadMemo.openPanel(
              context: sheetContext,
              usePromptUi: true,
            ),
          );
        },
      ),
      _DockAction(
        id: 'company_calendar',
        icon: Icons.calendar_month_rounded,
        label: '본사 달력',
        description: '본사 직원 간 일정을 공유합니다.',
        color: tokens.successContainer,
        foreground: tokens.onSuccessContainer,
        onTap: () async {
          await closeMenu();
          await openPromptSheet<dynamic>(
            (sheetContext) => CompanyCalendarPage.showAsBottomSheet(
              sheetContext,
              usePromptUi: true,
            ),
          );
        },
      ),
      _DockAction(
        id: 'attendance',
        icon: Icons.how_to_reg_rounded,
        label: '출·퇴근',
        description: '직원별 출퇴근 기록을 관리합니다.',
        color: tokens.infoContainer,
        foreground: tokens.onInfoContainer,
        onTap: () async {
          await closeMenu();
          await openPromptSheet<dynamic>(
            (sheetContext) => hr_att.AttendanceCalendar.showAsBottomSheet(
              sheetContext,
              usePromptUi: true,
            ),
          );
        },
      ),
      _DockAction(
        id: 'break',
        icon: Icons.free_breakfast_rounded,
        label: '휴게 관리',
        description: '직원별 휴게시간을 관리합니다.',
        color: tokens.warningContainer,
        foreground: tokens.onWarningContainer,
        onTap: () async {
          await closeMenu();
          await openPromptSheet<dynamic>(
            (sheetContext) => hr_break.BreakCalendar.showAsBottomSheet(
              sheetContext,
              usePromptUi: true,
            ),
          );
        },
      ),
      _DockAction(
        id: 'field',
        icon: Icons.map_rounded,
        label: '근무지 현황',
        description: '사업부별 지역과 근무 인원을 확인합니다.',
        color: tokens.accentContainer,
        foreground: tokens.onAccentContainer,
        onTap: () async {
          await closeMenu();
          await openPromptSheet<dynamic>(
            (sheetContext) => mgmt.Field.showAsBottomSheet(
              sheetContext,
              usePromptUi: true,
            ),
          );
        },
      ),
      _DockAction(
        id: 'community',
        icon: Icons.groups_rounded,
        label: 'Community',
        description: '커뮤니티 화면을 엽니다.',
        color: tokens.infoContainer,
        foreground: tokens.onInfoContainer,
        onTap: () async {
          await closeMenu();
          await HeadHubActions.closeAnySheet();
          await HeadHubActions.navigatorKey.currentState
              ?.pushNamed(AppRoutes.communityStub);
        },
      ),
      _DockAction(
        id: 'faq',
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
        id: 'statistics',
        icon: Icons.stacked_line_chart_rounded,
        label: '통계 비교',
        description: '입·출차와 정산 추이를 비교합니다.',
        color: tokens.accentContainer,
        foreground: tokens.onAccentContainer,
        onTap: () async {
          await closeMenu();
          await openPromptSheet<dynamic>(
            (sheetContext) => mgmt_stats.Statistics.showAsBottomSheet(
              sheetContext,
              usePromptUi: true,
            ),
          );
        },
      ),
      _DockAction(
        id: 'roadmap',
        icon: Icons.edit_note_rounded,
        label: '향후 로드맵',
        description: '출시 이후 계획을 확인합니다.',
        color: tokens.warningContainer,
        foreground: tokens.onWarningContainer,
        onTap: () async {
          await closeMenu();
          await openPromptSheet<dynamic>(
            (sheetContext) => showPromptOverlayBottomSheet<dynamic>(
              context: sheetContext,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (_) => const RoadmapBottomSheet(),
            ),
          );
        },
      ),
      _DockAction(
        id: 'tutorials',
        icon: Icons.menu_book_rounded,
        label: '튜토리얼',
        description: 'PDF 가이드를 선택합니다.',
        color: tokens.successContainer,
        foreground: tokens.onSuccessContainer,
        onTap: () async {
          await closeMenu();
          final selected = await openPromptSheet<TutorialItem>(
            (sheetContext) => HeadTutorials.showPickerBottomSheet(
              sheetContext,
              usePromptUi: true,
            ),
          );
          final viewerContext = HeadHubActions.currentContext();
          if (selected != null && viewerContext != null) {
            await TutorialPdfViewer.open(
              viewerContext,
              selected,
              usePromptUi: true,
            );
          }
        },
      ),
      if (_developerMode)
        _DockAction(
          id: 'notensystem',
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
      _DockAction(
        id: 'contact',
        icon: Icons.contact_support_rounded,
        label: '문의하기',
        description: '이슈와 오류를 문의합니다.',
        color: tokens.dangerContainer,
        foreground: tokens.onDangerContainer,
        onTap: () async {
          await closeMenu();
          await HeadHubActions.closeAnySheet();
          await HeadHubActions.openContactForm(actionContext);
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
    final tokens = PromptUiTheme.of(context);
    final reduceMotion = media?.disableAnimations ?? false;

    if (!_clampedOnce && screen != Size.zero) {
      _clampedOnce = true;
      _pos = _clampToScreen(_pos, screen, bottomInset + keyboardInset);
    }

    final dockRight = screen == Size.zero
        ? true
        : (_pos.dx + _handleTouchWidth / 2) >= screen.width / 2;

    final actions = _buildActions(context, tokens);

    final maxDockWidth = (screen.width * 0.92).clamp(240.0, double.infinity);
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
        ? slideDistance * (1 - _t.value)
        : -slideDistance * (1 - _t.value);

    final handleX = screen == Size.zero
        ? _pos.dx
        : (dockRight ? (screen.width - _handleTouchWidth) : 0.0);

    return Stack(
      children: [
        if (_expanded)
          Positioned.fill(
            child: GestureDetector(
              onTap: _toggleMenu,
              behavior: HitTestBehavior.opaque,
              child: AnimatedOpacity(
                opacity: 0.22 * _t.value,
                duration:
                    reduceMotion ? Duration.zero : PromptUiMotion.instant,
                child: ColoredBox(color: tokens.scrim),
              ),
            ),
          ),
        Positioned(
          top: 0,
          bottom: 0,
          left: dockRight ? null : 0,
          right: dockRight ? 0 : null,
          child: IgnorePointer(
            ignoring: !_expanded,
            child: Transform.translate(
              offset: Offset(slideX, 0),
              child: Opacity(
                opacity: _t.value,
                child: _GlassDock(
                  width: dockWidth,
                  height: screen.height,
                  borderRadius: dockBorderRadius,
                  child: SafeArea(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: keyboardInset),
                      child: _CommandPaletteDock(
                        actions: actions,
                        controller: _searchCtrl,
                        focusNode: _searchFocus,
                        onSelect: _handleActionTap,
                      ),
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
            onTap: _toggleMenu,
            onPanUpdate: (d) {
              if (screen == Size.zero) return;
              setState(() {
                final next = Offset(_pos.dx + d.delta.dx, _pos.dy + d.delta.dy);
                _pos =
                    _clampToScreen(next, screen, bottomInset + keyboardInset);
              });
            },
            onPanEnd: (_) async {
              if (screen == Size.zero) return;
              setState(() {
                _pos = _clampToScreen(_pos, screen, bottomInset + keyboardInset);
              });
              await widget.onPosSave(_pos);
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
                  progress: _t.value,
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
            .where((a) => !a.hiddenUntilExactQuery)
            .toList(growable: false)
        : actions.where((a) {
            if (a.hiddenUntilExactQuery) {
              return query == _normalize(a.id) || query == _normalize(a.label);
            }
            return _normalize(a.searchText).contains(query);
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
        const SizedBox(height: 10),
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
            builder: (context, v, _) {
              final hasText = v.text.trim().isNotEmpty;
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

    return ListView.separated(
      padding: EdgeInsets.zero,
      physics: const ClampingScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        return _PaletteTile(
          action: items[index],
          onSelect: onSelect,
        );
      },
    );
  }
}

class _PaletteTile extends StatelessWidget {
  final _DockAction action;
  final Future<void> Function(_DockAction action) onSelect;

  const _PaletteTile({required this.action, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
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
  final IconData icon;
  final String label;
  final String? description;
  final Color color;
  final Color foreground;
  final bool hiddenUntilExactQuery;
  final Future<void> Function() onTap;

  _DockAction({
    required this.id,
    required this.icon,
    required this.label,
    required this.description,
    required this.color,
    required this.foreground,
    this.hiddenUntilExactQuery = false,
    required this.onTap,
  });

  String get searchText =>
      [id, label, description].whereType<String>().join(' ');
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
    final tokens = PromptUiTheme.of(context);

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
