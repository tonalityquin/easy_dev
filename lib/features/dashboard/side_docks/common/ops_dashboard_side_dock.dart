import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/di/routes.dart';
import '../../../../app/models/capability.dart';
import '../../../../app/init/logout_helper.dart';
import '../../../../app/utils/operational_data_sync_workflow.dart';
import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../app/utils/status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../shared/sheet_tool/document_box_action.dart';
import '../../../../shared/sheet_tool/document_box_action_executor.dart';
import '../../../account/applications/user_state.dart';
import '../../../camera/photo_transfer_mail_page.dart';
import '../../../community/application/discord/discord_config.dart';
import '../../../community/page/sheets/discord/discord_bottom_sheet.dart';
import '../../../dev/application/area_state.dart';
import '../../../headquarter/application/fab/hub_quick_actions.dart';
import '../../../selector/application/dev_auth.dart';
import '../../../selector/sheets/service_bottom_sheet.dart';
import 'dashboard_dock_request.dart';
import '../../widgets/widgets/schedule/dashboard_work_schedule_surface.dart';

class OpsDashboardSideDock extends StatefulWidget {
  const OpsDashboardSideDock({
    super.key,
    required this.modeLabel,
    required this.modeIcon,
    required this.punchRecorderBuilder,
  });

  final String modeLabel;
  final IconData modeIcon;
  final Widget Function(
    BuildContext context,
    UserState userState,
    AreaState areaState,
  ) punchRecorderBuilder;

  @override
  State<OpsDashboardSideDock> createState() =>
      _OpsDashboardSideDockState();
}

class _OpsDashboardSideDockState extends State<OpsDashboardSideDock> {
  final ScrollController _dockScrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _lastSearchDebugSignature = '';
  String _lastBusinessDebugSignature = '';
  bool _developerMode = false;
  bool _developerModeResolved = false;

  bool _isFieldCommon(UserState userState) {
    final dynamic rawRole = userState.session?.role;
    final role =
        rawRole is String ? rawRole.trim() : (rawRole?.toString().trim() ?? '');
    return role == 'fieldCommon';
  }

  String _normalizeSearch(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  List<_DashboardAction> _filterActions(
    List<_DashboardAction> actions,
    String rawQuery,
  ) {
    final query = _normalizeSearch(rawQuery);
    if (query.isEmpty) return actions;
    return actions
        .where((action) => _normalizeSearch(action.searchText).contains(query))
        .toList(growable: false);
  }

  void _onSearchChanged() {
    if (!mounted) return;
    final userState = context.read<UserState>();
    final actions = _actions(
      context,
      _isFieldCommon(userState),
      developerMode: _developerMode,
    );
    final filtered = _filterActions(actions, _searchController.text);
    final sectionCount = _DashboardActionCategory.values
        .where(
          (category) => filtered.any((action) => action.category == category),
        )
        .length;
    final queryLength = _searchController.text.trim().length;
    final signature = '$queryLength:${filtered.length}:$sectionCount';
    if (_lastSearchDebugSignature != signature) {
      _lastSearchDebugSignature = signature;
      debugPrint(
        '[OpsDashboardSideDock] search_changed active=${queryLength > 0} queryLength=$queryLength resultCount=${filtered.length} visibleSectionCount=$sectionCount',
      );
    }
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    debugPrint(
      '[OpsDashboardSideDock] mounted mode=${widget.modeLabel} layout=single_scroll',
    );
    _refreshDeveloperMode();
  }

  Future<bool> _refreshDeveloperMode() async {
    debugPrint('[OpsDashboardSideDock] developer_mode_check_start');
    final enabled = await DevAuth.isDeveloperLoggedIn();
    if (!mounted) return enabled;
    final changed = !_developerModeResolved || _developerMode != enabled;
    if (changed) {
      setState(() {
        _developerMode = enabled;
        _developerModeResolved = true;
      });
    }
    debugPrint(
      '[OpsDashboardSideDock] developer_mode_resolved enabled=$enabled settingsVisible=true communityVisible=$enabled changed=$changed',
    );
    return enabled;
  }

  @override
  void dispose() {
    debugPrint('[OpsDashboardSideDock] disposed mode=${widget.modeLabel}');
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _dockScrollController.dispose();
    super.dispose();
  }

  Future<void> _closeCurrentDockAndRun(
    BuildContext context,
    Future<void> Function(BuildContext rootContext) action,
  ) async {
    _searchFocusNode.unfocus();
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      debugPrint('[OpsDashboardSideDock] close_before_external_action');
      nav.pop();
      await Future<void>.delayed(Duration.zero);
    }
    await action(rootNavigator.context);
  }

