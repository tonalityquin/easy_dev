import 'package:flutter/material.dart';

import '../application/sprint_mode_store.dart';
import '../domain/sprint_models.dart';
import 'sprint_ui.dart';

Future<bool> showSprintBlockEditorSheet({
  required BuildContext context,
  required SprintModeStore store,
  required SprintTask task,
  SprintScheduleBlock? block,
}) async {
  final colors = Theme.of(context).colorScheme;
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: colors.surface,
    barrierColor: colors.scrim,
    builder: (_) => _SprintBlockEditorSheet(
      store: store,
      task: task,
      block: block,
    ),
  );
  return result == true;
}

class _SprintBlockEditorSheet extends StatefulWidget {
  const _SprintBlockEditorSheet({
    required this.store,
    required this.task,
    required this.block,
  });

  final SprintModeStore store;
  final SprintTask task;
  final SprintScheduleBlock? block;

  @override
  State<_SprintBlockEditorSheet> createState() =>
      _SprintBlockEditorSheetState();
}

class _SprintBlockEditorSheetState extends State<_SprintBlockEditorSheet> {
  late DateTime _startDate;
  late DateTime _endDate;
  bool _locked = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _startDate = widget.task.startDate;
    _endDate = widget.task.endDate;
    _locked = widget.block?.locked ?? false;
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lower = widget.store.projectScheduleLowerBound(widget.task.projectId);
    final firstDate = lower != null && lower.isAfter(today) ? lower : today;
    var initial = _startDate;
    if (initial.isBefore(firstDate)) initial = firstDate;
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: DateTime(now.year + 10, 12, 31),
    );
    if (selected == null || !mounted) return;
    final duration = _endDate.difference(_startDate).inDays;
    setState(() {
      _startDate = selected;
      _endDate = selected.add(Duration(days: duration));
    });
  }

  Future<void> _pickEndDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _endDate.isBefore(_startDate) ? _startDate : _endDate,
      firstDate: _startDate,
      lastDate: DateTime(DateTime.now().year + 10, 12, 31),
    );
    if (selected == null || !mounted) return;
    setState(() => _endDate = selected);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final exclusiveEnd = DateTime(
      _endDate.year,
      _endDate.month,
      _endDate.day + 1,
    );
    final result = widget.block == null
        ? await widget.store.createBlock(
            taskId: widget.task.id,
            start: _startDate,
            end: exclusiveEnd,
            locked: _locked,
          )
        : await widget.store.updateBlock(
            blockId: widget.block!.id,
            start: _startDate,
            end: exclusiveEnd,
            locked: _locked,
          );
    if (!mounted) return;
    setState(() => _saving = false);
    sprintShowMessage(context: context, message: result.message);
    if (result.success) Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final block = widget.block;
    if (block == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('일정 삭제'),
        content: const Text('업무는 유지되고 종일 일정만 삭제됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final deleted = await widget.store.unscheduleBlock(block.id);
    if (!mounted) return;
    if (deleted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 220);
    return AnimatedPadding(
      duration: duration,
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '종일 일정 관리',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.task.title,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _pickStartDate,
                  icon: const Icon(Icons.play_circle_outline_rounded),
                  label: AnimatedSwitcher(
                    duration: duration,
                    child: Text(
                      sprintFormatDate(_startDate),
                      key: ValueKey<int>(_startDate.millisecondsSinceEpoch),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _pickEndDate,
                  icon: const Icon(Icons.flag_outlined),
                  label: AnimatedSwitcher(
                    duration: duration,
                    child: Text(
                      sprintFormatDate(_endDate),
                      key: ValueKey<int>(_endDate.millisecondsSinceEpoch),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AnimatedContainer(
            duration: duration,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.today_rounded),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '종일 · ${sprintFormatDateRange(_startDate, _endDate)}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const Text(
                  '날짜 고정',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                Switch(
                  value: _locked,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _locked = value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: AnimatedSwitcher(
              duration: duration,
              child: _saving
                  ? const SizedBox(
                      key: ValueKey<String>('saving'),
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('저장', key: ValueKey<String>('save')),
            ),
          ),
          if (widget.block != null) ...[
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _saving ? null : _delete,
              icon: Icon(Icons.delete_outline_rounded, color: colors.error),
              label: Text(
                '일정 삭제',
                style: TextStyle(color: colors.error),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
