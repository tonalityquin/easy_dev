import 'package:flutter/material.dart';

import '../application/sprint_mode_store.dart';
import '../domain/sprint_models.dart';

enum SprintComposerPlacementChoice {
  recommended,
  requested,
}

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
  SprintComposerPlacementChoice? choice;
  if (preview.hasConflicts) {
    if (preview.hasHardConflict) {
      final beforeProjectStart = preview.conflicts.any(
        (conflict) =>
            conflict.type == SprintConflictType.beforeProjectStart,
      );
      sprintShowMessage(
        context: context,
        message: beforeProjectStart
            ? '프로젝트 목표 시작일 이전에는 업무를 배치할 수 없습니다.'
            : '과거 시간에는 업무를 배치할 수 없습니다.',
      );
      return null;
    }
    choice = await showModalBottomSheet<SprintComposerPlacementChoice>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      barrierColor: Theme.of(context).colorScheme.scrim,
      builder: (sheetContext) {
        final colors = Theme.of(sheetContext).colorScheme;
        final reduceMotion =
            MediaQuery.maybeOf(sheetContext)?.disableAnimations ?? false;
        final duration =
            reduceMotion ? Duration.zero : const Duration(milliseconds: 220);
        final conflictTitles = preview.conflicts
            .map((conflict) => conflict.title)
            .toSet()
            .join(' · ');
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
                  '일정 충돌 확인',
                  style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  conflictTitles,
                  style: TextStyle(
                    color: colors.error,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                if (preview.requestedStart != null)
                  SprintSurface(
                    backgroundColor: colors.surfaceContainerLow,
                    child: Row(
                      children: [
                        const Icon(Icons.schedule_rounded),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${sprintFormatDate(preview.requestedStart!)} ${sprintFormatTime(preview.requestedStart!)}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (preview.recommendedStart != null) ...[
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(sheetContext).pop(
                      SprintComposerPlacementChoice.recommended,
                    ),
                    icon: const Icon(Icons.auto_fix_high_rounded),
                    label: Text(
                      '${sprintFormatDate(preview.recommendedStart!)} ${sprintFormatTime(preview.recommendedStart!)}에 배치',
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(sheetContext).pop(
                    SprintComposerPlacementChoice.requested,
                  ),
                  icon: const Icon(Icons.warning_amber_rounded),
                  label: const Text('현재 시간에 배치'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: const Text('취소'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (choice == null || !context.mounted) return null;
  }
  final task = await store.createTaskFromPreview(
    preview,
    useRecommendedStart:
        choice == SprintComposerPlacementChoice.recommended,
    allowConflicts: choice == SprintComposerPlacementChoice.requested,
  );
  if (task == null && context.mounted) {
    final error = store.taskInputError;
    if (error != null) {
      sprintShowMessage(context: context, message: error);
    }
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

String sprintWeekday(int weekday) {
  const labels = <String>['월', '화', '수', '목', '금', '토', '일'];
  return labels[(weekday - 1).clamp(0, 6).toInt()];
}

String sprintFormatDuration(int minutes) {
  final safe = minutes < 0 ? 0 : minutes;
  final hours = safe ~/ 60;
  final remaining = safe % 60;
  if (hours == 0) return '$remaining분';
  if (remaining == 0) return '$hours시간';
  return '$hours시간 $remaining분';
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
