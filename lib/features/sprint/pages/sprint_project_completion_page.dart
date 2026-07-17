import 'package:flutter/material.dart';

import '../application/sprint_mode_store.dart';
import '../domain/sprint_models.dart';
import 'sprint_ui.dart';

class SprintProjectCompletionPage extends StatefulWidget {
  const SprintProjectCompletionPage({
    super.key,
    required this.store,
    required this.projectId,
  });

  final SprintModeStore store;
  final String projectId;

  @override
  State<SprintProjectCompletionPage> createState() =>
      _SprintProjectCompletionPageState();
}

class _SprintProjectCompletionPageState
    extends State<SprintProjectCompletionPage> {
  final TextEditingController _reviewController = TextEditingController();
  bool _cancelRemaining = false;
  bool _acceptConflicts = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    _reviewController.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _complete() async {
    if (_saving) return;
    setState(() => _saving = true);
    final report = await widget.store.completeProject(
      projectId: widget.projectId,
      reviewNote: _reviewController.text,
      cancelRemaining: _cancelRemaining,
      acceptConflicts: _acceptConflicts,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (report == null) {
      final unfinished = widget.store.tasksForProject(widget.projectId).where((task) {
        return task.state != SprintTaskState.completed &&
            task.state != SprintTaskState.cancelled;
      }).length;
      final conflicts = widget.store.conflictsForProject(widget.projectId).length;
      final message = unfinished > 0 && !_cancelRemaining
          ? '미완료 업무 처리 방식을 확인하세요.'
          : conflicts > 0 && !_acceptConflicts
              ? '미해결 충돌 처리 방식을 확인하세요.'
              : '프로젝트 완료 상태를 저장하지 못했습니다.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return;
    }
    sprintShowMessage(
      context: context,
      message: '프로젝트를 완료했습니다.',
    );
    Navigator.of(context).pushReplacement<void, void>(
      _animatedRoute(
        context,
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
    final tasks = widget.store.tasksForProject(project.id);
    final unfinished = tasks.where((task) {
      return task.state != SprintTaskState.completed &&
          task.state != SprintTaskState.cancelled;
    }).toList(growable: false);
    final conflicts = widget.store.conflictsForProject(project.id);
    final planned = tasks.fold<int>(
      0,
      (sum, task) => sum + task.estimatedMinutes,
    );
    final actual = tasks.fold<int>(
      0,
      (sum, task) => sum + task.actualMinutes,
    );
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 240);
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: const Text('프로젝트 완료'),
        backgroundColor: colors.surface,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
          children: [
            SprintSurface(
              backgroundColor: colors.primaryContainer,
              borderColor: colors.primary,
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(project.icon),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project.name,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: colors.onPrimaryContainer,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '완료 상태를 확정하고 종료 보고서를 저장합니다.',
                          style: TextStyle(color: colors.onPrimaryContainer),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SprintSurface(
              child: Row(
                children: [
                  Expanded(
                    child: SprintMetric(
                      label: '업무',
                      value: '${tasks.length}',
                    ),
                  ),
                  Expanded(
                    child: SprintMetric(
                      label: '미완료',
                      value: '${unfinished.length}',
                      warning: unfinished.isNotEmpty,
                    ),
                  ),
                  Expanded(
                    child: SprintMetric(
                      label: '충돌',
                      value: '${conflicts.length}',
                      warning: conflicts.isNotEmpty,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SprintSurface(
              child: Row(
                children: [
                  Expanded(
                    child: SprintMetric(
                      label: '계획',
                      value: sprintFormatDuration(planned),
                    ),
                  ),
                  Expanded(
                    child: SprintMetric(
                      label: '실제',
                      value: sprintFormatDuration(actual),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            AnimatedSize(
              duration: duration,
              curve: Curves.easeOutCubic,
              child: unfinished.isEmpty
                  ? SprintSurface(
                      backgroundColor: colors.secondaryContainer,
                      child: Text(
                        '모든 업무가 완료 또는 취소 상태입니다.',
                        style: TextStyle(
                          color: colors.onSecondaryContainer,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    )
                  : SprintSurface(
                      backgroundColor: colors.errorContainer,
                      borderColor: colors.error,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '미완료 업무 ${unfinished.length}개',
                            style: TextStyle(
                              color: colors.onErrorContainer,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...unfinished.take(5).map(
                                (task) => Padding(
                                  padding: const EdgeInsets.only(bottom: 5),
                                  child: Text(
                                    task.title,
                                    style: TextStyle(
                                      color: colors.onErrorContainer,
                                    ),
                                  ),
                                ),
                              ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _cancelRemaining,
                            title: Text(
                              '남은 업무를 취소 처리',
                              style: TextStyle(
                                color: colors.onErrorContainer,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            subtitle: Text(
                              '완료로 바꾸지 않고 취소 기록으로 남깁니다.',
                              style: TextStyle(color: colors.onErrorContainer),
                            ),
                            onChanged: _saving
                                ? null
                                : (value) => setState(() => _cancelRemaining = value),
                          ),
                        ],
                      ),
                    ),
            ),
            if (conflicts.isNotEmpty) ...[
              const SizedBox(height: 12),
              SprintSurface(
                backgroundColor: colors.tertiaryContainer,
                borderColor: colors.tertiary,
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _acceptConflicts,
                  title: Text(
                    '미해결 충돌 ${conflicts.length}건을 확인함',
                    style: TextStyle(
                      color: colors.onTertiaryContainer,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  subtitle: Text(
                    '현재 배치 기록을 보고서에 남기고 프로젝트를 완료합니다.',
                    style: TextStyle(color: colors.onTertiaryContainer),
                  ),
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _acceptConflicts = value),
                ),
              ),
            ],
            const SizedBox(height: 18),
            TextField(
              controller: _reviewController,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: '종료 메모',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _saving ||
                      unfinished.isNotEmpty && !_cancelRemaining ||
                      conflicts.isNotEmpty && !_acceptConflicts
                  ? null
                  : _complete,
              icon: const Icon(Icons.verified_rounded),
              label: AnimatedSwitcher(
                duration: duration,
                child: _saving
                    ? const SizedBox(
                        key: ValueKey<String>('saving'),
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        '프로젝트 완료 확정',
                        key: ValueKey<String>('complete'),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SprintProjectReportPage extends StatelessWidget {
  const SprintProjectReportPage({
    super.key,
    required this.store,
    required this.report,
  });

  final SprintModeStore store;
  final SprintProjectReport report;

  @override
  Widget build(BuildContext context) {
    final project = store.projectById(report.projectId);
    final colors = Theme.of(context).colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 260);
    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: const Text('종료 보고서'),
        backgroundColor: colors.surface,
      ),
      body: SafeArea(
        child: TweenAnimationBuilder<double>(
          duration: duration,
          tween: Tween<double>(begin: 0, end: 1),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 18 * (1 - value)),
                child: child,
              ),
            );
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
            children: [
              SprintSurface(
                backgroundColor: colors.primaryContainer,
                borderColor: colors.primary,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      project?.name ?? '프로젝트',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: colors.onPrimaryContainer,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${sprintFormatDate(report.completedAt)} 완료',
                      style: TextStyle(color: colors.onPrimaryContainer),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SprintSurface(
                child: Row(
                  children: [
                    Expanded(
                      child: SprintMetric(
                        label: '계획',
                        value: sprintFormatDuration(report.plannedMinutes),
                      ),
                    ),
                    Expanded(
                      child: SprintMetric(
                        label: '실제',
                        value: sprintFormatDuration(report.actualMinutes),
                        warning: report.actualMinutes > report.plannedMinutes,
                      ),
                    ),
                    Expanded(
                      child: SprintMetric(
                        label: '배치',
                        value: sprintFormatDuration(report.scheduledMinutes),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SprintSurface(
                child: Row(
                  children: [
                    Expanded(
                      child: SprintMetric(
                        label: '완료 업무',
                        value: '${report.completedTaskCount}',
                      ),
                    ),
                    Expanded(
                      child: SprintMetric(
                        label: '취소 업무',
                        value: '${report.cancelledTaskCount}',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SprintSurface(
                child: Row(
                  children: [
                    Expanded(
                      child: SprintMetric(
                        label: '연기',
                        value: '${report.postponeCount}',
                      ),
                    ),
                    Expanded(
                      child: SprintMetric(
                        label: '충돌 해결',
                        value:
                            '${report.resolvedConflictCount}/${report.conflictCount}',
                      ),
                    ),
                  ],
                ),
              ),
              if (project?.targetStartDate != null ||
                  project?.targetDate != null) ...[
                const SizedBox(height: 10),
                SprintSurface(
                  backgroundColor: colors.surfaceContainerLow,
                  child: Text(
                    project?.targetStartDate != null &&
                            project?.targetDate != null
                        ? '목표 기간 ${sprintFormatShortDate(project!.targetStartDate!)}–${sprintFormatShortDate(project!.targetDate!)}'
                        : project?.targetStartDate != null
                            ? '목표 시작일 ${sprintFormatDate(project!.targetStartDate!)}'
                            : '목표 완료일 ${sprintFormatDate(project!.targetDate!)}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              SprintSurface(
                backgroundColor: report.targetDeltaDays > 0
                    ? colors.errorContainer
                    : colors.secondaryContainer,
                child: Text(
                  project?.targetDate == null
                      ? '설정된 목표 완료일 없이 완료했습니다.'
                      : report.targetDeltaDays == 0
                          ? '목표 완료일 기준 일정대로 완료했습니다.'
                          : report.targetDeltaDays > 0
                          ? '목표 완료일보다 ${report.targetDeltaDays}일 늦게 완료했습니다.'
                          : '목표 완료일보다 ${report.targetDeltaDays.abs()}일 빠르게 완료했습니다.',
                  style: TextStyle(
                    color: report.targetDeltaDays > 0
                        ? colors.onErrorContainer
                        : colors.onSecondaryContainer,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (report.reviewNote?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 14),
                SprintSectionHeader(title: '종료 메모'),
                const SizedBox(height: 8),
                SprintSurface(child: Text(report.reviewNote!.trim())),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Route<void> _animatedRoute(BuildContext context, Widget page) {
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
            begin: const Offset(0.04, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}
