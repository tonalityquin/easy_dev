import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/utils/developer_operation_status_dialog.dart';
import '../../../app/utils/snackbar_helper.dart';
import '../../../design_system/common_ui/common_ui_components.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../../shared/secondary/application/secondary_rule_workspace_state.dart';
import '../../../shared/secondary/widgets/ops_console_dialogs.dart';
import '../../../shared/secondary/widgets/ops_console_widgets.dart';
import '../../../shared/secondary/widgets/secondary_debug_scope.dart';
import '../../dev/application/area_state.dart';
import '../applications/rule_state.dart';
import '../domain/models/rule_model.dart';

class RuleManagement extends StatefulWidget {
  const RuleManagement({super.key});

  @override
  State<RuleManagement> createState() => _RuleManagementState();
}

class _RuleManagementState extends State<RuleManagement> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _log('mounted');
      unawaited(_initialRefresh());
    });
  }

  void _log(String message) {
    debugPrint('[RuleManagement] $message');
    if (!mounted) return;
    SecondaryDebugScope.maybeOf(context)?.call('rule_workspace $message');
  }

  Future<DeveloperOperationTrace> _startTrace({
    required String title,
    required String initialMessage,
  }) {
    return DeveloperOperationTrace.start(
      context: Navigator.of(context, rootNavigator: true).context,
      title: title,
      initialMessage: initialMessage,
      useCommonUi: true,
      developerModeMessage:
          '개발자 모드 ON: 상태와 debugPrint 코드를 확인하고 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF: 상태 다이얼로그 없이 작업을 실행합니다.',
    );
  }

  Future<void> _initialRefresh() async {
    final areaState = context.read<AreaState>();
    final division = areaState.currentDivision.trim();
    final area = areaState.currentArea.trim();
    _log('initial_refresh_started division=$division area=$area');
    try {
      await context.read<RuleState>().manualRuleRefresh();
      if (!mounted) return;
      _log('initial_refresh_completed found=${context.read<RuleState>().hasRule}');
    } catch (error, stackTrace) {
      _log('initial_refresh_failed error=$error stack=$stackTrace');
    }
  }

  Future<void> _refresh() async {
    final areaState = context.read<AreaState>();
    final division = areaState.currentDivision.trim();
    final area = areaState.currentArea.trim();
    final trace = await _startTrace(
      title: '업무 규칙 새로고침',
      initialMessage: '현재 지역의 업무 규칙을 확인하고 있습니다.',
    );
    try {
      if (division.isEmpty || area.isEmpty) {
        throw StateError('현재 지역 정보가 없습니다.');
      }
      trace.log('현재 지역 확인 완료: division=$division area=$area', progress: .18);
      trace.log('Firestore rule/$division-$area 문서를 조회합니다.', progress: .42);
      await context.read<RuleState>().manualRuleRefreshStrict();
      if (!mounted) return;
      final rule = context.read<RuleState>().rule;
      trace.log(
        'SQLite 업무 규칙 Snapshot 교체를 확인했습니다: found=${rule != null} todos=${rule?.todoItems.length ?? 0} contentLength=${rule?.content.length ?? 0}',
        progress: .84,
      );
      await trace.succeed('업무 규칙 새로고침이 완료되었습니다.');
      if (!mounted) return;
      showSuccessSnackbar(context, '업무 규칙을 새로고침했습니다.', useCommonUi: true);
    } catch (error, stackTrace) {
      await trace.fail(
        '업무 규칙 새로고침에 실패했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      showFailedSnackbar(
        context,
        _errorMessage(error, fallback: '업무 규칙 새로고침에 실패했습니다.'),
        useCommonUi: true,
      );
    }
  }

  Future<void> _openSettings({required bool edit}) async {
    final areaState = context.read<AreaState>();
    if (areaState.currentDivision.trim().isEmpty ||
        areaState.currentArea.trim().isEmpty) {
      showFailedSnackbar(context, '현재 지역 정보가 없습니다.', useCommonUi: true);
      return;
    }
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    final workspace = context.read<SecondaryRuleWorkspaceState>();
    if (edit) {
      workspace.openEdit(source: 'rule_management_edit');
    } else {
      workspace.openCreate(source: 'rule_management_create');
    }
  }

  Future<void> _delete(RuleModel rule) async {
    final confirmed = await showOpsConfirmDialog(
      context: context,
      title: '업무 규칙 삭제 확인',
      message: '${rule.area} 지역의 업무 규칙을 삭제하시겠습니까?',
      confirmLabel: '삭제',
      icon: Icons.delete_forever_rounded,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final trace = await _startTrace(
      title: '업무 규칙 삭제',
      initialMessage: '현재 지역 업무 규칙 삭제 요청을 확인하고 있습니다.',
    );
    try {
      trace.log('삭제 대상 확인: collection=rule id=${rule.id}', progress: .24);
      trace.log('지역 소유권을 확인합니다: division=${rule.division} area=${rule.area}', progress: .42);
      await context.read<RuleState>().deleteRule();
      trace.log('Firestore 문서와 SQLite Snapshot 삭제를 완료했습니다.', progress: .88);
      await trace.succeed('업무 규칙 삭제가 완료되었습니다.');
      if (!mounted) return;
      showSuccessSnackbar(context, '업무 규칙을 삭제했습니다.', useCommonUi: true);
    } catch (error, stackTrace) {
      await trace.fail(
        '업무 규칙 삭제에 실패했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      showFailedSnackbar(
        context,
        _errorMessage(error, fallback: '업무 규칙 삭제에 실패했습니다.'),
        useCommonUi: true,
      );
    }
  }

  String _errorMessage(Object error, {required String fallback}) {
    if (error is RuleAlreadyExistsException ||
        error is RuleNotFoundException ||
        error is RuleAreaMismatchException) {
      return error.toString();
    }
    if (error is StateError) return error.message;
    if (error is ArgumentError) return error.message?.toString() ?? fallback;
    return fallback;
  }

  String _formatUpdatedAt(DateTime? value) {
    if (value == null) return '시간 정보 없음';
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}.${two(local.month)}.${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }


  String _ruleSummary(RuleModel rule) {
    final parts = <String>[];
    if (rule.todoItems.isNotEmpty) {
      parts.add('${rule.todoItems.length}개 Todo');
    }
    final content = rule.content.trim();
    if (content.isNotEmpty) {
      parts.add('본문 ${content.length}자');
    }
    return parts.isEmpty ? '현재 지역 업무 규칙' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final state = context.watch<RuleState>();
    final rule = state.rule;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  rule == null ? '현재 지역 업무 규칙' : _ruleSummary(rule),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              CommonButton(
                label: '새로고침',
                icon: Icons.refresh_rounded,
                onPressed: state.isRefreshing || state.isSaving ? null : _refresh,
                loading: state.isRefreshing,
                variant: CommonButtonVariant.secondary,
                haptic: CommonHaptic.selection,
                minHeight: 40,
              ),
            ],
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 190),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: state.isLoading && rule == null
                ? Center(
                    key: const ValueKey<String>('rule-loading'),
                    child: CircularProgressIndicator(color: tokens.accent),
                  )
                : rule == null
                    ? OpsEmptyState(
                        key: const ValueKey<String>('rule-empty'),
                        icon: Icons.rule_rounded,
                        title: '등록된 업무 규칙이 없습니다',
                        message: '현재 지역의 Todo 체크리스트 또는 업무 안내문을 등록할 수 있습니다.',
                        action: CommonButton(
                          label: '업무 규칙 등록',
                          icon: Icons.add_rounded,
                          onPressed: state.isSaving ? null : () => _openSettings(edit: false),
                          haptic: CommonHaptic.selection,
                        ),
                      )
                    : Padding(
                        key: ValueKey<String>('rule-${rule.id}-${rule.updatedAt?.millisecondsSinceEpoch ?? 0}'),
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                        child: SingleChildScrollView(
                          child: OpsDockListSurface(
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (rule.todoItems.isNotEmpty) ...[
                                    Row(
                                      children: [
                                        Icon(Icons.checklist_rounded, size: 20, color: tokens.accent),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Todo 체크리스트 ${rule.todoItems.length}개',
                                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                                  color: tokens.textPrimary,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    ...rule.todoItems.take(4).map(
                                      (item) => Padding(
                                        padding: const EdgeInsets.only(bottom: 7),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Icon(Icons.check_box_outline_blank_rounded, size: 17, color: tokens.iconSecondary),
                                            const SizedBox(width: 7),
                                            Expanded(
                                              child: Text(
                                                item.text,
                                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                      color: tokens.textPrimary,
                                                      height: 1.35,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (rule.todoItems.length > 4)
                                      Text(
                                        '외 ${rule.todoItems.length - 4}개',
                                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                              color: tokens.textSecondary,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                  ],
                                  if (rule.todoItems.isNotEmpty && rule.content.trim().isNotEmpty) ...[
                                    const SizedBox(height: 16),
                                    Divider(height: 1, color: tokens.borderSubtle),
                                    const SizedBox(height: 14),
                                  ],
                                  if (rule.content.trim().isNotEmpty) ...[
                                    Row(
                                      children: [
                                        Icon(Icons.article_rounded, size: 20, color: tokens.accent),
                                        const SizedBox(width: 8),
                                        Text(
                                          '업무 안내문',
                                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                                color: tokens.textPrimary,
                                                fontWeight: FontWeight.w800,
                                              ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      rule.content.trim(),
                                      maxLines: 7,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: tokens.textPrimary,
                                            height: 1.5,
                                            fontWeight: FontWeight.w500,
                                          ),
                                    ),
                                  ],
                                  const SizedBox(height: 14),
                                  Text(
                                    '마지막 수정 ${_formatUpdatedAt(rule.updatedAt)}',
                                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                          color: tokens.textSecondary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
          ),
        ),
        OpsDockContextFooterTransition(
          child: rule == null
              ? const SizedBox.shrink()
              : OpsDockContextFooter(
                  children: [
                    Expanded(
                      child: CommonButton(
                        label: '수정',
                        icon: Icons.edit_rounded,
                        onPressed: state.isSaving ? null : () => _openSettings(edit: true),
                        variant: CommonButtonVariant.secondary,
                        haptic: CommonHaptic.selection,
                        expand: true,
                        minHeight: 42,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: CommonButton(
                        label: '삭제',
                        icon: Icons.delete_forever_rounded,
                        onPressed: state.isSaving ? null : () => _delete(rule),
                        variant: CommonButtonVariant.destructive,
                        haptic: CommonHaptic.medium,
                        expand: true,
                        minHeight: 42,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
