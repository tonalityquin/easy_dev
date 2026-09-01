import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/di/routes.dart';
import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../app/utils/snackbar_helper.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../shared/plate/application/double/double_plate_state.dart';
import '../../../../shared/plate/application/minor/minor_plate_state.dart';
import '../../../../shared/plate/application/triple/triple_plate_state.dart';
import '../../../../shared/secondary/side_docks/secondary_side_dock.dart';
import '../../../../shared/work_session/application/work_area_session_coordinator.dart';
import '../../../account/applications/user_state.dart';
import '../../../dashboard/side_docks/common/headquarter_work_area_side_dock.dart';
import '../../../dev/application/area_state.dart';
import '../../../dev/domain/repositories/area_repo_package/area_repository.dart';
import '../../../selector/application/dev_auth.dart';
import '../../../launcher/application/app_mode_registry.dart';
import '../headquarter_dashboard_context.dart';
import '../snapshot/headquarter_snapshot_repository.dart';

class HeadquarterContextNavigationCoordinator {
  HeadquarterContextNavigationCoordinator._();

  static const Set<String> _workModes = <String>{
    'single',
    'double',
    'triple',
    'minor',
  };

  static Future<void> openNavigationDock({
    required BuildContext context,
    required String currentModeKey,
    required String currentScreen,
    String source = 'unknown',
  }) async {
    final normalizedCurrent =
        HeadquarterDashboardContext.normalizeModeKey(currentModeKey);
    debugPrint(
      '[HQ-CONTEXT-NAV] dock_open source=$source screen=$currentScreen currentMode=$normalizedCurrent selectionOrder=area_then_mode dataSource=sqlite firebaseRead=0 firebaseWrite=0',
    );
    final result = await showHeadquarterWorkAreaSideDock(
      context: context,
      currentModeKey: normalizedCurrent,
      currentScreen: currentScreen,
    );
    if (result == null || !context.mounted) {
      debugPrint(
        '[HQ-CONTEXT-NAV] dock_close source=$source result=none',
      );
      return;
    }

    if (result.openSecondary) {
      debugPrint(
        '[HQ-CONTEXT-NAV] secondary_open source=$source currentMode=$normalizedCurrent',
      );
      await showSecondarySideDock<void>(
        context: context,
        barrierLabel: '운영 관리',
      );
      return;
    }

    if (result.areaName.trim().isNotEmpty) {
      await navigateToArea(
        context: context,
        currentModeKey: normalizedCurrent,
        targetModeKey: result.modeKey,
        targetArea: result.areaName,
        source: source,
      );
      return;
    }

    if (result.openSprint) {
      await _navigateToSprint(
        context: context,
        currentModeKey: normalizedCurrent,
        source: source,
      );
    }
  }

  static Future<void> navigateToArea({
    required BuildContext context,
    required String currentModeKey,
    required String targetModeKey,
    required String targetArea,
    String source = 'unknown',
  }) async {
    final currentMode =
        HeadquarterDashboardContext.normalizeModeKey(currentModeKey);
    final targetMode =
        HeadquarterDashboardContext.normalizeModeKey(targetModeKey);
    final areaName = targetArea.trim();
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '헤드쿼터 이동',
      initialMessage: 'SQLite Snapshot에서 이동 대상을 확인하고 있습니다.',
      useCommonUi: true,
      showDialogImmediately: false,
      developerModeMessage:
          '개발자 모드 ON: 이동 상태와 debugPrint 코드를 확인할 수 있습니다.',
      standardModeMessage: 'SQLite 로컬 데이터만 사용합니다.',
    );

    Future<void> fail(
      String message, {
      Object? error,
      StackTrace? stackTrace,
    }) async {
      await trace.fail(
        message,
        error: error,
        stackTrace: stackTrace,
      );
      if (!context.mounted) return;
      if (trace.developerMode) {
        await trace.showSnapshotStatusDialog(
          context,
          title: '헤드쿼터 이동 실패',
          description: message,
          failure: true,
        );
      } else {
        showFailedSnackbar(context, message, useCommonUi: true);
      }
    }

