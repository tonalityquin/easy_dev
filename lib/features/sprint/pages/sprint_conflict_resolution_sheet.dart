import 'package:flutter/material.dart';

import '../application/sprint_mode_store.dart';
import '../domain/sprint_models.dart';
import 'sprint_ui.dart';

Future<bool> showSprintConflictResolutionSheet({
  required BuildContext context,
  required SprintModeStore store,
  required SprintAttentionItem item,
}) async {
  final colors = Theme.of(context).colorScheme;
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: colors.surface,
    barrierColor: colors.scrim,
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
      sprintShowMessage(
        context: context,
        message: '일정 충돌을 해결했습니다.',
      );
      Navigator.of(context).pop(true);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('선택한 시간의 충돌을 먼저 조정하세요.')),
    );
  }

  Future<void> _adjust() async {
    final block = widget.store.blockById(widget.item.blockId);
    if (block == null) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initialDay = DateTime(
      block.start.year,
      block.start.month,
      block.start.day,
    );
    final date = await showDatePicker(
      context: context,
      initialDate: initialDay,
      firstDate: initialDay.isBefore(today) ? initialDay : today,
      lastDate: today.add(const Duration(days: 3650)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(block.start),
    );
    if (time == null || !mounted) return;
    await _resolve(
      SprintConflictResolutionType.adjusted,
      adjustedStart: widget.store.normalizeScheduleStart(
        DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final block = widget.store.blockById(widget.item.blockId);
    final colors = Theme.of(context).colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 220);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
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
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          if (block != null) ...[
            const SizedBox(height: 14),
            SprintSurface(
              backgroundColor: colors.surfaceContainerLow,
              child: Text(
                '${sprintFormatDate(block.start)} · ${sprintFormatTime(block.start)}–${sprintFormatTime(block.end)}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
          if (widget.item.suggestedStart != null) ...[
            const SizedBox(height: 12),
            SprintSurface(
              backgroundColor: colors.primaryContainer,
              borderColor: colors.primary,
              child: AnimatedSwitcher(
                duration: duration,
                child: Text(
                  '추천 ${sprintFormatDate(widget.item.suggestedStart!)} · ${sprintFormatTime(widget.item.suggestedStart!)}',
                  key: ValueKey<int>(
                    widget.item.suggestedStart!.millisecondsSinceEpoch,
                  ),
                  style: TextStyle(
                    color: colors.onPrimaryContainer,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _saving
                ? null
                : () => _resolve(SprintConflictResolutionType.moved),
            icon: const Icon(Icons.auto_fix_high_rounded),
            label: const Text('추천 위치로 이동'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _saving
                ? null
                : () => _resolve(SprintConflictResolutionType.kept),
            icon: const Icon(Icons.lock_outline_rounded),
            label: const Text('현재 위치 유지'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _saving ? null : _adjust,
            icon: const Icon(Icons.tune_rounded),
            label: const Text('직접 조정'),
          ),
          AnimatedSize(
            duration: duration,
            child: _saving
                ? const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
