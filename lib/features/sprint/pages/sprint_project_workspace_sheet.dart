import 'package:flutter/material.dart';

import '../../../app/auth/google_auth_session.dart';
import '../../../shared/google_calendar/google_event_colors.dart';
import '../application/sprint_mode_store.dart';
import '../domain/sprint_models.dart';
import 'sprint_project_form_sheet.dart';
import 'sprint_ui.dart';

enum SprintWorkspacePanelDestination {
  schedule,
  summary,
  path,
  attention,
  management,
  completion,
  archive,
}

class SprintWorkspacePanelResult {
  const SprintWorkspacePanelResult({
    required this.scope,
    required this.destination,
  });

  final SprintWorkspaceScope scope;
  final SprintWorkspacePanelDestination destination;
}

Future<SprintWorkspacePanelResult?> showSprintWorkspacePanel({
  required BuildContext context,
  required SprintModeStore store,
}) {
  final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  final colors = Theme.of(context).colorScheme;
  return Navigator.of(context).push<SprintWorkspacePanelResult>(
    PageRouteBuilder<SprintWorkspacePanelResult>(
      opaque: true,
      barrierDismissible: false,
      transitionDuration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 260),
      reverseTransitionDuration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => SprintPromptScope(
        child: SprintWorkspacePanelPage(store: store),
      ),
      transitionsBuilder: (_, animation, __, child) {
        if (reduceMotion) return child;
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return ColoredBox(
          color: colors.surface,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(-0.16, 0),
              end: Offset.zero,
            ).animate(curved),
            child: FadeTransition(opacity: curved, child: child),
          ),
        );
      },
    ),
  );
}

Future<SprintWorkspaceScope?> showSprintCreateProjectSheet({
  required BuildContext context,
  required SprintModeStore store,
}) async {
  return sprintShowBottomSheet<SprintWorkspaceScope>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _SprintCreateProjectSheet(store: store),
  );
}

Future<void> showSprintAccountSheet({
  required BuildContext context,
  required SprintModeStore store,
}) async {
  await sprintShowBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _SprintAccountSheet(store: store),
  );
}

class SprintWorkspacePanelPage extends StatefulWidget {
  const SprintWorkspacePanelPage({
    super.key,
    required this.store,
    this.onClose,
    this.onResult,
  });

  final SprintModeStore store;
  final VoidCallback? onClose;
  final Future<void> Function(SprintWorkspacePanelResult result)? onResult;

  @override
  State<SprintWorkspacePanelPage> createState() =>
      _SprintWorkspacePanelPageState();
}