    try {
      trace.log(
        'navigation_start source=$source currentMode=${currentMode.isEmpty ? 'none' : currentMode} targetMode=${targetMode.isEmpty ? 'none' : targetMode} targetArea=$areaName selectionOrder=area_then_mode firebaseRead=0 firebaseWrite=0',
        progress: 0.08,
      );
      if (areaName.isEmpty) {
        await fail('이동할 업무 지역 정보가 올바르지 않습니다.');
        return;
      }

      final userState = context.read<UserState>();
      final division = userState.division.trim();
      final userAreaNames = (userState.session?.areas ?? const <String>[])
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet();
      if (!userAreaNames.contains(areaName)) {
        await fail('현재 계정에서 선택한 업무 지역을 사용할 수 없습니다.');
        return;
      }
      if (division.isEmpty) {
        await fail('회사 정보가 없어 업무 지역을 확인할 수 없습니다.');
        return;
      }

      trace.log(
        'sqlite_read_start division=$division area=$areaName',
        progress: 0.18,
      );
      final snapshotArea = await HeadquarterSnapshotRepository.instance.readArea(
        division: division,
        area: areaName,
      );
      if (!context.mounted) return;
      if (snapshotArea == null) {
        await fail('본사 다운로드 데이터에서 선택한 지역을 찾을 수 없습니다.');
        return;
      }

      trace.log(
        'sqlite_read_complete area=${snapshotArea.name} modes=${snapshotArea.modes.join(',')} isHeadquarter=${snapshotArea.isHeadquarter} capabilities=${snapshotArea.capabilities.map((value) => value.name).join(',')}',
        progress: 0.32,
      );

      if (snapshotArea.isHeadquarter) {
        final routeName = AppRoutes.headquarterPage;
        final builder = appRoutes[routeName];
        if (builder == null) {
          await fail('이동할 본사 화면을 찾을 수 없습니다.');
          return;
        }
        final areaState = context.read<AreaState>();
        final currentArea = areaState.currentArea.trim();
        final previousRecord = areaState.currentRecord;
        if (currentArea == areaName && previousRecord?.isHeadquarter == true) {
          HeadquarterDashboardContext.clearMode(
            source: 'headquarter_context_navigation_noop:$source',
          );
          trace.log(
            'navigation_noop reason=already_headquarter area=$areaName modeIndependent=true',
            progress: 0.9,
          );
          await trace.succeed('현재 본사 업무 지역을 유지합니다.');
          if (trace.developerMode && context.mounted) {
            await trace.showSnapshotStatusDialog(
              context,
              title: '헤드쿼터 이동 상태',
              description: '이미 현재 본사 업무 지역입니다.',
            );
          }
          return;
        }

        if (currentMode.isNotEmpty || currentArea != areaName) {
          _disableModePlateState(context, currentMode);
          trace.log(
            'plate_cleanup mode=${currentMode.isEmpty ? 'none' : currentMode} reason=headquarter_context_change prevents_pre_navigation_refresh=true',
            progress: 0.44,
          );
        }
        final record = AreaRecord(
          name: snapshotArea.name,
          division: snapshotArea.division,
          email: snapshotArea.email,
          invite: snapshotArea.invite,
          communication: snapshotArea.communication,
          capabilities: snapshotArea.capabilities,
          modes: snapshotArea.modes.toList(growable: false),
          isHeadquarter: true,
        );
        areaState.applyLocalAreaRecord(
          record,
          source: 'headquarter_context_navigation:$source',
          syncWorkSession: false,
        );
        userState.setCurrentAreaLocalOnly(
          snapshotArea.name,
          source: 'headquarter_context_navigation:$source',
        );
        HeadquarterDashboardContext.clearMode(
          source: 'headquarter_context_navigation:$source',
        );
        final homeArea = userState.area.trim();
        final homeIsHeadquarter = homeArea.isNotEmpty && homeArea == areaName
            ? true
            : null;
        final sessionResult = await WorkAreaSessionCoordinator.activate(
          currentArea: snapshotArea.name,
          division: division,
          homeArea: homeArea,
          mode: '',
          currentIsHeadquarter: true,
          homeIsHeadquarter: homeIsHeadquarter,
          source: 'headquarter_context_navigation:$source',
          persistMode: false,
          useStoredModeFallback: false,
        );
        trace.log(
          'local_context_applied mode=none area=${snapshotArea.name} isHeadquarter=true homeArea=$homeArea ttsMode=${sessionResult.mode} persistMode=false storedModeFallback=false publishMode=false route=$routeName firebaseRead=0 firebaseWrite=0',
          progress: 0.78,
        );
        await trace.succeed('SQLite 기준 본사 업무 지역 전환이 완료되었습니다.');
        if (!context.mounted) return;
        if (trace.developerMode) {
          await trace.showSnapshotStatusDialog(
            context,
            title: '헤드쿼터 이동 상태',
            description: '본사 · ${snapshotArea.name}로 이동합니다.',
          );
        }
        if (!context.mounted) return;
        final reduceMotion =
            MediaQuery.maybeOf(context)?.disableAnimations ?? false;
        debugPrint(
          '[HQ-CONTEXT-NAV] navigate source=$source fromMode=${currentMode.isEmpty ? 'none' : currentMode} fromArea=$currentArea toMode=none toArea=${snapshotArea.name} isHeadquarter=true modeIndependent=true persistMode=false publishMode=false storedModeFallback=false route=$routeName dataSource=sqlite firebaseRead=0 firebaseWrite=0 reduceMotion=$reduceMotion',
        );
        Navigator.of(context).pushReplacement(
          _buildRoute(
            routeName: routeName,
            builder: builder,
            reduceMotion: reduceMotion,
          ),
        );
        return;
      }

      if (!_workModes.contains(targetMode)) {
        await fail('선택한 지역에서 사용할 업무 모드를 선택하세요.');
        return;
      }
      final userModeIds = AppModeRegistry.supportedModes(
        userState.session?.modes ?? const <String>[],
        allowedIds: _workModes,
      ).map((mode) => mode.id).toSet();
      if (!userModeIds.contains(targetMode)) {
        await fail('현재 계정에서 해당 업무 모드를 사용할 수 없습니다.');
        return;
      }
      if (!snapshotArea.supportsMode(targetMode)) {
        await fail('선택한 지역은 해당 업무 모드를 지원하지 않습니다.');
        return;
      }
      final routeName = _routeFor(
        modeKey: targetMode,
        isHeadquarter: false,
      );
      final builder = routeName == null ? null : appRoutes[routeName];
      if (routeName == null || builder == null) {
        await fail('이동할 화면을 찾을 수 없습니다.');
        return;
      }

      final areaState = context.read<AreaState>();
      final currentArea = areaState.currentArea.trim();
      final homeArea = userState.area.trim();
      final previousRecord = areaState.currentRecord;
      final homeIsHeadquarter =
          homeArea.isNotEmpty && homeArea == currentArea
              ? previousRecord?.isHeadquarter
              : null;
      if (currentMode == targetMode && currentArea == areaName) {
        trace.log(
          'navigation_noop reason=already_current mode=$targetMode area=$areaName',
          progress: 0.9,
        );
        await trace.succeed('현재 업무 지역을 유지합니다.');
        if (trace.developerMode && context.mounted) {
          await trace.showSnapshotStatusDialog(
            context,
            title: '헤드쿼터 이동 상태',
            description: '이미 현재 업무 지역입니다.',
          );
        }
        return;
      }

      final modeChanged = currentMode.isNotEmpty && currentMode != targetMode;
      final areaChanged = currentArea != areaName;
      if (modeChanged || areaChanged) {
        _disableModePlateState(context, currentMode);
        trace.log(
          'plate_cleanup mode=${currentMode.isEmpty ? 'none' : currentMode} reason=context_change prevents_pre_navigation_refresh=true',
          progress: 0.44,
        );
      }

      final record = AreaRecord(
        name: snapshotArea.name,
        division: snapshotArea.division,
        email: snapshotArea.email,
        invite: snapshotArea.invite,
        communication: snapshotArea.communication,
        capabilities: snapshotArea.capabilities,
        modes: snapshotArea.modes.toList(growable: false),
        isHeadquarter: false,
      );
      areaState.applyLocalAreaRecord(
        record,
        source: 'headquarter_context_navigation:$source',
        syncWorkSession: false,
      );
      userState.setCurrentAreaLocalOnly(
        snapshotArea.name,
        source: 'headquarter_context_navigation:$source',
      );
      HeadquarterDashboardContext.publishMode(
        targetMode,
        source: 'headquarter_context_navigation:$source',
      );
      final sessionResult = await WorkAreaSessionCoordinator.activate(
        currentArea: snapshotArea.name,
        division: division,
        homeArea: homeArea,
        mode: targetMode,
        currentIsHeadquarter: false,
        homeIsHeadquarter: homeIsHeadquarter,
        source: 'headquarter_context_navigation:$source',
      );
      trace.log(
        'local_context_applied mode=$targetMode area=${snapshotArea.name} isHeadquarter=false homeArea=$homeArea ttsMode=${sessionResult.mode} foreground=${sessionResult.foregroundServiceRunning} appFallback=${sessionResult.appFallbackListening} route=$routeName firebaseRead=0 firebaseWrite=0',
        progress: 0.78,
      );

      await trace.succeed('SQLite 기준 업무 지역 전환과 TTS 재바인딩이 완료되었습니다.');
      if (!context.mounted) return;
      if (trace.developerMode) {
        await trace.showSnapshotStatusDialog(
          context,
          title: '헤드쿼터 이동 상태',
          description:
              '${HeadquarterDashboardContext.exactModeLabel(targetMode)} · ${snapshotArea.name}로 이동합니다.',
        );
      }
      if (!context.mounted) return;

      final reduceMotion =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      debugPrint(
        '[HQ-CONTEXT-NAV] navigate source=$source fromMode=${currentMode.isEmpty ? 'none' : currentMode} fromArea=$currentArea toMode=$targetMode toArea=${snapshotArea.name} isHeadquarter=false route=$routeName dataSource=sqlite firebaseRead=0 firebaseWrite=0 reduceMotion=$reduceMotion',
      );
      Navigator.of(context).pushReplacement(
        _buildRoute(
          routeName: routeName,
          builder: builder,
          reduceMotion: reduceMotion,
        ),
      );
    } catch (error, stackTrace) {
      await fail(
        '업무 지역 이동 중 오류가 발생했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static Future<void> _navigateToSprint({
    required BuildContext context,
    required String currentModeKey,
    required String source,
  }) async {
    final developerMode = await DevAuth.isDevModeEnabled();
    if (!context.mounted) return;
    if (!developerMode) {
      showFailedSnackbar(
        context,
        '스프린트 모드는 개발자 모드에서만 사용할 수 있습니다.',
        useCommonUi: true,
      );
      return;
    }
    final builder = appRoutes[AppRoutes.sprintModeLoading];
    if (builder == null) {
      showFailedSnackbar(
        context,
        '이동할 화면을 찾을 수 없습니다.',
        useCommonUi: true,
      );
      return;
    }
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    debugPrint(
      '[HQ-CONTEXT-NAV] sprint_navigate source=$source currentMode=$currentModeKey firebaseRead=0 firebaseWrite=0 reduceMotion=$reduceMotion',
    );
    Navigator.of(context).pushReplacement(
      _buildRoute(
        routeName: AppRoutes.sprintModeLoading,
        builder: builder,
        reduceMotion: reduceMotion,
        duration: 420,
        vertical: true,
        scale: true,
        arguments: <String, String>{
          'returnRouteName': _headquarterRouteFor(),
        },
      ),
    );
  }

