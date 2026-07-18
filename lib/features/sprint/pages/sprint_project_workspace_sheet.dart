import 'package:flutter/material.dart';

import '../../../app/auth/google_auth_session.dart';
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
      pageBuilder: (_, __, ___) => SprintWorkspacePanelPage(store: store),
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
  final colors = Theme.of(context).colorScheme;
  return showModalBottomSheet<SprintWorkspaceScope>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: colors.surface,
    barrierColor: colors.scrim,
    builder: (_) => _SprintCreateProjectSheet(store: store),
  );
}

Future<void> showSprintAccountSheet({
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
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: colors.surface,
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('프로젝트를 삭제하지 못했습니다.')),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _deletingProjectId = null;
      _selectedScope = const SprintWorkspaceScope.all();
    });
    if (!deleted) return;
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

    return Scaffold(
      extendBody: false,
      extendBodyBehindAppBar: false,
      backgroundColor: colors.surface,
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
                        onTap: () => onSelect(
                          SprintWorkspaceScope.project(project.id),
                        ),
                      ),
                    ),
                  ),
                  _RailButton(
                    icon: Icons.add_rounded,
                    label: '새 프로젝트',
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
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Duration duration;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
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
                ? colors.primaryContainer
                : colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(selected ? 18 : 26),
            border: Border.all(
              color: selected ? colors.primary : colors.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Icon(
            icon,
            color: selected
                ? colors.onPrimaryContainer
                : colors.onSurfaceVariant,
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
    final user = GoogleAuthSession.instance.currentUser;
    final displayName = user?.displayName?.trim();
    final email = user?.email.trim();
    final title = displayName == null || displayName.isEmpty
        ? '스프린트 사용자'
        : displayName;
    final calendarLabel = store.googleCalendarId.isEmpty
        ? 'Google Calendar ID 미설정'
        : store.googleCalendarId;

    return ColoredBox(
      color: colors.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 10, 8),
        child: Row(
          children: [
            SizedBox(
              width: railWidth,
              child: CircleAvatar(
                radius: 24,
                backgroundColor: colors.primaryContainer,
                child: Text(
                  title.substring(0, 1).toUpperCase(),
                  style: TextStyle(
                    color: colors.onPrimaryContainer,
                    fontWeight: FontWeight.w900,
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
                          child: Column(
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
                                email == null || email.isEmpty
                                    ? calendarLabel
                                    : '$email · $calendarLabel',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (store.accountBusy)
                          const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        else
                          Icon(
                            store.googleCalendarIdLocked
                                ? Icons.lock_rounded
                                : Icons.manage_accounts_outlined,
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
  DateTime? _targetStartDate;
  DateTime? _targetDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
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

  Future<void> _selectTargetStartDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selected = await showDatePicker(
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
    final selected = await showDatePicker(
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
      targetStartDate: _targetStartDate,
      targetDate: _targetDate,
    );
    if (!mounted) return;
    if (project == null) {
      setState(() => _saving = false);
      sprintShowMessage(
        context: context,
        message: '프로젝트 정보를 확인하세요.',
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
                  '목표 기간',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                _CreateProjectDateTile(
                  title: '목표 시작일',
                  icon: Icons.play_circle_outline_rounded,
                  value: _targetStartDate,
                  duration: duration,
                  onTap: _saving ? null : _selectTargetStartDate,
                  onClear: _saving || _targetStartDate == null
                      ? null
                      : () => setState(() => _targetStartDate = null),
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
                  onPressed: _saving || invalidRange ? null : _create,
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
  late final TextEditingController _calendarController;
  final FocusNode _calendarFocusNode = FocusNode();
  late bool _locked;
  bool _localBusy = false;

  @override
  void initState() {
    super.initState();
    _calendarController = TextEditingController(
      text: widget.store.googleCalendarId,
    );
    _locked = widget.store.googleCalendarIdLocked;
  }

  @override
  void dispose() {
    _calendarController.dispose();
    _calendarFocusNode.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_localBusy || widget.store.accountBusy) return;
    final value = _calendarController.text.trim();
    if (value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Google Calendar ID를 입력하세요.')),
      );
      return;
    }
    setState(() => _localBusy = true);
    try {
      await widget.store.saveGoogleCalendarAccount(
        calendarId: value,
        locked: _locked,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('계정 설정을 저장했습니다.')),
      );
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('계정 설정을 저장하지 못했습니다.')),
      );
      setState(() => _localBusy = false);
    }
  }

  Future<void> _sync() async {
    if (_localBusy || widget.store.accountBusy) return;
    final value = _calendarController.text.trim();
    if (value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Google Calendar ID를 입력하세요.')),
      );
      return;
    }
    setState(() => _localBusy = true);
    try {
      await widget.store.saveGoogleCalendarAccountAndSync(
        calendarId: value,
        locked: _locked,
      );
      if (!mounted) return;
      if (widget.store.calendarState ==
          SprintCalendarConnectionState.connected) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Google 캘린더를 동기화했습니다.')),
        );
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Google 캘린더 동기화에 실패했습니다.')),
        );
        setState(() => _localBusy = false);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Google 캘린더 동기화에 실패했습니다.')),
      );
      setState(() => _localBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final user = GoogleAuthSession.instance.currentUser;
    final displayName = user?.displayName?.trim() ?? '';
    final email = user?.email.trim() ?? '';
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 180);
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, child) {
        final busy = _localBusy || widget.store.accountBusy;
        return Material(
          color: colors.surface,
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: 10),
            child: AnimatedPadding(
              duration: duration,
              padding: EdgeInsets.only(bottom: keyboardInset),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '사용자 계정',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 16),
                    SprintSurface(
                      backgroundColor: colors.surfaceContainerHigh,
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            child: Icon(
                              user == null
                                  ? Icons.person_outline_rounded
                                  : Icons.person_rounded,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayName.isNotEmpty
                                      ? displayName
                                      : '스프린트 사용자',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                if (email.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    email,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Google Calendar ID',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        Icon(
                          _locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _calendarController,
                      focusNode: _calendarFocusNode,
                      readOnly: _locked || busy,
                      keyboardType: TextInputType.text,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: colors.surfaceContainerHigh,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        suffixIcon: Icon(
                          _locked ? Icons.lock_rounded : Icons.edit_outlined,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        '필드 잠금',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        _locked
                            ? '잠금 상태에서는 Calendar ID를 수정할 수 없습니다.'
                            : '잠금을 켜면 저장 후 수정이 제한됩니다.',
                      ),
                      value: _locked,
                      onChanged: busy
                          ? null
                          : (value) {
                              if (value &&
                                  _calendarController.text.trim().isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Calendar ID 입력 후 잠글 수 있습니다.',
                                    ),
                                  ),
                                );
                                return;
                              }
                              setState(() => _locked = value);
                              if (!value) {
                                _calendarFocusNode.requestFocus();
                              } else {
                                _calendarFocusNode.unfocus();
                              }
                            },
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: busy ? null : _save,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                      ),
                      child: AnimatedSwitcher(
                        duration: duration,
                        child: busy
                            ? const SizedBox(
                                key: ValueKey<String>('saving'),
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Text(
                                '저장',
                                key: ValueKey<String>('save'),
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: busy ? null : _sync,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      icon: busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                              ),
                            )
                          : const Icon(Icons.sync_rounded),
                      label: const Text('저장 후 동기화'),
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