class _SprintWorkspacePanelPageState
    extends State<SprintWorkspacePanelPage> {
  late SprintWorkspaceScope _selectedScope;
  String? _deletingProjectId;

  @override
  void initState() {
    super.initState();
    _selectedScope = widget.store.workspaceScope;
    widget.store.addListener(_syncScope);
  }

  @override
  void dispose() {
    widget.store.removeListener(_syncScope);
    super.dispose();
  }

  void _syncScope() {
    final scope = widget.store.workspaceScope;
    if (!mounted || _selectedScope == scope) return;
    setState(() => _selectedScope = scope);
  }

  void _selectScope(SprintWorkspaceScope scope) {
    if (_selectedScope == scope) return;
    widget.store.selectScope(scope);
  }

  Future<void> _createProject() async {
    if (!widget.store.canCreateProject) {
      sprintShowMessage(
        context: context,
        message: '활성 프로젝트는 최대 11개까지 만들 수 있습니다.',
        danger: true,
      );
      return;
    }
    final scope = await showSprintCreateProjectSheet(
      context: context,
      store: widget.store,
    );
    if (scope == null || !mounted) return;
    widget.store.selectScope(scope);
  }

  Future<void> _openAccount() async {
    await showSprintAccountSheet(context: context, store: widget.store);
    if (mounted) setState(() {});
  }

  Future<void> _editProject(SprintProject project) async {
    await showSprintProjectEditSheet(
      context: context,
      store: widget.store,
      project: project,
    );
    if (mounted) setState(() {});
  }

  void _close() {
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose();
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _finish(SprintWorkspacePanelDestination destination) async {
    final result = SprintWorkspacePanelResult(
      scope: _selectedScope,
      destination: destination,
    );
    final onResult = widget.onResult;
    if (onResult != null) {
      await onResult(result);
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  Future<void> _deleteProject(SprintProject project) async {
    if (_deletingProjectId != null) return;
    final colors = Theme.of(context).colorScheme;
    final confirmed = await sprintShowDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('프로젝트 삭제'),
          content: Text(
            '${project.name} 프로젝트와 포함된 업무와 일정 블록을 삭제합니다.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              ),
              child: const Text('프로젝트 삭제'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deletingProjectId = project.id);
    var deleted = false;
    try {
      deleted = await widget.store.deleteProject(project.id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _deletingProjectId = null);
      sprintShowMessage(
        context: context,
        message: '프로젝트를 삭제하지 못했습니다.',
        danger: true,
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _deletingProjectId = null;
      _selectedScope = const SprintWorkspaceScope.all();
    });
    if (!deleted) {
      sprintShowMessage(
        context: context,
        message: '연결된 Google Calendar 일정을 삭제하지 못했습니다.',
        danger: true,
      );
      return;
    }
    sprintShowMessage(
      context: context,
      message: '${project.name} 프로젝트를 삭제했습니다.',
    );
    if (widget.onResult == null) {
      Navigator.of(context).pop(
        const SprintWorkspacePanelResult(
          scope: SprintWorkspaceScope.all(),
          destination: SprintWorkspacePanelDestination.schedule,
        ),
      );
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 210);

    return SprintScaffold(
      extendBody: false,
      extendBodyBehindAppBar: false,
      body: SafeArea(
        minimum: const EdgeInsets.only(bottom: 8),
        child: AnimatedBuilder(
          animation: widget.store,
          builder: (context, child) {
            return Column(
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _WorkspaceRail(
                        store: widget.store,
                        selectedScope: _selectedScope,
                        duration: duration,
                        onSelect: _selectScope,
                        onCreate: _createProject,
                        onClose: _close,
                      ),
                      VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: colors.outlineVariant,
                      ),
                      Expanded(
                        child: _WorkspaceMenuPanel(
                          store: widget.store,
                          scope: _selectedScope,
                          duration: duration,
                          onClose: _close,
                          onDestination: _finish,
                          onDeleteProject: _deleteProject,
                          onEditProject: _editProject,
                          deletingProjectId: _deletingProjectId,
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: colors.outlineVariant),
                _SprintAccountArea(
                  store: widget.store,
                  railWidth: 86,
                  onTap: widget.store.accountBusy ? null : _openAccount,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _WorkspaceRail extends StatelessWidget {
  const _WorkspaceRail({
    required this.store,
    required this.selectedScope,
    required this.duration,
    required this.onSelect,
    required this.onCreate,
    required this.onClose,
  });

  final SprintModeStore store;
  final SprintWorkspaceScope selectedScope;
  final Duration duration;
  final ValueChanged<SprintWorkspaceScope> onSelect;
  final VoidCallback onCreate;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.surfaceContainerLowest,
      child: SizedBox(
        width: 86,
        child: Column(
          children: [
            const SizedBox(height: 8),
            IconButton(
              tooltip: '뒤로가기',
              onPressed: onClose,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  _RailButton(
                    icon: Icons.dashboard_rounded,
                    label: '전체 일정',
                    selected: selectedScope.type == SprintWorkspaceScopeType.all,
                    duration: duration,
                    onTap: () => onSelect(const SprintWorkspaceScope.all()),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Divider(color: colors.outlineVariant),
                  ),
                  ...store.projects.map(
                    (project) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _RailButton(
                        icon: project.icon,
                        label: project.name,
                        selected: selectedScope ==
                            SprintWorkspaceScope.project(project.id),
                        duration: duration,
                        accentColor: googleEventColor(
                          project.googleColorId,
                          colors.primary,
                        ),
                        onTap: () => onSelect(
                          SprintWorkspaceScope.project(project.id),
                        ),
                      ),
                    ),
                  ),
                  _RailButton(
                    icon: Icons.add_rounded,
                    label:
                        '새 프로젝트 ${store.activeProjectCount}/${SprintModeStore.maxActiveProjectCount}',
                    selected: false,
                    duration: duration,
                    onTap: store.accountBusy ? null : onCreate,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.duration,
    required this.onTap,
    this.accentColor,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Duration duration;
  final VoidCallback? onTap;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = accentColor ?? colors.primary;
    final foreground = accentColor == null
        ? colors.onPrimaryContainer
        : ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
            ? Colors.white
            : Colors.black;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(selected ? 18 : 26),
        onTap: onTap,
        child: AnimatedContainer(
          duration: duration,
          curve: Curves.easeOutCubic,
          height: 56,
          decoration: BoxDecoration(
            color: selected
                ? accent.withOpacity(0.22)
                : colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(selected ? 18 : 26),
            border: Border.all(
              color: selected ? accent : colors.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Icon(
            icon,
            color: selected ? foreground : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _WorkspaceMenuPanel extends StatelessWidget {
  const _WorkspaceMenuPanel({
    required this.store,
    required this.scope,
    required this.duration,
    required this.onClose,
    required this.onDestination,
    required this.onDeleteProject,
    required this.onEditProject,
    required this.deletingProjectId,
  });

  final SprintModeStore store;
  final SprintWorkspaceScope scope;
  final Duration duration;
  final VoidCallback onClose;
  final ValueChanged<SprintWorkspacePanelDestination> onDestination;
  final ValueChanged<SprintProject> onDeleteProject;
  final ValueChanged<SprintProject> onEditProject;
  final String? deletingProjectId;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final project = scope.type == SprintWorkspaceScopeType.project
        ? store.projectById(scope.projectId)
        : null;
    final title = project?.name ?? '전체 일정';
    final subtitle = project == null
        ? '모든 활성 프로젝트의 일정을 한 번에 표시합니다.'
        : _projectSubtitle(project.id);

    return ColoredBox(
      color: colors.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 10, 12),
            child: Row(
              children: [
                Expanded(
                  child: AnimatedSwitcher(
                    duration: duration,
                    child: Column(
                      key: ValueKey<String>(scope.storageValue),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
                if (project != null && project.custom)
                  PopupMenuButton<String>(
                    tooltip: '프로젝트 메뉴',
                    enabled: deletingProjectId == null,
                    onSelected: (value) {
                      if (value == 'edit') onEditProject(project);
                      if (value == 'manage') {
                        onDestination(SprintWorkspacePanelDestination.management);
                      }
                      if (value == 'complete') {
                        onDestination(SprintWorkspacePanelDestination.completion);
                      }
                      if (value == 'delete') onDeleteProject(project);
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem<String>(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined),
                            SizedBox(width: 10),
                            Text('프로젝트 수정'),
                          ],
                        ),
                      ),
                      const PopupMenuItem<String>(
                        value: 'manage',
                        child: Row(
                          children: [
                            Icon(Icons.tune_rounded),
                            SizedBox(width: 10),
                            Text('프로젝트 관리'),
                          ],
                        ),
                      ),
                      const PopupMenuItem<String>(
                        value: 'complete',
                        child: Row(
                          children: [
                            Icon(Icons.verified_outlined),
                            SizedBox(width: 10),
                            Text('프로젝트 완료'),
                          ],
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline_rounded, color: colors.error),
                            const SizedBox(width: 10),
                            Text(
                              '프로젝트 삭제',
                              style: TextStyle(color: colors.error),
                            ),
                          ],
                        ),
                      ),
                    ],
                    icon: deletingProjectId == project.id
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.more_vert_rounded),
                  ),
                IconButton(
                  tooltip: '닫기',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.outlineVariant),
          Expanded(
            child: AnimatedSwitcher(
              duration: duration,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: ListView(
                key: ValueKey<String>('menu-${scope.storageValue}'),
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 20),
                children: [
                  _MenuActionTile(
                    icon: Icons.calendar_view_day_rounded,
                    title: '오늘 일정',
                    subtitle: '선택 범위의 일정과 외부 일정을 표시합니다.',
                    onTap: () => onDestination(
                      SprintWorkspacePanelDestination.schedule,
                    ),
                  ),
                  if (project != null) ...[
                    const SizedBox(height: 8),
                    _MenuActionTile(
                      icon: Icons.donut_large_rounded,
                      title: '종합 요약',
                      subtitle: '진행률과 완료 전망을 확인합니다.',
                      onTap: () => onDestination(
                        SprintWorkspacePanelDestination.summary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _MenuActionTile(
                      icon: Icons.route_rounded,
                      title: '진행 경로',
                      subtitle: '완료·진행·대기 업무 순서를 확인합니다.',
                      onTap: () => onDestination(
                        SprintWorkspacePanelDestination.path,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _MenuActionTile(
                      icon: Icons.tune_rounded,
                      title: '프로젝트 관리',
                      subtitle: '업무·일정·충돌·종료 흐름을 관리합니다.',
                      onTap: () => onDestination(
                        SprintWorkspacePanelDestination.management,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  _MenuActionTile(
                    icon: Icons.warning_amber_rounded,
                    title: '확인 필요',
                    subtitle: '${_attentionCount()}개의 항목이 있습니다.',
                    onTap: () => onDestination(
                      SprintWorkspacePanelDestination.attention,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _MenuActionTile(
                    icon: Icons.inventory_2_outlined,
                    title: '완료 및 보관함',
                    subtitle: '종료 보고서와 보관 프로젝트를 확인합니다.',
                    onTap: () => onDestination(
                      SprintWorkspacePanelDestination.archive,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '업무 추가',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  SprintSurface(
                    backgroundColor: colors.surfaceContainerHigh,
                    child: Text(
                      project == null
                          ? '전체 일정의 업무 추가 버튼에서 프로젝트, 우선순위, 날짜 범위를 선택합니다.'
                          : '${project.name} 일정의 날짜별 업무 추가 버튼에서 업무를 생성합니다.',
                      style: TextStyle(color: colors.onSurfaceVariant),
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

  String _projectSubtitle(String projectId) {
    final summary = store.summaryFor(projectId);
    if (summary.project.hasNotStarted) {
      return '${sprintFormatShortDate(summary.project.targetStartDate!)} 시작 예정 · 확인 ${summary.attentionCount}';
    }
    return '진행 ${(summary.progressRatio * 100).round()}% · 오늘 ${summary.todayTaskCount} · 확인 ${summary.attentionCount}';
  }

  int _attentionCount() {
    if (scope.type == SprintWorkspaceScopeType.project) {
      return store.attentionItems
          .where((item) => item.projectId == scope.projectId)
          .length;
    }
    final activeProjectIds = store.projects.map((project) => project.id).toSet();
    return store.attentionItems
        .where((item) => activeProjectIds.contains(item.projectId))
        .length;
  }
}

class _MenuActionTile extends StatelessWidget {
  const _MenuActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: colors.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _SprintAccountArea extends StatelessWidget {
  const _SprintAccountArea({
    required this.store,
    required this.railWidth,
    required this.onTap,
  });

  final SprintModeStore store;
  final double railWidth;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 180);
    final profile = store.defaultCalendarProfile;
    final account = store.accountForProfile(profile?.id);
    final profileCount = store.calendarProfiles.length;
    final title = profile?.label.trim().isNotEmpty == true
        ? profile!.label.trim()
        : 'Google 캘린더 계정';
    final email = account?.email.trim() ?? '';
    final calendarLabel = profile?.calendarId.trim().isNotEmpty == true
        ? profile!.calendarId.trim()
        : '캘린더 미설정';
    final accountSummary = email.isEmpty
        ? calendarLabel
        : '$email · $calendarLabel';
    final subtitle = profileCount <= 1
        ? accountSummary
        : '기본 · $accountSummary · 총 $profileCount개';
    final initial = title.isEmpty ? 'G' : title.substring(0, 1).toUpperCase();

    return ColoredBox(
      color: colors.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 10, 8),
        child: Row(
          children: [
            SizedBox(
              width: railWidth,
              child: AnimatedSwitcher(
                duration: duration,
                child: CircleAvatar(
                  key: ValueKey<String>(profile?.id ?? 'no-profile'),
                  radius: 24,
                  backgroundColor: colors.primaryContainer,
                  child: Text(
                    initial,
                    style: TextStyle(
                      color: colors.onPrimaryContainer,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Material(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: duration,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0.04, 0),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            ),
                            child: Column(
                              key: ValueKey<String>(profile?.id ?? 'empty'),
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        AnimatedSwitcher(
                          duration: duration,
                          child: store.accountBusy
                              ? const SizedBox(
                                  key: ValueKey<String>('account-busy'),
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                  ),
                                )
                              : Icon(
                                  profileCount > 1
                                      ? Icons.calendar_view_month_rounded
                                      : Icons.calendar_month_outlined,
                                  key: ValueKey<String>(
                                    'account-${store.defaultCalendarProfileId}',
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SprintCreateProjectSheet extends StatefulWidget {
  const _SprintCreateProjectSheet({required this.store});

  final SprintModeStore store;

  @override
  State<_SprintCreateProjectSheet> createState() =>
      _SprintCreateProjectSheetState();
}

class _SprintCreateProjectSheetState
    extends State<_SprintCreateProjectSheet> {
  final TextEditingController _nameController = TextEditingController();
  final FocusNode _nameFocusNode = FocusNode();
  String _iconKey = 'folder';
  String? _googleColorId;
  DateTime? _targetStartDate;
  DateTime? _targetDate;
  bool _indefinite = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final available = widget.store.availableProjectColorIds();
    _googleColorId = available.isEmpty ? null : available.first;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nameFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  void _setIndefinite(bool value) {
    setState(() {
      _indefinite = value;
      if (value) {
        _targetStartDate = null;
        _targetDate = null;
      }
    });
  }

  Future<void> _selectTargetStartDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selected = await sprintShowDatePicker(
      context: context,
      initialDate: _targetStartDate ?? today,
      firstDate: today,
      lastDate: DateTime(now.year + 10, 12, 31),
    );
    if (selected == null || !mounted) return;
    setState(() => _targetStartDate = selected);
  }

  Future<void> _selectTargetDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final minimum = _targetStartDate ?? today;
    var initial = _targetDate ?? minimum.add(const Duration(days: 7));
    if (initial.isBefore(minimum)) initial = minimum;
    final selected = await sprintShowDatePicker(
      context: context,
      initialDate: initial,
      firstDate: minimum,
      lastDate: DateTime(now.year + 10, 12, 31),
    );
    if (selected == null || !mounted) return;
    setState(() => _targetDate = selected);
  }

  Future<void> _create() async {
    if (_saving) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      sprintShowMessage(
        context: context,
        message: '프로젝트 이름을 입력하세요.',
      );
      _nameFocusNode.requestFocus();
      return;
    }
    if (_googleColorId == null) {
      sprintShowMessage(
        context: context,
        message: '사용 가능한 프로젝트 색상이 없습니다.',
        danger: true,
      );
      return;
    }
    if (_targetStartDate != null &&
        _targetDate != null &&
        _targetStartDate!.isAfter(_targetDate!)) {
      sprintShowMessage(
        context: context,
        message: '목표 시작일은 목표 완료일보다 늦을 수 없습니다.',
      );
      return;
    }
    setState(() => _saving = true);
    final project = await widget.store.createProject(
      name: name,
      iconKey: _iconKey,
      googleColorId: _googleColorId!,
      targetStartDate: _targetStartDate,
      targetDate: _targetDate,
    );
    if (!mounted) return;
    if (project == null) {
      setState(() => _saving = false);
      sprintShowMessage(
        context: context,
        message: widget.store.projectInputError ?? '프로젝트 정보를 확인하세요.',
      );
      return;
    }
    sprintShowMessage(
      context: context,
      message: '${project.name} 프로젝트를 생성했습니다.',
    );
    Navigator.of(context).pop(SprintWorkspaceScope.project(project.id));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 180);
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final invalidRange = _targetStartDate != null &&
        _targetDate != null &&
        _targetStartDate!.isAfter(_targetDate!);
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
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '새 프로젝트',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 20),
                const Text(
                  '프로젝트 이름',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameController,
                  focusNode: _nameFocusNode,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _create(),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: colors.surfaceContainerHigh,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  '아이콘',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: sprintProjectIcons.entries.map((entry) {
                    final selected = _iconKey == entry.key;
                    return AnimatedContainer(
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      decoration: BoxDecoration(
                        color: selected
                            ? colors.primaryContainer
                            : colors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: selected
                              ? colors.primary
                              : colors.outlineVariant,
                        ),
                      ),
                      child: IconButton(
                        tooltip: entry.key,
                        onPressed: _saving
                            ? null
                            : () => setState(() => _iconKey = entry.key),
                        icon: Icon(entry.value),
                      ),
                    );
                  }).toList(growable: false),
                ),
                const SizedBox(height: 20),
                const Text(
                  '프로젝트 색상',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                GoogleEventColorPicker(
                  selectedId: _googleColorId,
                  duration: duration,
                  disabledColorIds:
                      widget.store.projectColorOwners().keys.toSet(),
                  disabledLabels: widget.store.projectColorOwners(),
                  onSelected: _saving
                      ? (_) {}
                      : (colorId) {
                          setState(() => _googleColorId = colorId);
                        },
                ),
                const SizedBox(height: 20),
                const Text(
                  '목표 기간',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                AnimatedContainer(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: _indefinite
                        ? colors.primaryContainer
                        : colors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _indefinite
                          ? colors.primary
                          : colors.outlineVariant,
                    ),
                  ),
                  child: SwitchListTile(
                    value: _indefinite,
                    onChanged: _saving ? null : _setIndefinite,
                    title: const Text(
                      '무기한 프로젝트',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    secondary: const Icon(Icons.all_inclusive_rounded),
                  ),
                ),
                AnimatedSize(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  child: _indefinite
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Column(
                            children: [
                              _CreateProjectDateTile(
                                title: '목표 시작일',
                                icon: Icons.play_circle_outline_rounded,
                                value: _targetStartDate,
                                duration: duration,
                                onTap: _saving ? null : _selectTargetStartDate,
                                onClear: _saving || _targetStartDate == null
                                    ? null
                                    : () => setState(
                                          () => _targetStartDate = null,
                                        ),
                              ),
                              const SizedBox(height: 10),
                              _CreateProjectDateTile(
                                title: '목표 완료일',
                                icon: Icons.flag_outlined,
                                value: _targetDate,
                                duration: duration,
                                onTap: _saving ? null : _selectTargetDate,
                                onClear: _saving || _targetDate == null
                                    ? null
                                    : () => setState(() => _targetDate = null),
                              ),
                            ],
                          ),
                        ),
                ),
                AnimatedSize(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  child: invalidRange
                      ? Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            '목표 시작일은 목표 완료일보다 늦을 수 없습니다.',
                            style: TextStyle(
                              color: colors.error,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed:
                      _saving || invalidRange || _googleColorId == null
                          ? null
                          : _create,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                  child: AnimatedSwitcher(
                    duration: duration,
                    child: _saving
                        ? const SizedBox(
                            key: ValueKey<String>('saving'),
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : const Text(
                            '프로젝트 생성',
                            key: ValueKey<String>('create'),
                          ),
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

class _CreateProjectDateTile extends StatelessWidget {
  const _CreateProjectDateTile({
    required this.title,
    required this.icon,
    required this.value,
    required this.duration,
    required this.onTap,
    required this.onClear,
  });

  final String title;
  final IconData icon;
  final DateTime? value;
  final Duration duration;
  final VoidCallback? onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SprintSurface(
      padding: EdgeInsets.zero,
      backgroundColor: colors.surfaceContainerHigh,
      child: ListTile(
        minTileHeight: 58,
        leading: Icon(icon),
        title: Text(
          title,
          style: TextStyle(
            color: colors.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: AnimatedSwitcher(
          duration: duration,
          child: Text(
            value == null ? '설정하지 않음' : sprintFormatShortDate(value!),
            key: ValueKey<String>(
              '$title-${value?.toIso8601String() ?? 'none'}',
            ),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (value != null)
              IconButton(
                tooltip: '$title 제거',
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded),
              ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _SprintAccountSheet extends StatefulWidget {
  const _SprintAccountSheet({required this.store});

  final SprintModeStore store;

  @override
  State<_SprintAccountSheet> createState() => _SprintAccountSheetState();
}

class _SprintAccountSheetState extends State<_SprintAccountSheet> {
  String? _busyProfileId;
  bool _addingCurrentAccount = false;
  bool _addingOtherAccount = false;

  bool get _busy =>
      _addingCurrentAccount ||
      _addingOtherAccount ||
      _busyProfileId != null ||
      widget.store.accountBusy;

  String _errorMessage(Object error) {
    if (error is GoogleAccountMismatchException) {
      return '선택한 Google 계정이 저장된 계정과 일치하지 않습니다.';
    }
    if (error is StateError) {
      if (error.message == 'calendar_profile_in_use') {
        return '연결된 스프린트 업무가 있어 이 캘린더를 삭제할 수 없습니다.';
      }
      if (error.message == 'interactive_google_auth_not_supported') {
        return '이 환경에서는 Google 계정 선택을 시작할 수 없습니다.';
      }
      if (error.message == 'calendar_profile_not_found') {
        return '저장된 캘린더 정보를 찾지 못했습니다.';
      }
      if (error.message == 'calendar_profile_duplicate') {
        return '같은 Google 계정과 Calendar ID 조합이 이미 등록돼 있습니다.';
      }
      if (error.message == 'calendar_write_access_required') {
        return '선택한 Google 계정에 이 캘린더의 일정 변경 권한이 없습니다.';
      }
      if (error.message == 'account_operation_in_progress') {
        return '다른 Google 계정 작업이 진행 중입니다.';
      }
    }
    final message = error.toString().toLowerCase();
    if (message.contains('status: 403') || message.contains('status 403')) {
      return '선택한 Google 계정에 이 캘린더의 읽기 또는 쓰기 권한이 없습니다.';
    }
    if (message.contains('status: 404') || message.contains('status 404')) {
      return '캘린더를 찾지 못했거나 선택한 Google 계정으로 접근할 수 없습니다.';
    }
    return 'Google 캘린더 작업을 완료하지 못했습니다.';
  }

  Future<void> _addProfile({
    required bool forceAccountSelection,
  }) async {
    if (_busy) return;
    final draft = await _showSprintCalendarProfileEditor(context);
    if (draft == null || !mounted) return;
    setState(() {
      if (forceAccountSelection) {
        _addingOtherAccount = true;
      } else {
        _addingCurrentAccount = true;
      }
    });
    try {
      final firstProfile = widget.store.calendarProfiles.isEmpty;
      await widget.store.addGoogleCalendarProfile(
        label: draft.label,
        calendarId: draft.calendarId,
        locked: draft.locked,
        forceAccountSelection: forceAccountSelection,
        makeActive: firstProfile,
      );
      if (!mounted) return;
      sprintShowMessage(
        context: context,
        message: firstProfile
            ? 'Google 캘린더를 연결하고 기본 캘린더로 설정했습니다.'
            : 'Google 캘린더를 추가했습니다.',
      );
    } catch (error) {
      if (!mounted) return;
      sprintShowMessage(
        context: context,
        message: _errorMessage(error),
        danger: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _addingCurrentAccount = false;
          _addingOtherAccount = false;
        });
      }
    }
  }

  Future<void> _setDefault(SprintCalendarProfile profile) async {
    if (_busy || profile.id == widget.store.defaultCalendarProfileId) return;
    setState(() => _busyProfileId = profile.id);
    try {
      await widget.store.setDefaultCalendarProfile(profile.id);
      if (!mounted) return;
      sprintShowMessage(
        context: context,
        message: '${profile.label} 캘린더를 기본 업무 대상으로 설정했습니다.',
      );
    } catch (error) {
      if (!mounted) return;
      sprintShowMessage(
        context: context,
        message: _errorMessage(error),
        danger: true,
      );
    } finally {
      if (mounted) setState(() => _busyProfileId = null);
    }
  }

  Future<void> _syncProfile(SprintCalendarProfile profile) async {
    if (_busy) return;
    setState(() => _busyProfileId = profile.id);
    try {
      await widget.store.syncCalendarProfile(profile.id);
      if (!mounted) return;
      final state = widget.store.calendarStateForProfile(profile.id);
      final success = state == SprintCalendarConnectionState.connected;
      sprintShowMessage(
        context: context,
        message: success
            ? '${profile.label} 캘린더를 동기화했습니다.'
            : '${profile.label} 캘린더 동기화를 완료하지 못했습니다.',
        danger: !success,
      );
    } catch (error) {
      if (!mounted) return;
      sprintShowMessage(
        context: context,
        message: _errorMessage(error),
        danger: true,
      );
    } finally {
      if (mounted) setState(() => _busyProfileId = null);
    }
  }

  Future<void> _authenticateProfile(SprintCalendarProfile profile) async {
    if (_busy) return;
    setState(() => _busyProfileId = profile.id);
    try {
      await widget.store.authenticateCalendarProfile(
        profile.id,
        forceAccountSelection: true,
      );
      await widget.store.syncCalendarProfile(
        profile.id,
        interactive: false,
      );
      if (!mounted) return;
      sprintShowMessage(
        context: context,
        message: '${profile.label} Google 계정을 인증하고 동기화했습니다.',
      );
    } catch (error) {
      if (!mounted) return;
      sprintShowMessage(
        context: context,
        message: _errorMessage(error),
        danger: true,
      );
    } finally {
      if (mounted) setState(() => _busyProfileId = null);
    }
  }

  Future<void> _editProfile(SprintCalendarProfile profile) async {
    if (_busy) return;
    final draft = await _showSprintCalendarProfileEditor(
      context,
      profile: profile,
      calendarIdReadOnly: true,
    );
    if (draft == null || !mounted) return;
    setState(() => _busyProfileId = profile.id);
    try {
      await widget.store.updateCalendarProfile(
        profileId: profile.id,
        label: draft.label,
        locked: draft.locked,
      );
      if (!mounted) return;
      sprintShowMessage(
        context: context,
        message: '캘린더 설정을 저장했습니다.',
      );
    } catch (error) {
      if (!mounted) return;
      sprintShowMessage(
        context: context,
        message: _errorMessage(error),
        danger: true,
      );
    } finally {
      if (mounted) setState(() => _busyProfileId = null);
    }
  }

  Future<void> _removeProfile(SprintCalendarProfile profile) async {
    if (_busy) return;
    final colors = Theme.of(context).colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 280);
    final confirmed = await sprintShowDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('저장된 캘린더 삭제'),
              content: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: duration,
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, 10 * (1 - value)),
                      child: Transform.scale(
                        scale: 0.97 + 0.03 * value,
                        alignment: Alignment.topCenter,
                        child: child,
                      ),
                    ),
                  );
                },
                child: Text(
                  '${profile.label} 캘린더를 저장 목록에서 삭제할까요? 다른 캘린더는 유지됩니다.',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('취소'),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.error,
                    foregroundColor: colors.onError,
                  ),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('삭제'),
                ),
              ],
            );
          },
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() => _busyProfileId = profile.id);
    try {
      await widget.store.removeCalendarProfile(profile.id);
      if (!mounted) return;
      sprintShowMessage(
        context: context,
        message: '저장된 캘린더를 삭제했습니다.',
      );
    } catch (error) {
      if (!mounted) return;
      sprintShowMessage(
        context: context,
        message: _errorMessage(error),
        danger: true,
      );
    } finally {
      if (mounted) setState(() => _busyProfileId = null);
    }
  }

  Future<void> _syncAll() async {
    if (_busy || widget.store.calendarProfiles.isEmpty) return;
    setState(() => _busyProfileId = 'all');
    try {
      await widget.store.syncGoogleCalendar();
      if (!mounted) return;
      final success = widget.store.calendarState ==
          SprintCalendarConnectionState.connected;
      sprintShowMessage(
        context: context,
        message: success
            ? '연결된 Google 캘린더를 모두 동기화했습니다.'
            : '일부 Google 캘린더에 재인증 또는 동기화 확인이 필요합니다.',
        danger: !success,
      );
    } catch (error) {
      if (!mounted) return;
      sprintShowMessage(
        context: context,
        message: _errorMessage(error),
        danger: true,
      );
    } finally {
      if (mounted) setState(() => _busyProfileId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 260);
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, child) {
        final profiles = widget.store.calendarProfiles;
        final active = widget.store.defaultCalendarProfile;
        final activeAccount = widget.store.accountForProfile(active?.id);
        final activeEmail = activeAccount?.email.trim() ?? '';
        final calendarState = widget.store.calendarState;
        String? verificationMessage;
        IconData? verificationIcon;
        Color? verificationBackground;
        Color? verificationForeground;
        if (calendarState == SprintCalendarConnectionState.switching) {
          verificationMessage = 'Google 계정과 캘린더 권한을 확인하고 있습니다.';
          verificationIcon = Icons.verified_user_outlined;
          verificationBackground = colors.secondaryContainer;
          verificationForeground = colors.onSecondaryContainer;
        } else if (calendarState ==
            SprintCalendarConnectionState.reauthenticationRequired) {
          verificationMessage = '일부 Google 캘린더 계정에 재인증이 필요합니다.';
          verificationIcon = Icons.lock_person_outlined;
          verificationBackground = colors.tertiaryContainer;
          verificationForeground = colors.onTertiaryContainer;
        } else if (calendarState == SprintCalendarConnectionState.failed) {
          verificationMessage = '일부 Google 캘린더 동기화에 실패했습니다.';
          verificationIcon = Icons.error_outline_rounded;
          verificationBackground = colors.errorContainer;
          verificationForeground = colors.onErrorContainer;
        }
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
                      'Google 캘린더 계정',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '모든 캘린더는 업무 생성, 수정, 삭제와 독립 동기화를 동일하게 지원합니다. 기본 캘린더는 신규 업무의 최초 선택값입니다.',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 16),
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
                      child: active == null
                          ? SprintSurface(
                              key: const ValueKey<String>('no-default-profile'),
                              backgroundColor: colors.surfaceContainerHigh,
                              child: const Row(
                                children: [
                                  Icon(Icons.event_busy_outlined),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      '기본 Google 캘린더가 설정되지 않았습니다.',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : SprintSurface(
                              key: ValueKey<String>('default-${active.id}'),
                              backgroundColor: colors.primaryContainer,
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: colors.primary,
                                    foregroundColor: colors.onPrimary,
                                    child: const Icon(Icons.star_rounded),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          active.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: colors.onPrimaryContainer,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          activeEmail.isNotEmpty
                                              ? '$activeEmail · ${active.calendarId}'
                                              : 'Google 계정 연결 필요 · ${active.calendarId}',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: colors.onPrimaryContainer,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                    AnimatedSize(
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      child: AnimatedSwitcher(
                        duration: duration,
                        child: verificationMessage == null
                            ? const SizedBox.shrink(
                                key: ValueKey<String>('calendar-state-idle'),
                              )
                            : Padding(
                                key: ValueKey<String>(
                                  'calendar-state-${calendarState.name}',
                                ),
                                padding: const EdgeInsets.only(top: 10),
                                child: SprintSurface(
                                  backgroundColor: verificationBackground,
                                  child: Row(
                                    children: [
                                      AnimatedSwitcher(
                                        duration: duration,
                                        child: calendarState ==
                                                SprintCalendarConnectionState
                                                    .switching
                                            ? SizedBox(
                                                key: const ValueKey<String>(
                                                  'calendar-state-progress',
                                                ),
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2.2,
                                                  color:
                                                      verificationForeground,
                                                ),
                                              )
                                            : Icon(
                                                verificationIcon,
                                                key: ValueKey<String>(
                                                  'calendar-state-icon-${calendarState.name}',
                                                ),
                                                color: verificationForeground,
                                              ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          verificationMessage,
                                          style: TextStyle(
                                            color: verificationForeground,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                      ),
                    ),
                    if (profiles.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _syncAll,
                        icon: AnimatedSwitcher(
                          duration: duration,
                          child: _busyProfileId == 'all'
                              ? const SizedBox(
                                  key: ValueKey<String>('sync-all-busy'),
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                  ),
                                )
                              : const Icon(
                                  Icons.sync_rounded,
                                  key: ValueKey<String>('sync-all-ready'),
                                ),
                        ),
                        label: const Text('모든 캘린더 동기화'),
                      ),
                    ],
                    const SizedBox(height: 22),
                    _AnimatedCalendarProfileSection(
                      title: '연결된 캘린더',
                      emptyText: '연결된 Google 캘린더가 없습니다.',
                      profiles: profiles,
                      duration: duration,
                      builder: (profile) {
                        final state =
                            widget.store.calendarStateForProfile(profile.id);
                        return _SprintCalendarProfileCard(
                          profile: profile,
                          account: widget.store.accountForProfile(profile.id),
                          active: profile.id ==
                              widget.store.defaultCalendarProfileId,
                          busy: _busyProfileId == profile.id ||
                              widget.store.accountBusy,
                          duration: duration,
                          connectionState: state,
                          error: widget.store.calendarErrorForProfile(profile.id),
                          onSetDefault:
                              _busy ? null : () => _setDefault(profile),
                          onAuthenticate:
                              _busy ? null : () => _authenticateProfile(profile),
                          onSync: _busy ? null : () => _syncProfile(profile),
                          onEdit: _busy ? null : () => _editProfile(profile),
                          onDelete:
                              _busy ? null : () => _removeProfile(profile),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _addProfile(
                                forceAccountSelection: false,
                              ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      icon: AnimatedSwitcher(
                        duration: duration,
                        child: _addingCurrentAccount
                            ? const SizedBox(
                                key: ValueKey<String>('adding-current'),
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                ),
                              )
                            : const Icon(
                                Icons.event_available_outlined,
                                key: ValueKey<String>('add-current'),
                              ),
                      ),
                      label: const Text('현재 Google 계정 캘린더 추가'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _addProfile(
                                forceAccountSelection: true,
                              ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      icon: AnimatedSwitcher(
                        duration: duration,
                        child: _addingOtherAccount
                            ? const SizedBox(
                                key: ValueKey<String>('adding-other'),
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                ),
                              )
                            : const Icon(
                                Icons.person_add_alt_1_rounded,
                                key: ValueKey<String>('add-other'),
                              ),
                      ),
                      label: const Text('다른 Google 계정 캘린더 추가'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AnimatedCalendarProfileSection extends StatelessWidget {
  const _AnimatedCalendarProfileSection({
    required this.title,
    required this.emptyText,
    required this.profiles,
    required this.duration,
    required this.builder,
  });

  final String title;
  final String emptyText;
  final List<SprintCalendarProfile> profiles;
  final Duration duration;
  final Widget Function(SprintCalendarProfile profile) builder;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final contentKey = profiles.map((profile) => profile.id).join('|');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        AnimatedSize(
          duration: duration,
          curve: Curves.easeOutCubic,
          child: AnimatedSwitcher(
            duration: duration,
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.04),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: profiles.isEmpty
                ? SprintSurface(
                    key: ValueKey<String>('empty-$title'),
                    backgroundColor: colors.surfaceContainerHigh,
                    child: Text(emptyText),
                  )
                : Column(
                    key: ValueKey<String>('$title-$contentKey'),
                    children: [
                      for (var index = 0; index < profiles.length; index += 1)
                        TweenAnimationBuilder<double>(
                          key: ValueKey<String>(profiles[index].id),
                          tween: Tween<double>(begin: 0, end: 1),
                          duration: duration == Duration.zero
                              ? Duration.zero
                              : Duration(
                                  milliseconds:
                                      duration.inMilliseconds + index * 35,
                                ),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, child) {
                            return Opacity(
                              opacity: value,
                              child: Transform.translate(
                                offset: Offset(0, 12 * (1 - value)),
                                child: child,
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: builder(profiles[index]),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _SprintCalendarProfileCard extends StatelessWidget {
  const _SprintCalendarProfileCard({
    required this.profile,
    required this.account,
    required this.active,
    required this.busy,
    required this.duration,
    required this.connectionState,
    required this.error,
    required this.onSetDefault,
    required this.onAuthenticate,
    required this.onSync,
    required this.onEdit,
    required this.onDelete,
  });

  final SprintCalendarProfile profile;
  final SprintGoogleAccount? account;
  final bool active;
  final bool busy;
  final Duration duration;
  final SprintCalendarConnectionState connectionState;
  final String? error;
  final VoidCallback? onSetDefault;
  final VoidCallback? onAuthenticate;
  final VoidCallback? onSync;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accountEmail = account?.email.trim() ?? '';
    final requiresAuthentication = connectionState ==
        SprintCalendarConnectionState.reauthenticationRequired;
    final syncing = connectionState == SprintCalendarConnectionState.syncing ||
        connectionState == SprintCalendarConnectionState.switching;
    final background = active
        ? colors.secondaryContainer
        : colors.surfaceContainerHigh;
    final borderColor = active ? colors.secondary : colors.outlineVariant;
    final statusColor = requiresAuthentication
        ? colors.tertiaryContainer
        : connectionState == SprintCalendarConnectionState.failed
            ? colors.errorContainer
            : colors.surfaceContainerHighest;
    final statusForeground = requiresAuthentication
        ? colors.onTertiaryContainer
        : connectionState == SprintCalendarConnectionState.failed
            ? colors.onErrorContainer
            : colors.onSurfaceVariant;
    return AnimatedContainer(
      duration: duration,
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: borderColor,
          width: active ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedSwitcher(
                duration: duration,
                transitionBuilder: (child, animation) {
                  return ScaleTransition(scale: animation, child: child);
                },
                child: Icon(
                  active
                      ? Icons.star_rounded
                      : Icons.calendar_month_outlined,
                  key: ValueKey<bool>(active),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            profile.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        AnimatedContainer(
                          duration: duration,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: active
                                ? colors.secondary
                                : colors.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            active ? '기본' : '추가',
                            style: TextStyle(
                              color: active
                                  ? colors.onSecondary
                                  : colors.onSurfaceVariant,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    AnimatedSwitcher(
                      duration: duration,
                      child: Text(
                        accountEmail.isNotEmpty
                            ? accountEmail
                            : 'Google 계정 연결 필요',
                        key: ValueKey<String>(
                          '${profile.id}-${accountEmail.toLowerCase()}',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      profile.calendarId,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              AnimatedSwitcher(
                duration: duration,
                child: busy
                    ? const SizedBox(
                        key: ValueKey<String>('profile-busy'),
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    : IconButton(
                        key: const ValueKey<String>('profile-edit'),
                        tooltip: '캘린더 설정',
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined),
                      ),
              ),
              IconButton(
                tooltip: '저장 목록에서 삭제',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AnimatedContainer(
            duration: duration,
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                AnimatedSwitcher(
                  duration: duration,
                  child: syncing
                      ? SizedBox(
                          key: const ValueKey<String>('profile-state-progress'),
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: statusForeground,
                          ),
                        )
                      : Icon(
                          requiresAuthentication
                              ? Icons.lock_person_outlined
                              : connectionState ==
                                      SprintCalendarConnectionState.failed
                                  ? Icons.error_outline_rounded
                                  : connectionState ==
                                          SprintCalendarConnectionState.connected
                                      ? Icons.cloud_done_rounded
                                      : Icons.cloud_queue_rounded,
                          key: ValueKey<SprintCalendarConnectionState>(
                            connectionState,
                          ),
                          size: 18,
                          color: statusForeground,
                        ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _profileConnectionLabel(connectionState),
                    style: TextStyle(
                      color: statusForeground,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: duration,
            curve: Curves.easeOutCubic,
            child: AnimatedSwitcher(
              duration: duration,
              child: error?.trim().isNotEmpty == true
                  ? Padding(
                      key: ValueKey<String>('profile-error-${profile.id}-$error'),
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        '동기화 오류: $error',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(
                      key: ValueKey<String>('profile-error-none'),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!active)
                FilledButton.tonalIcon(
                  onPressed: busy ? null : onSetDefault,
                  icon: const Icon(Icons.star_outline_rounded),
                  label: const Text('기본으로 설정'),
                ),
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : requiresAuthentication
                        ? onAuthenticate
                        : onSync,
                icon: AnimatedSwitcher(
                  duration: duration,
                  child: busy || syncing
                      ? const SizedBox(
                          key: ValueKey<String>('profile-action-progress'),
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          requiresAuthentication
                              ? Icons.lock_open_rounded
                              : Icons.sync_rounded,
                          key: ValueKey<bool>(requiresAuthentication),
                        ),
                ),
                label: Text(requiresAuthentication ? '재인증' : '동기화'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _profileConnectionLabel(SprintCalendarConnectionState state) {
  switch (state) {
    case SprintCalendarConnectionState.notConnected:
      return '연결되지 않음';
    case SprintCalendarConnectionState.cached:
      return '인증됨';
    case SprintCalendarConnectionState.reauthenticationRequired:
      return '재인증 필요';
    case SprintCalendarConnectionState.switching:
      return '계정 확인 중';
    case SprintCalendarConnectionState.syncing:
      return '동기화 중';
    case SprintCalendarConnectionState.connected:
      return '동기화 완료';
    case SprintCalendarConnectionState.failed:
      return '동기화 실패';
  }
}

class _SprintCalendarProfileDraft {
  const _SprintCalendarProfileDraft({
    required this.label,
    required this.calendarId,
    required this.locked,
  });

  final String label;
  final String calendarId;
  final bool locked;
}

Future<_SprintCalendarProfileDraft?> _showSprintCalendarProfileEditor(
  BuildContext context, {
  SprintCalendarProfile? profile,
  bool calendarIdReadOnly = false,
}) async {
  final labelController = TextEditingController(text: profile?.label ?? '');
  final calendarController = TextEditingController(
    text: profile?.calendarId ?? 'primary',
  );
  var locked = profile?.locked ?? false;
  final result = await sprintShowDialog<_SprintCalendarProfileDraft>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(
              profile == null ? 'Google 캘린더 연결' : '캘린더 설정',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: labelController,
                    decoration: const InputDecoration(
                      labelText: '캘린더 이름',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: calendarController,
                    readOnly: calendarIdReadOnly || locked,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Google Calendar ID',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Calendar ID 잠금'),
                    value: locked,
                    onChanged: (value) => setState(() => locked = value),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () {
                  final calendarId = calendarController.text.trim();
                  if (calendarId.isEmpty) {
                    sprintShowMessage(
                      context: context,
                      message: 'Google Calendar ID를 입력하세요.',
                      danger: true,
                    );
                    return;
                  }
                  Navigator.of(dialogContext).pop(
                    _SprintCalendarProfileDraft(
                      label: labelController.text.trim(),
                      calendarId: calendarId,
                      locked: locked,
                    ),
                  );
                },
                child: const Text('확인'),
              ),
            ],
          );
        },
      );
    },
  );
  labelController.dispose();
  calendarController.dispose();
  return result;
}

