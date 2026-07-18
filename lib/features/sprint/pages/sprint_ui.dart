import 'package:flutter/material.dart';

import '../application/sprint_mode_store.dart';
import '../domain/sprint_models.dart';

void sprintShowMessage({
  required BuildContext context,
  required String message,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(SnackBar(content: Text(message)));
}

Future<String?> sprintSelectTaskProject({
  required BuildContext context,
  required SprintModeStore store,
  String? initialProjectId,
}) async {
  final preferred = store.preferredTaskProjectId(initialProjectId);
  if (preferred != null) return preferred;
  final projects = store.projects;
  if (projects.isEmpty) {
    sprintShowMessage(
      context: context,
      message: '업무를 추가하려면 먼저 프로젝트를 생성하세요.',
    );
    return null;
  }
  return showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    barrierColor: Theme.of(context).colorScheme.scrim,
    builder: (sheetContext) {
      final reduceMotion =
          MediaQuery.maybeOf(sheetContext)?.disableAnimations ?? false;
      final duration =
          reduceMotion ? Duration.zero : const Duration(milliseconds: 220);
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: AnimatedSize(
          duration: duration,
          curve: Curves.easeOutCubic,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '프로젝트 선택',
                style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 12),
              ...projects.map(
                (project) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: Theme.of(sheetContext)
                        .colorScheme
                        .surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                    child: ListTile(
                      minTileHeight: 56,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      leading: Icon(project.icon),
                      title: Text(
                        project.name,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(sheetContext).pop(project.id),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<SprintTask?> sprintCreateTaskFromComposer({
  required BuildContext context,
  required SprintModeStore store,
  required String rawText,
}) async {
  if (rawText.trim().isEmpty) return null;
  final projectId = await sprintSelectTaskProject(
    context: context,
    store: store,
    initialProjectId: store.selectedProjectId,
  );
  if (projectId == null || !context.mounted) return null;
  final preview = store.previewTaskFromText(rawText, projectId: projectId);
  if (preview == null) {
    final error = store.taskInputError;
    if (error != null && context.mounted) {
      sprintShowMessage(context: context, message: error);
    }
    return null;
  }
  if (preview.hasHardConflict) {
    if (context.mounted) {
      sprintShowMessage(
        context: context,
        message: store.taskInputError ?? '업무 날짜를 확인하세요.',
      );
    }
    return null;
  }
  final task = await store.createTaskFromPreview(preview);
  if (task == null && context.mounted) {
    sprintShowMessage(
      context: context,
      message: store.taskInputError ?? '업무를 추가하지 못했습니다.',
    );
  }
  return task;
}

String sprintTwoDigits(int value) => value.toString().padLeft(2, '0');

String sprintFormatTime(DateTime value) {
  return '${sprintTwoDigits(value.hour)}:${sprintTwoDigits(value.minute)}';
}

String sprintFormatDate(DateTime value) {
  return '${value.month}월 ${value.day}일 ${sprintWeekday(value.weekday)}요일';
}

String sprintFormatShortDate(DateTime value) {
  return '${value.month}/${value.day}';
}


String sprintFormatDateRange(DateTime start, DateTime end) {
  if (sprintSameDay(start, end)) return sprintFormatDate(start);
  return '${sprintFormatShortDate(start)}–${sprintFormatShortDate(end)}';
}

String sprintPriorityLabel(SprintTaskPriority priority) {
  switch (priority) {
    case SprintTaskPriority.high:
      return '높음';
    case SprintTaskPriority.normal:
      return '보통';
    case SprintTaskPriority.low:
      return '낮음';
  }
}

IconData sprintPriorityIcon(SprintTaskPriority priority) {
  switch (priority) {
    case SprintTaskPriority.high:
      return Icons.keyboard_double_arrow_up_rounded;
    case SprintTaskPriority.normal:
      return Icons.remove_rounded;
    case SprintTaskPriority.low:
      return Icons.keyboard_arrow_down_rounded;
  }
}

String sprintWeekday(int weekday) {
  const labels = <String>['월', '화', '수', '목', '금', '토', '일'];
  return labels[(weekday - 1).clamp(0, 6).toInt()];
}

bool sprintSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

class SprintSurface extends StatelessWidget {
  const SprintSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.backgroundColor,
    this.borderColor,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? backgroundColor;
  final Color? borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: borderColor ?? colors.outlineVariant,
        ),
      ),
      child: child,
    );

    if (onTap == null) return content;

    return Material(
      color: backgroundColor ?? colors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: content,
      ),
    );
  }
}

class SprintSectionHeader extends StatelessWidget {
  const SprintSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            child: Text(actionLabel!),
          ),
      ],
    );
  }
}

class SprintMetric extends StatelessWidget {
  const SprintMetric({
    super.key,
    required this.label,
    required this.value,
    this.warning = false,
  });

  final String label;
  final String value;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: warning ? colors.error : colors.onSurface,
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}
