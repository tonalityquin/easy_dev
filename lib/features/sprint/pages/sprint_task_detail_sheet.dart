import 'package:flutter/material.dart';

import '../application/sprint_mode_store.dart';
import '../domain/sprint_models.dart';
import 'sprint_block_editor_sheet.dart';
import 'sprint_ui.dart';

Future<bool> showSprintTaskDetailSheet({
  required BuildContext context,
  required SprintModeStore store,
  required String taskId,
}) async {
  final colors = Theme.of(context).colorScheme;
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: colors.surface,
    barrierColor: colors.scrim,
    builder: (_) => _SprintTaskDetailSheet(
      store: store,
      taskId: taskId,
    ),
  );
  return result == true;
}

class _SprintTaskDetailSheet extends StatefulWidget {
  const _SprintTaskDetailSheet({
    required this.store,
    required this.taskId,
  });

  final SprintModeStore store;
  final String taskId;

  @override
  State<_SprintTaskDetailSheet> createState() =>
      _SprintTaskDetailSheetState();
}

class _SprintTaskDetailSheetState extends State<_SprintTaskDetailSheet> {
  late final TextEditingController _titleController;
  String? _projectId;
  SprintTaskPriority _priority = SprintTaskPriority.normal;
  late DateTime _startDate;
  late DateTime _endDate;
  bool _saving = false;

  SprintTask? get _task => widget.store.taskById(widget.taskId);

  @override
  void initState() {
    super.initState();
    final task = _task;
    final today = DateTime.now();
    _titleController = TextEditingController(text: task?.title ?? '');
    _projectId = task?.projectId;
    _priority = task?.priority ?? SprintTaskPriority.normal;
    _startDate = task?.startDate ??
        DateTime(today.year, today.month, today.day);
    _endDate = task?.endDate ?? _startDate;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _selectProject(String? value) {
    if (value == null) return;
    final adjusted = widget.store.suggestedTaskStart(
      projectId: value,
      date: _startDate,
    );
    final duration = _endDate.difference(_startDate).inDays;
    setState(() {
      _projectId = value;
      _startDate = adjusted;
      _endDate = adjusted.add(Duration(days: duration));
    });
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lower = widget.store.projectScheduleLowerBound(_projectId);
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
    final task = _task;
    final projectId = _projectId;
    if (task == null || projectId == null) return;
    setState(() => _saving = true);
    final saved = await widget.store.updateTask(
      taskId: task.id,
      title: _titleController.text,
      projectId: projectId,
      priority: _priority,
      startDate: _startDate,
      endDate: _endDate,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    sprintShowMessage(
      context: context,
      message: saved ? '업무를 수정했습니다.' : '업무 날짜 범위를 확인하세요.',
    );
    if (saved) Navigator.of(context).pop(true);
  }

  Future<void> _complete() async {
    final task = _task;
    if (task == null) return;
    widget.store.completeTask(task.id);
    if (!mounted) return;
    sprintShowMessage(context: context, message: '업무를 완료했습니다.');
    Navigator.of(context).pop(true);
  }

  Future<void> _cancel() async {
    final task = _task;
    if (task == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('업무 취소'),
        content: const Text('업무와 연결된 종일 일정을 취소합니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('닫기'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('취소 처리'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final saved = await widget.store.cancelTask(task.id);
    if (!mounted) return;
    if (saved) Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final task = _task;
    if (task == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('업무 삭제'),
        content: const Text('업무와 연결된 종일 일정이 함께 삭제됩니다.'),
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
    final deleted = await widget.store.deleteTask(task.id);
    if (!mounted) return;
    if (deleted) Navigator.of(context).pop(true);
  }

  Future<void> _openSchedule() async {
    final task = _task;
    if (task == null) return;
    final blocks = widget.store.blocksForTask(task.id);
    await showSprintBlockEditorSheet(
      context: context,
      store: widget.store,
      task: task,
      block: blocks.isEmpty ? null : blocks.first,
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final task = _task;
    if (task == null) {
      return const SizedBox(
        height: 220,
        child: Center(child: Text('업무를 찾을 수 없습니다.')),
      );
    }
    final colors = Theme.of(context).colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 220);
    final projects = widget.store.projects;
    return AnimatedPadding(
      duration: duration,
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '업무 관리',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _titleController,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: '업무명',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _projectId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: '프로젝트',
                border: OutlineInputBorder(),
              ),
              items: projects
                  .map(
                    (project) => DropdownMenuItem<String>(
                      value: project.id,
                      child: Text(
                        project.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _saving ? null : _selectProject,
            ),
            const SizedBox(height: 14),
            SegmentedButton<SprintTaskPriority>(
              segments: SprintTaskPriority.values
                  .map(
                    (priority) => ButtonSegment<SprintTaskPriority>(
                      value: priority,
                      icon: Icon(sprintPriorityIcon(priority)),
                      label: Text(sprintPriorityLabel(priority)),
                    ),
                  )
                  .toList(growable: false),
              selected: <SprintTaskPriority>{_priority},
              onSelectionChanged: _saving
                  ? null
                  : (selection) => setState(() {
                        _priority = selection.first;
                      }),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : _pickStartDate,
                    icon: const Icon(Icons.play_circle_outline_rounded),
                    label: Text(sprintFormatDate(_startDate)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : _pickEndDate,
                    icon: const Icon(Icons.flag_outlined),
                    label: Text(sprintFormatDate(_endDate)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            AnimatedContainer(
              duration: duration,
              padding: const EdgeInsets.all(14),
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
                  TextButton(
                    onPressed: _openSchedule,
                    child: const Text('일정 관리'),
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
            const SizedBox(height: 10),
            if (task.state != SprintTaskState.completed)
              FilledButton.tonalIcon(
                onPressed: _complete,
                icon: const Icon(Icons.check_circle_outline_rounded),
                label: const Text('완료'),
              ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _cancel,
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('업무 취소'),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _delete,
              icon: Icon(Icons.delete_outline_rounded, color: colors.error),
              label: Text('업무 삭제', style: TextStyle(color: colors.error)),
            ),
          ],
        ),
      ),
    );
  }
}
