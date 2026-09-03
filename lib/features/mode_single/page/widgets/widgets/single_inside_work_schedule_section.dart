import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../app/utils/status_dialog.dart';
import '../../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../../design_system/common_ui/common_ui_side_dock.dart';
import '../../../../../design_system/common_ui/common_ui_side_dock_frame.dart';
import '../../../../dashboard/widgets/widgets/schedule/weekly_work_schedule_editor.dart';
import '../../../../selector/application/dev_auth.dart';

class _SingleWorkScheduleDiagnostics {
  static const int _limit = 120;
  static final List<String> _lines = <String>[];

  static void log(String message) {
    final normalized = message.trim();
    if (normalized.isEmpty) return;
    final line =
        '[SingleWorkSchedule][${DateTime.now().toIso8601String()}] $normalized';
    _lines.add(line);
    if (_lines.length > _limit) {
      _lines.removeRange(0, _lines.length - _limit);
    }
    debugPrint(line);
  }

  static String get debugPrintCode {
    if (_lines.isEmpty) {
      return 'debugPrint(${jsonEncode('[SingleWorkSchedule] 기록된 로그가 없습니다.')});';
    }
    return _lines.map((line) => 'debugPrint(${jsonEncode(line)});').join('\n');
  }

  static Future<void> showStatus(BuildContext context) async {
    final enabled = await DevAuth.isDevModeEnabled();
    if (!enabled || !context.mounted) return;
    log('developer_status_open');
    await StatusDialog.showSuccess(
      context,
      title: '근무 일정 상태',
      description: 'Single 근무 일정의 debugPrint 코드를 복사할 수 있습니다.',
      copyText: debugPrintCode,
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: Duration.zero,
      useCommonUi: true,
      awaitManualClose: true,
    );
  }
}

class SingleInsideWorkScheduleSection extends StatelessWidget {
  const SingleInsideWorkScheduleSection({
    super.key,
    required this.onChanged,
  });

  final VoidCallback onChanged;

  Future<void> _openEditor(BuildContext context) async {
    _SingleWorkScheduleDiagnostics.log('summary_edit_request');
    HapticFeedback.selectionClick();
    await openSingleInsideWorkScheduleSideDock(
      context,
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    return CommonAnimatedReveal(
      delay: const Duration(milliseconds: 45),
      offset: const Offset(0, 0.025),
      child: WeeklyWorkScheduleEditor(
        source: 'single_surface',
        presentation: WeeklyWorkSchedulePresentation.summaryOnly,
        compactSummary: true,
        onEditRequested: () => _openEditor(context),
      ),
    );
  }
}

enum _SingleWorkScheduleMenuAction {
  developerStatus,
}

Future<void> openSingleInsideWorkScheduleSideDock(
  BuildContext context, {
  required VoidCallback onChanged,
}) async {
  _SingleWorkScheduleDiagnostics.log('route_push');
  await showOperationsRightSideDock<void>(
    context: context,
    useRootNavigator: false,
    barrierLabel: '근무 일정',
    maxWidth: 360,
    widthFactor: .92,
    barrierDismissible: true,
    builder: (_) => _SingleWorkScheduleDock(onChanged: onChanged),
  );
  _SingleWorkScheduleDiagnostics.log('route_closed');
}

class _SingleWorkScheduleDock extends StatelessWidget {
  const _SingleWorkScheduleDock({required this.onChanged});

  final VoidCallback onChanged;

  void _handleChanged() {
    _SingleWorkScheduleDiagnostics.log('schedule_changed');
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return CommonSideDockFrame(
      title: '근무 일정',
      subtitle: 'Single',
      icon: Icons.calendar_month_rounded,
      onClose: () {
        _SingleWorkScheduleDiagnostics.log('close_request');
        Navigator.of(context).pop();
      },
      onLongPress: () => _SingleWorkScheduleDiagnostics.showStatus(context),
      headerAction: ValueListenableBuilder<bool>(
        valueListenable: DevAuth.devModeEnabled,
        builder: (context, enabled, _) {
          return AnimatedSwitcher(
            duration:
                reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              if (reduceMotion) return child;
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: .92, end: 1).animate(animation),
                  child: child,
                ),
              );
            },
            child: enabled
                ? PopupMenuButton<_SingleWorkScheduleMenuAction>(
                    key: const ValueKey<String>('single_schedule_dev_on'),
                    tooltip: '개발자 메뉴',
                    icon: const Icon(Icons.more_vert_rounded),
                    onOpened: () =>
                        _SingleWorkScheduleDiagnostics.log('developer_menu_open'),
                    onSelected: (action) {
                      _SingleWorkScheduleDiagnostics.log(
                        'developer_menu_select action=${action.name}',
                      );
                      switch (action) {
                        case _SingleWorkScheduleMenuAction.developerStatus:
                          _SingleWorkScheduleDiagnostics.showStatus(context);
                          break;
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem<_SingleWorkScheduleMenuAction>(
                        value:
                            _SingleWorkScheduleMenuAction.developerStatus,
                        child: Text('상태 확인'),
                      ),
                    ],
                  )
                : const SizedBox(
                    key: ValueKey<String>('single_schedule_dev_off'),
                  ),
          );
        },
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 12),
        child: WeeklyWorkScheduleEditor(
          source: 'single_schedule_dock',
          embedded: true,
          presentation: WeeklyWorkSchedulePresentation.editorOnly,
          onChanged: _handleChanged,
        ),
      ),
    );
  }
}
