import 'package:flutter/material.dart';

import '../application/sprint_mode_store.dart';
import '../domain/sprint_models.dart';
import 'sprint_block_editor_sheet.dart';
import 'sprint_ui.dart';

Future<bool> showSprintTaskDetailSheet({
  required BuildContext context,
  required SprintModeStore store,
  required SprintTask task,
}) async {
  final colors = Theme.of(context).colorScheme;
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: colors.surface,
    barrierColor: colors.scrim,
    builder: (_) => _SprintTaskDetailSheet(store: store, taskId: task.id),
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
  late final TextEditingController _minutesController;
  String? _projectId;
  DateTime? _deadline;
  bool _saving = false;

  SprintTask? get _task => widget.store.taskById(widget.taskId);

  @override
  void initState() {
    super.initState();
    final task = _task;
    _titleController = TextEditingController(text: task?.title ?? '');
    _minutesController = TextEditingController(
      text: '${task?.estimatedMinutes ?? 30}',
    );
    _projectId = task?.projectId;
    _deadline = task?.deadline;
    widget.store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    _titleController.dispose();
    _minutesController.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  void _selectProject(String? value) {
    if (value == null) return;
    final lowerBound = widget.store.projectScheduleLowerBound(value);
    final shouldClearDeadline = _deadline != null &&
        lowerBound != null &&
        _deadline!.isBefore(DateTime(
          lowerBound.year,
          lowerBound.month,
          lowerBound.day,
        ));
    setState(() {
      _projectId = value;
      if (shouldClearDeadline) _deadline = null;
    });
    if (shouldClearDeadline) {
      sprintShowMessage(
        context: context,
        message: '새 프로젝트의 목표 시작일보다 빠른 마감일을 제거했습니다.',
      );
    }
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lowerBound = widget.store.projectScheduleLowerBound(_projectId);
    final firstDate = lowerBound != null && lowerBound.isAfter(today)
        ? DateTime(lowerBound.year, lowerBound.month, lowerBound.day)
        : today;
    var initialDate = _deadline ?? firstDate.add(const Duration(days: 1));
    if (initialDate.isBefore(firstDate)) initialDate = firstDate;
    final selected = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: DateTime(now.year + 10, 12, 31),
    );
    if (selected == null || !mounted) return;
    setState(() => _deadline = selected);
  }

  bool _canEditTask(SprintTask task) {
    final project = widget.store.projectById(task.projectId);
    return task.state != SprintTaskState.completed &&
        task.state != SprintTaskState.cancelled &&
        project != null &&
        project.status == SprintProjectStatus.active;
  }

  Future<void> _save() async {
    if (_saving) return;
    final task = _task;
    final minutes = int.tryParse(_minutesController.text.trim());
    if (task == null ||
        !_canEditTask(task) ||
        _titleController.text.trim().isEmpty ||
        minutes == null ||
        minutes < 20 ||
        _projectId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('업무명과 20분 이상의 예상시간을 확인하세요.')),
      );
      return;
    }
    final lowerBound = widget.store.projectScheduleLowerBound(_projectId);
    if (_deadline != null &&
        lowerBound != null &&
        _deadline!.isBefore(DateTime(
          lowerBound.year,
          lowerBound.month,
          lowerBound.day,
        ))) {
      sprintShowMessage(
        context: context,
        message: '업무 마감일은 프로젝트 목표 시작일보다 빠를 수 없습니다.',
      );
      return;
    }
    final hasLockedBeforeStart = lowerBound != null &&
        widget.store.blocksForTask(task.id).any(
              (block) =>
                  block.status == SprintScheduleBlockStatus.planned &&
                  block.locked &&
                  block.start.isBefore(lowerBound),
            );
    if (hasLockedBeforeStart) {
      sprintShowMessage(
        context: context,
        message: '새 프로젝트의 목표 시작일 이전에 고정된 일정이 있습니다.',
      );
      return;
    }
    setState(() => _saving = true);
    final saved = await widget.store.updateTask(
      taskId: task.id,
      title: _titleController.text,
      projectId: _projectId!,
      estimatedMinutes: minutes,
      deadline: _deadline,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved) {
      sprintShowMessage(
        context: context,
        message: '업무를 수정했습니다.',
      );
    } else {
      sprintShowMessage(
        context: context,
        message: '프로젝트 목표 시작일과 일정 상태를 확인하세요.',
      );
    }
  }

  Future<void> _cancelTask() async {
    final task = _task;
    if (task == null || _saving || !_canEditTask(task)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('업무 취소'),
        content: const Text('기록된 실제 소요시간은 유지하고 남은 일정을 취소합니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('돌아가기'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('업무 취소'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    final cancelled = await widget.store.cancelTask(task.id);
    if (!mounted) return;
    setState(() => _saving = false);
    if (cancelled) {
      sprintShowMessage(
        context: context,
        message: '업무를 취소했습니다.',
      );
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _deleteTask() async {
    final task = _task;
    if (task == null || _saving || !_canEditTask(task)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('업무 삭제'),
        content: const Text('실제 소요시간 기록이 없는 업무와 일정 블록을 삭제합니다.'),
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
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    final deleted = await widget.store.deleteTask(task.id);
    if (!mounted) return;
    setState(() => _saving = false);
    if (deleted) {
      sprintShowMessage(
        context: context,
        message: '업무를 삭제했습니다.',
      );
      Navigator.of(context).pop(true);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('실제 소요시간 기록이 있는 업무는 삭제 대신 취소하세요.')),
    );
  }

  Future<void> _openBlock(SprintScheduleBlock? block) async {
    final task = _task;
    if (task == null || !_canEditTask(task)) return;
    await showSprintBlockEditorSheet(
      context: context,
      store: widget.store,
      task: task,
      block: block,
    );
  }

  @override
  Widget build(BuildContext context) {
    final task = _task;
    if (task == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 220);
    final blocks = widget.store.blocksForTask(task.id);
    final canEdit = _canEditTask(task);
    final selectedProject = widget.store.projectById(_projectId);
    final targetDate = selectedProject?.targetDate;
    final deadlineAfterTarget = _deadline != null &&
        targetDate != null &&
        DateTime(_deadline!.year, _deadline!.month, _deadline!.day).isAfter(
          DateTime(targetDate.year, targetDate.month, targetDate.day),
        );
    final projectItems = widget.store.allProjects
        .where((project) =>
            project.status == SprintProjectStatus.active ||
            project.id == _projectId)
        .toList(growable: false);
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    '업무 관리',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                _TaskStateBadge(state: task.state),
              ],
            ),
            const SizedBox(height: 18),
            AnimatedSwitcher(
              duration: duration,
              child: canEdit
                  ? const SizedBox.shrink(key: ValueKey<String>('editable'))
                  : SprintSurface(
                      key: const ValueKey<String>('readonly'),
                      backgroundColor: colors.surfaceContainerLow,
                      child: const Text(
                        '완료되거나 보관된 업무는 기록을 보존하기 위해 읽기 전용으로 표시합니다.',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
            ),
            if (!canEdit) const SizedBox(height: 12),
            TextField(
              controller: _titleController,
              enabled: canEdit && !_saving,
              decoration: const InputDecoration(
                labelText: '업무명',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _minutesController,
              enabled: canEdit && !_saving,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '예상시간 분',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _projectId,
              decoration: const InputDecoration(
                labelText: '프로젝트',
                border: OutlineInputBorder(),
              ),
              items: projectItems
                  .map(
                    (project) => DropdownMenuItem<String>(
                      value: project.id,
                      child: Text(project.name),
                    ),
                  )
                  .toList(growable: false),
              onChanged: !canEdit || _saving ? null : _selectProject,
            ),
            const SizedBox(height: 12),
            SprintSurface(
              backgroundColor: colors.surfaceContainerLow,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.flag_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: duration,
                      child: Text(
                        _deadline == null
                            ? '마감일 없음'
                            : sprintFormatDate(_deadline!),
                        key: ValueKey<String>(
                          _deadline?.toIso8601String() ?? 'none',
                        ),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: !canEdit || _saving ? null : _pickDeadline,
                    child: const Text('선택'),
                  ),
                  if (_deadline != null)
                    IconButton(
                      tooltip: '마감일 제거',
                      onPressed: !canEdit || _saving
                          ? null
                          : () => setState(() => _deadline = null),
                      icon: const Icon(Icons.close_rounded),
                    ),
                ],
              ),
            ),
            AnimatedSize(
              duration: duration,
              curve: Curves.easeOutCubic,
              child: deadlineAfterTarget
                  ? Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        '업무 마감일이 프로젝트 목표 완료일보다 늦습니다.',
                        style: TextStyle(
                          color: colors.tertiary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: !canEdit || _saving ? null : _save,
              child: const Text('업무 저장'),
            ),
            const SizedBox(height: 22),
            SprintSectionHeader(
              title: '일정 블록',
              actionLabel: '추가',
              onAction: !canEdit || _saving ? null : () => _openBlock(null),
            ),
            const SizedBox(height: 8),
            AnimatedSize(
              duration: duration,
              curve: Curves.easeOutCubic,
              child: blocks.isEmpty
                  ? SprintSurface(
                      backgroundColor: colors.surfaceContainerLow,
                      child: const Text('배치된 일정이 없습니다.'),
                    )
                  : Column(
                      children: blocks.map((block) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _BlockTile(
                            block: block,
                            onTap: canEdit ? () => _openBlock(block) : null,
                          ),
                        );
                      }).toList(growable: false),
                    ),
            ),
            const SizedBox(height: 18),
            SprintSurface(
              backgroundColor: colors.surfaceContainerLow,
              child: Row(
                children: [
                  Expanded(
                    child: SprintMetric(
                      label: '예상',
                      value: sprintFormatDuration(task.estimatedMinutes),
                    ),
                  ),
                  Expanded(
                    child: SprintMetric(
                      label: '실제',
                      value: sprintFormatDuration(task.actualMinutes),
                    ),
                  ),
                  Expanded(
                    child: SprintMetric(
                      label: '남음',
                      value: sprintFormatDuration(task.remainingMinutes),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: !canEdit || _saving ? null : _cancelTask,
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('업무 취소'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: !canEdit || _saving ? null : _deleteTask,
              icon: Icon(Icons.delete_outline_rounded, color: colors.error),
              label: Text('업무 삭제', style: TextStyle(color: colors.error)),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlockTile extends StatelessWidget {
  const _BlockTile({required this.block, required this.onTap});

  final SprintScheduleBlock block;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(
                block.locked ? Icons.lock_rounded : Icons.schedule_rounded,
                color: block.locked ? colors.primary : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sprintFormatDate(block.start),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${sprintFormatTime(block.start)}–${sprintFormatTime(block.end)} · ${sprintFormatDuration(block.durationMinutes)}',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                    if (block.executedMinutes > 0) ...[
                      const SizedBox(height: 3),
                      Text(
                        '완료 처리 ${sprintFormatDuration(block.executedMinutes)}',
                        style: TextStyle(color: colors.primary),
                      ),
                    ],
                  ],
                ),
              ),
              if (onTap != null) const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskStateBadge extends StatelessWidget {
  const _TaskStateBadge({required this.state});

  final SprintTaskState state;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = switch (state) {
      SprintTaskState.blocked => '대기',
      SprintTaskState.ready => '준비',
      SprintTaskState.scheduled => '배치',
      SprintTaskState.completed => '완료',
      SprintTaskState.cancelled => '취소',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors.onPrimaryContainer,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
