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
    widget.store.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onChanged);
    _reviewController.dispose();
    super.dispose();
  }

  void _onChanged() {
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
      sprintShowMessage(
        context: context,
        message: '미완료 업무와 확인 필요 항목의 처리 방식을 확인하세요.',
      );
      return;
    }
    await Navigator.of(context).pushReplacement(
      sprintPageRoute<void>(
        context: context,
        page: SprintProjectReportPage(
          store: widget.store,
          projectId: widget.projectId,
          report: report,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.store.projectById(widget.projectId);
    if (project == null) {
      return const SprintScaffold(
        body: Center(child: Text('프로젝트를 찾을 수 없습니다.')),
      );
    }
    final tasks = widget.store.tasksForProject(project.id);
    final unfinished = tasks.where((task) {
      return task.state != SprintTaskState.completed &&
          task.state != SprintTaskState.cancelled;
    }).toList(growable: false);
    final conflicts = widget.store.conflictsForProject(project.id);
    final colors = Theme.of(context).colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 220);
    return SprintScaffold(
      appBar: AppBar(
        title: const Text(
          '프로젝트 완료',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            SprintSurface(
              backgroundColor: colors.surfaceContainerHigh,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    project.name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _period(project),
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      SprintMetric(label: '전체 업무', value: '${tasks.length}'),
                      SprintMetric(
                        label: '완료',
                        value:
                            '${tasks.where((task) => task.state == SprintTaskState.completed).length}',
                      ),
                      SprintMetric(
                        label: '미완료',
                        value: '${unfinished.length}',
                        warning: unfinished.isNotEmpty,
                      ),
                      SprintMetric(
                        label: '확인',
                        value: '${conflicts.length}',
                        warning: conflicts.isNotEmpty,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            AnimatedContainer(
              duration: duration,
              decoration: BoxDecoration(
                color: unfinished.isEmpty
                    ? colors.surfaceContainerLow
                    : colors.errorContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: SwitchListTile(
                value: _cancelRemaining,
                onChanged: unfinished.isEmpty
                    ? null
                    : (value) => setState(() => _cancelRemaining = value),
                title: const Text(
                  '미완료 업무 취소 처리',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  unfinished.isEmpty
                      ? '미완료 업무가 없습니다.'
                      : '${unfinished.length}개 업무를 취소 상태로 전환합니다.',
                ),
              ),
            ),
            const SizedBox(height: 10),
            AnimatedContainer(
              duration: duration,
              decoration: BoxDecoration(
                color: conflicts.isEmpty
                    ? colors.surfaceContainerLow
                    : colors.tertiaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: SwitchListTile(
                value: _acceptConflicts,
                onChanged: conflicts.isEmpty
                    ? null
                    : (value) => setState(() => _acceptConflicts = value),
                title: const Text(
                  '남은 날짜 경고 확인',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  conflicts.isEmpty
                      ? '미해결 날짜 문제가 없습니다.'
                      : '${conflicts.length}개 경고를 확인한 상태로 완료합니다.',
                ),
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _reviewController,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: '종료 리뷰',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _complete,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
              icon: const Icon(Icons.task_alt_rounded),
              label: AnimatedSwitcher(
                duration: duration,
                child: _saving
                    ? const SizedBox(
                        key: ValueKey<String>('saving'),
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        '프로젝트 완료',
                        key: ValueKey<String>('complete'),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _period(SprintProject project) {
    final start = project.targetStartDate;
    final end = project.targetDate;
    if (start != null && end != null) {
      return '목표 기간 ${sprintFormatShortDate(start)}–${sprintFormatShortDate(end)}';
    }
    if (start != null) return '${sprintFormatDate(start)} 시작';
    if (end != null) return '목표 완료 ${sprintFormatDate(end)}';
    return '무기한 프로젝트';
  }
}

class SprintProjectReportPage extends StatelessWidget {
  const SprintProjectReportPage({
    super.key,
    required this.store,
    this.projectId,
    required this.report,
  });

  final SprintModeStore store;
  final String? projectId;
  final SprintProjectReport report;

  @override
  Widget build(BuildContext context) {
    final resolvedProjectId = projectId ?? report.projectId;
    final project = store.projectById(resolvedProjectId);
    final colors = Theme.of(context).colorScheme;
    return SprintScaffold(
      appBar: AppBar(
        title: const Text(
          '종료 보고서',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            SprintSurface(
              backgroundColor: colors.surfaceContainerHigh,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    project?.name ?? '프로젝트',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '완료 ${sprintFormatDate(report.completedAt)}',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 20,
                    runSpacing: 20,
                    alignment: WrapAlignment.spaceAround,
                    children: [
                      SprintMetric(
                        label: '전체 업무',
                        value: '${report.totalTaskCount}',
                      ),
                      SprintMetric(
                        label: '완료',
                        value: '${report.completedTaskCount}',
                      ),
                      SprintMetric(
                        label: '취소',
                        value: '${report.cancelledTaskCount}',
                      ),
                      SprintMetric(
                        label: '높음 완료',
                        value: '${report.highPriorityCompletedCount}',
                      ),
                      SprintMetric(
                        label: '기한 내',
                        value: '${report.onTimeCompletedCount}',
                      ),
                      SprintMetric(
                        label: '기한 초과',
                        value: '${report.overdueCompletedCount}',
                        warning: report.overdueCompletedCount > 0,
                      ),
                      SprintMetric(
                        label: '연기',
                        value: '${report.postponeCount}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (report.reviewNote != null) ...[
              const SizedBox(height: 18),
              const SprintSectionHeader(title: '종료 리뷰'),
              const SizedBox(height: 10),
              SprintSurface(child: Text(report.reviewNote!)),
            ],
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: () async {
                final archived = await store.archiveProject(resolvedProjectId);
                if (!context.mounted) return;
                sprintShowMessage(
                  context: context,
                  message: archived
                      ? '프로젝트를 보관했습니다.'
                      : '프로젝트를 보관하지 못했습니다.',
                );
                if (archived) Navigator.of(context).pop();
              },
              icon: const Icon(Icons.archive_outlined),
              label: const Text('완료 프로젝트 보관'),
            ),
          ],
        ),
      ),
    );
  }
}
