import 'package:flutter/material.dart';

import '../application/sprint_mode_store.dart';
import '../domain/sprint_models.dart';
import 'sprint_ui.dart';

enum _TaskCreationPlacementChoice {
  recommended,
  requested,
}

Future<SprintTask?> showSprintTaskCreateSheet({
  required BuildContext context,
  required SprintModeStore store,
  required DateTime initialDate,
  String? initialProjectId,
}) {
  final colors = Theme.of(context).colorScheme;
  return showModalBottomSheet<SprintTask>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: colors.surface,
    barrierColor: colors.scrim,
    builder: (_) => _SprintTaskCreateSheet(
      store: store,
      initialDate: initialDate,
      initialProjectId: initialProjectId,
    ),
  );
}

class _SprintTaskCreateSheet extends StatefulWidget {
  const _SprintTaskCreateSheet({
    required this.store,
    required this.initialDate,
    required this.initialProjectId,
  });

  final SprintModeStore store;
  final DateTime initialDate;
  final String? initialProjectId;

  @override
  State<_SprintTaskCreateSheet> createState() =>
      _SprintTaskCreateSheetState();
}

class _SprintTaskCreateSheetState extends State<_SprintTaskCreateSheet> {
  final TextEditingController _titleController = TextEditingController();
  final FocusNode _titleFocusNode = FocusNode();
  late DateTime _date;
  late TimeOfDay _time;
  String? _projectId;
  DateTime? _deadline;
  int _estimatedMinutes = 60;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final requested = DateTime(
      widget.initialDate.year,
      widget.initialDate.month,
      widget.initialDate.day,
    );
    _date = requested.isBefore(today) ? today : requested;
    _projectId = widget.store.preferredTaskProjectId(widget.initialProjectId);
    final projectId = _projectId;
    final suggested = projectId == null
        ? DateTime(_date.year, _date.month, _date.day, 9)
        : widget.store.suggestedTaskStart(
            projectId: projectId,
            date: _date,
            durationMinutes: _estimatedMinutes,
          );
    _date = DateTime(suggested.year, suggested.month, suggested.day);
    _time = TimeOfDay(hour: suggested.hour, minute: suggested.minute);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _titleFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _titleFocusNode.dispose();
    super.dispose();
  }


  void _selectProject(String? value) {
    if (value == null) {
      setState(() => _projectId = null);
      return;
    }
    final lowerBound = widget.store.projectScheduleLowerBound(value);
    final currentStart = _start;
    final beforeStart = lowerBound != null && currentStart.isBefore(lowerBound);
    final adjusted = beforeStart
        ? widget.store.suggestedTaskStart(
            projectId: value,
            date: lowerBound!,
            durationMinutes: _estimatedMinutes,
          )
        : currentStart;
    setState(() {
      _projectId = value;
      _date = DateTime(adjusted.year, adjusted.month, adjusted.day);
      _time = TimeOfDay(hour: adjusted.hour, minute: adjusted.minute);
      if (_deadline != null && _deadline!.isBefore(_date)) {
        _deadline = null;
      }
    });
    if (beforeStart) {
      sprintShowMessage(
        context: context,
        message: '프로젝트 목표 시작일에 맞춰 일정 날짜를 ${sprintFormatDate(_date)}로 변경했습니다.',
      );
    }
  }

  DateTime get _start => DateTime(
        _date.year,
        _date.month,
        _date.day,
        _time.hour,
        _time.minute,
      );

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final projectStart = widget.store.projectScheduleLowerBound(_projectId);
    final firstDate = projectStart != null && projectStart.isAfter(today)
        ? DateTime(projectStart.year, projectStart.month, projectStart.day)
        : today;
    var initial = _date;
    if (initial.isBefore(firstDate)) initial = firstDate;
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: DateTime(now.year + 10, 12, 31),
    );
    if (selected == null || !mounted) return;
    setState(() => _date = selected);
  }

  Future<void> _pickTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _time,
    );
    if (selected == null || !mounted) return;
    setState(() => _time = selected);
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final projectStart = widget.store.projectScheduleLowerBound(_projectId);
    final firstDate = projectStart != null && projectStart.isAfter(today)
        ? DateTime(projectStart.year, projectStart.month, projectStart.day)
        : today;
    var initial = _deadline ?? _date;
    if (initial.isBefore(firstDate)) initial = firstDate;
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: DateTime(now.year + 10, 12, 31),
    );
    if (selected == null || !mounted) return;
    setState(() => _deadline = selected);
  }

  Future<_TaskCreationPlacementChoice?> _resolveConflicts(
    SprintTaskCreationPreview preview,
  ) {
    final titles = preview.conflicts
        .map((conflict) => conflict.title)
        .toSet()
        .join(' · ');
    return showModalBottomSheet<_TaskCreationPlacementChoice>(
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
                  titles,
                  style: TextStyle(
                    color: colors.error,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (preview.recommendedStart != null) ...[
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(sheetContext).pop(
                      _TaskCreationPlacementChoice.recommended,
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
                    _TaskCreationPlacementChoice.requested,
                  ),
                  icon: const Icon(Icons.warning_amber_rounded),
                  label: Text(
                    '${sprintFormatTime(preview.requestedStart!)}에 그대로 배치',
                  ),
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
  }

  Future<void> _save() async {
    if (_saving) return;
    final projectId = _projectId;
    if (_titleController.text.trim().isEmpty || projectId == null) {
      sprintShowMessage(
        context: context,
        message: projectId == null
            ? '업무를 추가할 프로젝트를 선택하세요.'
            : '업무명을 입력하세요.',
      );
      return;
    }
    final preview = widget.store.previewTaskDetails(
      title: _titleController.text,
      projectId: projectId,
      estimatedMinutes: _estimatedMinutes,
      requestedStart: _start,
      deadline: _deadline,
    );
    if (preview == null) {
      final error = widget.store.taskInputError;
      if (error != null && mounted) {
        sprintShowMessage(context: context, message: error);
      }
      return;
    }
    if (preview.hasHardConflict) {
      sprintShowMessage(
        context: context,
        message: preview.conflicts.any(
          (conflict) =>
              conflict.type == SprintConflictType.beforeProjectStart,
        )
            ? '프로젝트 목표 시작일 이전에는 업무를 배치할 수 없습니다.'
            : '과거 시간에는 업무를 배치할 수 없습니다.',
      );
      return;
    }
    _TaskCreationPlacementChoice? choice;
    if (preview.hasConflicts) {
      choice = await _resolveConflicts(preview);
      if (choice == null || !mounted) return;
    }
    setState(() => _saving = true);
    final task = await widget.store.createTaskFromPreview(
      preview,
      useRecommendedStart:
          choice == _TaskCreationPlacementChoice.recommended,
      allowConflicts: choice == _TaskCreationPlacementChoice.requested,
    );
    if (!mounted) return;
    if (task == null) {
      setState(() => _saving = false);
      final error = widget.store.taskInputError;
      if (error != null) {
        sprintShowMessage(context: context, message: error);
      }
      return;
    }
    sprintShowMessage(
      context: context,
      message: '${task.title} 업무를 추가했습니다.',
    );
    Navigator.of(context).pop(task);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 220);
    final projects = widget.store.projects;
    final selectedProject = widget.store.projectById(_projectId);
    final targetDate = selectedProject?.targetDate;
    final deadlineAfterTarget = _deadline != null &&
        targetDate != null &&
        DateTime(_deadline!.year, _deadline!.month, _deadline!.day).isAfter(
          DateTime(targetDate.year, targetDate.month, targetDate.day),
        );
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return Material(
      color: colors.surface,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 10),
        child: AnimatedPadding(
          duration: duration,
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.only(bottom: keyboardInset),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '업무 추가',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 18),
                const Text(
                  '프로젝트',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final itemWidth = constraints.maxWidth > 72
                        ? constraints.maxWidth - 72
                        : 0.0;
                    return DropdownButtonFormField<String>(
                      value: _projectId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      items: projects
                          .map(
                            (project) => DropdownMenuItem<String>(
                              value: project.id,
                              child: SizedBox(
                                width: itemWidth,
                                child: Row(
                                  children: [
                                    Icon(project.icon, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        project.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: _saving ? null : _selectProject,
                    );
                  },
                ),
                const SizedBox(height: 16),
                const Text(
                  '업무명',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _titleController,
                  focusNode: _titleFocusNode,
                  enabled: !_saving,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '예상시간',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <int>[30, 60, 90, 120].map((minutes) {
                    final selected = _estimatedMinutes == minutes;
                    return AnimatedContainer(
                      duration: duration,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected
                              ? colors.primary
                              : colors.outlineVariant,
                        ),
                      ),
                      child: ChoiceChip(
                        label: Text(sprintFormatDuration(minutes)),
                        selected: selected,
                        onSelected: _saving
                            ? null
                            : (_) => setState(() {
                                  _estimatedMinutes = minutes;
                                }),
                      ),
                    );
                  }).toList(growable: false),
                ),
                const SizedBox(height: 16),
                const Text(
                  '일정 날짜와 시작 시각',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving ? null : _pickDate,
                        icon: const Icon(Icons.calendar_today_outlined),
                        label: Text(sprintFormatDate(_date)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving ? null : _pickTime,
                        icon: const Icon(Icons.schedule_rounded),
                        label: Text(sprintFormatTime(_start)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  '마감일',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                AnimatedContainer(
                  duration: duration,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      const Icon(Icons.flag_outlined),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: duration,
                          child: Text(
                            _deadline == null
                                ? '설정하지 않음'
                                : sprintFormatDate(_deadline!),
                            key: ValueKey<String>(
                              _deadline?.toIso8601String() ?? 'none',
                            ),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _saving ? null : _pickDeadline,
                        child: const Text('선택'),
                      ),
                      if (_deadline != null)
                        IconButton(
                          tooltip: '마감일 제거',
                          onPressed: _saving
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
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _saving || projects.isEmpty ? null : _save,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                  icon: const Icon(Icons.add_task_rounded),
                  label: AnimatedSwitcher(
                    duration: duration,
                    child: _saving
                        ? const SizedBox(
                            key: ValueKey<String>('saving'),
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : const Text(
                            '업무 추가',
                            key: ValueKey<String>('add'),
                          ),
                  ),
                ),
                if (projects.isEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    '업무를 추가하려면 먼저 프로젝트를 생성하세요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.error,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
