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
  late DateTime _start;
  late int _durationMinutes;
  late bool _locked;
  bool _saving = false;
  List<SprintScheduleConflict> _conflicts = const <SprintScheduleConflict>[];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final block = widget.block;
    _start = block?.start ?? DateTime(now.year, now.month, now.day + 1, 9);
    _durationMinutes = block?.durationMinutes ?? widget.task.remainingMinutes;
    if (_durationMinutes < 20) _durationMinutes = widget.task.estimatedMinutes;
    if (_durationMinutes < 20) _durationMinutes = 30;
    _locked = block?.locked ??
        widget.task.placementMode == SprintPlacementMode.manual;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initialDay = DateTime(_start.year, _start.month, _start.day);
    final selected = await showDatePicker(
      context: context,
      initialDate: initialDay,
      firstDate: initialDay.isBefore(today) ? initialDay : today,
      lastDate: today.add(const Duration(days: 3650)),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _start = DateTime(
        selected.year,
        selected.month,
        selected.day,
        _start.hour,
        _start.minute,
      );
      _conflicts = const <SprintScheduleConflict>[];
    });
  }

  Future<void> _pickTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_start),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _start = widget.store.normalizeScheduleStart(
        DateTime(
          _start.year,
          _start.month,
          _start.day,
          selected.hour,
          selected.minute,
        ),
      );
      _conflicts = const <SprintScheduleConflict>[];
    });
  }

  Future<void> _save({bool allowConflicts = false}) async {
    if (_saving) return;
    setState(() => _saving = true);
    final normalizedStart = widget.store.normalizeScheduleStart(_start);
    final end = normalizedStart.add(Duration(minutes: _durationMinutes));
    SprintOperationResult result;
    if (widget.block == null) {
      result = await widget.store.createBlock(
        taskId: widget.task.id,
        start: normalizedStart,
        end: end,
        locked: _locked,
        allowConflicts: allowConflicts,
      );
    } else {
      result = await widget.store.updateBlock(
        blockId: widget.block!.id,
        start: normalizedStart,
        end: end,
        locked: _locked,
        allowConflicts: allowConflicts,
      );
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _conflicts = result.conflicts;
    });
    if (result.success) {
      sprintShowMessage(
        context: context,
        message: result.message,
      );
      Navigator.of(context).pop(true);
      return;
    }
    if (result.conflicts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    }
  }

  Future<void> _deleteSchedule() async {
    final block = widget.block;
    if (block == null || _saving) return;
    final colors = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: colors.surface,
          title: const Text('일정 삭제'),
          content: const Text(
            '이 일정 블록을 삭제합니다. 업무는 유지되며 다른 일정 블록이 없으면 미배치 상태가 됩니다.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              ),
              child: const Text('일정 삭제'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    final removed = await widget.store.unscheduleBlock(block.id);
    if (!mounted) return;
    setState(() => _saving = false);
    if (removed) {
      sprintShowMessage(
        context: context,
        message: '일정을 삭제했습니다.',
      );
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _split() async {
    final block = widget.block;
    if (block == null || block.durationMinutes < 40 || _saving) return;
    final controller = TextEditingController(
      text: '${block.durationMinutes ~/ 2}',
    );
    final firstMinutes = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('일정 분할'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '첫 번째 블록 분',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                int.tryParse(controller.text.trim()),
              ),
              child: const Text('분할'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (firstMinutes == null || !mounted) return;
    setState(() => _saving = true);
    final split = await widget.store.splitBlock(
      blockId: block.id,
      firstMinutes: firstMinutes,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (split) {
      sprintShowMessage(
        context: context,
        message: '일정을 두 블록으로 분할했습니다.',
      );
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('각 블록은 20분 이상이어야 합니다.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 220);
    final canOverrideConflicts = _conflicts.every(
      (conflict) => conflict.type != SprintConflictType.pastTime,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.block == null ? '일정 생성' : '일정 관리',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.task.title,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            SprintSurface(
              backgroundColor: colors.surfaceContainerLow,
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_today_rounded),
                    title: Text(sprintFormatDate(_start)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _saving ? null : _pickDate,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule_rounded),
                    title: Text(sprintFormatTime(_start)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _saving ? null : _pickTime,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '길이',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <int>[20, 30, 60, 90, 120].map((minutes) {
                return ChoiceChip(
                  label: Text(sprintFormatDuration(minutes)),
                  selected: _durationMinutes == minutes,
                  onSelected: _saving
                      ? null
                      : (_) => setState(() {
                            _durationMinutes = minutes;
                            _conflicts = const <SprintScheduleConflict>[];
                          }),
                );
              }).toList(growable: false),
            ),
            const SizedBox(height: 10),
            Slider(
              min: 20,
              max: 240,
              divisions: 22,
              value: _durationMinutes.clamp(20, 240).toDouble(),
              label: sprintFormatDuration(_durationMinutes),
              onChanged: _saving
                  ? null
                  : (value) => setState(() {
                        _durationMinutes = ((value / 10).round() * 10)
                            .clamp(20, 240)
                            .toInt();
                        _conflicts = const <SprintScheduleConflict>[];
                      }),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _locked,
              title: const Text(
                '시간 고정',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: const Text('자동 재계획에서 이 블록을 이동하지 않습니다.'),
              onChanged: _saving ? null : (value) => setState(() => _locked = value),
            ),
            AnimatedSize(
              duration: duration,
              curve: Curves.easeOutCubic,
              child: _conflicts.isEmpty
                  ? const SizedBox.shrink()
                  : SprintSurface(
                      backgroundColor: colors.errorContainer,
                      borderColor: colors.error,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '충돌 ${_conflicts.length}건',
                            style: TextStyle(
                              color: colors.onErrorContainer,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ..._conflicts.map(
                            (conflict) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                '${conflict.title} · ${conflict.description}',
                                style: TextStyle(color: colors.onErrorContainer),
                              ),
                            ),
                          ),
                          if (canOverrideConflicts) ...[
                            const SizedBox(height: 6),
                            FilledButton.tonal(
                              onPressed: _saving
                                  ? null
                                  : () => _save(allowConflicts: true),
                              child: const Text('그래도 배치'),
                            ),
                          ],
                        ],
                      ),
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
                    : Text(
                        widget.block == null ? '일정 생성' : '변경 저장',
                        key: const ValueKey<String>('save'),
                      ),
              ),
            ),
            if (widget.block != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _saving ? null : _split,
                icon: const Icon(Icons.call_split_rounded),
                label: const Text('일정 분할'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _saving ? null : _deleteSchedule,
                style: TextButton.styleFrom(
                  foregroundColor: colors.error,
                ),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('일정 삭제'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
