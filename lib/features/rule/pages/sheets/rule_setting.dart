import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../app/utils/snackbar_helper.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../shared/secondary/application/secondary_rule_workspace_state.dart';
import '../../../../shared/secondary/widgets/ops_console_widgets.dart';
import '../../../../shared/secondary/widgets/secondary_debug_scope.dart';
import '../../applications/rule_state.dart';
import '../../domain/models/rule_model.dart';

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
  final GlobalKey _checklistKey = GlobalKey();
  final GlobalKey _contentKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _contentController = TextEditingController();
  final List<_RuleTodoEditor> _todoEditors = <_RuleTodoEditor>[];

  bool _saving = false;
  bool _submitted = false;
  String? _saveError;
  int _lastNavigationRequestId = -1;

  bool get isEditMode => widget.initialRule != null;
  bool get _todosStructurallyValid => _todoEditors.every(
        (editor) => editor.controller.text.trim().isNotEmpty,
      );
  bool get _hasTodos => _todoEditors.isNotEmpty && _todosStructurallyValid;
  bool get _hasContent => _contentController.text.trim().isNotEmpty;
  bool get _ruleValid =>
      _todosStructurallyValid && (_hasTodos || _hasContent);
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
    });
  }

  @override
  void didUpdateWidget(covariant RuleSettingWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldRule = oldWidget.initialRule;
    final newRule = widget.initialRule;
    final oldRuleId = oldRule == null ? null : oldRule.id;
    final newRuleId = newRule == null ? null : newRule.id;
    final oldUpdatedAt = oldRule?.updatedAt;
    final newUpdatedAt = newRule?.updatedAt;
    if (oldRuleId == newRuleId && oldUpdatedAt == newUpdatedAt) {
      return;
    }
    _disposeTodoEditors();
    _loadInitial(widget.initialRule);
    _submitted = false;
    _saveError = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateSectionStates(source: 'rule_settings_widget_updated');
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _contentController.dispose();
    _disposeTodoEditors();
    super.dispose();
  }

  void _loadInitial(RuleModel? rule) {
    _contentController.text = rule?.content ?? '';
    final source = rule?.todoItems ?? const <RuleTodoItem>[];
    for (final item in source) {
      final String itemId = item.id;
      _todoEditors.add(
        _RuleTodoEditor(
          id: itemId,
          controller: TextEditingController(text: item.text),
        ),
      );
    }
  }

  _RuleTodoEditor _newTodoEditor() {
    return _RuleTodoEditor(
      id: 'todo_${DateTime.now().microsecondsSinceEpoch}_${_todoEditors.length}',
      controller: TextEditingController(),
    );
  }

  void _disposeTodoEditors() {
    for (final editor in _todoEditors) {
      editor.controller.dispose();
    }
    _todoEditors.clear();
  }

  void _log(String message) {
    debugPrint('[RuleSetting] $message');
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

  void _markDirty() {
    final workspace = context.read<SecondaryRuleWorkspaceState>();
    workspace.setSettingsDirty(true, source: 'rule_settings_changed');
    _updateSectionStates(source: 'rule_settings_changed');
    if (_saveError != null) setState(() => _saveError = null);
  }

  Map<RuleSettingsSection, RuleSettingsSectionState> _sectionStates() {
    final checklistState = _todoEditors.isEmpty
        ? RuleSettingsSectionState.unused
        : _todosStructurallyValid
            ? RuleSettingsSectionState.complete
            : _submitted
                ? RuleSettingsSectionState.error
                : RuleSettingsSectionState.incomplete;
    final contentState = _hasContent
        ? RuleSettingsSectionState.complete
        : RuleSettingsSectionState.unused;
    return <RuleSettingsSection, RuleSettingsSectionState>{
      RuleSettingsSection.checklist: checklistState,
      RuleSettingsSection.content: contentState,
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
    if (_lastNavigationRequestId == workspace.settingsNavigationRequestId) return;
    _lastNavigationRequestId = workspace.settingsNavigationRequestId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = workspace.activeSettingsSection == RuleSettingsSection.checklist
          ? _checklistKey
          : _contentKey;
      final targetContext = key.currentContext;
      if (targetContext == null) return;
      Scrollable.ensureVisible(
        targetContext,
        duration: _reduceMotion ? Duration.zero : const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        alignment: .04,
      );
      _log('settings_section_scrolled section=${workspace.activeSettingsSection.name}');
    });
  }

  void _addTodo() {
    if (_todoEditors.length >= 30) {
      showFailedSnackbar(context, 'Todo 항목은 최대 30개까지 등록할 수 있습니다.', useCommonUi: true);
      return;
    }
    setState(() => _todoEditors.add(_newTodoEditor()));
    HapticFeedback.selectionClick();
    _markDirty();
    _log('todo_added count=${_todoEditors.length}');
  }

  void _removeTodo(int index) {
    final removed = _todoEditors.removeAt(index);
    removed.controller.dispose();
    setState(() {});
    HapticFeedback.mediumImpact();
    _markDirty();
    _log('todo_removed index=$index count=${_todoEditors.length}');
  }

  void _reorderTodo(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    setState(() {
      final item = _todoEditors.removeAt(oldIndex);
      _todoEditors.insert(newIndex, item);
    });
    HapticFeedback.selectionClick();
    _markDirty();
    _log('todo_reordered from=$oldIndex to=$newIndex');
  }

  List<RuleTodoItem> _buildTodoItems() {
    return List<RuleTodoItem>.generate(
      _todoEditors.length,
      (index) {
        final editor = _todoEditors[index];
        final String editorId = editor.id;
        return RuleTodoItem(
          id: editorId,
          text: editor.controller.text.trim(),
          order: index,
        );
      },
      growable: false,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _submitted = true;
      _saveError = null;
    });
    _updateSectionStates(source: 'rule_settings_submit');
    if (!_todosStructurallyValid) {
      await HapticFeedback.mediumImpact();
      if (!mounted) return;
      final workspace = context.read<SecondaryRuleWorkspaceState>();
      workspace.requestSettingsSection(
        RuleSettingsSection.checklist,
        source: 'rule_settings_validation',
      );
      setState(() => _saveError = '비어 있는 Todo 항목을 확인해 주세요.');
      return;
    }
    if (!_hasTodos && !_hasContent) {
      await HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(
        () => _saveError =
            'Todo 체크리스트 또는 업무 안내문 중 하나 이상 입력해 주세요.',
      );
      return;
    }

    final workspace = context.read<SecondaryRuleWorkspaceState>();
    final state = context.read<RuleState>();
    final title = isEditMode ? '업무 규칙 수정' : '업무 규칙 등록';
    final trace = await _startTrace(
      title: title,
      initialMessage: '$title 요청을 확인하고 있습니다.',
    );
    setState(() => _saving = true);
    workspace.setSettingsSaving(true, source: 'rule_settings_save');
    try {
      final todos = _buildTodoItems();
      final content = _contentController.text.trim();
      trace.log('입력 검증 완료: todos=${todos.length} contentLength=${content.length}', progress: .24);
      trace.log('Firestore rule 문서를 ${isEditMode ? '수정' : '생성'}합니다.', progress: .48);
      final RuleModel saved = isEditMode
          ? await state.updateRule(todoItems: todos, content: content)
          : await state.createRule(todoItems: todos, content: content);
      final String savedId = saved.id;
      trace.log(
        'SQLite 업무 규칙 Snapshot 저장 검증 완료: id=$savedId todos=${saved.todoItems.length} contentLength=${saved.content.length}',
        progress: .86,
      );
      await trace.succeed('$title이 완료되었습니다.');
      if (!mounted) return;
      workspace.setSettingsDirty(false, source: 'rule_settings_saved');
      workspace.returnToManagement(source: 'rule_settings_saved');
      showSuccessSnackbar(context, '$title이 완료되었습니다.', useCommonUi: true);
    } catch (error, stackTrace) {
      await trace.fail('$title에 실패했습니다.', error: error, stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _saveError = _errorMessage(error));
      showFailedSnackbar(context, _errorMessage(error), useCommonUi: true);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        workspace.setSettingsSaving(false, source: 'rule_settings_save_complete');
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
    if (_saving) return;
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
            : _todosStructurallyValid
                ? '규칙 내용 필요'
                : '입력 확인 필요';
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
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w700,
              ),
        ),
        const Spacer(),
        AnimatedSwitcher(
          duration: _reduceMotion ? Duration.zero : const Duration(milliseconds: 190),
          child: Icon(icon, key: ValueKey<String>(label), size: 17, color: color),
        ),
      ],
    );
  }

  Widget _checklistSection(BuildContext context, SecondaryRuleWorkspaceState workspace) {
    final tokens = CommonUiTheme.of(context);
    final selected = workspace.activeSettingsSection == RuleSettingsSection.checklist;
    return AnimatedContainer(
      key: _checklistKey,
      duration: _reduceMotion ? Duration.zero : const Duration(milliseconds: 190),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: selected ? tokens.accentContainer.withOpacity(.24) : tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(CommonUiShapes.card),
        border: Border.all(color: selected ? tokens.accent : tokens.borderSubtle),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.checklist_rounded, size: 20, color: tokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Todo 체크리스트',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              CommonButton(
                label: '추가',
                icon: Icons.add_rounded,
                onPressed: _saving ? null : _addTodo,
                variant: CommonButtonVariant.secondary,
                haptic: CommonHaptic.selection,
                minHeight: 38,
              ),
            ],
          ),
          const SizedBox(height: 10),
          AnimatedSize(
            duration: _reduceMotion ? Duration.zero : const Duration(milliseconds: 210),
            curve: Curves.easeOutCubic,
            child: ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: _todoEditors.length,
              onReorder: _saving ? (_, __) {} : _reorderTodo,
              itemBuilder: (context, index) {
                final editor = _todoEditors[index];
                final String editorId = editor.id;
                return Padding(
                  key: ValueKey<String>(editorId),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 13, right: 6),
                          child: Icon(Icons.drag_indicator_rounded, size: 19, color: tokens.iconSecondary),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: editor.controller,
                          enabled: !_saving,
                          maxLength: 120,
                          maxLines: 2,
                          minLines: 1,
                          textInputAction: TextInputAction.next,
                          onChanged: (_) {
                            setState(() {});
                            _markDirty();
                          },
                          decoration: opsInputDecoration(
                            context,
                            label: 'Todo ${index + 1}',
                            errorText: _submitted && editor.controller.text.trim().isEmpty
                                ? '내용을 입력해 주세요.'
                                : null,
                          ).copyWith(counterText: ''),
                        ),
                      ),
                      const SizedBox(width: 4),
                      CommonButton(
                        label: '삭제',
                        icon: Icons.delete_outline_rounded,
                        onPressed: _saving ? null : () => _removeTodo(index),
                        variant: CommonButtonVariant.destructive,
                        haptic: CommonHaptic.medium,
                        minHeight: 38,
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
  }

  Widget _contentSection(BuildContext context, SecondaryRuleWorkspaceState workspace) {
    final tokens = CommonUiTheme.of(context);
    final selected = workspace.activeSettingsSection == RuleSettingsSection.content;
    return AnimatedContainer(
      key: _contentKey,
      duration: _reduceMotion ? Duration.zero : const Duration(milliseconds: 190),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: selected ? tokens.accentContainer.withOpacity(.24) : tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(CommonUiShapes.card),
        border: Border.all(color: selected ? tokens.accent : tokens.borderSubtle),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          const SizedBox(height: 10),
          TextField(
            controller: _contentController,
            enabled: !_saving,
            minLines: 7,
            maxLines: 12,
            maxLength: 4000,
            onChanged: (_) {
              setState(() {});
              _markDirty();
            },
            decoration: opsInputDecoration(
              context,
              label: '업무 안내문',
            ).copyWith(counterText: '${_contentController.text.length}/4000'),
          ),
        ],
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
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: const ClampingScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
            child: Column(
              children: [
                AnimatedSize(
                  duration: _reduceMotion ? Duration.zero : const Duration(milliseconds: 190),
                  child: _saveError == null
                      ? const SizedBox.shrink()
                      : Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: tokens.dangerContainer,
                            borderRadius: BorderRadius.circular(CommonUiShapes.control),
                            border: Border.all(color: tokens.danger),
                          ),
                          child: Text(
                            _saveError!,
                            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: tokens.onDangerContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                ),
                _checklistSection(context, workspace),
                const SizedBox(height: 10),
                _contentSection(context, workspace),
              ],
            ),
          ),
        ),
        OpsDockContextFooter(
          children: [
            Expanded(
              child: CommonButton(
                label: '업무 규칙 목록',
                icon: Icons.arrow_back_rounded,
                onPressed: _saving ? null : _returnToManagement,
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
                onPressed: _saving ? null : _save,
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

class _RuleTodoEditor {
  _RuleTodoEditor({
    required this.id,
    required this.controller,
  });

  final String id;
  final TextEditingController controller;
}
