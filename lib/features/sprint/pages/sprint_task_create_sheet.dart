import 'package:flutter/material.dart';

import '../../../shared/google_calendar/google_event_colors.dart';
import '../application/sprint_mode_store.dart';
import '../domain/sprint_models.dart';
import 'sprint_ui.dart';

Future<SprintTask?> showSprintTaskCreateSheet({
  required BuildContext context,
  required SprintModeStore store,
  required DateTime initialDate,
  String? initialProjectId,
}) {
  return sprintShowBottomSheet<SprintTask>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
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
  final TextEditingController _descriptionController = TextEditingController();
  final FocusNode _titleFocusNode = FocusNode();
  late DateTime _startDate;
  late DateTime _endDate;
  String? _projectId;
  String? _calendarProfileId;
  SprintTaskPriority _priority = SprintTaskPriority.normal;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final requested = DateTime(
      widget.initialDate.year,
      widget.initialDate.month,
      widget.initialDate.day,
    );
    _projectId = widget.store.preferredTaskProjectId(widget.initialProjectId);
    _calendarProfileId = widget.store.defaultCalendarProfile?.id;
    final projectId = _projectId;
    _startDate = projectId == null
        ? requested
        : widget.store.suggestedTaskStart(
            projectId: projectId,
            date: requested,
          );
    _endDate = _startDate;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _titleFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _titleFocusNode.dispose();
    super.dispose();
  }

  void _selectProject(String? value) {
    if (value == null) {
      setState(() => _projectId = null);
      return;
    }
    final adjusted = widget.store.suggestedTaskStart(
      projectId: value,
      date: _startDate,
    );
    final changed = adjusted != _startDate;
    final duration = _endDate.difference(_startDate).inDays;
    setState(() {
      _projectId = value;
      _startDate = adjusted;
      _endDate = adjusted.add(Duration(days: duration));
    });
    if (changed) {
      sprintShowMessage(
        context: context,
        message: '프로젝트 목표 시작일에 맞춰 시작일을 ${sprintFormatDate(adjusted)}로 변경했습니다.',
      );
    }
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
    final now = DateTime.now();
    var initial = _endDate;
    if (initial.isBefore(_startDate)) initial = _startDate;
    final selected = await sprintShowDatePicker(
      context: context,
      initialDate: initial,
      firstDate: _startDate,
      lastDate: DateTime(now.year + 10, 12, 31),
    );
    if (selected == null || !mounted) return;
    setState(() => _endDate = selected);
  }

  Future<void> _save() async {
    if (_saving) return;
    final projectId = _projectId;
    if (projectId == null || _titleController.text.trim().isEmpty) {
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
      description: _descriptionController.text,
      projectId: projectId,
      calendarProfileId: _calendarProfileId,
      priority: _priority,
      startDate: _startDate,
      endDate: _endDate,
    );
    if (preview == null) {
      sprintShowMessage(
        context: context,
        message: widget.store.taskInputError ?? '업무 정보를 확인하세요.',
      );
      return;
    }
    if (preview.hasHardConflict) {
      sprintShowMessage(
        context: context,
        message: '종료일은 시작일보다 빠를 수 없습니다.',
      );
      return;
    }
    setState(() => _saving = true);
    final calendarProfileId = preview.calendarProfileId;
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
    final task = await widget.store.createTaskFromPreview(preview);
    if (!mounted) return;
    if (task == null) {
      setState(() => _saving = false);
      sprintShowMessage(
        context: context,
        message: widget.store.taskInputError ?? '업무를 추가하지 못했습니다.',
      );
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
    final calendarProfiles = widget.store.calendarProfiles;
    final calendarProfile =
        widget.store.calendarProfileById(_calendarProfileId);
    final calendarAccount =
        widget.store.accountForProfile(calendarProfile?.id);
    final project = widget.store.projectById(_projectId);
    final targetDate = project?.targetDate;
    final afterTarget = targetDate != null &&
        _endDate.isAfter(DateTime(
          targetDate.year,
          targetDate.month,
          targetDate.day,
        ));
    return Material(
      color: colors.surface,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 10),
        child: AnimatedPadding(
          duration: duration,
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
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
                const SizedBox(height: 14),
                if (calendarProfiles.isNotEmpty) ...[
                  const Text(
                    'Google 캘린더',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _calendarProfileId,
                    isExpanded: true,
                    decoration: const InputDecoration(
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
                    key: ValueKey<String>(calendarProfile?.id ?? 'local-only'),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          calendarProfile == null
                              ? Icons.cloud_off_outlined
                              : Icons.event_available_outlined,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                calendarProfile == null
                                    ? '로컬 업무'
                                    : calendarProfile.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                calendarProfile == null
                                    ? '연결된 캘린더가 없어 로컬에 저장합니다.'
                                    : '${calendarAccount?.email ?? ''} · ${calendarProfile.calendarId}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
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
                                    Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: googleEventColor(
                                          project.googleColorId,
                                          Theme.of(context).colorScheme.primary,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
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
                  '업무 내용',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
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
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '우선순위',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
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
                const SizedBox(height: 16),
                const Text(
                  '기간',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
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
                            key: ValueKey<int>(
                              _startDate.millisecondsSinceEpoch,
                            ),
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
                            key: ValueKey<int>(
                              _endDate.millisecondsSinceEpoch,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                AnimatedContainer(
                  duration: duration,
                  curve: Curves.easeOutCubic,
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
                    ],
                  ),
                ),
                AnimatedSize(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  child: afterTarget
                      ? Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            '종료일이 프로젝트 목표 완료일보다 늦습니다.',
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
