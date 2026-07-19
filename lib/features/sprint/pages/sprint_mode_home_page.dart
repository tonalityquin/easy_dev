import 'dart:async';
import 'package:flutter/material.dart';

import '../../../shared/google_calendar/google_event_colors.dart';
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
  await sprintShowBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
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
    if (state == AppLifecycleState.resumed) {
      _store.handleAppResumed();
      return;
    }
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
    final validationMessage = _selectedDateAddError();
    if (validationMessage != null) {
      sprintShowMessage(context: context, message: validationMessage);
      return;
    }
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
      message:
          '${task.title} 업무를 ${sprintFormatDate(task.startDate)}에 추가했습니다.',
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
    return sprintPageRoute<void>(
      context: context,
      page: SprintProjectHomePage(
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
      pageBuilder: (_, __, ___) => SprintPromptScope(child: page),
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
      sprintPageRoute<void>(
        context: context,
        page: _SprintReviewSettingsPage(store: _store),
      ),
    );
  }

  void _openUnplaced() {
    sprintShowBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _UnplacedTasksSheet(store: _store),
    );
  }

  void _openAttention() {
    showSprintAttentionSheet(context: context, store: _store);
  }

  String? _selectedDateAddError() {
    if (_store.projects.isEmpty) {
      return '업무를 추가하려면 먼저 프로젝트를 생성하세요.';
    }
    return null;
  }

  Future<void> _openTaskCreate() {
    return _openTaskCreateForDate(_store.selectedDate);
  }

  Future<void> _openTaskCreateForDate(DateTime date) async {
    final selected = DateTime(date.year, date.month, date.day);
    _store.selectDate(selected);
    final validationMessage = _selectedDateAddError();
    if (validationMessage != null) {
      sprintShowMessage(context: context, message: validationMessage);
      return;
    }
    await showSprintTaskCreateSheet(
      context: context,
      store: _store,
      initialDate: selected,
      initialProjectId: _store.selectedProjectId,
    );
  }

  Future<void> _openDateJumpSheet() async {
    final selected = await sprintShowBottomSheet<DateTime>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _DateJumpSheet(
        selectedDate: _store.selectedDate,
        project: _store.selectedProject,
      ),
    );
    if (selected != null) {
      _store.selectDate(selected);
    }
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
          return SprintScaffold(
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
          return const SprintScaffold(
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

            return SprintScaffold(
          extendBody: false,
          extendBodyBehindAppBar: false,
          appBar: AppBar(
            leading: IconButton(
              tooltip: '프로젝트 메뉴',
              onPressed: _openWorkspacePanel,
              icon: const Icon(Icons.menu_rounded),
            ),
            title: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _openDateJumpSheet,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedSwitcher(
                      duration: (MediaQuery.maybeOf(context)?.disableAnimations ??
                              false)
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      child: Text(
                        sprintFormatDate(_store.selectedDate),
                        key: ValueKey<int>(
                          _store.selectedDate.millisecondsSinceEpoch,
                        ),
                      ),
                    ),
                    Text(
                      _store.scopeLabel,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
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
                        label: Text('일간'),
                        icon: Icon(Icons.view_day_outlined),
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
                _DateNavigationBar(
                  store: _store,
                  onTitleTap: _openDateJumpSheet,
                ),
                if (_store.weekMode)
                  _WeekDensityPager(
                    store: _store,
                    onDateLongPress: _openTaskCreateForDate,
                  ),
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
            onPreviousProject: _store.selectPreviousScope,
            onNextProject: _store.selectNextScope,
            onDateTap: _openDateJumpSheet,
            onTodayTap: _store.selectToday,
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

class _DateJumpSheet extends StatelessWidget {
  const _DateJumpSheet({
    required this.selectedDate,
    required this.project,
  });

  final DateTime selectedDate;
  final SprintProject? project;

  Future<void> _pickDate(BuildContext context) async {
    final selected = await sprintShowDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(1970),
      lastDate: DateTime(2200),
      cancelText: '취소',
      confirmText: '이동',
    );
    if (selected != null && context.mounted) {
      Navigator.of(context).pop(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final start = project?.targetStartDate;
    final end = project?.targetDate;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '날짜로 이동',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 10),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.today_rounded),
            title: const Text(
              '오늘',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(sprintFormatDate(DateTime.now())),
            onTap: () => Navigator.of(context).pop(DateTime.now()),
          ),
          if (start != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.flag_outlined),
              title: const Text(
                '프로젝트 목표 시작일',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(sprintFormatDate(start)),
              onTap: () => Navigator.of(context).pop(start),
            ),
          if (end != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.outlined_flag_rounded),
              title: const Text(
                '프로젝트 목표 완료일',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(sprintFormatDate(end)),
              onTap: () => Navigator.of(context).pop(end),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_month_rounded),
            title: const Text(
              '날짜 선택',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text('현재 선택 · ${sprintFormatDate(selectedDate)}'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _pickDate(context),
          ),
        ],
      ),
    );
  }
}

class _DateNavigationBar extends StatelessWidget {
  const _DateNavigationBar({
    required this.store,
    required this.onTitleTap,
  });

  final SprintModeStore store;
  final VoidCallback onTitleTap;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 220);
    final title = store.weekMode
        ? sprintFormatDateRange(
            store.weekStart(store.selectedDate),
            store.weekEnd(store.selectedDate),
          )
        : sprintFormatDate(store.selectedDate);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Row(
        children: [
          IconButton(
            tooltip: store.weekMode ? '이전 주' : '이전 날짜',
            onPressed: store.weekMode
                ? store.selectPreviousWeek
                : store.selectPreviousDay,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Material(
              color: sprintTransparent(context),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onTitleTap,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                  child: AnimatedSwitcher(
                    duration: duration,
                    transitionBuilder: (child, animation) {
                      if (reduceMotion) return child;
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0.04, 0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: Row(
                      key: ValueKey<String>(
                        '${store.weekMode}-$title',
                      ),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w900,
                                    ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: store.weekMode ? '다음 주' : '다음 날짜',
            onPressed:
                store.weekMode ? store.selectNextWeek : store.selectNextDay,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          AnimatedSize(
            duration: duration,
            curve: Curves.easeOutCubic,
            child: store.isTodaySelected
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: FilledButton.tonalIcon(
                      onPressed: store.selectToday,
                      icon: const Icon(Icons.today_rounded, size: 18),
                      label: const Text('오늘'),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _WeekDensityPager extends StatefulWidget {
  const _WeekDensityPager({
    required this.store,
    required this.onDateLongPress,
  });

  final SprintModeStore store;
  final ValueChanged<DateTime> onDateLongPress;

  @override
  State<_WeekDensityPager> createState() => _WeekDensityPagerState();
}

class _WeekDensityPagerState extends State<_WeekDensityPager> {
  static const int _centerPage = 10000;
  late final PageController _controller;
  late final DateTime _anchorWeekStart;
  int _currentPage = _centerPage;
  bool _programmaticMove = false;
  int _moveGeneration = 0;

  @override
  void initState() {
    super.initState();
    _anchorWeekStart = widget.store.weekStart(widget.store.selectedDate);
    _controller = PageController(initialPage: _centerPage);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int _pageFor(DateTime date) {
    final target = widget.store.weekStart(date);
    return _centerPage + target.difference(_anchorWeekStart).inDays ~/ 7;
  }

  DateTime _weekStartForPage(int page) {
    return _anchorWeekStart.add(
      Duration(days: (page - _centerPage) * 7),
    );
  }

  void _syncController(BuildContext context) {
    final targetPage = _pageFor(widget.store.selectedDate);
    if (targetPage == _currentPage || !_controller.hasClients) return;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final generation = ++_moveGeneration;
    _programmaticMove = true;
    if (reduceMotion || (targetPage - _currentPage).abs() > 4) {
      _controller.jumpToPage(targetPage);
      _currentPage = targetPage;
      if (generation == _moveGeneration) {
        _programmaticMove = false;
      }
      return;
    }
    _controller
        .animateToPage(
          targetPage,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() {
      if (generation != _moveGeneration) return;
      _currentPage = targetPage;
      _programmaticMove = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncController(context);
    });
    return SizedBox(
      height: 102,
      child: PageView.builder(
        controller: _controller,
        onPageChanged: (page) {
          _currentPage = page;
          if (_programmaticMove) return;
          final selectedWeekday = widget.store.selectedDate.weekday;
          final nextDate = _weekStartForPage(page).add(
            Duration(days: selectedWeekday - 1),
          );
          widget.store.selectDate(nextDate);
        },
        itemBuilder: (context, page) {
          final weekStart = _weekStartForPage(page);
          final dates = List<DateTime>.generate(
            7,
            (index) => weekStart.add(Duration(days: index)),
            growable: false,
          );
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
            child: Row(
              children: [
                for (var index = 0; index < dates.length; index++) ...[
                  Expanded(
                    child: _WeekDayCard(
                      store: widget.store,
                      date: dates[index],
                      onLongPress: () =>
                          widget.onDateLongPress(dates[index]),
                    ),
                  ),
                  if (index < dates.length - 1) const SizedBox(width: 5),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _WeekDayCard extends StatelessWidget {
  const _WeekDayCard({
    required this.store,
    required this.date,
    required this.onLongPress,
  });

  final SprintModeStore store;
  final DateTime date;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selected = sprintSameDay(date, store.selectedDate);
    final today = sprintSameDay(date, DateTime.now());
    final load = store.dayLoadFor(date);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 220);
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${sprintFormatDate(date)}, 업무 ${load.taskCount}개, 높은 우선순위 ${load.highPriorityCount}개',
      child: Material(
        color: selected
            ? colors.primaryContainer
            : colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () => store.selectDate(date),
          onLongPress: onLongPress,
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: load.overloaded
                    ? colors.error
                    : today
                        ? colors.primary
                        : colors.outlineVariant,
                width: load.overloaded || today ? 1.5 : 1,
              ),
            ),
            child: Column(
              children: [
                Text(
                  sprintWeekday(date.weekday),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                AnimatedSwitcher(
                  duration: duration,
                  child: Text(
                    '${date.day}',
                    key: ValueKey<int>(date.millisecondsSinceEpoch),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                const Spacer(),
                SizedBox(
                  height: 24,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      AnimatedContainer(
                        duration: duration,
                        curve: Curves.easeOutCubic,
                        width: 8,
                        height: 4 + load.ratio * 20,
                        decoration: BoxDecoration(
                          color: load.overloaded
                              ? colors.error
                              : colors.primary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      if (load.highPriorityCount > 0) ...[
                        const SizedBox(width: 1),
                        Icon(
                          Icons.keyboard_double_arrow_up_rounded,
                          size: 12,
                          color: colors.error,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
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
        if (store.activeCalendarProfile != null &&
            store.calendarState != SprintCalendarConnectionState.switching &&
            store.calendarState != SprintCalendarConnectionState.syncing) {
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
            return _ScheduleEmptyState(
              store: store,
              onAddTask: onAddTask,
            );
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
    final hasProjects = store.projects.isNotEmpty;
    final enabled = hasProjects;
    final label = hasProjects
        ? '${sprintFormatDate(store.selectedDate)}에 업무 추가'
        : '프로젝트를 만든 뒤 업무를 추가하세요';
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
        color: sprintTransparent(context),
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
      case SprintCalendarConnectionState.cached:
        calendarLabel = '저장된 캘린더';
        break;
      case SprintCalendarConnectionState.reauthenticationRequired:
        calendarLabel = 'Google 계정 재인증 필요';
        break;
      case SprintCalendarConnectionState.switching:
        calendarLabel = 'Google 계정 전환 중';
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
            today ? '오늘 · 종일 업무' : sprintFormatDate(store.selectedDate),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ),
        Text(
          calendarLabel,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: calendarState == SprintCalendarConnectionState.failed ||
                        calendarState ==
                            SprintCalendarConnectionState
                                .reauthenticationRequired
                    ? colors.error
                    : colors.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}

class _TaskDismissibleCard extends StatelessWidget {
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

  Future<void> _showActions(BuildContext context) async {
    await sprintShowBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _TaskQuickActionSheet(
        store: store,
        task: task,
        onComplete: () {
          Navigator.of(context).pop();
          onCompletion();
        },
        onManageTask: () async {
          Navigator.of(context).pop();
          await showSprintTaskDetailSheet(
            context: context,
            store: store,
            taskId: task.id,
          );
        },
        onManageBlock: () {
          Navigator.of(context).pop();
          onOpenBlock();
        },
      ),
    );
  }

  Future<bool> _confirmDismiss(
    BuildContext context,
    DismissDirection direction,
  ) async {
    if (direction == DismissDirection.startToEnd) {
      onCompletion();
      return false;
    }
    final type = await sprintShowBottomSheet<SprintPostponeType>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PostponeTile(
              title: '내일로 이동',
              subtitle: '현재 기간을 하루 뒤로 이동합니다.',
              value: SprintPostponeType.tomorrow,
            ),
            _PostponeTile(
              title: '다음 주로 이동',
              subtitle: '현재 기간을 7일 뒤로 이동합니다.',
              value: SprintPostponeType.nextWeek,
            ),
          ],
        ),
      ),
    );
    if (type != null) store.postponeTask(task.id, type);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 220);
    final completed = task.state == SprintTaskState.completed;
    final today = DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);
    final overdue = !completed && task.endDate.isBefore(todayDay);
    final projectLabel = project?.name ?? '프로젝트 없음';
    final projectColor = googleEventColor(
      project?.googleColorId,
      colors.primary,
    );

    return Dismissible(
      key: ValueKey<String>('task-${task.id}'),
      direction: completed
          ? DismissDirection.none
          : DismissDirection.horizontal,
      confirmDismiss: (direction) => _confirmDismiss(context, direction),
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: colors.primaryContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(Icons.check_rounded),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: colors.tertiaryContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(Icons.arrow_forward_rounded),
      ),
      child: Material(
        color: completed
            ? colors.surfaceContainerLow
            : colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onOpenBlock,
          onLongPress: () => _showActions(context),
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minHeight: 104),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: overdue ? colors.error : colors.outlineVariant,
                width: overdue ? 1.5 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  width: 5,
                  height: 74,
                  decoration: BoxDecoration(
                    color: projectColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 10),
                AnimatedContainer(
                  duration: duration,
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: task.priority == SprintTaskPriority.high
                        ? colors.errorContainer
                        : colors.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    completed
                        ? Icons.check_rounded
                        : sprintPriorityIcon(task.priority),
                    color: task.priority == SprintTaskPriority.high
                        ? colors.onErrorContainer
                        : colors.onPrimaryContainer,
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
                              projectLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(
                                    color: projectColor,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                          ),
                          AnimatedSwitcher(
                            duration: duration,
                            child: Text(
                              sprintPriorityLabel(task.priority),
                              key: ValueKey<SprintTaskPriority>(task.priority),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    color: overdue
                                        ? colors.error
                                        : colors.onSurfaceVariant,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        task.title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                              decoration: completed
                                  ? TextDecoration.lineThrough
                                  : null,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      AnimatedSize(
                        duration: duration,
                        curve: Curves.easeOutCubic,
                        child: task.description.trim().isEmpty
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.only(top: 5),
                                child: Text(
                                  task.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colors.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '종일 · ${sprintFormatDateRange(task.startDate, task.endDate)}',
                              style: TextStyle(
                                color: overdue
                                    ? colors.error
                                    : colors.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (block.locked)
                            Icon(
                              Icons.lock_rounded,
                              size: 17,
                              color: colors.onSurfaceVariant,
                            ),
                          if (block.locked &&
                              task.googleSyncState !=
                                  SprintGoogleSyncState.none)
                            const SizedBox(width: 6),
                          AnimatedSwitcher(
                            duration: duration,
                            child: task.googleSyncState ==
                                    SprintGoogleSyncState.failed
                                ? Icon(
                                    Icons.cloud_off_rounded,
                                    key: const ValueKey<String>('sync-failed'),
                                    size: 17,
                                    color: colors.error,
                                  )
                                : task.hasPendingGoogleSync
                                    ? SizedBox(
                                        key: const ValueKey<String>(
                                          'sync-pending',
                                        ),
                                        width: 15,
                                        height: 15,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: projectColor,
                                        ),
                                      )
                                    : const SizedBox.shrink(
                                        key: ValueKey<String>('sync-idle'),
                                      ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
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
    sprintShowBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
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
                    ? 'Google 캘린더 · 시간 점유 · 읽기 전용'
                    : 'Google 캘린더 · 시간 비점유 · 읽기 전용',
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
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 220);
    final eventColor = googleEventColor(event.colorId, colors.outline);
    return Material(
      color: eventColor.withOpacity(0.08),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _openDetails(context),
        child: AnimatedContainer(
          duration: duration,
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minHeight: 84),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: eventColor.withOpacity(0.7)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: eventColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.event_outlined,
                  color: eventColor,
                ),
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
  const _ScheduleEmptyState({
    required this.store,
    required this.onAddTask,
  });

  final SprintModeStore store;
  final VoidCallback onAddTask;

  @override
  Widget build(BuildContext context) {
    final previous = store.previousScheduledDate(store.selectedDate);
    final next = store.nextScheduledDate(store.selectedDate);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 220);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity > 260) {
          store.selectPreviousDay();
        } else if (velocity < -260) {
          store.selectNextDay();
        }
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 34, 24, 24),
        child: Column(
          children: [
            AnimatedContainer(
              duration: duration,
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.event_available_outlined,
                size: 42,
                color: Theme.of(context).colorScheme.outline,
              ),
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
              '좌우로 넘겨 날짜를 이동하거나 가까운 일정으로 바로 이동할 수 있습니다.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (previous != null)
                  OutlinedButton.icon(
                    onPressed: () => store.selectDate(previous),
                    icon: const Icon(Icons.chevron_left_rounded),
                    label: const Text('이전 일정'),
                  ),
                if (next != null)
                  OutlinedButton.icon(
                    onPressed: () => store.selectDate(next),
                    icon: const Icon(Icons.chevron_right_rounded),
                    label: const Text('다음 일정'),
                  ),
                FilledButton.tonalIcon(
                  onPressed: onAddTask,
                  icon: const Icon(Icons.add_task_rounded),
                  label: const Text('이 날짜에 추가'),
                ),
              ],
            ),
          ],
        ),
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
    required this.onPreviousProject,
    required this.onNextProject,
    required this.onDateTap,
    required this.onTodayTap,
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
  final VoidCallback onPreviousProject;
  final VoidCallback onNextProject;
  final VoidCallback onDateTap;
  final VoidCallback onTodayTap;
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
    final inputEnabled = store.projects.isNotEmpty;

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
                              onPrevious: onPreviousProject,
                              onNext: onNextProject,
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
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: onDateTap,
                      icon: const Icon(Icons.event_available_rounded, size: 18),
                      label: AnimatedSwitcher(
                        duration: duration,
                        child: Text(
                          '${sprintFormatDate(store.selectedDate)}에 업무 입력',
                          key: ValueKey<int>(
                            store.selectedDate.millisecondsSinceEpoch,
                          ),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ),
                  AnimatedSize(
                    duration: duration,
                    child: store.isTodaySelected
                        ? const SizedBox.shrink()
                        : TextButton(
                            onPressed: onTodayTap,
                            child: const Text('오늘로 이동'),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: duration,
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: inputEnabled
                      ? colors.surfaceContainerHighest
                      : colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: inputEnabled
                        ? colors.outlineVariant
                        : colors.error.withAlpha(115),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: '상세 업무 추가',
                        onPressed: inputEnabled ? onAddTask : null,
                        icon: const Icon(Icons.add_task_rounded),
                      ),
                      Expanded(
                        child: TextField(
                          controller: controller,
                          focusNode: focusNode,
                          enabled: inputEnabled,
                          textInputAction: TextInputAction.send,
                          onSubmitted: inputEnabled ? (_) => onSubmit() : null,
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            filled: true,
                            fillColor: inputEnabled
                                ? colors.surfaceContainerHighest
                                : colors.surfaceContainerLow,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                      IconButton.filled(
                        tooltip: '업무 추가',
                        onPressed: inputEnabled ? onSubmit : null,
                        icon: const Icon(Icons.arrow_upward_rounded),
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedSize(
                duration: duration,
                curve: Curves.easeOutCubic,
                child: inputEnabled
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '프로젝트를 만든 뒤 업무를 추가할 수 있습니다.',
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(
                                color: colors.error,
                                fontWeight: FontWeight.w800,
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

class _ProjectContextControl extends StatelessWidget {
  const _ProjectContextControl({
    required this.icon,
    required this.label,
    required this.onSummaryTap,
    required this.onSwitchTap,
    required this.onPrevious,
    required this.onNext,
  });

  final IconData icon;
  final String label;
  final VoidCallback onSummaryTap;
  final VoidCallback onSwitchTap;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 180);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity > 260) {
          onPrevious();
        } else if (velocity < -260) {
          onNext();
        }
      },
      child: Material(
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
                      AnimatedSwitcher(
                        duration: duration,
                        child: Icon(
                          icon,
                          key: ValueKey<IconData>(icon),
                          size: 19,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: duration,
                          transitionBuilder: (child, animation) {
                            if (reduceMotion) return child;
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0.04, 0),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: Text(
                            label,
                            key: ValueKey<String>(label),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontWeight: FontWeight.w800),
                          ),
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
          Text(
            '${sprintPriorityLabel(task.priority)} · 종일 · ${sprintFormatDateRange(task.startDate, task.endDate)}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.check_circle_outline_rounded),
            title: const Text(
              '완료',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            onTap: onComplete,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.arrow_forward_rounded),
            title: const Text(
              '내일로 이동',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            onTap: () {
              store.postponeTask(task.id, SprintPostponeType.tomorrow);
              Navigator.of(context).pop();
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.date_range_rounded),
            title: const Text(
              '다음 주로 이동',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            onTap: () {
              store.postponeTask(task.id, SprintPostponeType.nextWeek);
              Navigator.of(context).pop();
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.edit_note_rounded),
            title: const Text(
              '업무 관리',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            onTap: onManageTask,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.edit_calendar_rounded),
            title: const Text(
              '기간 관리',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            onTap: onManageBlock,
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
                        ? const Center(child: Text('미배치 업무가 없습니다.'))
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
                                    Row(
                                      children: [
                                        Icon(sprintPriorityIcon(task.priority)),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            task.title,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          sprintPriorityLabel(task.priority),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '종일 · ${sprintFormatDateRange(task.startDate, task.endDate)}',
                                    ),
                                    const SizedBox(height: 12),
                                    FilledButton.tonal(
                                      onPressed: () async {
                                        await store.placeUnplacedTask(task);
                                        if (!context.mounted) return;
                                        sprintShowMessage(
                                          context: context,
                                          message:
                                              '${sprintFormatDate(store.selectedDate)}에 업무를 배치했습니다.',
                                        );
                                      },
                                      child: const Text('선택 날짜에 배치'),
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
                                        if (item.blockId != null &&
                                            (item.conflictType ==
                                                    SprintConflictType
                                                        .beforeProjectStart ||
                                                item.conflictType ==
                                                    SprintConflictType
                                                        .afterProjectTargetDate))
                                          FilledButton.tonal(
                                            onPressed: () async {
                                              await showSprintConflictResolutionSheet(
                                                context: context,
                                                store: store,
                                                item: item,
                                              );
                                            },
                                            child: const Text('해결 방법 선택'),
                                          )
                                        else if (item.taskId != null)
                                          FilledButton.tonal(
                                            onPressed: () async {
                                              await showSprintTaskDetailSheet(
                                                context: context,
                                                store: store,
                                                taskId: item.taskId!,
                                              );
                                            },
                                            child: const Text('업무 관리'),
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
        final activeTasks = store.tasks.where((task) {
          return task.state != SprintTaskState.cancelled;
        }).toList(growable: false);
        final completed = activeTasks
            .where((task) => task.state == SprintTaskState.completed)
            .length;
        final highRemaining = activeTasks.where((task) {
          return task.priority == SprintTaskPriority.high &&
              task.state != SprintTaskState.completed;
        }).length;
        final overdue = activeTasks.where((task) {
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          return task.state != SprintTaskState.completed &&
              task.endDate.isBefore(today);
        }).length;

        return SprintScaffold(
          appBar: AppBar(title: const Text('리뷰 및 설정')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
            children: [
              const SprintSectionHeader(title: '업무 현황'),
              const SizedBox(height: 10),
              SprintSurface(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _ReviewCount(
                      label: '전체',
                      value: activeTasks.length,
                      icon: Icons.view_list_rounded,
                    ),
                    _ReviewCount(
                      label: '완료',
                      value: completed,
                      icon: Icons.check_circle_outline_rounded,
                    ),
                    _ReviewCount(
                      label: '높음 남음',
                      value: highRemaining,
                      icon: Icons.keyboard_double_arrow_up_rounded,
                    ),
                    _ReviewCount(
                      label: '기한 초과',
                      value: overdue,
                      icon: Icons.warning_amber_rounded,
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
                              '진행 ${(summary.progressRatio * 100).round()}% · 완료 ${summary.completedTaskCount}/${summary.totalTaskCount}',
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '남은 높은 우선순위 ${summary.highPriorityRemainingCount}개',
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
                      leading: Icon(Icons.today_outlined),
                      title: Text('업무 일정 형식'),
                      subtitle: Text('모든 내부 업무는 종일 날짜 범위로 관리'),
                    ),
                    const Divider(height: 1),
                    const ListTile(
                      leading: Icon(Icons.notifications_outlined),
                      title: Text('알림 설정'),
                      subtitle: Text('기한과 확인 필요 항목 중심'),
                    ),
                    const Divider(height: 1),
                    const ListTile(
                      leading: Icon(Icons.accessibility_new_rounded),
                      title: Text('화면 및 접근성'),
                      subtitle: Text('시스템 글자 크기와 애니메이션 설정 사용'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              const SprintSectionHeader(title: '이번 주 인사이트'),
              const SizedBox(height: 10),
              SprintSurface(
                child: Text(
                  highRemaining > 0
                      ? '높은 우선순위 업무 $highRemaining개가 남아 있습니다. 종료일이 가까운 업무부터 확인하세요.'
                      : '높은 우선순위 업무가 모두 정리됐습니다. 보통 우선순위 업무의 종료일을 확인하세요.',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ReviewCount extends StatelessWidget {
  const _ReviewCount({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 132,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon),
          const SizedBox(height: 10),
          Text(
            '$value',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          Text(
            label,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _GoogleCalendarSettingTile extends StatelessWidget {
  const _GoogleCalendarSettingTile({required this.store});

  final SprintModeStore store;

  @override
  Widget build(BuildContext context) {
    final state = store.calendarState;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 180);
    String status;
    switch (state) {
      case SprintCalendarConnectionState.notConnected:
        status = '연결 안 됨';
        break;
      case SprintCalendarConnectionState.cached:
        status = '저장된 일정 표시 중';
        break;
      case SprintCalendarConnectionState.reauthenticationRequired:
        status = '재인증 필요';
        break;
      case SprintCalendarConnectionState.switching:
        status = '계정 전환 중';
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
    final email = store.activeGoogleEmail;
    final calendar = store.googleCalendarId;
    final detail = email.isEmpty
        ? '$calendar · $status'
        : '$email · $calendar · $status';
    final busy = state == SprintCalendarConnectionState.syncing ||
        state == SprintCalendarConnectionState.switching;

    return ListTile(
      leading: AnimatedSwitcher(
        duration: duration,
        child: Icon(
          store.googleCalendarIdLocked
              ? Icons.lock_rounded
              : Icons.event_available_outlined,
          key: ValueKey<String>(
            '${store.activeCalendarProfileId}-${store.googleCalendarIdLocked}',
          ),
        ),
      ),
      title: Text(store.activeCalendarLabel),
      subtitle: Text(
        detail,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: AnimatedSwitcher(
        duration: duration,
        child: busy
            ? const SizedBox(
                key: ValueKey<String>('calendar-busy'),
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : const Icon(
                Icons.chevron_right_rounded,
                key: ValueKey<String>('calendar-ready'),
              ),
      ),
      onTap: busy
          ? null
          : () => showSprintAccountSheet(
                context: context,
                store: store,
              ),
    );
  }
}
