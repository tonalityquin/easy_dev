import 'package:flutter/material.dart';

import '../../../shared/google_calendar/google_event_colors.dart';
import '../application/sprint_mode_store.dart';
import '../domain/sprint_models.dart';
import 'sprint_block_editor_sheet.dart';
import 'sprint_ui.dart';

Future<bool> showSprintTaskDetailSheet({
  required BuildContext context,
  required SprintModeStore store,
  required String taskId,
}) async {
  final result = await sprintShowBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
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
  late final TextEditingController _descriptionController;
  String? _projectId;
  String? _calendarProfileId;
  SprintTaskPriority _priority = SprintTaskPriority.normal;
  late DateTime _startDate;
  late DateTime _endDate;
  bool _saving = false;
  bool _syncing = false;

  SprintTask? get _task => widget.store.taskById(widget.taskId);

  @override
  void initState() {
    super.initState();
    final task = _task;
    final today = DateTime.now();
    _titleController = TextEditingController(text: task?.title ?? '');
    _descriptionController = TextEditingController(
      text: task?.description ?? '',
    );
    _projectId = task?.projectId;
    _calendarProfileId =
        task?.googleCalendarProfileId ?? widget.store.defaultCalendarProfile?.id;
    _priority = task?.priority ?? SprintTaskPriority.normal;
    _startDate = task?.startDate ??
        DateTime(today.year, today.month, today.day);
    _endDate = task?.endDate ?? _startDate;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
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

  void _selectCalendar(String? value) {
    setState(() => _calendarProfileId = value);
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final firstDate = DateTime(1900, 1, 1);
    var initial = _startDate;
    if (initial.isBefore(firstDate)) initial = firstDate;
    final selected = await sprintShowDatePicker(
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
    final selected = await sprintShowDatePicker(
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
    final calendarProfileId = _calendarProfileId;
    if (calendarProfileId != null &&
        !widget.store.isProfileAuthenticated(calendarProfileId)) {
      try {
        await widget.store.authenticateCalendarProfile(
          calendarProfileId,
          forceAccountSelection: true,
        );
      } catch (_) {
        if (!mounted) return;
        setState(() => _saving = false);
        sprintShowMessage(
          context: context,
          message: '선택한 캘린더의 Google 계정을 인증하지 못했습니다.',
          danger: true,
        );
        return;
      }
    }
    final saved = await widget.store.updateTask(
      taskId: task.id,
      title: _titleController.text,
      description: _descriptionController.text,
      projectId: projectId,
      calendarProfileId: _calendarProfileId,
      priority: _priority,
      startDate: _startDate,
      endDate: _endDate,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    sprintShowMessage(
      context: context,
      message: saved
          ? '업무를 수정했습니다.'
          : widget.store.taskInputError ?? '업무 정보를 확인하세요.',
      danger: !saved,
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
    final confirmed = await sprintShowDialog<bool>(
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
    setState(() => _saving = true);
    final saved = await widget.store.cancelTask(task.id);
    if (!mounted) return;
    if (saved) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final task = _task;
    if (task == null) return;
    final confirmed = await sprintShowDialog<bool>(
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
    setState(() => _saving = true);
    final deleted = await widget.store.deleteTask(task.id);
    if (!mounted) return;
    if (deleted) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _saving = false);
      sprintShowMessage(
        context: context,
        message: 'Google Calendar 일정 삭제 후 다시 시도하세요.',
        danger: true,
      );
    }
  }

  Future<void> _retrySync() async {
    final task = _task;
    if (task == null || _syncing) return;
    setState(() => _syncing = true);
    final success = await widget.store.retryTaskGoogleSync(task.id);
    if (!mounted) return;
    setState(() => _syncing = false);
    sprintShowMessage(
      context: context,
      message: success
          ? 'Google Calendar 동기화를 완료했습니다.'
          : 'Google Calendar 동기화에 실패했습니다.',
      danger: !success,
    );
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
    final calendarProfiles = widget.store.calendarProfiles;
    final taskProfile = widget.store.calendarProfileById(_calendarProfileId);
    final taskAccount = widget.store.accountForProfile(taskProfile?.id);
    final project = widget.store.projectById(_projectId);
    final projectColor = googleEventColor(
      project?.googleColorId,
      colors.primary,
    );
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
            const SizedBox(height: 14),
            if (calendarProfiles.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                value: _calendarProfileId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Google 캘린더',
                  border: OutlineInputBorder(),
                ),
                items: calendarProfiles
                    .map(
                      (profile) {
                        final account =
                            widget.store.accountForProfile(profile.id);
                        return DropdownMenuItem<String>(
                          value: profile.id,
                          child: Row(
                            children: [
                              Icon(
                                profile.id ==
                                        widget.store.defaultCalendarProfileId
                                    ? Icons.star_rounded
                                    : Icons.calendar_month_outlined,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${profile.label} · ${account?.email ?? ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    )
                    .toList(growable: false),
                onChanged: _saving ? null : _selectCalendar,
              ),
              const SizedBox(height: 10),
            ],
            AnimatedSwitcher(
              duration: duration,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.05),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: Container(
                key: ValueKey<String>(taskProfile?.id ?? 'local-only'),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Icon(
                      taskProfile == null
                          ? Icons.cloud_off_outlined
                          : Icons.event_available_outlined,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            taskProfile?.label ?? '로컬 업무',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            taskProfile == null
                                ? '연결된 캘린더가 없어 로컬 변경만 저장합니다.'
                                : '${taskAccount?.email ?? ''} · ${taskProfile.calendarId}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _titleController,
              enabled: !_saving,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '업무명',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            AnimatedContainer(
              duration: duration,
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
              ),
              child: TextField(
                controller: _descriptionController,
                enabled: !_saving,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: '업무 내용',
                  border: OutlineInputBorder(),
                ),
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
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: googleEventColor(
                                project.googleColorId,
                                colors.primary,
                              ),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
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
            const SizedBox(height: 10),
            AnimatedContainer(
              duration: duration,
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: projectColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: task.googleSyncState == SprintGoogleSyncState.failed
                      ? colors.error
                      : projectColor.withOpacity(0.6),
                ),
              ),
              child: Row(
                children: [
                  AnimatedSwitcher(
                    duration: duration,
                    child: _syncing ||
                            task.googleSyncState ==
                                SprintGoogleSyncState.pendingCreate ||
                            task.googleSyncState ==
                                SprintGoogleSyncState.pendingUpdate ||
                            task.googleSyncState ==
                                SprintGoogleSyncState.pendingDelete
                        ? SizedBox(
                            key: const ValueKey<String>('syncing'),
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: projectColor,
                            ),
                          )
                        : Icon(
                            task.googleSyncState ==
                                    SprintGoogleSyncState.synced
                                ? Icons.cloud_done_rounded
                                : task.googleSyncState ==
                                        SprintGoogleSyncState.failed
                                    ? Icons.cloud_off_rounded
                                    : Icons.cloud_queue_rounded,
                            key: ValueKey<SprintGoogleSyncState>(
                              task.googleSyncState,
                            ),
                            color: task.googleSyncState ==
                                    SprintGoogleSyncState.failed
                                ? colors.error
                                : projectColor,
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Google Calendar',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _googleSyncLabel(task.googleSyncState),
                          style: TextStyle(
                            color: task.googleSyncState ==
                                    SprintGoogleSyncState.failed
                                ? colors.error
                                : colors.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (task.googleSyncState == SprintGoogleSyncState.failed)
                    TextButton(
                      onPressed: _syncing ? null : _retrySync,
                      child: const Text('다시 시도'),
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
              onPressed: _saving ? null : _cancel,
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('업무 취소'),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _saving ? null : _delete,
              icon: Icon(Icons.delete_outline_rounded, color: colors.error),
              label: Text('업무 삭제', style: TextStyle(color: colors.error)),
            ),
          ],
        ),
      ),
    );
  }
}


String _googleSyncLabel(SprintGoogleSyncState state) {
  switch (state) {
    case SprintGoogleSyncState.none:
      return '연결 대기';
    case SprintGoogleSyncState.pendingCreate:
      return '일정 생성 대기';
    case SprintGoogleSyncState.pendingUpdate:
      return '변경사항 반영 대기';
    case SprintGoogleSyncState.pendingDelete:
      return '일정 삭제 대기';
    case SprintGoogleSyncState.synced:
      return '동기화 완료';
    case SprintGoogleSyncState.failed:
      return '동기화 실패';
  }
}
