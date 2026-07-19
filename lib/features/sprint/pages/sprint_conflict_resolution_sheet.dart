import 'package:flutter/material.dart';

import '../application/sprint_mode_store.dart';
import '../domain/sprint_models.dart';
import 'sprint_ui.dart';

Future<bool> showSprintConflictResolutionSheet({
  required BuildContext context,
  required SprintModeStore store,
  required SprintAttentionItem item,
}) async {
  final result = await sprintShowBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _SprintConflictResolutionSheet(
      store: store,
      item: item,
    ),
  );
  return result == true;
}

class _SprintConflictResolutionSheet extends StatefulWidget {
  const _SprintConflictResolutionSheet({
    required this.store,
    required this.item,
  });

  final SprintModeStore store;
  final SprintAttentionItem item;

  @override
  State<_SprintConflictResolutionSheet> createState() =>
      _SprintConflictResolutionSheetState();
}

class _SprintConflictResolutionSheetState
    extends State<_SprintConflictResolutionSheet> {
  bool _saving = false;

  Future<void> _resolve(
    SprintConflictResolutionType type, {
    DateTime? adjustedStart,
  }) async {
    if (_saving) return;
    setState(() => _saving = true);
    final resolved = await widget.store.resolveConflict(
      item: widget.item,
      resolutionType: type,
      adjustedStart: adjustedStart,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (resolved) {
      sprintShowMessage(context: context, message: '업무 날짜를 조정했습니다.');
      Navigator.of(context).pop(true);
      return;
    }
    sprintShowMessage(context: context, message: '업무 날짜를 조정하지 못했습니다.');
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 220);
    final task = widget.store.taskById(widget.item.taskId);
    final canKeep =
        widget.item.conflictType == SprintConflictType.afterProjectTargetDate;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: AnimatedSize(
        duration: duration,
        curve: Curves.easeOutCubic,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.item.title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.item.description,
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (task != null) ...[
              const SizedBox(height: 12),
              SprintSurface(
                backgroundColor: colors.surfaceContainerLow,
                child: Row(
                  children: [
                    Icon(sprintPriorityIcon(task.priority)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.title,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '종일 · ${sprintFormatDateRange(task.startDate, task.endDate)}',
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (widget.item.suggestedStart != null) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _saving
                    ? null
                    : () => _resolve(
                          SprintConflictResolutionType.moved,
                          adjustedStart: widget.item.suggestedStart,
                        ),
                icon: const Icon(Icons.calendar_month_rounded),
                label: Text(
                  '${sprintFormatDate(widget.item.suggestedStart!)}로 이동',
                ),
              ),
            ],
            if (canKeep) ...[
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: _saving
                    ? null
                    : () => _resolve(SprintConflictResolutionType.kept),
                icon: const Icon(Icons.check_rounded),
                label: const Text('현재 종료일 유지'),
              ),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: const Text('닫기'),
            ),
          ],
        ),
      ),
    );
  }
}