  Future<void> _runDocumentAction(
    BuildContext context,
    DocumentBoxAction action,
  ) async {
    await _closeCurrentDockAndRun(context, (rootContext) async {
      await executeDocumentBoxAction(rootContext, action);
    });
  }

  Future<void> _openPhotoTransfer(BuildContext context) async {
    await _closeCurrentDockAndRun(context, (rootContext) async {
      final reduceMotion =
          MediaQuery.maybeOf(rootContext)?.disableAnimations ?? false;
      await Navigator.of(rootContext, rootNavigator: true).push<void>(
        PageRouteBuilder<void>(
          transitionDuration:
              reduceMotion ? Duration.zero : CommonUiMotion.overlay,
          reverseTransitionDuration:
              reduceMotion ? Duration.zero : CommonUiMotion.component,
          pageBuilder: (_, __, ___) => const CommonUiScope(
            child: PhotoTransferMailPage(),
          ),
          transitionsBuilder: (_, animation, __, child) {
            if (reduceMotion) return child;
            final curved = CurvedAnimation(
              parent: animation,
              curve: CommonUiMotion.enter,
              reverseCurve: CommonUiMotion.exit,
            );
            return FadeTransition(opacity: curved, child: child);
          },
        ),
      );
    });
  }

  Future<void> _openCommunity(BuildContext context) async {
    await _closeCurrentDockAndRun(context, (rootContext) async {
      await Navigator.of(
        rootContext,
        rootNavigator: true,
      ).pushNamed(AppRoutes.communityStub);
    });
  }

  bool _canUseThirdParty(BuildContext context) {
    return context
        .read<AreaState>()
        .capabilitiesOfCurrentArea
        .contains(Capability.record);
  }

