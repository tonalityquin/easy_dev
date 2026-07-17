import 'package:flutter/material.dart';

import '../application/sprint_mode_store.dart';
import '../domain/sprint_models.dart';
import 'sprint_project_completion_page.dart';
import 'sprint_ui.dart';

class SprintProjectArchivePage extends StatefulWidget {
  const SprintProjectArchivePage({
    super.key,
    required this.store,
  });

  final SprintModeStore store;

  @override
  State<SprintProjectArchivePage> createState() =>
      _SprintProjectArchivePageState();
}

class _SprintProjectArchivePageState extends State<SprintProjectArchivePage> {
  String? _busyProjectId;

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

  Future<void> _archive(SprintProject project) async {
    if (_busyProjectId != null) return;
    setState(() => _busyProjectId = project.id);
    final archived = await widget.store.archiveProject(project.id);
    if (!mounted) return;
    setState(() => _busyProjectId = null);
    if (archived) {
      sprintShowMessage(
        context: context,
        message: '프로젝트를 보관했습니다.',
      );
    }
  }

  Future<void> _reopen(SprintProject project) async {
    if (_busyProjectId != null) return;
    setState(() => _busyProjectId = project.id);
    final reopened = await widget.store.reopenProject(project.id);
    if (!mounted) return;
    setState(() => _busyProjectId = null);
    if (reopened) {
      sprintShowMessage(
        context: context,
        message: '프로젝트를 다시 열었습니다.',
      );
      Navigator.of(context).pop();
    }
  }

  void _openReport(SprintProject project) {
    final report = widget.store.latestReportFor(project.id);
    if (report == null) return;
    Navigator.of(context).push<void>(
      _route(
        context,
        SprintProjectReportPage(store: widget.store, report: report),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final completed = widget.store.completedProjects;
    final archived = widget.store.archivedProjects;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 240);
    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: const Text('완료 및 보관함'),
        backgroundColor: colors.surface,
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: duration,
          child: ListView(
            key: ValueKey<String>('${completed.length}-${archived.length}'),
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
            children: [
              SprintSectionHeader(title: '완료 프로젝트'),
              const SizedBox(height: 8),
              if (completed.isEmpty)
                SprintSurface(
                  backgroundColor: colors.surfaceContainerLow,
                  child: const Text('완료된 프로젝트가 없습니다.'),
                )
              else
                ...completed.map(
                  (project) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _ArchiveProjectCard(
                      project: project,
                      busy: _busyProjectId == project.id,
                      primaryLabel: '다시 열기',
                      onPrimary: () => _reopen(project),
                      secondaryLabel: '보관',
                      onSecondary: () => _archive(project),
                      onReport: () => _openReport(project),
                    ),
                  ),
                ),
              const SizedBox(height: 22),
              SprintSectionHeader(title: '보관 프로젝트'),
              const SizedBox(height: 8),
              if (archived.isEmpty)
                SprintSurface(
                  backgroundColor: colors.surfaceContainerLow,
                  child: const Text('보관된 프로젝트가 없습니다.'),
                )
              else
                ...archived.map(
                  (project) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _ArchiveProjectCard(
                      project: project,
                      busy: _busyProjectId == project.id,
                      primaryLabel: '다시 열기',
                      onPrimary: () => _reopen(project),
                      onReport: () => _openReport(project),
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

class _ArchiveProjectCard extends StatelessWidget {
  const _ArchiveProjectCard({
    required this.project,
    required this.busy,
    required this.primaryLabel,
    required this.onPrimary,
    required this.onReport,
    this.secondaryLabel,
    this.onSecondary,
  });

  final SprintProject project;
  final bool busy;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final VoidCallback onReport;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SprintSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(project.icon, color: colors.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.name,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      project.completedAt == null
                          ? '완료 기록 없음'
                          : '${sprintFormatDate(project.completedAt!)} 완료',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onReport,
                  child: const Text('종료 보고서'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : onPrimary,
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(primaryLabel),
                ),
              ),
            ],
          ),
          if (secondaryLabel != null && onSecondary != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: busy ? null : onSecondary,
              icon: const Icon(Icons.inventory_2_outlined),
              label: Text(secondaryLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

Route<void> _route(BuildContext context, Widget page) {
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
      );
      return FadeTransition(opacity: curved, child: child);
    },
  );
}
