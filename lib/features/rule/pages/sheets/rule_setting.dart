import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../app/utils/snackbar_helper.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../shared/secondary/application/secondary_rule_workspace_state.dart';
import '../../../../shared/secondary/widgets/ops_console_widgets.dart';
import '../../../../shared/secondary/widgets/secondary_debug_scope.dart';
import '../../applications/rule_state.dart';
import '../../domain/models/rule_model.dart';
import '../../domain/utils/work_manual_text.dart';
import 'rule_content_editor_dialog.dart';
import 'rule_response_manual_editor_dialog.dart';
import 'rule_todo_editor_dialog.dart';

class RuleSettingWorkspace extends StatefulWidget {
  const RuleSettingWorkspace({
    super.key,
    this.initialRule,
  });

  final RuleModel? initialRule;

  @override
  State<RuleSettingWorkspace> createState() => _RuleSettingWorkspaceState();
}

class _RuleSettingWorkspaceState extends State<RuleSettingWorkspace> {
  List<RuleTodoItem> _todoItems = <RuleTodoItem>[];
  String _content = '';
  List<RuleManualPage> _responseManualPages = const <RuleManualPage>[];
  bool _saving = false;
  bool _sectionDialogOpen = false;
  String? _saveError;
  int _lastNavigationRequestId = -1;

