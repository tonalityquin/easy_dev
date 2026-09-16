import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/di/routes.dart';
import '../../../app/utils/snackbar_helper.dart';
import '../../../design_system/common_ui/common_ui_side_dock.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../community/application/discord/discord_config.dart';
import '../../community/page/faq_side_dock.dart';
import '../../community/page/side_docks/discord_side_dock.dart';
import '../../selector/application/dev_auth.dart';
import '../application/actions/headquarter_common_actions.dart';
import '../application/download/headquarter_area_master_download_workflow.dart';
import '../application/headquarter_dashboard_context.dart';
import '../application/headquarter_side_dock_launcher_controller.dart';
import '../application/headquarter_support_actions.dart';
import '../application/navigation/headquarter_context_navigation_coordinator.dart';
import '../page/sheets/head_memo.dart';
import 'headquarter_quick_work_context.dart';
import 'hr/attendance_calendar.dart' as hr_att;
import 'hr/break_calendar.dart' as hr_break;
import 'mgmt/field.dart' as mgmt;
import 'mgmt/statistics.dart' as mgmt_stats;

Future<void> showHeadquarterQuickActionsSideDock({
  required BuildContext context,
  required String source,
  bool useRootNavigator = true,
}) async {
  final developerMode = await DevAuth.isDevModeEnabled();
  if (!context.mounted) return;

  final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final route = _HeadquarterQuickActionsRoute(
    reduceMotion: reduceMotion,
    source: source,
    developerMode: developerMode,
  );

  HeadquarterSideDockLauncherController.recordDebug(
    'quick_actions_route_push source=$source side=left design=legacy_head_hub_actions_v1519 developerMode=$developerMode reduceMotion=$reduceMotion',
  );

  final action = await navigator.push<_DockAction>(route);
  if (action == null) {
    HeadquarterSideDockLauncherController.recordDebug(
      'quick_actions_route_closed source=$source selection=none',
    );
    return;
  }

  final actionContext = navigator.context;
  HeadquarterSideDockLauncherController.recordDebug(
    'quick_actions_action_start source=$source id=${action.id} category=${action.category.name}',
  );
  await HapticFeedback.selectionClick();

  try {
    await action.onTap(actionContext);
    HeadquarterSideDockLauncherController.recordDebug(
      'quick_actions_action_complete source=$source id=${action.id}',
    );
  } catch (error, stackTrace) {
    HeadquarterSideDockLauncherController.recordDebug(
      'quick_actions_action_failure source=$source id=${action.id} error=$error stack=$stackTrace',
    );
    if (actionContext.mounted) {
      showFailedSnackbar(
        actionContext,
        '요청을 처리하지 못했습니다.',
        useCommonUi: true,
      );
    }
    rethrow;
  }
}

class _HeadquarterQuickActionsRoute extends PopupRoute<_DockAction> {
  _HeadquarterQuickActionsRoute({
    required this.reduceMotion,
    required this.source,
    required this.developerMode,
  });

  final bool reduceMotion;
  final String source;
  final bool developerMode;

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => '본사 빠른 실행';

