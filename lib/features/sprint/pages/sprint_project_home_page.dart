import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../application/sprint_mode_store.dart';
import '../domain/sprint_models.dart';
import 'sprint_project_archive_page.dart';
import 'sprint_project_completion_page.dart';
import 'sprint_project_management_page.dart';
import 'sprint_project_workspace_sheet.dart';
import 'sprint_task_create_sheet.dart';
import 'sprint_task_detail_sheet.dart';
import 'sprint_ui.dart';

class SprintProjectHomePage extends StatefulWidget {
  const SprintProjectHomePage({
    super.key,
    required this.store,
    this.initialDestination = SprintWorkspacePanelDestination.summary,
  });

  final SprintModeStore store;
  final SprintWorkspacePanelDestination initialDestination;

  @override
  State<SprintProjectHomePage> createState() => _SprintProjectHomePageState();
}

class _SprintProjectHomePageState extends State<SprintProjectHomePage> {
  final TextEditingController _composerController = TextEditingController();
  final FocusNode _composerFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _pathKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _applyDestination(widget.initialDestination);
    });
  }

  @override
  void dispose() {
    _composerController.dispose();
    _composerFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _applyDestination(SprintWorkspacePanelDestination destination) {
    switch (destination) {
      case SprintWorkspacePanelDestination.schedule:
        return;
      case SprintWorkspacePanelDestination.summary:
        if (_scrollController.hasClients) {
          if (_motionDuration == Duration.zero) {
            _scrollController.jumpTo(0);
          } else {
            _scrollController.animateTo(
              0,
              duration: _motionDuration,
              curve: Curves.easeOutCubic,
            );
          }
        }
        return;
      case SprintWorkspacePanelDestination.path:
        final targetContext = _pathKey.currentContext;
        if (targetContext != null) {
          Scrollable.ensureVisible(
            targetContext,
            duration: _motionDuration,
            curve: Curves.easeOutCubic,
            alignment: 0.08,
          );
        }
        return;
      case SprintWorkspacePanelDestination.attention:
        _openAttention();
        return;
      case SprintWorkspacePanelDestination.management:
      case SprintWorkspacePanelDestination.completion:
      case SprintWorkspacePanelDestination.archive:
        return;
    }
  }

  Duration get _motionDuration {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return reduceMotion ? Duration.zero : const Duration(milliseconds: 260);
  }

  Route<void> _lifecycleRoute(Widget page) {
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

  Future<void> _switchProject() async {
    final result = await showSprintWorkspacePanel(
      context: context,
      store: widget.store,
    );
    if (result == null || !mounted) return;
    widget.store.selectScope(result.scope);
    if (result.destination == SprintWorkspacePanelDestination.archive) {
      await Navigator.of(context).push<void>(
        _lifecycleRoute(SprintProjectArchivePage(store: widget.store)),
      );
      return;
    }
    if (result.scope.type != SprintWorkspaceScopeType.project ||
        result.destination == SprintWorkspacePanelDestination.schedule) {
      Navigator.of(context).pop();
      return;
    }
    if (result.destination == SprintWorkspacePanelDestination.management) {
      await Navigator.of(context).push<void>(
        _lifecycleRoute(
          SprintProjectManagementPage(
            store: widget.store,
            projectId: result.scope.projectId!,
          ),
        ),
      );
      return;
    }
    if (result.destination == SprintWorkspacePanelDestination.completion) {
      await Navigator.of(context).push<void>(
        _lifecycleRoute(
          SprintProjectCompletionPage(
            store: widget.store,
            projectId: result.scope.projectId!,
          ),
        ),
      );
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _applyDestination(result.destination);
    });
  }

  Future<void> _openTask(SprintTask task) async {
    await showSprintTaskDetailSheet(
      context: context,
      store: widget.store,
      task: task,
    );
  }

  Future<void> _submitTask() async {
    final task = await sprintCreateTaskFromComposer(
      context: context,
      store: widget.store,
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

  Future<void> _openTaskCreate() async {
    await showSprintTaskCreateSheet(
      context: context,
      store: widget.store,
      initialDate: widget.store.selectedDate,
      initialProjectId: widget.store.selectedProjectId,
    );
  }

  void _openAttention() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      barrierColor: Theme.of(context).colorScheme.scrim,
      builder: (_) => _ProjectAttentionSheet(store: widget.store),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, child) {
        final project = widget.store.selectedProject;
        final reduceMotion =
            MediaQuery.maybeOf(context)?.disableAnimations ?? false;
        final motionDuration = reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 220);
        if (project == null) {
          return const Scaffold(
            body: Center(child: Text('프로젝트를 찾을 수 없습니다.')),
          );
        }
        final summary = widget.store.summaryFor(project.id);
        final previewTasks = _pathPreview(summary.pathTasks);

        return Scaffold(
          extendBody: false,
          extendBodyBehindAppBar: false,
          backgroundColor: Theme.of(context).colorScheme.surface,
          appBar: AppBar(
            titleSpacing: 4,
            title: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _switchProject,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: AnimatedSwitcher(
                        duration: motionDuration,
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) {
                          if (reduceMotion) return child;
                          final offset = Tween<Offset>(
                            begin: const Offset(0, 0.18),
                            end: Offset.zero,
                          ).animate(animation);
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: offset,
                              child: child,
                            ),
                          );
                        },
                        child: Text(
                          project.name,
                          key: ValueKey<String>(project.id),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_down_rounded),
                  ],
                ),
              ),
            ),
            actions: [
              if (summary.attentionCount > 0)
                IconButton(
                  tooltip: '확인 필요 ${summary.attentionCount}개',
                  onPressed: _openAttention,
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.warning_amber_rounded),
                      Positioned(
                        right: -7,
                        top: -7,
                        child: Container(
                          constraints: const BoxConstraints(
                            minWidth: 18,
                            minHeight: 18,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.error,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${summary.attentionCount}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onError,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              IconButton(
                tooltip: '프로젝트 전환',
                onPressed: _switchProject,
                icon: const Icon(Icons.swap_horiz_rounded),
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate(
                      [
                      const SprintSectionHeader(title: '종합 요약'),
                      const SizedBox(height: 10),
                      _ProjectSummaryCard(summary: summary),
                      const SizedBox(height: 16),
                      _DeliveryForecastCard(
                        summary: summary,
                        onResolve: _openAttention,
                      ),
                      const SizedBox(height: 16),
                      _ProjectWorkloadCard(
                        summary: summary,
                        onSelectDate: widget.store.selectDate,
                      ),
                      const SizedBox(height: 24),
                      SprintSectionHeader(
                        title: '오늘 일정',
                        actionLabel: '${summary.todayTasks.length}개',
                        onAction: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(height: 10),
                      if (summary.todayTasks.isEmpty)
                        const SprintSurface(
                          child: Text('오늘 배치된 프로젝트 업무가 없습니다.'),
                        )
                      else
                        ...summary.todayTasks.take(3).map(
                              (task) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _ProjectTodayTaskCard(
                                  store: widget.store,
                                  task: task,
                                  onTap: () => _openTask(task),
                                ),
                              ),
                            ),
                      const SizedBox(height: 14),
                      KeyedSubtree(
                        key: _pathKey,
                        child: SprintSectionHeader(
                        title: '진행 경로',
                        actionLabel: '전체',
                        onAction: () => _openFullPath(summary),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SprintSurface(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                        child: Column(
                          children: List<Widget>.generate(
                            previewTasks.length,
                            (index) => _ProjectPathItem(
                              task: previewTasks[index],
                              isLast: index == previewTasks.length - 1,
                            ),
                            growable: false,
                          ),
                        ),
                      ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: _ProjectBottomComposer(
            controller: _composerController,
            focusNode: _composerFocusNode,
            projectName: project.name,
            onAddTask: _openTaskCreate,
            onSubmit: _submitTask,
          ),
        );
      },
    );
  }

  List<SprintTask> _pathPreview(List<SprintTask> tasks) {
    if (tasks.length <= 5) return tasks;
    var pendingIndex = tasks.indexWhere(
      (task) =>
          task.state == SprintTaskState.scheduled ||
          task.state == SprintTaskState.ready,
    );
    if (pendingIndex < 0) pendingIndex = tasks.length - 1;
    final start = math.max(0, pendingIndex - 2).toInt();
    final end = math.min(tasks.length, start + 5).toInt();
    return tasks.sublist(start, end);
  }

  void _openFullPath(SprintProjectSummary summary) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _FullProjectPathPage(
          projectName: summary.project.name,
          tasks: summary.pathTasks,
        ),
      ),
    );
  }
}

class _ProjectSummaryCard extends StatelessWidget {
  const _ProjectSummaryCard({required this.summary});

  final SprintProjectSummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final progress = summary.progressRatio.clamp(0, 1).toDouble();
    final percentage = (progress * 100).round();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Semantics(
                label: '프로젝트 진행률 $percentage퍼센트',
                child: SizedBox(
                  width: 92,
                  height: 92,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 9,
                          color: colors.primary,
                          backgroundColor:
                              colors.surfaceContainerHighest,
                        ),
                      ),
                      Text(
                        '$percentage%',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: colors.onPrimaryContainer,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.project.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: colors.onPrimaryContainer,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      summary.completedTaskCount == summary.totalTaskCount &&
                              summary.totalTaskCount > 0
                          ? '완료'
                          : '진행 중',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colors.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '남은 예상 작업 ${sprintFormatDuration(summary.remainingMinutes)}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colors.onPrimaryContainer,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SprintMetric(
                    label: '완료',
                    value:
                        '${summary.completedTaskCount}/${summary.totalTaskCount}',
                  ),
                ),
                Expanded(
                  child: SprintMetric(
                    label: '오늘',
                    value: '${summary.todayTaskCount}',
                  ),
                ),
                Expanded(
                  child: SprintMetric(
                    label: '확인',
                    value: '${summary.attentionCount}',
                    warning: summary.attentionCount > 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeliveryForecastCard extends StatelessWidget {
  const _DeliveryForecastCard({
    required this.summary,
    required this.onResolve,
  });

  final SprintProjectSummary summary;
  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) {
    final start = summary.project.targetStartDate;
    final target = summary.project.targetDate;
    final colors = Theme.of(context).colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 220);
    final periodLabel = start != null && target != null
        ? '${sprintFormatShortDate(start)}–${sprintFormatShortDate(target)}'
        : start != null
            ? '${sprintFormatShortDate(start)} 시작'
            : target != null
                ? '${sprintFormatShortDate(target)} 완료 목표'
                : '목표 기간 없음';

    return SprintSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '완료 일정',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: duration,
            child: Text(
              periodLabel,
              key: ValueKey<String>(periodLabel),
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          AnimatedSize(
            duration: duration,
            curve: Curves.easeOutCubic,
            child: summary.project.hasNotStarted
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        '${sprintFormatDate(start!)} 시작 예정 · 시작까지 ${summary.project.daysUntilStart}일',
                        style: TextStyle(
                          color: colors.onPrimaryContainer,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(height: 18),
          _ForecastTimeline(
            today: DateTime.now(),
            estimate: summary.estimatedCompletion,
            target: target,
          ),
          const SizedBox(height: 14),
          if (target == null)
            Text(
              '목표 완료일이 설정되지 않았습니다.',
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            )
          else if (summary.isLate)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.errorContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '예상 완료가 목표 완료일보다 ${summary.delayDays}일 늦습니다.',
                    style: TextStyle(
                      color: colors.onErrorContainer,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: onResolve,
                    child: const Text('해결안 보기'),
                  ),
                ],
              ),
            )
          else
            Text(
              '목표 완료일 안에 완료할 수 있는 일정입니다.',
              style: TextStyle(
                color: colors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
    );
  }
}

class _ForecastTimeline extends StatelessWidget {
  const _ForecastTimeline({
    required this.today,
    required this.estimate,
    required this.target,
  });

  final DateTime today;
  final DateTime estimate;
  final DateTime? target;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dates = <DateTime>[today, estimate, if (target != null) target!];
    final minimum = dates.reduce((a, b) => a.isBefore(b) ? a : b);
    final maximum = dates.reduce((a, b) => a.isAfter(b) ? a : b);
    final totalDays =
        math.max(1, maximum.difference(minimum).inDays).toDouble();

    double position(DateTime date) {
      return date.difference(minimum).inDays / totalDays;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final todayX = width * position(today);
        final estimateX = width * position(estimate);
        final targetX = target == null ? null : width * position(target!);

        return SizedBox(
          height: 76,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 18,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.outlineVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              _ForecastPoint(
                x: todayX,
                width: width,
                topLabel: '오늘',
                bottomLabel: sprintFormatShortDate(today),
                color: colors.primary,
                icon: Icons.circle,
              ),
              _ForecastPoint(
                x: estimateX,
                width: width,
                topLabel: '예상',
                bottomLabel: sprintFormatShortDate(estimate),
                color: colors.tertiary,
                icon: Icons.adjust_rounded,
              ),
              if (targetX != null)
                _ForecastPoint(
                  x: targetX,
                  width: width,
                  topLabel: '목표',
                  bottomLabel: sprintFormatShortDate(target!),
                  color: colors.error,
                  icon: Icons.change_history_rounded,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ForecastPoint extends StatelessWidget {
  const _ForecastPoint({
    required this.x,
    required this.width,
    required this.topLabel,
    required this.bottomLabel,
    required this.color,
    required this.icon,
  });

  final double x;
  final double width;
  final String topLabel;
  final String bottomLabel;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final clamped = x.clamp(22, math.max(22, width - 22)).toDouble();
    return Positioned(
      left: clamped - 28,
      top: 0,
      child: SizedBox(
        width: 56,
        child: Column(
          children: [
            Text(
              topLabel,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w900,
                  ),
            ),
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 4),
            Text(
              bottomLabel,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectWorkloadCard extends StatelessWidget {
  const _ProjectWorkloadCard({
    required this.summary,
    required this.onSelectDate,
  });

  final SprintProjectSummary summary;
  final ValueChanged<DateTime> onSelectDate;

  @override
  Widget build(BuildContext context) {
    return SprintSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '향후 7일 프로젝트 작업량',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 112,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: summary.workload
                  .map(
                    (day) => Expanded(
                      child: _LoadBar(
                        load: day,
                        onTap: () => onSelectDate(day.date),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
          const SizedBox(height: 12),
          Builder(
            builder: (context) {
              final overloaded = summary.workload
                  .where((day) => day.overloaded)
                  .toList(growable: false);
              if (overloaded.isEmpty) {
                return const Text('향후 7일 동안 과부하가 없습니다.');
              }
              return Text(
                '${sprintWeekday(overloaded.first.date.weekday)}요일은 배치 가능시간을 초과했습니다.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w800,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _LoadBar extends StatelessWidget {
  const _LoadBar({
    required this.load,
    required this.onTap,
  });

  final SprintDayLoad load;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final ratio = load.availableMinutes <= 0 && load.plannedMinutes == 0
        ? 0.06
        : load.ratio.clamp(0.08, 1).toDouble();

    return Semantics(
      button: true,
      label:
          '${sprintWeekday(load.date.weekday)}요일, 프로젝트 업무 ${load.plannedMinutes}분${load.overloaded ? ', 과부하' : ''}',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (load.overloaded)
                Icon(
                  Icons.warning_amber_rounded,
                  size: 17,
                  color: colors.error,
                )
              else
                const SizedBox(height: 17),
              const SizedBox(height: 4),
              Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    heightFactor: ratio,
                    widthFactor: 0.66,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.primary,
                        borderRadius: BorderRadius.circular(999),
                        border: load.overloaded
                            ? Border.all(color: colors.error, width: 2)
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                sprintWeekday(load.date.weekday),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectTodayTaskCard extends StatelessWidget {
  const _ProjectTodayTaskCard({
    required this.store,
    required this.task,
    required this.onTap,
  });

  final SprintModeStore store;
  final SprintTask task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    SprintScheduleBlock? block;
    for (final item in store.blocks) {
      if (item.taskId == task.id) {
        block = item;
        break;
      }
    }
    final colors = Theme.of(context).colorScheme;

    return SprintSurface(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              block == null ? Icons.task_alt_outlined : Icons.schedule_rounded,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  block == null
                      ? sprintFormatDuration(task.estimatedMinutes)
                      : '${sprintFormatTime(block.start)}–${sprintFormatTime(block.end)} · ${sprintFormatDuration(block.durationMinutes)}',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}

class _ProjectPathItem extends StatelessWidget {
  const _ProjectPathItem({
    required this.task,
    required this.isLast,
  });

  final SprintTask task;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final completed = task.state == SprintTaskState.completed;
    final pending = task.state == SprintTaskState.scheduled ||
        task.state == SprintTaskState.ready;
    final icon = completed
        ? Icons.check_circle_rounded
        : pending
            ? Icons.timelapse_rounded
            : Icons.radio_button_unchecked_rounded;
    final color = completed
        ? colors.primary
        : pending
            ? colors.tertiary
            : colors.outline;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 36,
            child: Column(
              children: [
                Icon(icon, color: color, size: 22),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: colors.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      decoration:
                          completed ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _taskStateLabel(task),
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _taskStateLabel(SprintTask task) {
    switch (task.state) {
      case SprintTaskState.completed:
        return '실제 ${sprintFormatDuration(task.actualMinutes)}';
      case SprintTaskState.scheduled:
        return '일정에 배치됨';
      case SprintTaskState.ready:
        return '배치 대기';
      case SprintTaskState.blocked:
        return '선행 업무 완료 후 시작';
      case SprintTaskState.cancelled:
        return '취소됨';
    }
  }
}

class _ProjectBottomComposer extends StatelessWidget {
  const _ProjectBottomComposer({
    required this.controller,
    required this.focusNode,
    required this.projectName,
    required this.onAddTask,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String projectName;
  final VoidCallback onAddTask;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 180);
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Material(
      color: colors.surfaceContainer,
      elevation: 8,
      child: SafeArea(
        top: false,
        maintainBottomViewPadding: true,
        minimum: const EdgeInsets.only(bottom: 8),
        child: AnimatedPadding(
          duration: duration,
          padding: EdgeInsets.fromLTRB(
            12,
            8,
            12,
            keyboardVisible ? 4 : 8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '$projectName 업무 입력',
                style: const TextStyle(fontWeight: FontWeight.w800),
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

class _ProjectAttentionSheet extends StatelessWidget {
  const _ProjectAttentionSheet({required this.store});

  final SprintModeStore store;

  @override
  Widget build(BuildContext context) {
    final items = store.attentionItems
        .where((item) => item.projectId == store.selectedProjectId)
        .toList(growable: false);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '확인 필요 ${items.length}',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 14),
          if (items.isEmpty)
            const SprintSurface(
              child: Text('확인이 필요한 항목이 없습니다.'),
            )
          else
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SprintSurface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item.title,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900),
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
                          FilledButton.tonal(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('추천 위치로 이동'),
                          ),
                          OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('직접 조정'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FullProjectPathPage extends StatelessWidget {
  const _FullProjectPathPage({
    required this.projectName,
    required this.tasks,
  });

  final String projectName;
  final List<SprintTask> tasks;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('$projectName · 진행 경로')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
        children: [
          SprintSurface(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
            child: Column(
              children: List<Widget>.generate(
                tasks.length,
                (index) => _ProjectPathItem(
                  task: tasks[index],
                  isLast: index == tasks.length - 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