  Future<void> _openThirdPartySupport(BuildContext context) async {
    if (!_canUseThirdParty(context)) {
      await StatusDialog.showFailure(
        context,
        title: '서드파티 연결 권한이 없습니다.',
        useCommonUi: true,
      );
      return;
    }
    await _closeCurrentDockAndRun(context, (rootContext) async {
      debugPrint('[OpsDashboardSideDock] third_party_support_open');
      await showModalBottomSheet<bool>(
        context: rootContext,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) => DiscordBottomSheet(rootContext: rootContext),
      );
      debugPrint('[OpsDashboardSideDock] third_party_support_closed');
    });
  }

  Future<void> _openThirdPartyChannel(BuildContext context) async {
    if (!_canUseThirdParty(context)) {
      await StatusDialog.showFailure(
        context,
        title: '서드파티 연결 권한이 없습니다.',
        useCommonUi: true,
      );
      return;
    }
    await _closeCurrentDockAndRun(context, (rootContext) async {
      final trace = await DeveloperOperationTrace.start(
        context: rootContext,
        title: '서드파티 채널 연결',
        initialMessage: '저장된 Discord 채널 연결 정보를 확인합니다.',
        useCommonUi: true,
        developerModeMessage: '개발자 모드 ON: 채널 연결 debugPrint 코드를 복사할 수 있습니다.',
        standardModeMessage: '개발자 모드 OFF',
        showDialogImmediately: false,
      );
      final channelUrl = await loadDiscordChannelUrl();
      final valid = isDiscordChannelUrl(channelUrl);
      trace.log(
        'capability=record enabled=true channelPresent=${channelUrl.isNotEmpty} channelLength=${channelUrl.length} channelValid=$valid',
        progress: 0.24,
      );
      if (!valid) {
        await trace.fail('저장된 Discord 채널 링크가 없습니다.');
        if (rootContext.mounted) {
          await StatusDialog.showFailure(
            rootContext,
            title: 'Discord 채널 링크를 먼저 설정해 주세요.',
            useCommonUi: true,
          );
        }
        if (trace.developerMode && rootContext.mounted) {
          await trace.showStatusDialog(rootContext);
        }
        if (rootContext.mounted) {
          await showModalBottomSheet<bool>(
            context: rootContext,
            isScrollControlled: true,
            useSafeArea: true,
            backgroundColor: Colors.transparent,
            builder: (_) => DiscordBottomSheet(rootContext: rootContext),
          );
        }
        return;
      }

      final appUrl = discordChannelDeepLink(channelUrl);
      var opened = false;
      var destination = 'https_channel';
      if (appUrl != null) {
        final appUri = Uri.tryParse(appUrl);
        if (appUri != null) {
          try {
            opened = await launchUrl(
              appUri,
              mode: LaunchMode.externalApplication,
            );
            trace.log(
              'discordAppLaunch opened=$opened deepLink=$appUrl',
              progress: 0.55,
            );
          } catch (error, stackTrace) {
            trace.log('discordAppLaunch error=$error', progress: 0.55);
            debugPrintStack(
              label: '[OpsDashboardSideDock] third_party_app_launch',
              stackTrace: stackTrace,
            );
          }
        }
        if (opened) destination = 'discord_app_channel';
      }

      if (!opened) {
        final uri = Uri.tryParse(channelUrl);
        if (uri != null) {
          try {
            opened = await launchUrl(
              uri,
              mode: LaunchMode.externalApplication,
            );
          } catch (error, stackTrace) {
            trace.log('httpsFallback error=$error', progress: 0.72);
            debugPrintStack(
              label: '[OpsDashboardSideDock] third_party_https_launch',
              stackTrace: stackTrace,
            );
          }
        }
      }

      trace.log(
        'result opened=$opened destination=$destination launchPolicy=discord_scheme_then_https_fallback',
        progress: 0.86,
      );
      if (opened) {
        await trace.succeed('Discord 업무 채널을 열었습니다.');
      } else {
        await trace.fail('Discord 업무 채널을 열 수 없습니다.');
        if (rootContext.mounted) {
          await StatusDialog.showFailure(
            rootContext,
            title: 'Discord 채널을 열 수 없습니다.',
            useCommonUi: true,
          );
        }
      }
      if (trace.developerMode && rootContext.mounted) {
        await trace.showStatusDialog(rootContext);
      }
    });
  }

  Future<void> _openFaq(BuildContext context) async {
    await _closeCurrentDockAndRun(context, (rootContext) async {
      await Navigator.of(
        rootContext,
        rootNavigator: true,
      ).pushNamed(AppRoutes.faq);
    });
  }

  Future<void> _openTermsOfService(BuildContext context) async {
    await _closeCurrentDockAndRun(context, (rootContext) async {
      final opened = await HeadHubActions.openTermsOfService(rootContext);
      debugPrint(
        '[OpsDashboardSideDock] support_external_result id=terms opened=$opened',
      );
    });
  }

  Future<void> _openPrivacyPolicy(BuildContext context) async {
    await _closeCurrentDockAndRun(context, (rootContext) async {
      final opened = await HeadHubActions.openPrivacyPolicy(rootContext);
      debugPrint(
        '[OpsDashboardSideDock] support_external_result id=privacy opened=$opened',
      );
    });
  }

  Future<void> _openServiceSettings(BuildContext context) async {
    await _closeCurrentDockAndRun(context, (rootContext) async {
      await ServiceBottomSheet.show(context: rootContext);
    });
  }

  Future<void> _runOperationalSync(BuildContext context) async {
    await _closeCurrentDockAndRun(context, (rootContext) async {
      debugPrint('[OpsDashboardSideDock] operational_sync_start');
      final result = await OperationalDataSyncWorkflow.run(
        context: rootContext,
        title: '운영 데이터 동기화',
        message: '현재 지역의 주차 구역, 섹터, 정산 데이터를 로컬에 내려받기 전 요청을 준비하고 있습니다.',
        useCommonUi: true,
      );
      debugPrint(
        '[OpsDashboardSideDock] operational_sync_result result=${result.name}',
      );
    });
  }

  Future<void> _logout(BuildContext context) async {
    await _closeCurrentDockAndRun(context, (rootContext) async {
      debugPrint('[OpsDashboardSideDock] logout_start');
      await LogoutHelper.logoutAndGoToLogin(
        rootContext,
        checkWorking: false,
        delay: const Duration(seconds: 1),
        useCommonUi: true,
      );
      debugPrint('[OpsDashboardSideDock] logout_complete');
    });
  }

  Future<void> _openSecondary(BuildContext context) async {
    _searchFocusNode.unfocus();
    debugPrint('[OpsDashboardSideDock] secondary_handoff_request');
    Navigator.of(context).pop(DashboardDockRequest.secondary);
  }

  List<_DashboardAction> _actions(
    BuildContext context,
    bool isFieldCommon, {
    required bool developerMode,
  }) {
    final tokens = CommonUiTheme.of(context);
    final canUseThirdParty = context
        .read<AreaState>()
        .capabilitiesOfCurrentArea
        .contains(Capability.record);
    final actions = <_DashboardAction>[
      _DashboardAction(
        id: 'third_party_connect',
        category: _DashboardActionCategory.thirdParty,
        label: '서드 파티 연결',
        description: canUseThirdParty
            ? '저장된 Discord 업무 채널을 앱에서 바로 엽니다.'
            : '현재 지역의 서드파티 연결 capability가 비활성화되어 있습니다.',
        icon: Icons.forum_rounded,
        color: canUseThirdParty
            ? tokens.accentContainer
            : tokens.surfaceSelected,
        foreground: canUseThirdParty
            ? tokens.onAccentContainer
            : tokens.textDisabled,
        enabled: canUseThirdParty,
        disabledReason: '서드파티 연결 capability가 필요합니다.',
        onPressed: () => _openThirdPartyChannel(context),
      ),
    ];

    if (!isFieldCommon) {
      actions.addAll([
        _DashboardAction(
          id: 'work_start_report',
          category: _DashboardActionCategory.report,
          label: '업무 시작 보고',
          description: '업무 시작 보고서를 작성합니다.',
          icon: Icons.play_circle_outline_rounded,
          color: tokens.infoContainer,
          foreground: tokens.onInfoContainer,
          onPressed: () => _runDocumentAction(
            context,
            DocumentBoxAction.openWorkStartReportForm,
          ),
        ),
        _DashboardAction(
          id: 'work_end_report',
          category: _DashboardActionCategory.report,
          label: '업무 종료 보고',
          description: '업무 종료 보고서를 작성합니다.',
          icon: Icons.task_alt_rounded,
          color: tokens.successContainer,
          foreground: tokens.onSuccessContainer,
          onPressed: () => _runDocumentAction(
            context,
            DocumentBoxAction.openWorkEndReportForm,
          ),
        ),
      ]);
    }

    actions.addAll([
      _DashboardAction(
        id: 'commute_submit',
        category: _DashboardActionCategory.submit,
        label: '출퇴근 기록 제출',
        description: '단말기의 출퇴근 기록을 서버에 제출합니다.',
        icon: Icons.sync_alt_rounded,
        color: tokens.infoContainer,
        foreground: tokens.onInfoContainer,
        onPressed: () => _runDocumentAction(
          context,
          isFieldCommon
              ? DocumentBoxAction.submitFielderCommuteRecords
              : DocumentBoxAction.submitLeaderCommuteRecords,
        ),
      ),
      _DashboardAction(
        id: 'rest_time_submit',
        category: _DashboardActionCategory.submit,
        label: '휴게시간 기록 제출',
        description: '단말기의 휴게시간 기록을 서버에 제출합니다.',
        icon: Icons.free_breakfast_rounded,
        color: tokens.successContainer,
        foreground: tokens.onSuccessContainer,
        onPressed: () => _runDocumentAction(
          context,
          isFieldCommon
              ? DocumentBoxAction.submitFielderRestTimeRecords
              : DocumentBoxAction.submitLeaderRestTimeRecords,
        ),
      ),
      _DashboardAction(
        id: 'photo_transfer',
        category: _DashboardActionCategory.submit,
        label: '사진 전송',
        description: '사진 전송 메일 화면으로 이동합니다.',
        icon: Icons.photo_camera_back_rounded,
        color: tokens.warningContainer,
        foreground: tokens.onWarningContainer,
        onPressed: () => _openPhotoTransfer(context),
      ),
      _DashboardAction(
        id: 'statement_form',
        category: _DashboardActionCategory.form,
        label: '경위서 양식',
        description: '경위서 작성 화면으로 이동합니다.',
        icon: Icons.description_rounded,
        color: tokens.warningContainer,
        foreground: tokens.onWarningContainer,
        onPressed: () => _runDocumentAction(
          context,
          DocumentBoxAction.openUserStatementForm,
        ),
      ),
      _DashboardAction(
        id: 'leave_application',
        category: _DashboardActionCategory.form,
        label: '연차 지원 신청서',
        description: '연차·결근 지원 신청서를 작성합니다.',
        icon: Icons.event_available_rounded,
        color: tokens.successContainer,
        foreground: tokens.onSuccessContainer,
        onPressed: () => _runDocumentAction(
          context,
          DocumentBoxAction.openBackupForm,
        ),
      ),
      _DashboardAction(
        id: 'faq',
        category: _DashboardActionCategory.support,
        label: 'FAQ',
        description: '자주 묻는 질문을 확인합니다.',
        icon: Icons.help_center_rounded,
        color: tokens.surfaceSelected,
        foreground: tokens.textPrimary,
        onPressed: () => _openFaq(context),
      ),
      _DashboardAction(
        id: 'terms',
        category: _DashboardActionCategory.support,
        label: '이용약관',
        description: '서비스 이용약관을 확인합니다.',
        icon: Icons.description_rounded,
        color: tokens.surfaceSelected,
        foreground: tokens.textPrimary,
        onPressed: () => _openTermsOfService(context),
      ),
      _DashboardAction(
        id: 'privacy',
        category: _DashboardActionCategory.support,
        label: '개인정보보호처리방침',
        description: '개인정보 처리 기준을 확인합니다.',
        icon: Icons.privacy_tip_rounded,
        color: tokens.infoContainer,
        foreground: tokens.onInfoContainer,
        onPressed: () => _openPrivacyPolicy(context),
      ),
    ]);

    if (developerMode) {
      actions.addAll([
        _DashboardAction(
          id: 'community',
          category: _DashboardActionCategory.form,
          label: 'Community',
          description: '개발자 모드에서 운영 커뮤니티로 이동합니다.',
          icon: Icons.groups_rounded,
          color: tokens.surfaceSelected,
          foreground: tokens.textPrimary,
          onPressed: () => _openCommunity(context),
        ),
        _DashboardAction(
          id: 'settings',
          category: _DashboardActionCategory.settings,
          label: '설정',
          description: '개발자 모드에서 서비스 설정을 조정합니다.',
          icon: Icons.settings_rounded,
          color: tokens.infoContainer,
          foreground: tokens.onInfoContainer,
          onPressed: () => _openServiceSettings(context),
        ),
      ]);
    }

    if (!isFieldCommon) {
      actions.add(
        _DashboardAction(
          id: 'secondary',
          category: _DashboardActionCategory.settings,
          label: '운영 페이지 열기',
          description: '운영 관리 Side Dock을 엽니다.',
          icon: Icons.open_in_new_rounded,
          color: tokens.successContainer,
          foreground: tokens.onSuccessContainer,
          onPressed: () => _openSecondary(context),
        ),
      );
    }

    actions.addAll([
      _DashboardAction(
        id: 'third_party_support',
        category: _DashboardActionCategory.settings,
        label: '서드파티 연결 지원',
        description: canUseThirdParty
            ? 'Discord 설치, 서버 초대, 업무 채널 링크를 설정합니다.'
            : '현재 지역의 서드파티 연결 capability가 비활성화되어 있습니다.',
        icon: Icons.extension_rounded,
        color: canUseThirdParty
            ? tokens.accentContainer
            : tokens.surfaceSelected,
        foreground: canUseThirdParty
            ? tokens.onAccentContainer
            : tokens.textDisabled,
        enabled: canUseThirdParty,
        disabledReason: '서드파티 연결 capability가 필요합니다.',
        onPressed: () => _openThirdPartySupport(context),
      ),
      _DashboardAction(
        id: 'operational_sync',
        category: _DashboardActionCategory.settings,
        label: '지금 내려받기',
        description: '현재 지역의 운영 데이터를 최신 상태로 내려받습니다.',
        icon: Icons.download_rounded,
        color: tokens.infoContainer,
        foreground: tokens.onInfoContainer,
        onPressed: () => _runOperationalSync(context),
      ),
      _DashboardAction(
        id: 'logout',
        category: _DashboardActionCategory.settings,
        label: '로그아웃',
        description: '현재 계정에서 안전하게 로그아웃합니다.',
        icon: Icons.logout_rounded,
        color: tokens.dangerContainer,
        foreground: tokens.onDangerContainer,
        onPressed: () => _logout(context),
      ),
    ]);

    return actions;
  }

  Future<void> _showDeveloperStatus(
    BuildContext context, {
    required UserState userState,
    required AreaState areaState,
  }) async {
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '운영 대시보드 상태',
      initialMessage: '대시보드 Side Dock 상태를 확인하고 있습니다.',
      useCommonUi: true,
      developerModeMessage: '개발자 모드 ON: debugPrint 코드를 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF',
    );
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final width = MediaQuery.sizeOf(context).width;
    final dockWidth = math.min(
      360.0,
      (width * 0.92).clamp(240.0, double.infinity),
    );
    final isFieldCommon = _isFieldCommon(userState);
    final developerMode = await _refreshDeveloperMode();
    final actions = _actions(
      context,
      isFieldCommon,
      developerMode: developerMode,
    );
    final filteredActions = _filterActions(actions, _searchController.text);
    final queryLength = _searchController.text.trim().length;
    final searchSectionCount = _DashboardActionCategory.values
        .where(
          (category) => filteredActions.any(
            (action) => action.category == category,
          ),
        )
        .length;
    trace.log('component=ops_dashboard_side_dock', progress: 0.03);
    trace.log('presentation=right_side_dock', progress: 0.045);
    trace.log('container=right_side_dock', progress: 0.06);
    trace.log('direction=right_to_left', progress: 0.12);
    trace.log('uiParity=quick_actions', progress: 0.18);
    trace.log('layout=single_scroll', progress: 0.24);
    trace.log(
      'topContent=work_schedule,punch_recorder,business,search',
      progress: 0.3,
    );
    trace.log('scheduleEditor=inline_weekday_editor', progress: 0.36);
    trace.log('mode=${widget.modeLabel}', progress: 0.42);
    trace.log('screenWidth=${width.toStringAsFixed(1)}', progress: 0.48);
    trace.log('dockWidth=${dockWidth.toStringAsFixed(1)}', progress: 0.54);
    trace.log('reduceMotion=$reduceMotion', progress: 0.6);
    trace.log(
      'areaConfigured=${areaState.currentArea.trim().isNotEmpty}',
      progress: 0.66,
    );
    trace.log(
      'divisionConfigured=${areaState.currentDivision.trim().isNotEmpty}',
      progress: 0.72,
    );
    final visibleSectionCount = _DashboardActionCategory.values
        .where(
          (category) => actions.any((action) => action.category == category),
        )
        .length;
    final groupCounts = _DashboardActionCategory.values
        .map(
          (category) =>
              '${category.name}:${actions.where((action) => action.category == category).length}',
        )
        .join(',');
    final hasMonthlyCapability =
        areaState.capabilitiesOfCurrentArea.contains(Capability.monthly);
    final monthlyVisible = hasMonthlyCapability && !isFieldCommon;
    trace.log('fieldCommon=$isFieldCommon', progress: 0.75);
    trace.log('monthlyCapability=$hasMonthlyCapability', progress: 0.76);
    trace.log('monthlyVisible=$monthlyVisible', progress: 0.765);
    trace.log('businessUi=dashboard_action_tile', progress: 0.768);
    trace.log('businessTileCount=${monthlyVisible ? 2 : 1}', progress: 0.769);
    trace.log('developerMode=$developerMode', progress: 0.77);
    trace.log('developerModeResolved=$_developerModeResolved', progress: 0.79);
    trace.log('settingsVisible=true', progress: 0.81);
    trace.log('communityVisible=$developerMode', progress: 0.82);
    trace.log('myInfoAction=false', progress: 0.83);
    trace.log('documentBox=false', progress: 0.85);
    trace.log('groupCounts=$groupCounts', progress: 0.87);
    trace.log('visibleSectionCount=$visibleSectionCount', progress: 0.89);
    trace.log('actionCount=${actions.length}', progress: 0.91);
    trace.log('searchActive=${queryLength > 0}', progress: 0.93);
    trace.log('searchQueryLength=$queryLength', progress: 0.95);
    trace.log('searchResultCount=${filteredActions.length}', progress: 0.97);
    trace.log('searchVisibleSectionCount=$searchSectionCount', progress: 0.98);
    trace.log('backPolicy=close_side_dock', progress: 0.99);
    await trace.succeed('대시보드 Side Dock 상태 확인을 완료했습니다.');
  }

  Widget _buildPunchRecorder(
    BuildContext context, {
    required UserState userState,
    required AreaState areaState,
  }) {
    return Semantics(
      label: '출퇴근 기록기',
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPress: () {
          debugPrint(
            '[OpsDashboardSideDock] developer_status_request source=punch_recorder',
          );
          _showDeveloperStatus(
            context,
            userState: userState,
            areaState: areaState,
          );
        },
        child: widget.punchRecorderBuilder(context, userState, areaState),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String label) {
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

  void _requestBusinessAction(
    BuildContext context,
    DashboardDockRequest request,
  ) {
    _searchFocusNode.unfocus();
    debugPrint(
      '[OpsDashboardSideDock] business_action_request action=${request.name} mode=${widget.modeLabel}',
    );
    Navigator.of(context).pop(request);
  }

  void _logBusinessVisibility({
    required bool canUseMonthly,
    required bool hasMonthlyCapability,
    required bool isFieldCommon,
  }) {
    final signature =
        '$canUseMonthly:$hasMonthlyCapability:$isFieldCommon:${widget.modeLabel}';
    if (_lastBusinessDebugSignature == signature) return;
    _lastBusinessDebugSignature = signature;
    debugPrint(
      '[OpsDashboardSideDock] business_section mode=${widget.modeLabel} monthlyVisible=$canUseMonthly monthlyCapability=$hasMonthlyCapability fieldCommon=$isFieldCommon departureVisible=true',
    );
  }

  Widget _buildBusinessSection(
    BuildContext context, {
    required UserState userState,
    required AreaState areaState,
  }) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final hasMonthlyCapability =
        areaState.capabilitiesOfCurrentArea.contains(Capability.monthly);
    final isFieldCommon = userState.role.trim() == 'fieldCommon';
    final canUseMonthly = hasMonthlyCapability && !isFieldCommon;
    _logBusinessVisibility(
      canUseMonthly: canUseMonthly,
      hasMonthlyCapability: hasMonthlyCapability,
      isFieldCommon: isFieldCommon,
    );

    final actions = <_DashboardAction>[
      if (canUseMonthly)
        _DashboardAction(
          id: 'monthly_parking',
          category: _DashboardActionCategory.business,
          label: '정기 주차',
          description: '',
          icon: Icons.dashboard_customize_rounded,
          color: tokens.accentContainer,
          foreground: tokens.onAccentContainer,
          onPressed: () async {
            _requestBusinessAction(
              context,
              DashboardDockRequest.monthlyParking,
            );
          },
        ),
      _DashboardAction(
        id: 'departure_completed',
        category: _DashboardActionCategory.business,
        label: '출차 완료',
        description: '',
        icon: Icons.directions_car_filled_rounded,
        color: tokens.successContainer,
        foreground: tokens.onSuccessContainer,
        onPressed: () async {
          _requestBusinessAction(
            context,
            DashboardDockRequest.departureCompleted,
          );
        },
      ),
    ];

    final tiles = Column(
      key: ValueKey<String>(
        canUseMonthly ? 'business:monthly_departure' : 'business:departure',
      ),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < actions.length; index++) ...[
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: _DashboardActionTile(action: actions[index]),
          ),
          if (index != actions.length - 1) const SizedBox(height: 10),
        ],
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(context, '업무'),
        const SizedBox(height: 8),
        AnimatedSize(
          duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
          curve: CommonUiMotion.standard,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
            switchInCurve: CommonUiMotion.enter,
            switchOutCurve: CommonUiMotion.exit,
            transitionBuilder: (child, animation) {
              if (reduceMotion) return child;
              final curved = CurvedAnimation(
                parent: animation,
                curve: CommonUiMotion.enter,
                reverseCurve: CommonUiMotion.exit,
              );
              return FadeTransition(
                opacity: curved,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.04),
                    end: Offset.zero,
                  ).animate(curved),
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
                    child: child,
                  ),
                ),
              );
            },
            child: tiles,
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;

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
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) async {
                        final userState = context.read<UserState>();
                        final filtered = _filterActions(
                          _actions(
                            context,
                            _isFieldCommon(userState),
                            developerMode: _developerMode,
                          ),
                          _searchController.text,
                        );
                        if (filtered.isEmpty) return;
                        final action = filtered.first;
                        if (!action.enabled) {
                          debugPrint(
                            '[OpsDashboardSideDock] action_blocked id=${action.id} source=search_submit reason=${action.disabledReason}',
                          );
                          return;
                        }
                        HapticFeedback.selectionClick();
                        debugPrint(
                          '[OpsDashboardSideDock] action_start id=${action.id} category=${action.category.name} source=search_submit',
                        );
                        try {
                          await action.onPressed();
                          debugPrint(
                            '[OpsDashboardSideDock] action_complete id=${action.id} source=search_submit',
                          );
                        } catch (error, stackTrace) {
                          debugPrint(
                            '[OpsDashboardSideDock] action_failure id=${action.id} source=search_submit error=$error\nStackTrace:\n$stackTrace',
                          );
                          rethrow;
                        }
                      },
                    ),
                  ),
                  if (_searchController.text.trim().isNotEmpty)
                    IconButton(
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        _searchController.clear();
                      },
                      icon: Icon(
                        Icons.close_rounded,
                        color: tokens.iconSecondary,
                      ),
                      tooltip: '검색어 지우기',
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionArea(
    BuildContext context,
    List<_DashboardAction> actions,
  ) {
    final query = _normalizeSearch(_searchController.text);
    final filtered = _filterActions(actions, query);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final resultKey = query.isEmpty
        ? 'all_${filtered.length}'
        : 'search_${query.hashCode}_${filtered.map((action) => action.id).join('_')}';

    Widget child;
    if (query.isNotEmpty && filtered.isEmpty) {
      final tokens = CommonUiTheme.of(context);
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
        children: _buildActionSections(
          context,
          filtered,
          query.isEmpty ? 4 : 0,
        ),
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

  List<Widget> _buildActionSections(
    BuildContext context,
    List<_DashboardAction> actions,
    int startingOrder,
  ) {
    final children = <Widget>[];
    var revealOrder = startingOrder;

    for (final category in _DashboardActionCategory.values) {
      final sectionActions = actions
          .where((action) => action.category == category)
          .toList(growable: false);
      if (sectionActions.isEmpty) continue;

      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 14));
      }

      children.add(
        _DashboardStaggeredReveal(
          key: ValueKey<String>('header_${category.name}'),
          order: revealOrder++,
          offsetY: 6,
          child: _sectionHeader(context, category.label),
        ),
      );
      children.add(const SizedBox(height: 8));

      for (var index = 0; index < sectionActions.length; index++) {
        final action = sectionActions[index];
        children.add(
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: _DashboardStaggeredReveal(
              key: ValueKey<String>('section_${category.name}_${action.id}'),
              order: revealOrder++,
              child: _DashboardActionTile(action: action),
            ),
          ),
        );
        if (index != sectionActions.length - 1) {
          children.add(const SizedBox(height: 10));
        }
      }
    }

    return children;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<UserState, AreaState>(
      builder: (context, userState, areaState, _) {
        final isFieldCommon = _isFieldCommon(userState);
        final actions = _actions(
          context,
          isFieldCommon,
          developerMode: _developerMode,
        );
        final children = <Widget>[
          const _DashboardStaggeredReveal(
            key: ValueKey<String>('work_schedule'),
            order: 0,
            offsetY: 6,
            child: DashboardWorkScheduleSurface(),
          ),
          const SizedBox(height: 14),
          _DashboardStaggeredReveal(
            key: const ValueKey<String>('punch_recorder'),
            order: 1,
            offsetY: 6,
            child: _buildPunchRecorder(
              context,
              userState: userState,
              areaState: areaState,
            ),
          ),
          const SizedBox(height: 14),
          _DashboardStaggeredReveal(
            key: const ValueKey<String>('business_actions'),
            order: 2,
            offsetY: 6,
            child: _buildBusinessSection(
              context,
              userState: userState,
              areaState: areaState,
            ),
          ),
          const SizedBox(height: 14),
          _DashboardStaggeredReveal(
            key: const ValueKey<String>('action_search'),
            order: 3,
            offsetY: 6,
            child: _buildSearchField(context),
          ),
          const SizedBox(height: 14),
          _buildActionArea(context, actions),
          const SizedBox(height: 4),
        ];

        return SingleChildScrollView(
          controller: _dockScrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        );
      },
    );
  }
}