  @override
  Duration get transitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 240);

  @override
  Duration get reverseTransitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 240);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final panelAnimation = CurvedAnimation(
      parent: animation,
      curve: const _SpringCurve(),
      reverseCurve: Curves.easeInCubic,
    );
    return CommonUiScope(
      child: Material(
        type: MaterialType.transparency,
        child: _HeadquarterQuickActionsPanel(
          animation: panelAnimation,
          source: source,
          developerMode: developerMode,
        ),
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
}

class _HeadquarterQuickActionsPanel extends StatefulWidget {
  const _HeadquarterQuickActionsPanel({
    required this.animation,
    required this.source,
    required this.developerMode,
  });

  final Animation<double> animation;
  final String source;
  final bool developerMode;

  @override
  State<_HeadquarterQuickActionsPanel> createState() =>
      _HeadquarterQuickActionsPanelState();
}

class _HeadquarterQuickActionsPanelState
    extends State<_HeadquarterQuickActionsPanel> {
  static const double _dockRadius = 18;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _lastSearchValue = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    HeadquarterSideDockLauncherController.recordDebug(
      'quick_actions_panel_initialized source=${widget.source} side=left design=legacy_head_hub_actions_v1519 workContext=dashboard_style searchPresentation=dashboard_style groupedResults=true',
    );
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    HeadquarterSideDockLauncherController.recordDebug(
      'quick_actions_panel_disposed source=${widget.source}',
    );
    super.dispose();
  }

  void _handleSearchChanged() {
    final next = _searchController.text.trim();
    if (next != _lastSearchValue) {
      _lastSearchValue = next;
      HeadquarterSideDockLauncherController.recordDebug(
        'quick_actions_search_query_changed active=${next.isNotEmpty} length=${next.length}',
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _showDeveloperStatus() async {
    if (!widget.developerMode) return;
    HeadquarterSideDockLauncherController.recordDebug(
      'quick_actions_developer_status_request source=${widget.source}',
    );
    await HeadquarterSideDockLauncherController.showDeveloperStatus(context);
  }

  void _close([_DockAction? action]) {
    _searchFocus.unfocus();
    Navigator.of(context).pop<_DockAction>(action);
  }

  Future<bool> _launchExternal(String value) async {
    final uri = Uri.tryParse(value.trim());
    if (uri == null) {
      HeadquarterSideDockLauncherController.recordDebug(
        'quick_actions_external_invalid_uri value=$value',
      );
      return false;
    }
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error, stackTrace) {
      HeadquarterSideDockLauncherController.recordDebug(
        'quick_actions_external_failure uri=$value error=$error stack=$stackTrace',
      );
      return false;
    }
  }

  Future<void> _openThirdPartyChannel(BuildContext rootContext) async {
    HeadquarterSideDockLauncherController.recordDebug(
      'quick_actions_third_party_channel_start source=${widget.source}',
    );
    String channel = '';
    try {
      channel = (await loadDiscordChannelUrl()).trim();
    } catch (error, stackTrace) {
      HeadquarterSideDockLauncherController.recordDebug(
        'quick_actions_third_party_channel_load_failure error=$error stack=$stackTrace',
      );
    }

    final valid = isDiscordChannelUrl(channel);
    HeadquarterSideDockLauncherController.recordDebug(
      'quick_actions_third_party_channel_config present=${channel.isNotEmpty} valid=$valid',
    );

    if (!valid) {
      if (rootContext.mounted) {
        showFailedSnackbar(
          rootContext,
          'Discord 업무 채널 링크가 설정되어 있지 않습니다.',
          useCommonUi: true,
        );
        await showDiscordConnectionSupportSideDock(
          context: rootContext,
          source: 'headquarter_quick_actions_channel_fallback',
          side: CommonSideDockSide.left,
          accessPolicy: DiscordConnectionSupportAccessPolicy.headquarter,
        );
      }
      return;
    }

    final deepLink = discordChannelDeepLink(channel);
    var opened = false;
    var destination = 'https_channel';
    if (deepLink != null) {
      opened = await _launchExternal(deepLink);
      if (opened) destination = 'discord_app_channel';
    }
    if (!opened) {
      opened = await _launchExternal(channel);
    }

    HeadquarterSideDockLauncherController.recordDebug(
      'quick_actions_third_party_channel_result opened=$opened destination=$destination',
    );

    if (!opened && rootContext.mounted) {
      showFailedSnackbar(
        rootContext,
        'Discord 업무 채널을 열 수 없습니다.',
        useCommonUi: true,
      );
    }
  }

  List<_DockAction> _buildActions(CommonUiTokens tokens) {
    return <_DockAction>[
      _DockAction(
        id: 'third_party_connect',
        category: _QuickActionCategory.thirdParty,
        icon: Icons.forum_rounded,
        label: '서드 파티 연결',
        description: '저장된 Discord 업무 채널을 바로 엽니다.',
        color: tokens.accentContainer,
        foreground: tokens.onAccentContainer,
        onTap: _openThirdPartyChannel,
      ),
      _DockAction(
        id: 'headquarter_navigation',
        category: _QuickActionCategory.work,
        icon: Icons.location_city_rounded,
        label: '업무 지역',
        description: '본사 업무 지역으로 이동합니다.',
        color: tokens.accentContainer,
        foreground: tokens.onAccentContainer,
        onTap: (rootContext) async {
          await HeadquarterContextNavigationCoordinator.openNavigationDock(
            context: rootContext,
            currentModeKey: HeadquarterDashboardContext.currentModeKey.value,
            currentScreen: 'headquarter_quick_actions_side_dock',
            source: 'headquarter_quick_actions_side_dock',
            useRootNavigator: true,
          );
        },
      ),
      _DockAction(
        id: 'launcher_disable',
        category: _QuickActionCategory.work,
        icon: Icons.lightbulb_rounded,
        label: '빠른 열기 끄기',
        description: '본사 Side Dock 전역 핸들을 끕니다.',
        color: tokens.warningContainer,
        foreground: tokens.onWarningContainer,
        onTap: (_) => HeadquarterSideDockLauncherController.setEnabled(
          false,
          source: 'headquarter_quick_actions_side_dock',
        ),
      ),
      _DockAction(
        id: 'memo',
        category: _QuickActionCategory.work,
        icon: Icons.sticky_note_2_rounded,
        label: '메모',
        description: '본사 메모를 열어 기록을 관리합니다.',
        color: tokens.infoContainer,
        foreground: tokens.onInfoContainer,
        onTap: (rootContext) => HeadMemo.openPanel(
          context: rootContext,
          useCommonUi: true,
        ),
      ),
      _DockAction(
        id: 'refresh_area_master',
        category: _QuickActionCategory.work,
        icon: Icons.download_rounded,
        label: '다운받기',
        description: '현재 근무 회사의 전체 지역 정보를 최신 상태로 내려받습니다.',
        color: tokens.infoContainer,
        foreground: tokens.onInfoContainer,
        onTap: (rootContext) async {
          final outcome = await HeadquarterAreaMasterDownloadWorkflow.run(
            context: rootContext,
            source: 'headquarter_quick_actions_side_dock',
            useCommonUi: true,
          );
          HeadquarterSideDockLauncherController.recordDebug(
            'quick_actions_area_master_download_result status=${outcome.status.name} areas=${outcome.areaCount} downloadedAt=${outcome.downloadedAtIso}',
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
        onTap: (rootContext) async {
          await mgmt.Field.showAsLeftSideDock<dynamic>(
            rootContext,
            useRootNavigator: true,
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
        onTap: (rootContext) async {
          await hr_att.AttendanceCalendar.showAsLeftSideDock<dynamic>(
            rootContext,
            useRootNavigator: true,
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
        onTap: (rootContext) async {
          await hr_break.BreakCalendar.showAsLeftSideDock<dynamic>(
            rootContext,
            useRootNavigator: true,
          );
        },
      ),
      _DockAction(
        id: 'statistics',
        category: _QuickActionCategory.operations,
        icon: Icons.stacked_line_chart_rounded,
        label: '통계 비교',
        description: '출차·정산 추이를 비교합니다.',
        color: tokens.accentContainer,
        foreground: tokens.onAccentContainer,
        onTap: (rootContext) async {
          await mgmt_stats.Statistics.showAsLeftSideDock<dynamic>(
            rootContext,
            useRootNavigator: true,
          );
        },
      ),
      _DockAction(
        id: 'third_party_support',
        category: _QuickActionCategory.settings,
        icon: Icons.extension_rounded,
        label: '서드파티 연결 지원',
        description: 'Discord 앱, 서버 초대, 업무 채널 연결 상태를 확인하고 엽니다.',
        color: tokens.surfaceSelected,
        foreground: tokens.textPrimary,
        onTap: (rootContext) async {
          await showDiscordConnectionSupportSideDock(
            context: rootContext,
            source: 'headquarter_quick_actions_side_dock',
            side: CommonSideDockSide.left,
            accessPolicy: DiscordConnectionSupportAccessPolicy.headquarter,
          );
        },
      ),
      _DockAction(
        id: 'logout',
        category: _QuickActionCategory.settings,
        icon: Icons.logout_rounded,
        label: '로그아웃',
        description: '현재 계정의 세션을 종료합니다.',
        color: tokens.dangerContainer,
        foreground: tokens.onDangerContainer,
        onTap: (rootContext) => HeadquarterCommonActions.logout(
          rootContext,
          source: 'headquarter_quick_actions_side_dock',
        ),
      ),
      _DockAction(
        id: 'faq',
        category: _QuickActionCategory.support,
        icon: Icons.help_center_rounded,
        label: 'FAQ',
        description: '자주 묻는 질문을 확인합니다.',
        color: tokens.surfaceSelected,
        foreground: tokens.textPrimary,
        onTap: (rootContext) async {
          await showFaqSideDock<void>(
            context: rootContext,
            side: CommonSideDockSide.left,
            source: 'headquarter_quick_actions_side_dock',
          );
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
        onTap: (rootContext) async {
          final opened =
              await HeadquarterSupportActions.openTermsOfService(rootContext);
          HeadquarterSideDockLauncherController.recordDebug(
            'quick_actions_support_external_result id=terms opened=$opened',
          );
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
        onTap: (rootContext) async {
          final opened =
              await HeadquarterSupportActions.openPrivacyPolicy(rootContext);
          HeadquarterSideDockLauncherController.recordDebug(
            'quick_actions_support_external_result id=privacy opened=$opened',
          );
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
        onTap: (rootContext) async {
          final opened =
              await HeadquarterSupportActions.openContactForm(rootContext);
          HeadquarterSideDockLauncherController.recordDebug(
            'quick_actions_support_external_result id=contact opened=$opened',
          );
        },
      ),
      if (widget.developerMode)
        _DockAction(
          id: 'developer_status',
          category: _QuickActionCategory.developer,
          icon: Icons.bug_report_rounded,
          label: 'Side Dock 상태',
          description: '현재 런처 상태와 debugPrint 로그를 확인합니다.',
          color: tokens.warningContainer,
          foreground: tokens.onWarningContainer,
          onTap: (rootContext) async {
            HeadquarterSideDockLauncherController.recordDebug(
              'quick_actions_developer_status_action source=${widget.source}',
            );
            await HeadquarterSideDockLauncherController.showDeveloperStatus(
              rootContext,
            );
          },
        ),
      if (widget.developerMode)
        _DockAction(
          id: 'notensystem',
          category: _QuickActionCategory.developer,
          icon: Icons.auto_stories_rounded,
          label: 'notensystem',
          description: '소설 설계 및 집필 스튜디오',
          color: tokens.infoContainer,
          foreground: tokens.onInfoContainer,
          hiddenUntilExactQuery: true,
          onTap: (rootContext) async {
            await Navigator.of(rootContext, rootNavigator: true)
                .pushNamed(AppRoutes.noteSystem);
          },
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.animation,
      builder: (context, _) {
        final media = MediaQuery.maybeOf(context);
        final screen = media?.size ?? Size.zero;
        final keyboardInset = media?.viewInsets.bottom ?? 0;
        final tokens = CommonUiTheme.of(context);
        final progress = widget.animation.value.clamp(0.0, 1.0).toDouble();
        final maxDockWidth =
            (screen.width * 0.92).clamp(240.0, double.infinity).toDouble();
        final dockWidth = math.min(360.0, maxDockWidth);
        final slideDistance = dockWidth + 68;
        final slideX = -slideDistance * (1 - progress);
        final dockScale = 0.985 + (0.015 * progress);
        final actions = _buildActions(tokens);

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  HeadquarterSideDockLauncherController.recordDebug(
                    'quick_actions_close source=scrim',
                  );
                  _close();
                },
                behavior: HitTestBehavior.opaque,
                child: ColoredBox(
                  color: tokens.scrim.withOpacity(0.22 * progress),
                ),
              ),
            ),
            Positioned(
              top: 0,
              bottom: 0,
              left: 0,
              child: Transform.translate(
                offset: Offset(slideX, 0),
                child: Transform.scale(
                  alignment: Alignment.centerLeft,
                  scale: dockScale,
                  child: Opacity(
                    opacity: progress,
                    child: _GlassDock(
                      width: dockWidth,
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(_dockRadius),
                        bottomRight: Radius.circular(_dockRadius),
                      ),
                      child: SafeArea(
                        child: Padding(
                          padding: EdgeInsets.only(bottom: keyboardInset),
                          child: _CommandPaletteDock(
                            actions: actions,
                            controller: _searchController,
                            focusNode: _searchFocus,
                            developerMode: widget.developerMode,
                            onDeveloperStatus: _showDeveloperStatus,
                            onDebug: (message) =>
                                HeadquarterSideDockLauncherController
                                    .recordDebug(
                              'quick_actions_$message',
                            ),
                            onSelect: (action) async {
                              HeadquarterSideDockLauncherController.recordDebug(
                                'quick_actions_selection id=${action.id} category=${action.category.name}',
                              );
                              _close(action);
                            },
                          ),
                        ),
                      ),
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
  thirdParty,
  work,
  operations,
  settings,
  support,
  developer,
}

extension _QuickActionCategoryUi on _QuickActionCategory {
  static const List<_QuickActionCategory> mainCategories =
      <_QuickActionCategory>[
    _QuickActionCategory.thirdParty,
    _QuickActionCategory.work,
    _QuickActionCategory.operations,
    _QuickActionCategory.settings,
    _QuickActionCategory.support,
  ];

  String get label {
    switch (this) {
      case _QuickActionCategory.thirdParty:
        return '서드 파티';
      case _QuickActionCategory.work:
        return '업무';
      case _QuickActionCategory.operations:
        return '운영';
      case _QuickActionCategory.settings:
        return '설정';
      case _QuickActionCategory.support:
        return '지원';
      case _QuickActionCategory.developer:
        return '개발자';
    }
  }
}

class _CommandPaletteDock extends StatelessWidget {
  const _CommandPaletteDock({
    required this.actions,
    required this.controller,
    required this.focusNode,
    required this.developerMode,
    required this.onDeveloperStatus,
    required this.onDebug,
    required this.onSelect,
  });

  final List<_DockAction> actions;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool developerMode;
  final Future<void> Function() onDeveloperStatus;
  final ValueChanged<String> onDebug;
  final Future<void> Function(_DockAction action) onSelect;

  @override
  Widget build(BuildContext context) {
    final queryRaw = controller.text.trim();
    final query = _normalize(queryRaw);
    final searching = query.isNotEmpty;
    final filtered = searching
        ? actions.where((action) {
            if (action.hiddenUntilExactQuery) {
              return query == _normalize(action.id) ||
                  query == _normalize(action.label);
            }
            return _normalize(action.searchText).contains(query);
          }).toList(growable: false)
        : actions
            .where((action) => !action.hiddenUntilExactQuery)
            .toList(growable: false);

    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const ClampingScrollPhysics(),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HeadquarterQuickWorkContext(
            developerMode: developerMode,
            onDeveloperStatus: onDeveloperStatus,
            onDebug: onDebug,
          ),
          const SizedBox(height: 14),
          _StaggeredReveal(
            key: const ValueKey<String>('action_search'),
            order: 3,
            offsetY: 6,
            child: _SearchField(
              controller: controller,
              focusNode: focusNode,
              onDebug: onDebug,
              onSubmit: () async {
                if (filtered.isEmpty) {
                  onDebug('search_submit result=empty');
                  return;
                }
                onDebug('search_submit result=action id=${filtered.first.id}');
                await onSelect(filtered.first);
              },
            ),
          ),
          const SizedBox(height: 14),
          _PaletteArea(
            query: query,
            items: filtered,
            onSelect: onSelect,
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onDebug,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onDebug;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Material(
      color: tokens.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '빠른 실행 검색',
            style: text.labelLarge?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),
          Semantics(
            textField: true,
            label: '빠른 실행 검색',
            child: Container(
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: tokens.borderSubtle),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, color: tokens.iconSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => onSubmit(),
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 160),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.88, end: 1).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutCubic,
                          ),
                        ),
                        child: child,
                      ),
                    ),
                    child: controller.text.trim().isNotEmpty
                        ? IconButton(
                            key: const ValueKey<String>('search_clear'),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              onDebug('search_clear source=button');
                              controller.clear();
                            },
                            icon: Icon(
                              Icons.close_rounded,
                              color: tokens.iconSecondary,
                            ),
                          )
                        : const SizedBox.shrink(
                            key: ValueKey<String>('search_clear_empty'),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaletteArea extends StatelessWidget {
  const _PaletteArea({
    required this.query,
    required this.items,
    required this.onSelect,
  });

  final String query;
  final List<_DockAction> items;
  final Future<void> Function(_DockAction action) onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final resultKey = query.isEmpty
        ? 'all_${items.length}'
        : 'search_${query.hashCode}_${items.map((action) => action.id).join('_')}';

    Widget child;
    if (query.isNotEmpty && items.isEmpty) {
      child = Container(
        key: ValueKey<String>(resultKey),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 22),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tokens.borderSubtle),
        ),
        child: Column(
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 26,
              color: tokens.iconSecondary,
            ),
            const SizedBox(height: 8),
            Text(
              '검색 결과가 없습니다.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 3),
            Text(
              '다른 검색어를 입력해 주세요.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                  ),
            ),
          ],
        ),
      );
    } else {
      child = Column(
        key: ValueKey<String>(resultKey),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _buildSections(query.isEmpty ? 4 : 0),
      );
    }

    return AnimatedSwitcher(
      duration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 190),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (item, animation) {
        if (reduceMotion) return item;
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.025),
              end: Offset.zero,
            ).animate(animation),
            child: item,
          ),
        );
      },
      child: child,
    );
  }

  List<Widget> _buildSections(int startingOrder) {
    final children = <Widget>[];
    var revealOrder = startingOrder;
    final categories = query.isEmpty
        ? <_QuickActionCategory>[
            ..._QuickActionCategoryUi.mainCategories,
            if (items.any(
              (action) => action.category == _QuickActionCategory.developer,
            ))
              _QuickActionCategory.developer,
          ]
        : _QuickActionCategory.values;

    for (final category in categories) {
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

    return children;
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

class _PaletteTile extends StatefulWidget {
  const _PaletteTile({
    required this.action,
    required this.onSelect,
  });

  final _DockAction action;
  final Future<void> Function(_DockAction action) onSelect;

  @override
  State<_PaletteTile> createState() => _PaletteTileState();
}

class _PaletteTileState extends State<_PaletteTile> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final background =
        _pressed || _hovered ? tokens.surfaceSelected : tokens.surface;
    final border = _focused ? tokens.focusRing : tokens.borderSubtle;

    return Semantics(
      button: true,
      label: widget.action.label,
      child: AnimatedScale(
        scale: _pressed ? .985 : 1,
        duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
        curve: CommonUiMotion.enter,
        child: AnimatedContainer(
          duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
          curve: CommonUiMotion.standard,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: border,
              width: _focused ? 2 : 1,
            ),
            boxShadow: _hovered
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
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                unawaited(widget.onSelect(widget.action));
              },
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
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: reduceMotion
                          ? Duration.zero
                          : CommonUiMotion.selection,
                      curve: CommonUiMotion.standard,
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: widget.action.color,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: tokens.shadow,
                            blurRadius: _hovered ? 11 : 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        widget.action.icon,
                        color: widget.action.foreground,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.action.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleSmall?.copyWith(
                              color: tokens.textPrimary,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                          if ((widget.action.description ?? '')
                              .trim()
                              .isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              widget.action.description!,
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
                    AnimatedSlide(
                      offset: _hovered ? const Offset(.08, 0) : Offset.zero,
                      duration: reduceMotion
                          ? Duration.zero
                          : CommonUiMotion.selection,
                      curve: CommonUiMotion.enter,
                      child: Icon(
                        Icons.chevron_right_rounded,
                        color: tokens.iconSecondary,
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

class _DockAction {
  const _DockAction({
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

  final String id;
  final _QuickActionCategory category;
  final IconData icon;
  final String label;
  final String? description;
  final Color color;
  final Color foreground;
  final bool hiddenUntilExactQuery;
  final Future<void> Function(BuildContext context) onTap;

  String get searchText =>
      [id, category.label, label, description].whereType<String>().join(' ');
}

class _GlassDock extends StatelessWidget {
  const _GlassDock({
    required this.width,
    required this.borderRadius,
    required this.child,
  });

  final double width;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: width,
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

class _SpringCurve extends Curve {
  const _SpringCurve();

  @override
  double transform(double t) {
    final e = math.exp(-6 * t);
    final c = math.cos(10 * t);
    final y = 1 - e * c;
    return y.clamp(0.0, 1.0);
  }
}
