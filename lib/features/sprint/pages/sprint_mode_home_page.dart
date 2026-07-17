import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../application/sprint_mode_store.dart';
import '../domain/sprint_models.dart';
import 'sprint_block_editor_sheet.dart';
import 'sprint_conflict_resolution_sheet.dart';
import 'sprint_project_archive_page.dart';
import 'sprint_project_completion_page.dart';
import 'sprint_project_management_page.dart';
import 'sprint_project_home_page.dart';
import 'sprint_project_workspace_sheet.dart';
import 'sprint_task_create_sheet.dart';
import 'sprint_task_detail_sheet.dart';
import 'sprint_ui.dart';

Future<void> showSprintAttentionSheet({
  required BuildContext context,
  required SprintModeStore store,
}) async {
  final colors = Theme.of(context).colorScheme;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: colors.surface,
    barrierColor: colors.scrim,
    builder: (_) => _AttentionSheet(store: store),
  );
}

class SprintModeHomePage extends StatefulWidget {
  const SprintModeHomePage({
    super.key,
    this.store,
    this.disposeStore = true,
  });

  final SprintModeStore? store;
  final bool disposeStore;

  @override
  State<SprintModeHomePage> createState() => _SprintModeHomePageState();
}

class _SprintModeHomePageState extends State<SprintModeHomePage>
    with WidgetsBindingObserver {
  late final SprintModeStore _store;
  late final Future<void> _initialization;
  final TextEditingController _composerController = TextEditingController();
  final FocusNode _composerFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _store = widget.store ?? SprintModeStore();
    _initialization = _store.initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_store.flush());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_store.flush());
    _composerController.dispose();
    _composerFocusNode.dispose();
    if (widget.disposeStore) {
      _store.dispose();
    }
    super.dispose();
  }

  Future<void> _submitTask() async {
    final task = await sprintCreateTaskFromComposer(
      context: context,
      store: _store,
      rawText: _composerController.text,
    );
    if (!mounted || task == null) return;
    _composerController.clear();
    _composerFocusNode.unfocus();
    sprintShowMessage(
      context: context,
      message: '${task.title} 업무를 추가했습니다.',
    );
  }

  Future<void> _openProject() async {
    final project = _store.selectedProject;
    if (project == null) {
      await _openWorkspacePanel();
      return;
    }
    await Navigator.of(context).push<void>(_projectRoute());
  }

  Route<void> _projectRoute({
    SprintWorkspacePanelDestination destination =
        SprintWorkspacePanelDestination.summary,
  }) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      return PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) => SprintProjectHomePage(
          store: _store,
          initialDestination: destination,
        ),
      );
    }
    return MaterialPageRoute<void>(
      builder: (_) => SprintProjectHomePage(
        store: _store,
        initialDestination: destination,
      ),
    );
  }

  Route<void> _pageRoute(Widget page) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return PageRouteBuilder<void>(
      transitionDuration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 260),
      reverseTransitionDuration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 210),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        if (reduceMotion) return child;
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.035, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _openWorkspacePanel() async {
    final result = await showSprintWorkspacePanel(
      context: context,
      store: _store,
    );
    if (result == null || !mounted) return;
    _store.selectScope(result.scope);
    switch (result.destination) {
      case SprintWorkspacePanelDestination.schedule:
        return;
      case SprintWorkspacePanelDestination.summary:
      case SprintWorkspacePanelDestination.path:
        if (result.scope.type == SprintWorkspaceScopeType.project) {
          await Navigator.of(context).push<void>(
            _projectRoute(destination: result.destination),
          );
        }
        return;
      case SprintWorkspacePanelDestination.attention:
        _openAttention();
        return;
      case SprintWorkspacePanelDestination.management:
        if (result.scope.type != SprintWorkspaceScopeType.project) return;
        await Navigator.of(context).push<void>(
          _pageRoute(
            SprintProjectManagementPage(
              store: _store,
              projectId: result.scope.projectId!,
            ),
          ),
        );
        return;
      case SprintWorkspacePanelDestination.completion:
        if (result.scope.type != SprintWorkspaceScopeType.project) return;
        await Navigator.of(context).push<void>(
          _pageRoute(
            SprintProjectCompletionPage(
              store: _store,
              projectId: result.scope.projectId!,
            ),
          ),
        );
        return;
      case SprintWorkspacePanelDestination.archive:
        await Navigator.of(context).push<void>(
          _pageRoute(SprintProjectArchivePage(store: _store)),
        );
        return;
    }
  }

  Future<void> _openReview() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _SprintReviewSettingsPage(store: _store),
      ),
    );
  }

  void _openUnplaced() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      barrierColor: Theme.of(context).colorScheme.scrim,
      builder: (_) => _UnplacedTasksSheet(store: _store),
    );
  }

  void _openAttention() {
    showSprintAttentionSheet(context: context, store: _store);
  }

  Future<void> _openTaskCreate() async {
    final now = DateTime.now();
    final selected = DateTime(
      _store.selectedDate.year,
      _store.selectedDate.month,
      _store.selectedDate.day,
    );
    final today = DateTime(now.year, now.month, now.day);
    if (selected.isBefore(today)) {
      sprintShowMessage(
        context: context,
        message: '과거 날짜에는 업무를 추가할 수 없습니다.',
      );
      return;
    }
    final projectId = _store.selectedProjectId;
    if (projectId != null && !_store.canScheduleProjectOn(projectId, selected)) {
      final lowerBound = _store.projectScheduleLowerBound(projectId)!;
      sprintShowMessage(
        context: context,
        message: '이 프로젝트는 ${sprintFormatDate(lowerBound)}부터 업무를 추가할 수 있습니다.',
      );
      return;
    }
    await showSprintTaskCreateSheet(
      context: context,
      store: _store,
      initialDate: selected,
      initialProjectId: _store.selectedProjectId,
    );
  }

  void _showCompletionMessage(String title) {
    sprintShowMessage(
      context: context,
      message: '$title 업무를 완료했습니다.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('스프린트 모드')),
            body: const SafeArea(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('로컬 데이터를 불러오지 못했습니다.'),
                ),
              ),
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done ||
            !_store.initialized) {
          return const Scaffold(
            body: SafeArea(
              child: Center(
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
          );
        }
        return AnimatedBuilder(
          animation: _store,
          builder: (context, child) {
            final unplacedCount = _store.unplacedTasks().length;
            final attentionCount = _store.currentScopeAttentionItems.length;

            return Scaffold(
          extendBody: false,
          extendBodyBehindAppBar: false,
          backgroundColor: Theme.of(context).colorScheme.surface,
          appBar: AppBar(
            leading: IconButton(
              tooltip: '프로젝트 메뉴',
              onPressed: _openWorkspacePanel,
              icon: const Icon(Icons.menu_rounded),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sprintFormatDate(_store.selectedDate)),
                Text(
                  _store.scopeLabel,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            actions: [
              TextButton.icon(
                onPressed: _openUnplaced,
                icon: const Icon(Icons.inbox_outlined),
                label: Text('미배치 $unplacedCount'),
              ),
              IconButton(
                tooltip: '리뷰 및 설정',
                onPressed: _openReview,
                icon: const Icon(Icons.tune_rounded),
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                  child: SegmentedButton<bool>(
                    segments: const <ButtonSegment<bool>>[
                      ButtonSegment<bool>(
                        value: false,
                        label: Text('오늘'),
                        icon: Icon(Icons.today_outlined),
                      ),
                      ButtonSegment<bool>(
                        value: true,
                        label: Text('주간'),
                        icon: Icon(Icons.date_range_outlined),
                      ),
                    ],
                    selected: <bool>{_store.weekMode},
                    onSelectionChanged: (selection) {
                      _store.setWeekMode(selection.first);
                    },
                  ),
                ),
                if (_store.weekMode)
                  _WeekDensityStrip(store: _store),
                Expanded(
                  child: _ScheduleTimeline(
                    store: _store,
                    onCompletion: _showCompletionMessage,
                    onAddTask: _openTaskCreate,
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: _SprintBottomDock(
            store: _store,
            controller: _composerController,
            focusNode: _composerFocusNode,
            attentionCount: attentionCount,
            onProjectTap: _openProject,
            onProjectSwitchTap: _openWorkspacePanel,
            onAddTask: _openTaskCreate,
            onAttentionTap: _openAttention,
            onSubmit: _submitTask,
          ),
            );
          },
        );
      },
    );
  }
}

class _WeekDensityStrip extends StatelessWidget {
  const _WeekDensityStrip({required this.store});

  final SprintModeStore store;

  @override
  Widget build(BuildContext context) {
    final dates = store.weekDates(store.selectedDate);
    final colors = Theme.of(context).colorScheme;

    return SizedBox(
      height: 102,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
        scrollDirection: Axis.horizontal,
        itemCount: dates.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final date = dates[index];
          final selected = sprintSameDay(date, store.selectedDate);
          final today = sprintSameDay(date, DateTime.now());
          final minutes = store.plannedMinutesForCurrentScope(date);
          final ratio = (minutes / 360).clamp(0.08, 1).toDouble();
          final overloaded = minutes > 360;

          return Material(
            color: selected
                ? colors.primaryContainer
                : colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => store.selectDate(date),
              child: Container(
                width: 52,
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: overloaded
                        ? colors.error
                        : today
                            ? colors.primary
                            : colors.outlineVariant,
                    width: overloaded || today ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      sprintWeekday(date.weekday),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '${date.day}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 22,
                      height: 24,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: ratio,
                          child: Container(
                            decoration: BoxDecoration(
                              color: colors.primary,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ScheduleTimeline extends StatelessWidget {
  const _ScheduleTimeline({
    required this.store,
    required this.onCompletion,
    required this.onAddTask,
  });

  final SprintModeStore store;
  final ValueChanged<String> onCompletion;
  final VoidCallback onAddTask;

  @override
  Widget build(BuildContext context) {
    final entries = store.timelineFor(store.selectedDate);
    return RefreshIndicator(
      onRefresh: () async {
        if (store.calendarState == SprintCalendarConnectionState.connected ||
            store.calendarState == SprintCalendarConnectionState.failed) {
          await store.syncGoogleCalendar();
        }
      },
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: entries.length + 2 + (entries.isEmpty ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _TimelineStatusHeader(store: store),
            );
          }
          if (index == 1) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _DateTaskAddButton(
                store: store,
                onPressed: onAddTask,
              ),
            );
          }
          if (entries.isEmpty) {
            return const _ScheduleEmptyState();
          }
          final entry = entries[index - 2];
          if (entry.isExternal) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ExternalEventCard(event: entry.externalEvent!),
            );
          }
          final task = entry.task!;
          final block = entry.block!;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _TaskDismissibleCard(
              store: store,
              task: task,
              block: block,
              project: entry.project,
              onOpenBlock: () {
                showSprintBlockEditorSheet(
                  context: context,
                  store: store,
                  task: task,
                  block: block,
                );
              },
              onCompletion: () {
                store.completeTask(task.id);
                onCompletion(task.title);
              },
            ),
          );
        },
      ),
    );
  }
}

class _DateTaskAddButton extends StatelessWidget {
  const _DateTaskAddButton({
    required this.store,
    required this.onPressed,
  });

  final SprintModeStore store;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 200);
    final now = DateTime.now();
    final selected = DateTime(
      store.selectedDate.year,
      store.selectedDate.month,
      store.selectedDate.day,
    );
    final today = DateTime(now.year, now.month, now.day);
    final isPast = selected.isBefore(today);
    final hasProjects = store.projects.isNotEmpty;
    final selectedProjectId = store.selectedProjectId;
    final beforeProjectStart = selectedProjectId != null &&
        !store.canScheduleProjectOn(selectedProjectId, selected);
    final enabled = !isPast && hasProjects && !beforeProjectStart;
    final label = isPast
        ? '과거 날짜에는 업무를 추가할 수 없습니다'
        : !hasProjects
            ? '프로젝트를 만든 뒤 업무를 추가하세요'
            : beforeProjectStart
                ? '이 프로젝트는 ${sprintFormatDate(store.projectScheduleLowerBound(selectedProjectId)!)}부터 시작합니다'
                : '${sprintFormatDate(store.selectedDate)}에 업무 추가';
    return AnimatedContainer(
      duration: duration,
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: enabled ? colors.primaryContainer : colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: enabled ? colors.primary : colors.outlineVariant,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: enabled ? onPressed : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: duration,
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: enabled
                          ? colors.primary
                          : colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.add_task_rounded,
                      color: enabled
                          ? colors.onPrimary
                          : colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: enabled
                            ? colors.onPrimaryContainer
                            : colors.onSurfaceVariant,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (enabled)
                    Icon(
                      Icons.chevron_right_rounded,
                      color: colors.onPrimaryContainer,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TimelineStatusHeader extends StatelessWidget {
  const _TimelineStatusHeader({required this.store});

  final SprintModeStore store;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = sprintSameDay(store.selectedDate, now);
    final calendarState = store.calendarState;
    String calendarLabel;
    switch (calendarState) {
      case SprintCalendarConnectionState.notConnected:
        calendarLabel = 'Google 캘린더 연결 안 됨';
        break;
      case SprintCalendarConnectionState.syncing:
        calendarLabel = 'Google 캘린더 동기화 중';
        break;
      case SprintCalendarConnectionState.connected:
        calendarLabel = 'Google 캘린더 연결됨';
        break;
      case SprintCalendarConnectionState.failed:
        calendarLabel = 'Google 캘린더 동기화 실패';
        break;
    }

    return Row(
      children: [
        Expanded(
          child: Text(
            today ? '현재 ${sprintFormatTime(now)}' : sprintFormatDate(store.selectedDate),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ),
        Text(
          calendarLabel,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: calendarState == SprintCalendarConnectionState.failed
                    ? colors.error
                    : colors.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}

enum _DirectPlacementChoice {
  recommended,
  requested,
}

class _TaskDismissibleCard extends StatefulWidget {
  const _TaskDismissibleCard({
    required this.store,
    required this.task,
    required this.block,
    required this.project,
    required this.onOpenBlock,
    required this.onCompletion,
  });

  final SprintModeStore store;
  final SprintTask task;
  final SprintScheduleBlock block;
  final SprintProject? project;
  final VoidCallback onOpenBlock;
  final VoidCallback onCompletion;

  @override
  State<_TaskDismissibleCard> createState() =>
      _TaskDismissibleCardState();
}

class _TaskDismissibleCardState extends State<_TaskDismissibleCard> {
  static const double _pixelsPerSlot = 36;
  double _movePixels = 0;
  double _resizePixels = 0;
  DateTime? _previewStart;
  DateTime? _previewEnd;
  SprintPlacementValidation? _previewValidation;
  bool _moving = false;
  bool _resizing = false;
  bool _saving = false;
  int _timeAnimationRevision = 0;
  late int _lastBlockStartMilliseconds;
  late int _lastBlockEndMilliseconds;

  @override
  void initState() {
    super.initState();
    _lastBlockStartMilliseconds =
        widget.block.start.millisecondsSinceEpoch;
    _lastBlockEndMilliseconds = widget.block.end.millisecondsSinceEpoch;
  }

  @override
  void didUpdateWidget(covariant _TaskDismissibleCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final startMilliseconds = widget.block.start.millisecondsSinceEpoch;
    final endMilliseconds = widget.block.end.millisecondsSinceEpoch;
    if (startMilliseconds != _lastBlockStartMilliseconds ||
        endMilliseconds != _lastBlockEndMilliseconds) {
      _lastBlockStartMilliseconds = startMilliseconds;
      _lastBlockEndMilliseconds = endMilliseconds;
      _timeAnimationRevision += 1;
    }
  }

  bool get _editable {
    return widget.task.state != SprintTaskState.completed &&
        widget.task.state != SprintTaskState.cancelled &&
        widget.block.status == SprintScheduleBlockStatus.planned;
  }

  DateTime _moveCandidate(double pixels) {
    final slots = (pixels / _pixelsPerSlot).round();
    final duration = widget.block.durationMinutes;
    final dayStart = DateTime(
      widget.block.start.year,
      widget.block.start.month,
      widget.block.start.day,
    );
    final dayEnd = dayStart.add(const Duration(days: 1));
    var candidate = widget.block.start.add(
      Duration(minutes: slots * 30),
    );
    if (candidate.isBefore(dayStart)) candidate = dayStart;
    candidate = widget.store.normalizeScheduleStart(candidate);
    if (candidate.add(Duration(minutes: duration)).isAfter(dayEnd)) {
      final availableMinutes = dayEnd.difference(dayStart).inMinutes - duration;
      final latestSlotMinutes =
          math.max(0, availableMinutes ~/ 30 * 30).toInt();
      candidate = dayStart.add(Duration(minutes: latestSlotMinutes));
    }
    return candidate;
  }

  DateTime _resizeCandidate(double pixels) {
    final slots = (pixels / _pixelsPerSlot).round();
    final duration = math.max(
      20,
      widget.block.durationMinutes + slots * 30,
    ).toInt();
    final dayEnd = DateTime(
      widget.block.start.year,
      widget.block.start.month,
      widget.block.start.day + 1,
    );
    final candidate = widget.block.start.add(Duration(minutes: duration));
    return candidate.isAfter(dayEnd) ? dayEnd : candidate;
  }

  void _startMove(DragStartDetails _) {
    if (!_editable || widget.block.locked || _saving) return;
    setState(() {
      _timeAnimationRevision += 1;
      _moving = true;
      _resizing = false;
      _movePixels = 0;
      _previewStart = widget.block.start;
      _previewEnd = widget.block.end;
      _previewValidation = null;
    });
  }

  void _updateMove(DragUpdateDetails details) {
    if (!_moving) return;
    _movePixels += details.delta.dy;
    final start = _moveCandidate(_movePixels);
    final end = start.add(
      Duration(minutes: widget.block.durationMinutes),
    );
    final validation = widget.store.validateBlockPlacement(
      start: start,
      end: end,
      blockId: widget.block.id,
      taskId: widget.task.id,
    );
    setState(() {
      _timeAnimationRevision += 1;
      _previewStart = start;
      _previewEnd = end;
      _previewValidation = validation;
    });
  }

  Future<void> _endMove(DragEndDetails _) async {
    if (!_moving) return;
    final start = _previewStart ?? widget.block.start;
    final validation = _previewValidation ??
        widget.store.validateBlockPlacement(
          start: start,
          end: start.add(
            Duration(minutes: widget.block.durationMinutes),
          ),
          blockId: widget.block.id,
          taskId: widget.task.id,
        );
    if (start == widget.block.start) {
      _resetManipulation();
      return;
    }
    await _commitMove(start, validation);
  }

  void _startResize(DragStartDetails _) {
    if (!_editable || widget.block.locked || _saving) return;
    setState(() {
      _timeAnimationRevision += 1;
      _resizing = true;
      _moving = false;
      _resizePixels = 0;
      _previewStart = widget.block.start;
      _previewEnd = widget.block.end;
      _previewValidation = null;
    });
  }

  void _updateResize(DragUpdateDetails details) {
    if (!_resizing) return;
    _resizePixels += details.delta.dy;
    final end = _resizeCandidate(_resizePixels);
    final validation = widget.store.validateBlockPlacement(
      start: widget.block.start,
      end: end,
      blockId: widget.block.id,
      taskId: widget.task.id,
    );
    setState(() {
      _timeAnimationRevision += 1;
      _previewStart = widget.block.start;
      _previewEnd = end;
      _previewValidation = validation;
    });
  }

  Future<void> _endResize(DragEndDetails _) async {
    if (!_resizing) return;
    final end = _previewEnd ?? widget.block.end;
    final validation = _previewValidation ??
        widget.store.validateBlockPlacement(
          start: widget.block.start,
          end: end,
          blockId: widget.block.id,
          taskId: widget.task.id,
        );
    if (end == widget.block.end) {
      _resetManipulation();
      return;
    }
    await _commitResize(end, validation);
  }

  Future<_DirectPlacementChoice?> _requestPlacementChoice({
    required SprintPlacementValidation validation,
    required DateTime start,
    required int durationMinutes,
  }) async {
    if (validation.conflicts.isEmpty) {
      return _DirectPlacementChoice.requested;
    }
    final beforeProjectStart = validation.conflicts.any(
      (conflict) => conflict.type == SprintConflictType.beforeProjectStart,
    );
    final hard = beforeProjectStart ||
        validation.conflicts.any(
          (conflict) => conflict.type == SprintConflictType.pastTime,
        );
    if (hard) {
      if (mounted) {
        sprintShowMessage(
          context: context,
          message: beforeProjectStart
              ? '프로젝트 목표 시작일 이전에는 일정을 배치할 수 없습니다.'
              : '과거 시간에는 일정을 배치할 수 없습니다.',
        );
      }
      return null;
    }
    final recommended = widget.store.nextAvailableStartForBlock(
      blockId: widget.block.id,
      anchor: start,
      durationMinutes: durationMinutes,
    );
    return showModalBottomSheet<_DirectPlacementChoice>(
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
        final titles = validation.conflicts
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
                  '배치 위치 확인',
                  style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  titles,
                  style: TextStyle(
                    color: Theme.of(sheetContext).colorScheme.error,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () => Navigator.of(sheetContext).pop(
                    _DirectPlacementChoice.recommended,
                  ),
                  icon: const Icon(Icons.auto_fix_high_rounded),
                  label: Text(
                    '${sprintFormatDate(recommended)} ${sprintFormatTime(recommended)}에 배치',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(sheetContext).pop(
                    _DirectPlacementChoice.requested,
                  ),
                  icon: const Icon(Icons.warning_amber_rounded),
                  label: Text(
                    '${sprintFormatTime(start)}에 그대로 배치',
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

  Future<void> _commitMove(
    DateTime start,
    SprintPlacementValidation validation,
  ) async {
    final choice = await _requestPlacementChoice(
      validation: validation,
      start: start,
      durationMinutes: widget.block.durationMinutes,
    );
    if (choice == null || !mounted) {
      _resetManipulation();
      return;
    }
    setState(() {
      _timeAnimationRevision += 1;
      _saving = true;
    });
    final target = choice == _DirectPlacementChoice.recommended
        ? widget.store.nextAvailableStartForBlock(
            blockId: widget.block.id,
            anchor: start,
          )
        : start;
    final result = await widget.store.moveBlock(
      blockId: widget.block.id,
      newStart: target,
      allowConflicts: validation.conflicts.isNotEmpty &&
          choice == _DirectPlacementChoice.requested,
    );
    if (!mounted) return;
    _resetManipulation();
    if (result.success) {
      sprintShowMessage(
        context: context,
        message: result.message,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    }
  }

  Future<void> _commitResize(
    DateTime end,
    SprintPlacementValidation validation,
  ) async {
    final durationMinutes = end.difference(widget.block.start).inMinutes;
    final choice = await _requestPlacementChoice(
      validation: validation,
      start: widget.block.start,
      durationMinutes: durationMinutes,
    );
    if (choice == null || !mounted) {
      _resetManipulation();
      return;
    }
    setState(() {
      _timeAnimationRevision += 1;
      _saving = true;
    });
    SprintOperationResult result;
    if (choice == _DirectPlacementChoice.recommended) {
      final target = widget.store.nextAvailableStartForBlock(
        blockId: widget.block.id,
        anchor: widget.block.start,
        durationMinutes: durationMinutes,
      );
      result = await widget.store.updateBlock(
        blockId: widget.block.id,
        start: target,
        end: target.add(Duration(minutes: durationMinutes)),
        locked: widget.block.locked,
      );
    } else {
      result = await widget.store.resizeBlock(
        blockId: widget.block.id,
        newEnd: end,
        allowConflicts: validation.conflicts.isNotEmpty,
      );
    }
    if (!mounted) return;
    _resetManipulation();
    if (result.success) {
      sprintShowMessage(
        context: context,
        message: result.message,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    }
  }

  void _resetManipulation() {
    if (!mounted) return;
    setState(() {
      _timeAnimationRevision += 1;
      _moving = false;
      _resizing = false;
      _saving = false;
      _movePixels = 0;
      _resizePixels = 0;
      _previewStart = null;
      _previewEnd = null;
      _previewValidation = null;
    });
  }

  Future<bool> _confirmDismiss(
    BuildContext context,
    DismissDirection direction,
  ) async {
    if (direction == DismissDirection.startToEnd) {
      widget.onCompletion();
      return false;
    }

    final type = await showModalBottomSheet<SprintPostponeType>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      barrierColor: Theme.of(context).colorScheme.scrim,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '언제 다시 할까요?',
                style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 12),
              _PostponeTile(
                title: '오늘 나중',
                subtitle: '가까운 빈 시간',
                value: SprintPostponeType.laterToday,
              ),
              _PostponeTile(
                title: '내일',
                subtitle: '09:30',
                value: SprintPostponeType.tomorrow,
              ),
              _PostponeTile(
                title: '다음 주',
                subtitle: '월요일 10:00',
                value: SprintPostponeType.nextWeek,
              ),
              _PostponeTile(
                title: '자동 재배치',
                subtitle: '빈 시간을 다시 계산',
                value: SprintPostponeType.automatic,
              ),
            ],
          ),
        );
      },
    );

    if (type != null) {
      widget.store.postponeTask(widget.task.id, type);
      if (mounted) {
        sprintShowMessage(
          context: context,
          message: '${widget.task.title} 업무를 연기했습니다.',
        );
      }
    }
    return false;
  }

  void _openQuickActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      barrierColor: Theme.of(context).colorScheme.scrim,
      builder: (sheetContext) {
        return _TaskQuickActionSheet(
          store: widget.store,
          task: widget.task,
          onComplete: () {
            Navigator.of(sheetContext).pop();
            widget.onCompletion();
          },
          onManageTask: () {
            Navigator.of(sheetContext).pop();
            Future<void>.delayed(Duration.zero, () {
              if (!context.mounted) return;
              showSprintTaskDetailSheet(
                context: context,
                store: widget.store,
                task: widget.task,
              );
            });
          },
          onManageBlock: () {
            Navigator.of(sheetContext).pop();
            Future<void>.delayed(Duration.zero, () {
              if (!context.mounted) return;
              showSprintBlockEditorSheet(
                context: context,
                store: widget.store,
                task: widget.task,
                block: widget.block,
              );
            });
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 180);
    final previewStart = _previewStart ?? widget.block.start;
    final previewEnd = _previewEnd ?? widget.block.end;
    final conflict = _previewValidation?.conflicts.isNotEmpty ?? false;
    final visualOffset = _moving ? _movePixels.clamp(-120, 120).toDouble() : 0.0;
    final interactionEnabled = !_moving && !_resizing && !_saving;
    return Dismissible(
      key: ValueKey<String>('task-${widget.task.id}-${widget.block.id}'),
      direction: !_editable || !interactionEnabled
          ? DismissDirection.none
          : DismissDirection.horizontal,
      confirmDismiss: (direction) => _confirmDismiss(context, direction),
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_rounded),
            SizedBox(width: 8),
            Text('완료'),
          ],
        ),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('연기'),
            SizedBox(width: 8),
            Icon(Icons.schedule_rounded),
          ],
        ),
      ),
      child: AnimatedContainer(
        duration: _moving ? Duration.zero : duration,
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, visualOffset, 0),
        child: _TaskScheduleCard(
          task: widget.task,
          block: widget.block,
          project: widget.project,
          displayStart: previewStart,
          displayEnd: previewEnd,
          timeAnimationRevision: _timeAnimationRevision,
          manipulating: _moving || _resizing || _saving,
          conflict: conflict,
          onTap: widget.onOpenBlock,
          onLongPress: () => _openQuickActions(context),
          onMoveStart: _startMove,
          onMoveUpdate: _updateMove,
          onMoveEnd: _endMove,
          onResizeStart: _startResize,
          onResizeUpdate: _updateResize,
          onResizeEnd: _endResize,
        ),
      ),
    );
  }
}

class _TaskScheduleCard extends StatelessWidget {
  const _TaskScheduleCard({
    required this.task,
    required this.block,
    required this.project,
    required this.displayStart,
    required this.displayEnd,
    required this.timeAnimationRevision,
    required this.manipulating,
    required this.conflict,
    required this.onTap,
    required this.onLongPress,
    required this.onMoveStart,
    required this.onMoveUpdate,
    required this.onMoveEnd,
    required this.onResizeStart,
    required this.onResizeUpdate,
    required this.onResizeEnd,
  });

  final SprintTask task;
  final SprintScheduleBlock block;
  final SprintProject? project;
  final DateTime displayStart;
  final DateTime displayEnd;
  final int timeAnimationRevision;
  final bool manipulating;
  final bool conflict;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final GestureDragStartCallback onMoveStart;
  final GestureDragUpdateCallback onMoveUpdate;
  final GestureDragEndCallback onMoveEnd;
  final GestureDragStartCallback onResizeStart;
  final GestureDragUpdateCallback onResizeUpdate;
  final GestureDragEndCallback onResizeEnd;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final completed = task.state == SprintTaskState.completed || block.completed;
    final manual = task.placementMode == SprintPlacementMode.manual;
    final editable = !completed &&
        task.state != SprintTaskState.cancelled &&
        block.status == SprintScheduleBlockStatus.planned;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 180);
    final previewDuration = displayEnd.difference(displayStart).inMinutes;
    final extraHeight =
        (((previewDuration - 30) / 30).clamp(0, 4) * 6).toDouble();
    final cardColor =
        completed ? colors.surfaceContainerLow : colors.surface;
    return AnimatedSize(
      duration: duration,
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOutCubic,
        constraints: BoxConstraints(
          minHeight: (completed ? 58.0 : 86.0) + extraHeight,
        ),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: manipulating
              ? <BoxShadow>[
                  BoxShadow(
                    color: colors.shadow.withOpacity(0.16),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : const <BoxShadow>[],
        ),
        child: Material(
          color: cardColor,
          borderRadius: BorderRadius.circular(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: completed ? null : onTap,
                  onLongPress: completed ? null : onLongPress,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(15, 15, 15, 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: conflict
                            ? colors.error
                            : manipulating
                                ? colors.primary
                                : manual
                                    ? colors.primary
                                    : colors.outlineVariant,
                        width: conflict || manipulating || manual ? 1.8 : 1,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          button: editable && !block.locked,
                          label: block.locked ? '고정된 일정' : '일정 이동 핸들',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onVerticalDragStart:
                                editable && !block.locked ? onMoveStart : null,
                            onVerticalDragUpdate:
                                editable && !block.locked ? onMoveUpdate : null,
                            onVerticalDragEnd:
                                editable && !block.locked ? onMoveEnd : null,
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: colors.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                completed
                                    ? Icons.check_rounded
                                    : manipulating
                                        ? Icons.open_with_rounded
                                        : editable && !block.locked
                                            ? Icons.drag_indicator_rounded
                                            : Icons.circle_outlined,
                                color: completed || manipulating
                                    ? colors.primary
                                    : colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      project?.name ?? '알 수 없는 프로젝트',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            color: colors.primary,
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                  ),
                                  if (manual)
                                    const Icon(
                                      Icons.lock_outline_rounded,
                                      size: 18,
                                      semanticLabel: '수동 고정',
                                    ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                task.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  decoration: completed
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                              const SizedBox(height: 5),
                              AnimatedSwitcher(
                                duration:
                                    manipulating ? Duration.zero : duration,
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                transitionBuilder: (child, animation) {
                                  if (reduceMotion || manipulating) return child;
                                  return FadeTransition(
                                    opacity: animation,
                                    child: SlideTransition(
                                      position: Tween<Offset>(
                                        begin: const Offset(0, 0.12),
                                        end: Offset.zero,
                                      ).animate(animation),
                                      child: child,
                                    ),
                                  );
                                },
                                child: Text(
                                  '${sprintFormatTime(displayStart)}–${sprintFormatTime(displayEnd)} · ${sprintFormatDuration(previewDuration)}${manual ? ' · 수동 고정' : ' · 자동 배치'}',
                                  key: ValueKey<String>(
                                    'time-${block.id}-$timeAnimationRevision',
                                  ),
                                  style: TextStyle(
                                    color: conflict
                                        ? colors.error
                                        : colors.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              AnimatedSwitcher(
                                duration:
                                    manipulating ? Duration.zero : duration,
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                child: conflict
                                    ? Padding(
                                        key: ValueKey<String>(
                                          'conflict-${block.id}-$timeAnimationRevision',
                                        ),
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Text(
                                          '충돌 위치 · 놓으면 해결 방법을 선택합니다.',
                                          style: TextStyle(
                                            color: colors.error,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      )
                                    : manipulating
                                        ? Padding(
                                            key: ValueKey<String>(
                                              'move-${block.id}-$timeAnimationRevision',
                                            ),
                                            padding:
                                                const EdgeInsets.only(top: 6),
                                            child: Text(
                                              '30분 단위로 직접 조정 중',
                                              style: TextStyle(
                                                color: colors.primary,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          )
                                        : SizedBox(
                                            key: ValueKey<String>(
                                              'idle-${block.id}-$timeAnimationRevision',
                                            ),
                                          ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (editable)
                Semantics(
                  button: !block.locked,
                  label: block.locked ? '고정된 일정' : '일정 길이 조절 핸들',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragStart: block.locked ? null : onResizeStart,
                    onVerticalDragUpdate: block.locked ? null : onResizeUpdate,
                    onVerticalDragEnd: block.locked ? null : onResizeEnd,
                    child: SizedBox(
                      height: 44,
                      child: Center(
                        child: AnimatedContainer(
                          duration: duration,
                          width: manipulating ? 54 : 42,
                          height: 5,
                          decoration: BoxDecoration(
                            color: block.locked
                                ? colors.outlineVariant
                                : conflict
                                    ? colors.error
                                    : colors.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExternalEventCard extends StatelessWidget {
  const _ExternalEventCard({required this.event});

  final SprintExternalEvent event;

  void _openDetails(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      barrierColor: Theme.of(context).colorScheme.scrim,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.event_outlined),
                  const SizedBox(width: 8),
                  Text(
                    '외부 일정',
                    style: Theme.of(sheetContext)
                        .textTheme
                        .labelLarge
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                event.title,
                style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 8),
              Text(sprintFormatDate(event.start)),
              const SizedBox(height: 4),
              Text(
                event.allDay
                    ? '종일 일정'
                    : '${sprintFormatTime(event.start)}–${sprintFormatTime(event.end)}',
              ),
              const SizedBox(height: 14),
              Text(
                event.blocksTime
                    ? 'Google 캘린더 · 읽기 전용 · 자동 배치 시간을 차단함'
                    : 'Google 캘린더 · 읽기 전용 · 자동 배치 시간을 차단하지 않음',
              ),
              const SizedBox(height: 20),
              FilledButton.tonal(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: const Text('닫기'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _openDetails(context),
        child: Container(
          constraints: const BoxConstraints(minHeight: 84),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.event_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '외부 일정',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        Icon(
                          Icons.link_rounded,
                          size: 18,
                          color: colors.onSurfaceVariant,
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      event.allDay
                          ? '종일 · 읽기 전용'
                          : '${sprintFormatTime(event.start)}–${sprintFormatTime(event.end)} · 읽기 전용',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScheduleEmptyState extends StatelessWidget {
  const _ScheduleEmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 34, 24, 24),
      child: Column(
        children: [
          Icon(
            Icons.event_available_outlined,
            size: 52,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            '이 날짜에 배치된 프로젝트 업무가 없습니다.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 7),
          Text(
            '위의 업무 추가 버튼에서 프로젝트와 시간을 지정할 수 있습니다.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SprintBottomDock extends StatelessWidget {
  const _SprintBottomDock({
    required this.store,
    required this.controller,
    required this.focusNode,
    required this.attentionCount,
    required this.onProjectTap,
    required this.onProjectSwitchTap,
    required this.onAddTask,
    required this.onAttentionTap,
    required this.onSubmit,
  });

  final SprintModeStore store;
  final TextEditingController controller;
  final FocusNode focusNode;
  final int attentionCount;
  final VoidCallback onProjectTap;
  final VoidCallback onProjectSwitchTap;
  final VoidCallback onAddTask;
  final VoidCallback onAttentionTap;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 180);

    return Material(
      color: colors.surfaceContainer,
      elevation: 10,
      child: SafeArea(
        top: false,
        maintainBottomViewPadding: true,
        minimum: const EdgeInsets.only(bottom: 8),
        child: AnimatedPadding(
          duration: duration,
          padding: EdgeInsets.only(
            left: 10,
            top: 8,
            right: 10,
            bottom: keyboardVisible ? 4 : 8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSize(
                duration: duration,
                curve: Curves.easeOutCubic,
                child: keyboardVisible
                    ? const SizedBox.shrink()
                    : Row(
                        children: [
                          Expanded(
                            child: _ProjectContextControl(
                              icon: store.scopeIcon,
                              label: store.scopeLabel,
                              onSummaryTap: onProjectTap,
                              onSwitchTap: onProjectSwitchTap,
                            ),
                          ),
                          const SizedBox(width: 6),
                          _AttentionContextButton(
                            count: attentionCount,
                            onTap: onAttentionTap,
                          ),
                        ],
                      ),
              ),
              if (!keyboardVisible) const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '업무 입력',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 6),
              Material(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(22),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: '상세 업무 추가',
                        onPressed: onAddTask,
                        icon: const Icon(Icons.add_task_rounded),
                      ),
                      Expanded(
                        child: TextField(
                          controller: controller,
                          focusNode: focusNode,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => onSubmit(),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            filled: true,
                            fillColor: colors.surfaceContainerHighest,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                      IconButton.filled(
                        tooltip: '업무 추가',
                        onPressed: onSubmit,
                        icon: const Icon(Icons.arrow_upward_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectContextControl extends StatelessWidget {
  const _ProjectContextControl({
    required this.icon,
    required this.label,
    required this.onSummaryTap,
    required this.onSwitchTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onSummaryTap;
  final VoidCallback onSwitchTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onSummaryTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
                child: Row(
                  children: [
                    Icon(icon, size: 19),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            width: 1,
            height: 28,
            color: colors.outlineVariant,
          ),
          SizedBox(
            width: 44,
            height: 44,
            child: InkWell(
              onTap: onSwitchTap,
              child: const Icon(Icons.keyboard_arrow_down_rounded),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttentionContextButton extends StatelessWidget {
  const _AttentionContextButton({
    required this.count,
    required this.onTap,
  });

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded, size: 19),
              const SizedBox(width: 5),
              Text(
                '$count',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskQuickActionSheet extends StatelessWidget {
  const _TaskQuickActionSheet({
    required this.store,
    required this.task,
    required this.onComplete,
    required this.onManageTask,
    required this.onManageBlock,
  });

  final SprintModeStore store;
  final SprintTask task;
  final VoidCallback onComplete;
  final VoidCallback onManageTask;
  final VoidCallback onManageBlock;

  @override
  Widget build(BuildContext context) {
    final manual = task.placementMode == SprintPlacementMode.manual;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            task.title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 4),
          Text(store.projectName(task.projectId)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onComplete,
            icon: const Icon(Icons.check_rounded),
            label: const Text('완료'),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.edit_outlined),
            title: const Text('업무 관리'),
            onTap: onManageTask,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_note_rounded),
            title: const Text('일정 블록 관리'),
            onTap: onManageBlock,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              manual
                  ? Icons.lock_open_rounded
                  : Icons.lock_outline_rounded,
            ),
            title: Text(manual ? '자동 이동 다시 허용' : '시간 고정'),
            onTap: () {
              store.setTaskManual(task.id, !manual);
              sprintShowMessage(
                context: context,
                message: manual ? '자동 이동을 다시 허용했습니다.' : '업무 시간을 고정했습니다.',
              );
              Navigator.of(context).pop();
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule_rounded),
            title: const Text('내일로 연기'),
            onTap: () {
              store.postponeTask(task.id, SprintPostponeType.tomorrow);
              sprintShowMessage(
                context: context,
                message: '업무를 내일로 연기했습니다.',
              );
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}

class _PostponeTile extends StatelessWidget {
  const _PostponeTile({
    required this.title,
    required this.subtitle,
    required this.value,
  });

  final String title;
  final String subtitle;
  final SprintPostponeType value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => Navigator.of(context).pop(value),
    );
  }
}

class _UnplacedTasksSheet extends StatelessWidget {
  const _UnplacedTasksSheet({required this.store});

  final SprintModeStore store;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, child) {
        final tasks = store.unplacedTasks();
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          minChildSize: 0.42,
          maxChildSize: 0.94,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '미배치 업무 ${tasks.length}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: tasks.isEmpty
                        ? const Center(
                            child: Text('미배치 업무가 없습니다.'),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            itemCount: tasks.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final task = tasks[index];
                              return SprintSurface(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      task.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      '예상 ${sprintFormatDuration(task.estimatedMinutes)}',
                                    ),
                                    const SizedBox(height: 12),
                                    FilledButton.tonal(
                                      onPressed: () async {
                                        await store.placeUnplacedTask(task);
                                        if (!context.mounted) return;
                                        sprintShowMessage(
                                          context: context,
                                          message: '빈 시간에 업무를 배치했습니다.',
                                        );
                                      },
                                      child: const Text('빈 시간에 배치'),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _AttentionSheet extends StatelessWidget {
  const _AttentionSheet({required this.store});

  final SprintModeStore store;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, child) {
        final items = store.currentScopeAttentionItems;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.42,
          maxChildSize: 0.94,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '확인 필요 ${items.length}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: items.isEmpty
                        ? const Center(
                            child: Text('확인이 필요한 항목이 없습니다.'),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            itemCount: items.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final item = items[index];
                              return SprintSurface(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.warning_amber_rounded,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            item.title,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(item.description),
                                    const SizedBox(height: 12),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        if (item.blockId != null)
                                          FilledButton.tonal(
                                            onPressed: () async {
                                              await showSprintConflictResolutionSheet(
                                                context: context,
                                                store: store,
                                                item: item,
                                              );
                                            },
                                            child: const Text('해결 방법 선택'),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _SprintReviewSettingsPage extends StatelessWidget {
  const _SprintReviewSettingsPage({required this.store});

  final SprintModeStore store;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, child) {
        final project = store.selectedProject;
        final summary = project == null ? null : store.summaryFor(project.id);
        final planned = store.blocks.fold<int>(
          0,
          (sum, block) => sum + block.durationMinutes,
        );
        final actual = store.tasks.fold<int>(
          0,
          (sum, task) => sum + task.actualMinutes,
        );

        return Scaffold(
          appBar: AppBar(title: const Text('리뷰 및 설정')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
            children: [
              const SprintSectionHeader(title: '이번 주'),
              const SizedBox(height: 10),
              SprintSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ReviewBar(
                      label: '계획',
                      minutes: planned,
                      maximum: math.max(planned, actual).toInt(),
                    ),
                    const SizedBox(height: 14),
                    _ReviewBar(
                      label: '실제',
                      minutes: actual,
                      maximum: math.max(planned, actual).toInt(),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '평균 예상시간 오차 ${sprintFormatDuration((planned - actual).abs())}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              if (summary != null) ...[
                const SizedBox(height: 22),
                const SprintSectionHeader(title: '현재 프로젝트'),
                const SizedBox(height: 10),
                SprintSurface(
                  child: Row(
                    children: [
                      CircleAvatar(child: Icon(summary.project.icon)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              summary.project.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '진행 ${(summary.progressRatio * 100).round()}% · 남은 ${sprintFormatDuration(summary.remainingMinutes)}',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 22),
              const SprintSectionHeader(title: '연결 및 설정'),
              const SizedBox(height: 10),
              SprintSurface(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _GoogleCalendarSettingTile(store: store),
                    const Divider(height: 1),
                    const ListTile(
                      leading: Icon(Icons.schedule_outlined),
                      title: Text('업무 가능 시간'),
                      subtitle: Text('평일 09:00–18:00 · 점심 12:00–13:00'),
                      trailing: Icon(Icons.chevron_right_rounded),
                    ),
                    const Divider(height: 1),
                    const ListTile(
                      leading: Icon(Icons.notifications_outlined),
                      title: Text('알림 설정'),
                      subtitle: Text('판단이 필요한 항목만 표시'),
                      trailing: Icon(Icons.chevron_right_rounded),
                    ),
                    const Divider(height: 1),
                    const ListTile(
                      leading: Icon(Icons.accessibility_new_rounded),
                      title: Text('화면 및 접근성'),
                      subtitle: Text('시스템 글자 크기와 애니메이션 설정 사용'),
                      trailing: Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              const SprintSectionHeader(title: '이번 주 인사이트'),
              const SizedBox(height: 10),
              const SprintSurface(
                child: Text(
                  '오후 4시 이후 업무가 다음 날로 이동되는 빈도가 높습니다. 이 시간대의 자동 배치량을 줄이는 것이 적합합니다.',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ReviewBar extends StatelessWidget {
  const _ReviewBar({
    required this.label,
    required this.minutes,
    required this.maximum,
  });

  final String label;
  final int minutes;
  final int maximum;

  @override
  Widget build(BuildContext context) {
    final ratio = maximum <= 0 ? 0.0 : minutes / maximum;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Text(sprintFormatDuration(minutes)),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: ratio.clamp(0, 1).toDouble(),
            minHeight: 10,
          ),
        ),
      ],
    );
  }
}

class _GoogleCalendarSettingTile extends StatelessWidget {
  const _GoogleCalendarSettingTile({required this.store});

  final SprintModeStore store;

  @override
  Widget build(BuildContext context) {
    final state = store.calendarState;
    String status;
    switch (state) {
      case SprintCalendarConnectionState.notConnected:
        status = '연결 안 됨';
        break;
      case SprintCalendarConnectionState.syncing:
        status = '동기화 중';
        break;
      case SprintCalendarConnectionState.connected:
        status = '연결됨';
        break;
      case SprintCalendarConnectionState.failed:
        status = '동기화 실패';
        break;
    }

    return ListTile(
      leading: Icon(
        store.googleCalendarIdLocked
            ? Icons.lock_rounded
            : Icons.event_available_outlined,
      ),
      title: const Text('Google 캘린더 계정'),
      subtitle: Text('${store.googleCalendarId} · $status'),
      trailing: state == SprintCalendarConnectionState.syncing
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          : const Icon(Icons.chevron_right_rounded),
      onTap: state == SprintCalendarConnectionState.syncing
          ? null
          : () => showSprintAccountSheet(
                context: context,
                store: store,
              ),
    );
  }
}
