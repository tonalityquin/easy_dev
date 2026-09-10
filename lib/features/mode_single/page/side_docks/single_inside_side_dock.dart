import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../design_system/common_ui/common_ui_side_dock.dart';
import '../../../../design_system/common_ui/common_ui_side_dock_action_tile.dart';
import '../../../../design_system/common_ui/common_ui_side_dock_frame.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../shared/utils/side_dock_action_catalog.dart';
import '../../../dashboard/widgets/widgets/schedule/weekly_work_schedule_editor.dart';
import '../../application/single_inside_diagnostics.dart';
import '../widgets/widgets/single_inside_punch_recorder_section.dart';

enum SingleInsideDockRequest {
  workStartReport,
  workEndReport,
  commuteSubmit,
  restTimeSubmit,
  statementForm,
  leaveApplication,
  operations,
  operationalSync,
  logout,
  exitApp,
}

Future<SingleInsideDockRequest?> showSingleInsideSideDock({
  required BuildContext context,
  required String userId,
  required String userName,
  required String area,
  required String division,
  required int scheduleRevision,
  required VoidCallback onScheduleChanged,
  required Future<void> Function() onDeveloperStatus,
  required bool showReport,
  required bool showOperations,
}) async {
  SingleInsideDiagnostics.log(
    'menu',
    'dock_open userId=$userId area=$area division=$division showReport=$showReport showOperations=$showOperations scheduleRevision=$scheduleRevision',
  );
  final result = await showCommonRightSideDock<SingleInsideDockRequest>(
    context: context,
    barrierLabel: '싱글 메뉴',
    builder: (_) => _SingleInsideSideDock(
      userId: userId,
      userName: userName,
      area: area,
      division: division,
      scheduleRevision: scheduleRevision,
      onScheduleChanged: onScheduleChanged,
      onDeveloperStatus: onDeveloperStatus,
      showReport: showReport,
      showOperations: showOperations,
    ),
  );
  SingleInsideDiagnostics.log(
    'menu',
    'dock_closed request=${result?.name ?? 'dismissed'}',
  );
  return result;
}

class _SingleInsideSideDock extends StatefulWidget {
  const _SingleInsideSideDock({
    required this.userId,
    required this.userName,
    required this.area,
    required this.division,
    required this.scheduleRevision,
    required this.onScheduleChanged,
    required this.onDeveloperStatus,
    required this.showReport,
    required this.showOperations,
  });

  final String userId;
  final String userName;
  final String area;
  final String division;
  final int scheduleRevision;
  final VoidCallback onScheduleChanged;
  final Future<void> Function() onDeveloperStatus;
  final bool showReport;
  final bool showOperations;

  @override
  State<_SingleInsideSideDock> createState() => _SingleInsideSideDockState();
}

class _SingleInsideSideDockState extends State<_SingleInsideSideDock> {
  final ScrollController _dockScrollController = ScrollController();
  late int _scheduleRevision;

  @override
  void initState() {
    super.initState();
    _scheduleRevision = widget.scheduleRevision;
  }

  @override
  void dispose() {
    _dockScrollController.dispose();
    super.dispose();
  }

  Future<void> _handleDeveloperStatus() async {
    SingleInsideDiagnostics.log(
      'status',
      'developer_status_request source=punch_recorder_long_press',
    );
    await widget.onDeveloperStatus();
  }

  void _select(BuildContext context, SingleInsideDockRequest request) {
    HapticFeedback.selectionClick();
    SingleInsideDiagnostics.log('menu', 'action_selected request=${request.name}');
    Navigator.of(context).pop(request);
  }

  void _handleScheduleChanged() {
    if (!mounted) return;
    setState(() => _scheduleRevision++);
    widget.onScheduleChanged();
    SingleInsideDiagnostics.log(
      'schedule',
      'changed source=single_side_dock revision=$_scheduleRevision',
    );
  }

