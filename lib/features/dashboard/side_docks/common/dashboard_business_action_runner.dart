import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/models/capability.dart';
import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_side_dock.dart';
import '../../../account/applications/user_state.dart';
import '../../../dev/application/area_state.dart';
import '../../../../shared/secondary/application/secondary_info.dart';
import '../../../../shared/secondary/side_docks/secondary_side_dock.dart';
import 'dashboard_dock_request.dart';

class DashboardBusinessActionRunner {
  const DashboardBusinessActionRunner._();

  static Future<void> run({
    required BuildContext context,
    required DashboardDockRequest request,
    required Widget Function() buildDepartureCompletedSheet,
    required Map<String, dynamic> debugMeta,
  }) async {
    if (request != DashboardDockRequest.monthlyParking &&
        request != DashboardDockRequest.departureCompleted) {
      return;
    }

    final screen = debugMeta['screen']?.toString() ?? 'type_page';
    final areaState = context.read<AreaState>();
    final userState = context.read<UserState>();
    final hasMonthlyCapability =
        areaState.capabilitiesOfCurrentArea.contains(Capability.monthly);
    final roleName = userState.role.trim();
    final roleType = RoleType.fromName(roleName);
    final roleAllowsMonthly =
        (kRolePolicy[roleType] ?? const <Section>{}).contains(Section.monthly);
    final isFieldCommon = roleName == 'fieldCommon';
    final canUseMonthly =
        hasMonthlyCapability && roleAllowsMonthly && !isFieldCommon;
    final actionLabel = request == DashboardDockRequest.monthlyParking
        ? '정기 주차'
        : '출차 완료';
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '대시보드 업무 · $actionLabel',
      initialMessage: '$actionLabel 요청을 처리합니다.',
      useCommonUi: true,
      developerModeMessage:
          '개발자 모드 ON: $actionLabel debugPrint 코드를 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF',
      showDialogImmediately: false,
    );
    trace.log(
      'request=${request.name} screen=$screen area=${areaState.currentArea.trim()} role=$roleName monthlyCapability=$hasMonthlyCapability monthlyRoleAllowed=$roleAllowsMonthly monthlyVisible=$canUseMonthly',
      progress: 0.12,
    );

    Object? caughtError;
    StackTrace? caughtStackTrace;

    try {
      if (request == DashboardDockRequest.monthlyParking) {
        if (!canUseMonthly) {
          trace.log(
            'monthly_action_blocked capability=$hasMonthlyCapability roleAllowed=$roleAllowsMonthly fieldCommon=$isFieldCommon',
            progress: 0.4,
          );
          await trace.fail('정기 주차 표시 조건을 충족하지 않아 실행하지 않았습니다.');
        } else {
          trace.log('monthly_operations_open section=${Section.monthly.name}', progress: 0.38);
          await showSecondarySideDock<void>(
            context: context,
            initialSection: Section.monthly,
          );
          trace.log('monthly_operations_closed section=${Section.monthly.name}', progress: 0.9);
          await trace.succeed('정기 주차 업무를 종료했습니다.');
        }
      } else {
        trace.log('departure_completed_dock_open presentation=operations_right_side_dock rail=left', progress: 0.38);
        await showOperationsRightSideDock<void>(
          context: context,
          barrierLabel: '출차 완료',
          maxWidth: 420,
          widthFactor: .96,
          builder: (_) => buildDepartureCompletedSheet(),
        );
        trace.log('departure_completed_dock_closed presentation=operations_right_side_dock', progress: 0.9);
        await trace.succeed('출차 완료 업무를 종료했습니다.');
      }
    } catch (error, stackTrace) {
      caughtError = error;
      caughtStackTrace = stackTrace;
      await trace.fail(
        '$actionLabel 실행 중 오류가 발생했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
    }

    if (trace.developerMode && context.mounted) {
      await trace.showStatusDialog(context);
    }

    if (caughtError != null && caughtStackTrace != null) {
      Error.throwWithStackTrace(caughtError, caughtStackTrace);
    }
  }
}