  static void _disableModePlateState(
    BuildContext context,
    String modeKey,
  ) {
    switch (modeKey) {
      case 'double':
        context.read<DoublePlateState>().doubleDisableAll();
        return;
      case 'triple':
        context.read<TriplePlateState>().tripleDisableAll();
        return;
      case 'minor':
        context.read<MinorPlateState>().minorDisableAll();
        return;
      default:
        return;
    }
  }

  static String? _routeFor({
    required String modeKey,
    required bool isHeadquarter,
  }) {
    if (isHeadquarter) return AppRoutes.headquarterPage;
    switch (modeKey) {
      case 'single':
        return AppRoutes.singleCommute;
      case 'double':
        return AppRoutes.doubleTypePage;
      case 'triple':
        return AppRoutes.tripleTypePage;
      case 'minor':
        return AppRoutes.minorTypePage;
      default:
        return null;
    }
  }

  static String _headquarterRouteFor() {
    return AppRoutes.headquarterPage;
  }

  static PageRouteBuilder<void> _buildRoute({
    required String routeName,
    required WidgetBuilder builder,
    required bool reduceMotion,
    int duration = 240,
    bool vertical = false,
    bool scale = false,
    Object? arguments,
  }) {
    final transitionDuration =
        reduceMotion ? Duration.zero : Duration(milliseconds: duration);
    return PageRouteBuilder<void>(
      settings: RouteSettings(name: routeName, arguments: arguments),
      transitionDuration: transitionDuration,
      reverseTransitionDuration: transitionDuration,
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
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
              begin: vertical ? const Offset(0, .045) : const Offset(.035, 0),
              end: Offset.zero,
            ).animate(curved),
            child: ScaleTransition(
              scale: Tween<double>(
                begin: scale ? .985 : 1,
                end: 1,
              ).animate(curved),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