  bool get isEditMode => widget.initialRule != null;
  bool get _todosStructurallyValid =>
      _todoItems.length <= 30 &&
      _todoItems.every((item) {
        final value = item.text.trim();
        return item.id.trim().isNotEmpty &&
            value.isNotEmpty &&
            value.length <= 120;
      });
  bool get _contentValid => _content.trim().length <= 4000;
  bool get _responseManualValid {
    final ids = <String>{};
    for (var index = 0; index < _responseManualPages.length; index += 1) {
      final page = _responseManualPages[index];
      if (page.id.trim().isEmpty ||
          isWorkManualBlank(page.content) ||
          page.order != index ||
          !ids.add(page.id.trim())) {
        return false;
      }
    }
    return flattenRuleManualPages(_responseManualPages).length <= 4000;
  }
  bool get _hasTodos => _todoItems.isNotEmpty && _todosStructurallyValid;
  bool get _hasContent => _content.trim().isNotEmpty;
  bool get _hasResponseManual => _responseManualPages.isNotEmpty;
  bool get _ruleValid =>
      _todosStructurallyValid &&
      _contentValid &&
      _responseManualValid &&
      (_hasTodos || _hasContent || _hasResponseManual);
  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  @override
  void initState() {
    super.initState();
    _loadInitial(widget.initialRule);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateSectionStates(source: 'rule_settings_init');
      context.read<SecondaryRuleWorkspaceState>().setSettingsDirty(
            false,
            source: 'rule_settings_init',
          );
      _log(
        'settings_ready mode=${isEditMode ? 'edit' : 'create'} todos=${_todoItems.length} contentLength=${_content.length} responseManualLength=${flattenRuleManualPages(_responseManualPages).length} responseManualPageCount=${_responseManualPages.length} editorPresentation=center_dialog_flat',
      );
    });
  }

  @override
  void didUpdateWidget(covariant RuleSettingWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldRule = oldWidget.initialRule;
    final newRule = widget.initialRule;
    final oldRuleId = oldRule?.id;
    final newRuleId = newRule?.id;
    final oldUpdatedAt = oldRule?.updatedAt;
    final newUpdatedAt = newRule?.updatedAt;
    if (oldRuleId == newRuleId && oldUpdatedAt == newUpdatedAt) return;
    _loadInitial(widget.initialRule);
    _saveError = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateSectionStates(source: 'rule_settings_widget_updated');
    });
  }

  void _loadInitial(RuleModel? rule) {
    _todoItems = List<RuleTodoItem>.unmodifiable(
      rule?.todoItems ?? const <RuleTodoItem>[],
    );
    _content = rule?.content ?? '';
    _responseManualPages = List<RuleManualPage>.unmodifiable(
      rule?.responseManualPages ?? const <RuleManualPage>[],
    );
  }

  void _log(String message) {
    debugPrint('[RuleSetting] $message');
    SecondaryDebugScope.maybeOf(context)?.call('rule_workspace $message');
  }

  Future<DeveloperOperationTrace> _startTrace({
    required String title,
    required String initialMessage,
    bool showDialogImmediately = true,
  }) {
    return DeveloperOperationTrace.start(
      context: Navigator.of(context, rootNavigator: true).context,
      title: title,
      initialMessage: initialMessage,
      useCommonUi: true,
      showDialogImmediately: showDialogImmediately,
      developerModeMessage:
          '개발자 모드 ON: 상태와 debugPrint 코드를 확인하고 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF: 상태 다이얼로그 없이 작업을 실행합니다.',
    );
  }

  void _markDirty() {
    final workspace = context.read<SecondaryRuleWorkspaceState>();
    workspace.setSettingsDirty(true, source: 'rule_settings_changed');
    _updateSectionStates(source: 'rule_settings_changed');
    if (_saveError != null) setState(() => _saveError = null);
  }

  Map<RuleSettingsSection, RuleSettingsSectionState> _sectionStates() {
    final checklistState = !_todosStructurallyValid
        ? RuleSettingsSectionState.error
        : _todoItems.isEmpty
            ? RuleSettingsSectionState.unused
            : RuleSettingsSectionState.complete;
    final contentState = !_contentValid
        ? RuleSettingsSectionState.error
        : _hasContent
            ? RuleSettingsSectionState.complete
            : RuleSettingsSectionState.unused;
    final responseManualState = !_responseManualValid
        ? RuleSettingsSectionState.error
        : _hasResponseManual
            ? RuleSettingsSectionState.complete
            : RuleSettingsSectionState.unused;
    return <RuleSettingsSection, RuleSettingsSectionState>{
      RuleSettingsSection.checklist: checklistState,
      RuleSettingsSection.content: contentState,
      RuleSettingsSection.responseManual: responseManualState,
    };
  }

  void _updateSectionStates({required String source}) {
    if (!mounted) return;
    context.read<SecondaryRuleWorkspaceState>().updateSectionStates(
          _sectionStates(),
          source: source,
        );
  }

  void _handleNavigationRequest(SecondaryRuleWorkspaceState workspace) {
    final requestId = workspace.settingsNavigationRequestId;
    if (_lastNavigationRequestId < 0 || requestId == 0) {
      _lastNavigationRequestId = requestId;
      return;
    }
    if (_lastNavigationRequestId == requestId) return;
    _lastNavigationRequestId = requestId;
    final section = workspace.activeSettingsSection;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_openSectionEditor(section));
    });
  }

  Future<void> _requestSection(RuleSettingsSection section) async {
    if (_saving || _sectionDialogOpen) return;
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    context.read<SecondaryRuleWorkspaceState>().requestSettingsSection(
          section,
          source: 'rule_settings_section_row',
        );
  }

  String _sectionTitle(RuleSettingsSection section) {
    switch (section) {
      case RuleSettingsSection.checklist:
        return 'Todo 업무 절차';
      case RuleSettingsSection.content:
        return '업무 안내문';
      case RuleSettingsSection.responseManual:
        return '업무 메뉴얼';
    }
  }

  Future<void> _openSectionEditor(RuleSettingsSection section) async {
    if (_saving || _sectionDialogOpen || !mounted) return;
    setState(() => _sectionDialogOpen = true);
    final title = _sectionTitle(section);
    final trace = await _startTrace(
      title: '$title 편집',
      initialMessage: '$title 중앙 편집 Dialog를 엽니다.',
      showDialogImmediately: false,
    );
    if (!mounted) {
      _sectionDialogOpen = false;
      trace.dispose();
      return;
    }
    try {
      final editorStyle = section == RuleSettingsSection.responseManual
          ? 'structured_page_editor'
          : 'flat_line';
      trace.log(
        'section_opened section=${section.name} presentation=center_dialog fieldStyle=$editorStyle todoCount=${_todoItems.length} contentLength=${_content.length} responseManualLength=${flattenRuleManualPages(_responseManualPages).length} responseManualPageCount=${_responseManualPages.length}',
      );
      switch (section) {
        case RuleSettingsSection.checklist:
          final result = await showCommonOverlayDialog<List<RuleTodoItem>>(
            context: context,
            barrierDismissible: false,
            builder: (_) => RuleTodoEditorDialog(
              initialItems: _todoItems,
              trace: trace,
            ),
          );
          if (!mounted) return;
          if (result == null) {
            trace.log('section_closed section=checklist applied=false');
            return;
          }
          if (!_sameTodoItems(_todoItems, result)) {
            setState(() => _todoItems = List<RuleTodoItem>.unmodifiable(result));
            _markDirty();
          }
          trace.log(
            'section_closed section=checklist applied=true todoCount=${result.length}',
          );
          break;
        case RuleSettingsSection.content:
          final result = await showCommonOverlayDialog<String>(
            context: context,
            barrierDismissible: false,
            builder: (_) => RuleContentEditorDialog(
              initialContent: _content,
              trace: trace,
            ),
          );
          if (!mounted) return;
          if (result == null) {
            trace.log('section_closed section=content applied=false');
            return;
          }
          final normalized = result.trim();
          if (normalized != _content) {
            setState(() => _content = normalized);
            _markDirty();
          }
          trace.log(
            'section_closed section=content applied=true contentLength=${normalized.length}',
          );
          break;
        case RuleSettingsSection.responseManual:
          final result = await showCommonOverlayDialog<List<RuleManualPage>>(
            context: context,
            barrierDismissible: false,
            builder: (_) => RuleResponseManualEditorDialog(
              initialPages: _responseManualPages,
              trace: trace,
            ),
          );
          if (!mounted) return;
          if (result == null) {
            trace.log('section_closed section=responseManual applied=false');
            return;
          }
          final normalized = normalizeRuleManualPagesForStorage(result);
          if (!sameRuleManualPages(normalized, _responseManualPages)) {
            setState(() {
              _responseManualPages = List<RuleManualPage>.unmodifiable(normalized);
            });
            _markDirty();
          }
          trace.log(
            'section_closed section=responseManual applied=true responseManualLength=${flattenRuleManualPages(normalized).length} responseManualPageCount=${normalized.length}',
          );
          break;
      }
    } finally {
      trace.dispose();
      if (mounted) {
        setState(() => _sectionDialogOpen = false);
      } else {
        _sectionDialogOpen = false;
      }
    }
  }

  bool _sameTodoItems(List<RuleTodoItem> a, List<RuleTodoItem> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index += 1) {
      final left = a[index];
      final right = b[index];
      if (left.id != right.id ||
          left.text.trim() != right.text.trim() ||
          left.order != right.order) {
        return false;
      }
    }
    return true;
  }

  Future<void> _save() async {
    if (_saving || _sectionDialogOpen) return;
    setState(() => _saveError = null);
    _updateSectionStates(source: 'rule_settings_submit');

    final workspace = context.read<SecondaryRuleWorkspaceState>();
    if (!_todosStructurallyValid) {
      await HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() => _saveError = 'Todo 업무 절차의 입력 내용을 확인해 주세요.');
      workspace.requestSettingsSection(
        RuleSettingsSection.checklist,
        source: 'rule_settings_validation',
      );
      return;
    }
    if (!_contentValid) {
      await HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() => _saveError = '업무 안내문은 4000자 이하로 입력해 주세요.');
      workspace.requestSettingsSection(
        RuleSettingsSection.content,
        source: 'rule_settings_validation',
      );
      return;
    }
    if (!_responseManualValid) {
      await HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() => _saveError = '업무 메뉴얼은 4000자 이하로 입력해 주세요.');
      workspace.requestSettingsSection(
        RuleSettingsSection.responseManual,
        source: 'rule_settings_validation',
      );
      return;
    }
    if (!_hasTodos && !_hasContent && !_hasResponseManual) {
      await HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(
        () => _saveError =
            'Todo 업무 절차, 업무 안내문 또는 업무 메뉴얼 중 하나 이상 입력해 주세요.',
      );
      return;
    }

    final state = context.read<RuleState>();
    final title = isEditMode ? '업무 규칙 수정' : '업무 규칙 등록';
    final trace = await _startTrace(
      title: title,
      initialMessage: '$title 요청을 확인하고 있습니다.',
    );
    if (!mounted) {
      trace.dispose();
      return;
    }
    setState(() => _saving = true);
    workspace.setSettingsSaving(true, source: 'rule_settings_save');
    try {
      final todos = List<RuleTodoItem>.unmodifiable(_todoItems);
      final content = _content.trim();
      final responseManualPages = normalizeRuleManualPagesForStorage(
        _responseManualPages,
      );
      final responseManual = flattenRuleManualPages(responseManualPages);
      trace.log(
        '입력 검증 완료: todos=${todos.length} contentLength=${content.length} responseManualLength=${responseManual.length} responseManualPageCount=${responseManualPages.length}',
        progress: .24,
      );
      trace.log(
        'Firestore rule 문서를 ${isEditMode ? '수정' : '생성'}합니다.',
        progress: .48,
      );
      final RuleModel saved = isEditMode
          ? await state.updateRule(
              todoItems: todos,
              content: content,
              responseManualPages: responseManualPages,
            )
          : await state.createRule(
              todoItems: todos,
              content: content,
              responseManualPages: responseManualPages,
            );
      trace.log(
        'SQLite 업무 규칙 Snapshot 저장 검증 완료: id=${saved.id} todos=${saved.todoItems.length} contentLength=${saved.content.length} responseManualLength=${saved.responseManual.length} responseManualPageCount=${saved.responseManualPages.length}',
        progress: .86,
      );
      await trace.succeed('$title이 완료되었습니다.');
      if (!mounted) return;
      workspace.setSettingsDirty(false, source: 'rule_settings_saved');
      workspace.returnToManagement(source: 'rule_settings_saved');
      showSuccessSnackbar(context, '$title이 완료되었습니다.', useCommonUi: true);
    } catch (error, stackTrace) {
      await trace.fail(
        '$title에 실패했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() => _saveError = _errorMessage(error));
      showFailedSnackbar(context, _errorMessage(error), useCommonUi: true);
    } finally {
      trace.dispose();
      if (mounted) {
        setState(() => _saving = false);
        workspace.setSettingsSaving(
          false,
          source: 'rule_settings_save_complete',
        );
      }
    }
  }

  String _errorMessage(Object error) {
    if (error is RuleAlreadyExistsException ||
        error is RuleNotFoundException ||
        error is RuleAreaMismatchException) {
      return error.toString();
    }
    if (error is StateError) return error.message;
    if (error is ArgumentError) {
      return error.message?.toString() ?? '업무 규칙 저장에 실패했습니다.';
    }
    return '업무 규칙 저장에 실패했습니다.';
  }

  void _returnToManagement() {
    if (_saving || _sectionDialogOpen) return;
    context.read<SecondaryRuleWorkspaceState>().returnToManagement(
          source: 'rule_settings_footer_back',
        );
  }

  Widget _statusStrip(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final hasError = _saveError != null && _saveError!.trim().isNotEmpty;
    final label = hasError
        ? '저장 확인 필요'
        : _ruleValid
            ? '입력 확인 완료'
            : '규칙 내용 필요';
    final color = hasError
        ? tokens.danger
        : _ruleValid
            ? tokens.success
            : tokens.warning;
    final icon = hasError
        ? Icons.error_rounded
        : _ruleValid
            ? Icons.check_circle_rounded
            : Icons.priority_high_rounded;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        AnimatedSwitcher(
          duration: _reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 180),
          child: Icon(
            icon,
            key: ValueKey<String>(label),
            size: 17,
            color: color,
          ),
        ),
      ],
    );
  }

  String _sectionSummary(RuleSettingsSection section) {
    switch (section) {
      case RuleSettingsSection.checklist:
        return _todoItems.isEmpty ? '미등록' : '${_todoItems.length}개 항목';
      case RuleSettingsSection.content:
        return _hasContent ? '${_content.trim().length}자' : '미등록';
      case RuleSettingsSection.responseManual:
        return _hasResponseManual
            ? '${_responseManualPages.length}페이지 · ${flattenRuleManualPages(_responseManualPages).length}자'
            : '미등록';
    }
  }

  String _sectionDescription(RuleSettingsSection section) {
    switch (section) {
      case RuleSettingsSection.checklist:
        return '출근 전에 확인할 업무 절차와 순서';
      case RuleSettingsSection.content:
        return '업무 중 반복해서 확인할 운영 안내';
      case RuleSettingsSection.responseManual:
        return '페이지를 직접 구성해 상황별 기준과 순서를 관리';
    }
  }

  IconData _sectionIcon(RuleSettingsSection section) {
    switch (section) {
      case RuleSettingsSection.checklist:
        return Icons.checklist_rounded;
      case RuleSettingsSection.content:
        return Icons.article_rounded;
      case RuleSettingsSection.responseManual:
        return Icons.menu_book_rounded;
    }
  }

  Widget _sectionRow(
    BuildContext context,
    SecondaryRuleWorkspaceState workspace,
    RuleSettingsSection section,
  ) {
    final tokens = CommonUiTheme.of(context);
    final state = workspace.stateFor(section);
    final selected = workspace.activeSettingsSection == section;
    final statusColor = switch (state) {
      RuleSettingsSectionState.complete => tokens.success,
      RuleSettingsSectionState.unused => tokens.textSecondary,
      RuleSettingsSectionState.incomplete => tokens.warning,
      RuleSettingsSectionState.error => tokens.danger,
    };
    final statusIcon = switch (state) {
      RuleSettingsSectionState.complete => Icons.check_circle_rounded,
      RuleSettingsSectionState.unused => Icons.remove_circle_outline_rounded,
      RuleSettingsSectionState.incomplete => Icons.priority_high_rounded,
      RuleSettingsSectionState.error => Icons.error_rounded,
    };
    final title = _sectionTitle(section);
    return Semantics(
      button: true,
      label: '$title, ${_sectionSummary(section)}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _saving || _sectionDialogOpen
              ? null
              : () => _requestSection(section),
          child: AnimatedContainer(
            duration: _reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            color: selected
                ? tokens.accentContainer.withOpacity(.12)
                : Colors.transparent,
            padding: const EdgeInsets.fromLTRB(0, 14, 4, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: _reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  width: 3,
                  height: 44,
                  color: selected ? tokens.accent : Colors.transparent,
                ),
                const SizedBox(width: 11),
                Icon(
                  _sectionIcon(section),
                  size: 21,
                  color: selected ? tokens.accent : tokens.iconSecondary,
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
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    color: tokens.textPrimary,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _sectionSummary(section),
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: statusColor,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _sectionDescription(section),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: tokens.textSecondary,
                              height: 1.35,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedSwitcher(
                  duration: _reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 160),
                  child: Icon(
                    statusIcon,
                    key: ValueKey<RuleSettingsSectionState>(state),
                    size: 18,
                    color: statusColor,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: tokens.iconSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorStrip(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final value = _saveError;
    return AnimatedSize(
      duration: _reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: value == null || value.trim().isEmpty
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(width: 3, height: 38, color: tokens.danger),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      value,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: tokens.danger,
                            height: 1.4,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final workspace = context.watch<SecondaryRuleWorkspaceState>();
    _handleNavigationRequest(workspace);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: _statusStrip(context),
        ),
        Expanded(
          child: ListView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
            children: [
              Text(
                '규칙 구성',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                '각 영역을 선택하면 화면 중앙에서 내용을 생성하거나 수정할 수 있습니다.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                    ),
              ),
              const SizedBox(height: 12),
              Divider(height: 1, color: tokens.borderStrong),
              _sectionRow(
                context,
                workspace,
                RuleSettingsSection.checklist,
              ),
              Divider(height: 1, color: tokens.borderSubtle),
              _sectionRow(
                context,
                workspace,
                RuleSettingsSection.content,
              ),
              Divider(height: 1, color: tokens.borderSubtle),
              _sectionRow(
                context,
                workspace,
                RuleSettingsSection.responseManual,
              ),
              Divider(height: 1, color: tokens.borderStrong),
              _errorStrip(context),
            ],
          ),
        ),
        OpsDockContextFooter(
          children: [
            Expanded(
              child: CommonButton(
                label: '업무 규칙 목록',
                icon: Icons.arrow_back_rounded,
                onPressed: _saving || _sectionDialogOpen
                    ? null
                    : _returnToManagement,
                variant: CommonButtonVariant.secondary,
                haptic: CommonHaptic.selection,
                minHeight: 42,
                expand: true,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: CommonButton(
                label: isEditMode ? '수정 완료' : '등록 완료',
                icon: isEditMode ? Icons.save_rounded : Icons.add_rounded,
                onPressed: _saving || _sectionDialogOpen ? null : _save,
                loading: _saving,
                haptic: CommonHaptic.selection,
                minHeight: 42,
                expand: true,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
