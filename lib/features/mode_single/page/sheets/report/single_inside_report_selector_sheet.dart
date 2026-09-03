import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../app/utils/status_dialog.dart';
import '../../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../../design_system/common_ui/common_ui_side_dock.dart';
import '../../../../../design_system/common_ui/common_ui_side_dock_frame.dart';
import '../../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../../shared/document/work_start_report/dashboard_start_report_form_page.dart';
import '../../../../../shared/secondary/widgets/ops_console_widgets.dart';
import '../../../../selector/application/dev_auth.dart';
import '../../widgets/widgets/single_inside_report_bottom_sheet.dart';

enum _SingleReportSheetResult {
  workStart,
  workEnd,
}

class _SingleReportSelectorDiagnostics {
  static const int _limit = 100;
  static final List<String> _lines = <String>[];

  static void log(String message) {
    final normalized = message.trim();
    if (normalized.isEmpty) return;
    final line =
        '[SingleReportSelector][${DateTime.now().toIso8601String()}] $normalized';
    _lines.add(line);
    if (_lines.length > _limit) {
      _lines.removeRange(0, _lines.length - _limit);
    }
    debugPrint(line);
  }

  static String get debugPrintCode {
    if (_lines.isEmpty) {
      return 'debugPrint(${jsonEncode('[SingleReportSelector] 기록된 로그가 없습니다.')});';
    }
    return _lines.map((line) => 'debugPrint(${jsonEncode(line)});').join('\n');
  }

  static Future<void> showStatus(BuildContext context) async {
    final enabled = await DevAuth.isDevModeEnabled();
    if (!enabled || !context.mounted) return;
    log('developer_status_open');
    await StatusDialog.showSuccess(
      context,
      title: '업무 보고 상태',
      description: <String>[
        'Single 업무 보고 선택 상태',
        '업무 시작=Dashboard 공용',
        '업무 종료=Single 전용',
        'debugPrint 코드를 복사할 수 있습니다.',
      ].join('\n'),
      copyText: debugPrintCode,
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: Duration.zero,
      useCommonUi: true,
      awaitManualClose: true,
    );
  }
}

Future<void> openSingleInsideReportSelectorSheet(BuildContext context) async {
  _SingleReportSelectorDiagnostics.log('route_push');
  final result = await showOperationsRightSideDock<_SingleReportSheetResult>(
    context: context,
    useRootNavigator: false,
    barrierLabel: '업무 보고',
    maxWidth: 360,
    widthFactor: .92,
    barrierDismissible: true,
    builder: (_) => const _SingleReportSelectorDock(),
  );
  _SingleReportSelectorDiagnostics.log(
    'route_closed result=${result?.name ?? 'none'}',
  );
  if (result == null || !context.mounted) return;

  switch (result) {
    case _SingleReportSheetResult.workStart:
      _SingleReportSelectorDiagnostics.log(
        'open work_start target=dashboard_shared',
      );
      await showDashboardStartReportSideDock(context: context);
      _SingleReportSelectorDiagnostics.log(
        'closed work_start target=dashboard_shared',
      );
      break;
    case _SingleReportSheetResult.workEnd:
      await showSingleInsideReportSideDock(context);
      break;
  }
}

class _SingleReportSelectorDock extends StatelessWidget {
  const _SingleReportSelectorDock();

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return CommonSideDockFrame(
      title: '업무 보고',
      subtitle: 'Single',
      icon: Icons.assignment_outlined,
      onClose: () => Navigator.of(context).pop(),
      onLongPress: () => _SingleReportSelectorDiagnostics.showStatus(context),
      headerAction: ValueListenableBuilder<bool>(
        valueListenable: DevAuth.devModeEnabled,
        builder: (context, enabled, _) {
          if (!enabled) return const SizedBox.shrink();
          return IconButton(
            tooltip: '상태 확인',
            onPressed: () => _SingleReportSelectorDiagnostics.showStatus(context),
            icon: const Icon(Icons.bug_report_rounded),
          );
        },
      ),
      child: OpsDockListSurface(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CommonAnimatedReveal(
              child: _SingleReportSelectorRow(
                icon: Icons.wb_sunny_outlined,
                label: '업무 시작 보고서',
                onTap: () {
                  _SingleReportSelectorDiagnostics.log('select work_start');
                  HapticFeedback.selectionClick();
                  Navigator.of(context).pop(_SingleReportSheetResult.workStart);
                },
              ),
            ),
            Divider(height: 1, thickness: 1, color: tokens.borderSubtle),
            CommonAnimatedReveal(
              delay: const Duration(milliseconds: 60),
              child: _SingleReportSelectorRow(
                icon: Icons.nights_stay_outlined,
                label: '업무 종료 보고서',
                onTap: () {
                  _SingleReportSelectorDiagnostics.log('select work_end');
                  HapticFeedback.selectionClick();
                  Navigator.of(context).pop(_SingleReportSheetResult.workEnd);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SingleReportSelectorRow extends StatefulWidget {
  const _SingleReportSelectorRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_SingleReportSelectorRow> createState() =>
      _SingleReportSelectorRowState();
}

class _SingleReportSelectorRowState extends State<_SingleReportSelectorRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Semantics(
      button: true,
      label: widget.label,
      child: AnimatedScale(
        scale: _pressed ? .985 : 1,
        duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
        curve: CommonUiMotion.enter,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            onHighlightChanged: (value) {
              if (!mounted || _pressed == value) return;
              setState(() => _pressed = value);
            },
            child: AnimatedContainer(
              duration:
                  reduceMotion ? Duration.zero : CommonUiMotion.selection,
              curve: CommonUiMotion.standard,
              color: _pressed
                  ? tokens.surfaceSelected.withOpacity(.6)
                  : Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration:
                        reduceMotion ? Duration.zero : CommonUiMotion.selection,
                    curve: CommonUiMotion.standard,
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: tokens.accentContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Icon(widget.icon, color: tokens.accent, size: 21),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: tokens.iconSecondary,
                    size: 22,
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