  Widget _action({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String description,
    required SingleInsideDockRequest request,
    Color? accentColor,
    Color? foregroundColor,
  }) {
    return CommonSideDockActionTile(
      icon: icon,
      title: title,
      description: description,
      accentColor: accentColor,
      foregroundColor: foregroundColor,
      onTap: () => _select(context, request),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    var order = 0;

    return SingleChildScrollView(
      controller: _dockScrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const ClampingScrollPhysics(),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CommonSideDockSection(
            title: '근무',
            order: order++,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CommonSideDockReveal(
                  order: order++,
                  offsetY: 7,
                  child: WeeklyWorkScheduleEditor(
                    source: 'single_side_dock',
                    onChanged: _handleScheduleChanged,
                  ),
                ),
                const SizedBox(height: 10),
                CommonSideDockReveal(
                  order: order++,
                  offsetY: 7,
                  child: AnimatedSwitcher(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 190),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      if (reduceMotion) return child;
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, .025),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: SingleInsidePunchRecorderSection(
                      key: ValueKey<int>(_scheduleRevision),
                      userId: widget.userId,
                      userName: widget.userName,
                      area: widget.area,
                      division: widget.division,
                      scheduleRevision: _scheduleRevision,
                      onDeveloperStatus: _handleDeveloperStatus,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (widget.showReport) ...[
            const SizedBox(height: 14),
            CommonSideDockSection(
              title: SideDockActionCatalog.sectionReport,
              order: order++,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _action(
                    context: context,
                    icon: SideDockActionCatalog.workStartReportIcon,
                    title: SideDockActionCatalog.workStartReportLabel,
                    description:
                        SideDockActionCatalog.workStartReportDescription,
                    request: SingleInsideDockRequest.workStartReport,
                    accentColor: tokens.infoContainer,
                    foregroundColor: tokens.onInfoContainer,
                  ),
                  const SizedBox(height: 10),
                  _action(
                    context: context,
                    icon: SideDockActionCatalog.workEndReportIcon,
                    title: SideDockActionCatalog.workEndReportLabel,
                    description:
                        SideDockActionCatalog.workEndReportDescription,
                    request: SingleInsideDockRequest.workEndReport,
                    accentColor: tokens.successContainer,
                    foregroundColor: tokens.onSuccessContainer,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          CommonSideDockSection(
            title: SideDockActionCatalog.sectionSubmit,
            order: order++,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _action(
                  context: context,
                  icon: SideDockActionCatalog.commuteSubmitIcon,
                  title: SideDockActionCatalog.commuteSubmitLabel,
                  description:
                      SideDockActionCatalog.commuteSubmitDescription,
                  request: SingleInsideDockRequest.commuteSubmit,
                  accentColor: tokens.infoContainer,
                  foregroundColor: tokens.onInfoContainer,
                ),
                const SizedBox(height: 10),
                _action(
                  context: context,
                  icon: SideDockActionCatalog.restTimeSubmitIcon,
                  title: SideDockActionCatalog.restTimeSubmitLabel,
                  description:
                      SideDockActionCatalog.restTimeSubmitDescription,
                  request: SingleInsideDockRequest.restTimeSubmit,
                  accentColor: tokens.successContainer,
                  foregroundColor: tokens.onSuccessContainer,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          CommonSideDockSection(
            title: SideDockActionCatalog.sectionForm,
            order: order++,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _action(
                  context: context,
                  icon: SideDockActionCatalog.statementFormIcon,
                  title: SideDockActionCatalog.statementFormLabel,
                  description:
                      SideDockActionCatalog.statementFormDescription,
                  request: SingleInsideDockRequest.statementForm,
                  accentColor: tokens.warningContainer,
                  foregroundColor: tokens.onWarningContainer,
                ),
                const SizedBox(height: 10),
                _action(
                  context: context,
                  icon: SideDockActionCatalog.leaveApplicationIcon,
                  title: SideDockActionCatalog.leaveApplicationLabel,
                  description:
                      SideDockActionCatalog.leaveApplicationDescription,
                  request: SingleInsideDockRequest.leaveApplication,
                  accentColor: tokens.successContainer,
                  foregroundColor: tokens.onSuccessContainer,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          CommonSideDockSection(
            title: SideDockActionCatalog.sectionSettings,
            order: order++,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.showOperations) ...[
                  _action(
                    context: context,
                    icon: SideDockActionCatalog.operationsIcon,
                    title: SideDockActionCatalog.operationsLabel,
                    description: SideDockActionCatalog.operationsDescription,
                    request: SingleInsideDockRequest.operations,
                    accentColor: tokens.successContainer,
                    foregroundColor: tokens.onSuccessContainer,
                  ),
                  const SizedBox(height: 10),
                ],
                _action(
                  context: context,
                  icon: SideDockActionCatalog.operationalSyncIcon,
                  title: SideDockActionCatalog.operationalSyncLabel,
                  description: SideDockActionCatalog.operationalSyncDescription,
                  request: SingleInsideDockRequest.operationalSync,
                  accentColor: tokens.infoContainer,
                  foregroundColor: tokens.onInfoContainer,
                ),
                const SizedBox(height: 10),
                _action(
                  context: context,
                  icon: SideDockActionCatalog.logoutIcon,
                  title: SideDockActionCatalog.logoutLabel,
                  description: SideDockActionCatalog.logoutDescription,
                  request: SingleInsideDockRequest.logout,
                  accentColor: tokens.dangerContainer,
                  foregroundColor: tokens.onDangerContainer,
                ),
                const SizedBox(height: 10),
                _action(
                  context: context,
                  icon: Icons.power_settings_new_rounded,
                  title: '앱 종료',
                  description: '현재 앱을 종료합니다.',
                  request: SingleInsideDockRequest.exitApp,
                  accentColor: tokens.dangerContainer,
                  foregroundColor: tokens.onDangerContainer,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
