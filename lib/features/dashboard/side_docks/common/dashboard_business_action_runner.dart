import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/models/capability.dart';
import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../account/applications/user_state.dart';
import '../../../dev/application/area_state.dart';
import '../../widgets/productivity_sheet.dart';
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
    final isFieldCommon = userState.role.trim() == 'fieldCommon';
    final canUseMonthly = hasMonthlyCapability && !isFieldCommon;
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
      'request=${request.name} screen=$screen area=${areaState.currentArea.trim()} role=${userState.role.trim()} monthlyCapability=$hasMonthlyCapability monthlyVisible=$canUseMonthly',
      progress: 0.12,
    );

    Object? caughtError;
    StackTrace? caughtStackTrace;

    try {
      if (request == DashboardDockRequest.monthlyParking) {
        if (!canUseMonthly) {
          trace.log(
            'monthly_action_blocked capability=$hasMonthlyCapability fieldCommon=$isFieldCommon',
            progress: 0.4,
          );
          await trace.fail('정기 주차 표시 조건을 충족하지 않아 실행하지 않았습니다.');
        } else {
          trace.log('monthly_panel_open', progress: 0.38);
          await ProductivitySheet.togglePanel();
          trace.log('monthly_panel_closed', progress: 0.9);
          await trace.succeed('정기 주차 업무를 종료했습니다.');
        }
      } else {
        trace.log('departure_completed_sheet_open', progress: 0.38);
        await showCommonOverlayBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          transparentBackground: true,
          builder: (_) => buildDepartureCompletedSheet(),
        );
        trace.log('departure_completed_sheet_closed', progress: 0.9);
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
