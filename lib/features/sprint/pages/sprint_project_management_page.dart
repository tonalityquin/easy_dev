import 'package:flutter/material.dart';

import '../application/sprint_mode_store.dart';
import '../domain/sprint_models.dart';
import 'sprint_conflict_resolution_sheet.dart';
import 'sprint_project_completion_page.dart';
import 'sprint_project_form_sheet.dart';
import 'sprint_task_detail_sheet.dart';
import 'sprint_ui.dart';

class SprintProjectManagementPage extends StatefulWidget {
  const SprintProjectManagementPage({
    super.key,
    required this.store,
    required this.projectId,
  });

  final SprintModeStore store;
  final String projectId;

  @override
  State<SprintProjectManagementPage> createState() =>
      _SprintProjectManagementPageState();
}

class _SprintProjectManagementPageState
    extends State<SprintProjectManagementPage> {
  int _sectionIndex = 0;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  Route<void> _route(Widget page) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return PageRouteBuilder<void>(
      transitionDuration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 280),
      reverseTransitionDuration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
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

  Future<void> _editProject(SprintProject project) async {
    await showSprintProjectEditSheet(
      context: context,
      store: widget.store,
      project: project,
    );
  }

  Future<void> _openTask(SprintTask task) async {
    await showSprintTaskDetailSheet(
      context: context,
      store: widget.store,
      task: task,
    );
  }

  Future<void> _resolve(SprintAttentionItem item) async {
    await showSprintConflictResolutionSheet(
      context: context,
      store: widget.store,
      item: item,
    );
  }

  void _openCompletion() {
    Navigator.of(context).push<void>(
      _route(
        SprintProjectCompletionPage(
          store: widget.store,
          projectId: widget.projectId,
        ),
      ),
    );
  }

  void _openReport(SprintProjectReport report) {
    Navigator.of(context).push<void>(
      _route(
        SprintProjectReportPage(
          store: widget.store,
          report: report,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.store.projectById(widget.projectId);
    if (project == null) {
      return const Scaffold(body: Center(child: Text('프로젝트를 찾지 못했습니다.')));
    }
    final colors = Theme.of(context).colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 240);
    final tasks = widget.store.tasksForProject(project.id);
    final attention = widget.store.attentionItems
        .where((item) => item.projectId == project.id)
        .toList(growable: false);
    final report = widget.store.latestReportFor(project.id);
    final summary = widget.store.summaryFor(project.id);
    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: const Text('프로젝트 관리'),
        backgroundColor: colors.surface,
        actions: [
          IconButton(
            tooltip: '프로젝트 수정',
            onPressed: project.status == SprintProjectStatus.active
                ? () => _editProject(project)
                : null,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: _ProjectHeader(
                project: project,
                summary: summary,
                duration: duration,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment<int>(
                    value: 0,
                    icon: Icon(Icons.checklist_rounded),
                    label: Text('업무'),
                  ),
                  ButtonSegment<int>(
                    value: 1,
                    icon: Icon(Icons.warning_amber_rounded),
                    label: Text('충돌'),
                  ),
                  ButtonSegment<int>(
                    value: 2,
                    icon: Icon(Icons.verified_outlined),
                    label: Text('종료'),
                  ),
                ],
                selected: <int>{_sectionIndex},
                onSelectionChanged: (value) {
                  setState(() => _sectionIndex = value.first);
                },
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: AnimatedSwitcher(
                duration: duration,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  if (reduceMotion) return child;
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.025, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: switch (_sectionIndex) {
                  0 => _TaskSection(
                      key: const ValueKey<String>('tasks'),
                      tasks: tasks,
                      onTask: _openTask,
                    ),
                  1 => _ConflictSection(
                      key: const ValueKey<String>('conflicts'),
                      items: attention,
                      onResolve: _resolve,
                    ),
                  _ => _LifecycleSection(
                      key: const ValueKey<String>('lifecycle'),
                      project: project,
                      report: report,
                      onComplete: _openCompletion,
                      onReport: report == null ? null : () => _openReport(report),
                    ),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectHeader extends StatelessWidget {
  const _ProjectHeader({
    required this.project,
    required this.summary,
    required this.duration,
  });

  final SprintProject project;
  final SprintProjectSummary summary;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final statusLabel = switch (project.status) {
      SprintProjectStatus.active => '진행 중',
      SprintProjectStatus.completed => '완료',
      SprintProjectStatus.archived => '보관',
    };
    return SprintSurface(
      backgroundColor: colors.surfaceContainerLow,
      child: Column(
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: duration,
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(project.icon, color: colors.onPrimaryContainer),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$statusLabel · 진행 ${(summary.progressRatio * 100).round()}%',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: TweenAnimationBuilder<double>(
              duration: duration,
              tween: Tween<double>(begin: 0, end: summary.progressRatio),
              builder: (context, value, child) {
                return LinearProgressIndicator(
                  value: value,
                  minHeight: 8,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskSection extends StatelessWidget {
  const _TaskSection({
    super.key,
    required this.tasks,
    required this.onTask,
  });

  final List<SprintTask> tasks;
  final ValueChanged<SprintTask> onTask;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (tasks.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          SprintSurface(
            backgroundColor: colors.surfaceContainerLow,
            child: const Text('프로젝트 업무가 없습니다.'),
          ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: _TaskManagementCard(
            task: task,
            onTap: () => onTask(task),
          ),
        );
      },
    );
  }
}

class _TaskManagementCard extends StatelessWidget {
  const _TaskManagementCard({required this.task, required this.onTap});

  final SprintTask task;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final icon = switch (task.state) {
      SprintTaskState.completed => Icons.check_circle_rounded,
      SprintTaskState.cancelled => Icons.cancel_rounded,
      SprintTaskState.scheduled => Icons.schedule_rounded,
      SprintTaskState.blocked => Icons.lock_clock_rounded,
      SprintTaskState.ready => Icons.radio_button_unchecked_rounded,
    };
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: colors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '예상 ${sprintFormatDuration(task.estimatedMinutes)} · 실제 ${sprintFormatDuration(task.actualMinutes)} · 남음 ${sprintFormatDuration(task.remainingMinutes)}',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
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

class _ConflictSection extends StatelessWidget {
  const _ConflictSection({
    super.key,
    required this.items,
    required this.onResolve,
  });

  final List<SprintAttentionItem> items;
  final ValueChanged<SprintAttentionItem> onResolve;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (items.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          SprintSurface(
            backgroundColor: colors.secondaryContainer,
            child: Text(
              '확인할 충돌이 없습니다.',
              style: TextStyle(
                color: colors.onSecondaryContainer,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: SprintSurface(
            backgroundColor: colors.errorContainer,
            borderColor: colors.error,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  item.title,
                  style: TextStyle(
                    color: colors.onErrorContainer,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  item.description,
                  style: TextStyle(color: colors.onErrorContainer),
                ),
                if (item.blockId != null) ...[
                  const SizedBox(height: 10),
                  FilledButton.tonal(
                    onPressed: () => onResolve(item),
                    child: const Text('해결 방법 선택'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LifecycleSection extends StatelessWidget {
  const _LifecycleSection({
    super.key,
    required this.project,
    required this.report,
    required this.onComplete,
    required this.onReport,
  });

  final SprintProject project;
  final SprintProjectReport? report;
  final VoidCallback onComplete;
  final VoidCallback? onReport;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final currentReport = report;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        SprintSurface(
          backgroundColor: colors.surfaceContainerLow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                project.status == SprintProjectStatus.active
                    ? '프로젝트를 완료할 준비가 되었나요?'
                    : '프로젝트가 완료 상태입니다.',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                project.status == SprintProjectStatus.active
                    ? '미완료 업무와 충돌을 점검한 뒤 종료 보고서를 저장합니다.'
                    : '종료 보고서를 열거나 완료 및 보관함에서 상태를 변경할 수 있습니다.',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              if (project.status == SprintProjectStatus.active)
                FilledButton.icon(
                  onPressed: onComplete,
                  icon: const Icon(Icons.verified_rounded),
                  label: const Text('프로젝트 완료'),
                )
              else if (onReport != null)
                FilledButton.icon(
                  onPressed: onReport,
                  icon: const Icon(Icons.summarize_rounded),
                  label: const Text('종료 보고서'),
                ),
            ],
          ),
        ),
        if (currentReport != null) ...[
          const SizedBox(height: 12),
          SprintSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '최근 종료 기록',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: SprintMetric(
                        label: '계획',
                        value: sprintFormatDuration(currentReport.plannedMinutes),
                      ),
                    ),
                    Expanded(
                      child: SprintMetric(
                        label: '실제',
                        value: sprintFormatDuration(currentReport.actualMinutes),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: onReport,
                  child: const Text('보고서 열기'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