enum _DashboardActionCategory {
  business,
  thirdParty,
  report,
  submit,
  form,
  support,
  settings,
}

extension _DashboardActionCategoryUi on _DashboardActionCategory {
  String get label {
    switch (this) {
      case _DashboardActionCategory.business:
        return '업무';
      case _DashboardActionCategory.thirdParty:
        return '서드 파티';
      case _DashboardActionCategory.report:
        return '보고';
      case _DashboardActionCategory.submit:
        return '제출';
      case _DashboardActionCategory.form:
        return '양식';
      case _DashboardActionCategory.support:
        return '지원';
      case _DashboardActionCategory.settings:
        return '설정';
    }
  }
}

class _DashboardStaggeredReveal extends StatelessWidget {
  const _DashboardStaggeredReveal({
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

class _DashboardAction {
  const _DashboardAction({
    required this.id,
    required this.category,
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
    required this.foreground,
    required this.onPressed,
    this.enabled = true,
    this.disabledReason = '',
  });

  final String id;
  final _DashboardActionCategory category;
  final String label;
  final String description;
  final IconData icon;
  final Color color;
  final Color foreground;
  final Future<void> Function() onPressed;
  final bool enabled;
  final String disabledReason;

  String get searchText =>
      <String>[id, category.label, label, description, disabledReason].join(' ');
}

class _DashboardActionTile extends StatelessWidget {
  const _DashboardActionTile({required this.action});

  final _DashboardAction action;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      label: action.label,
      enabled: action.enabled,
      child: Material(
        color: tokens.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: action.enabled
              ? () async {
                  HapticFeedback.selectionClick();
                  debugPrint(
                    '[OpsDashboardSideDock] action_start id=${action.id} category=${action.category.name}',
                  );
                  try {
                    await action.onPressed();
                    debugPrint(
                      '[OpsDashboardSideDock] action_complete id=${action.id}',
                    );
                  } catch (error, stackTrace) {
                    debugPrint(
                      '[OpsDashboardSideDock] action_failure id=${action.id} error=$error\nStackTrace:\n$stackTrace',
                    );
                    rethrow;
                  }
                }
              : null,
          child: AnimatedOpacity(
            opacity: action.enabled ? 1 : .52,
            duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
                ? Duration.zero
                : CommonUiMotion.selection,
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: tokens.borderSubtle, width: 1),
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
                    child: Icon(
                      action.icon,
                      color: action.foreground,
                      size: 22,
                    ),
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
                        if (action.description.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            action.description,
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
                  Icon(
                    Icons.chevron_right_rounded,
                    color: tokens.iconSecondary,
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
