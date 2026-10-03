import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../domain/models/rule_model.dart';

class RuleTodoEditorDialog extends StatefulWidget {
  const RuleTodoEditorDialog({
    super.key,
    required this.initialItems,
    required this.trace,
  });

  final List<RuleTodoItem> initialItems;
  final DeveloperOperationTrace trace;

  @override
  State<RuleTodoEditorDialog> createState() => _RuleTodoEditorDialogState();
}

class _RuleTodoEditorDialogState extends State<RuleTodoEditorDialog> {
  final List<_RuleTodoDraft> _items = <_RuleTodoDraft>[];
  bool _submitted = false;
  bool _reduceMotion = false;

  bool get _valid => _items.length <= 30 && _items.every((item) {
        final value = item.controller.text.trim();
        return value.isNotEmpty && value.length <= 120;
      });

  @override
  void initState() {
    super.initState();
    for (final item in widget.initialItems) {
      _items.add(
        _RuleTodoDraft(
          id: item.id,
          controller: TextEditingController(text: item.text),
        ),
      );
    }
    widget.trace.log(
      'Todo 편집 Dialog 시작 initialCount=${_items.length} editorStyle=flat_sequence',
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.controller.dispose();
    }
    super.dispose();
  }

  void _add() {
    if (_items.length >= 30) {
      widget.trace.log('Todo 추가 차단 reason=max_count count=${_items.length}');
      HapticFeedback.mediumImpact();
      return;
    }
    setState(() {
      _items.add(
        _RuleTodoDraft(
          id: 'todo_${DateTime.now().microsecondsSinceEpoch}_${_items.length}',
          controller: TextEditingController(),
        ),
      );
    });
    widget.trace.log('Todo 추가 count=${_items.length}');
    HapticFeedback.selectionClick();
  }

  void _remove(int index) {
    final removed = _items.removeAt(index);
    removed.controller.dispose();
    setState(() {});
    widget.trace.log('Todo 삭제 index=$index count=${_items.length}');
    HapticFeedback.mediumImpact();
  }

  void _reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    setState(() {
      final item = _items.removeAt(oldIndex);
      _items.insert(newIndex, item);
    });
    widget.trace.log('Todo 순서 변경 from=$oldIndex to=$newIndex');
    HapticFeedback.selectionClick();
  }

  List<RuleTodoItem> _result() {
    return List<RuleTodoItem>.generate(
      _items.length,
      (index) => RuleTodoItem(
        id: _items[index].id,
        text: _items[index].controller.text.trim(),
        order: index,
      ),
      growable: false,
    );
  }

  void _apply() {
    setState(() => _submitted = true);
    if (!_valid) {
      final invalid = <int>[];
      for (var index = 0; index < _items.length; index += 1) {
        final value = _items[index].controller.text.trim();
        if (value.isEmpty || value.length > 120) invalid.add(index + 1);
      }
      widget.trace.log(
        'Todo 편집 validation 실패 invalid=${invalid.join(',')} count=${_items.length}',
      );
      HapticFeedback.mediumImpact();
      return;
    }
    final result = _result();
    widget.trace.log('Todo 편집 적용 count=${result.length}');
    HapticFeedback.selectionClick();
    Navigator.of(context, rootNavigator: true).pop(result);
  }

  void _cancel() {
    widget.trace.log('Todo 편집 취소 currentCount=${_items.length}');
    Navigator.of(context, rootNavigator: true).pop();
  }

  Future<void> _showDeveloperStatus() async {
    widget.trace.log(
      'Todo 편집 개발자 상태 요청 count=${_items.length} valid=$_valid submitted=$_submitted',
    );
    await widget.trace.showSnapshotStatusDialog(
      context,
      title: 'Todo 편집 상태',
      description: '현재 Todo 편집 상태의 debugPrint 코드를 확인하고 복사할 수 있습니다.',
      failure: _submitted && !_valid,
    );
  }

  Widget _headerAction({
    required String semanticsLabel,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    final tokens = CommonUiTheme.of(context);
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 20, color: tokens.iconSecondary),
      ),
    );
  }

  InputDecoration _flatDecoration() {
    return const InputDecoration(
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      isDense: true,
      contentPadding: EdgeInsets.fromLTRB(0, 10, 0, 4),
      counterText: '',
    );
  }

  Widget _emptyState(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Center(
      key: const ValueKey<String>('todo-empty'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.checklist_rounded, size: 34, color: tokens.iconSecondary),
            const SizedBox(height: 10),
            Text(
              '등록된 Todo가 없습니다',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 5),
            Text(
              '추가를 눌러 출근 전에 확인할 업무 절차를 등록할 수 있습니다.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _todoRow(BuildContext context, int index) {
    final tokens = CommonUiTheme.of(context);
    final item = _items[index];
    final value = item.controller.text.trim();
    final error = _submitted && (value.isEmpty || value.length > 120);
    return Column(
      key: ValueKey<String>(item.id),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 36,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    (index + 1).toString().padLeft(2, '0'),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: error ? tokens.danger : tokens.textSecondary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .7,
                        ),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: item.controller,
                      maxLength: 120,
                      maxLengthEnforcement: MaxLengthEnforcement.enforced,
                      minLines: 1,
                      maxLines: 3,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      onTapOutside: (_) => FocusScope.of(context).unfocus(),
                      onChanged: (_) => setState(() {}),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: tokens.textPrimary,
                            height: 1.45,
                            fontWeight: FontWeight.w600,
                          ),
                      decoration: _flatDecoration(),
                    ),
                    Row(
                      children: [
                        AnimatedSwitcher(
                          duration: _reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 150),
                          child: error
                              ? Text(
                                  value.isEmpty ? '내용을 입력해 주세요.' : '120자 이하로 입력해 주세요.',
                                  key: ValueKey<String>('error-$index-$value'),
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: tokens.danger,
                                        fontWeight: FontWeight.w700,
                                      ),
                                )
                              : const SizedBox.shrink(
                                  key: ValueKey<String>('ok'),
                                ),
                        ),
                        const Spacer(),
                        Text(
                          '${item.controller.text.length}/120',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: tokens.textSecondary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              ReorderableDragStartListener(
                index: index,
                child: Semantics(
                  label: 'Todo ${index + 1} 순서 이동',
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 10, 6, 10),
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      size: 19,
                      color: tokens.iconSecondary,
                    ),
                  ),
                ),
              ),
              Semantics(
                button: true,
                label: 'Todo ${index + 1} 삭제',
                child: IconButton(
                  onPressed: () => _remove(index),
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: tokens.danger,
                  ),
                ),
              ),
            ],
          ),
        ),
        AnimatedContainer(
          duration: _reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 160),
          height: 1,
          color: error ? tokens.danger : tokens.borderSubtle,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final media = MediaQuery.of(context);
    final availableHeight =
        media.size.height - media.padding.vertical - media.viewInsets.bottom - 48;
    final dialogHeight = availableHeight.clamp(0.0, 720.0).toDouble();

    return Dialog(
      backgroundColor: tokens.surfaceRaised,
      surfaceTintColor: tokens.transparent,
      shadowColor: tokens.shadow,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CommonUiShapes.dialog),
        side: BorderSide(color: tokens.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: SizedBox(
          width: 680,
          height: dialogHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.checklist_rounded,
                        size: 22,
                        color: tokens.accent,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Todo 업무 절차',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: tokens.textPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '출근 전에 확인할 업무 절차와 순서를 관리합니다.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: tokens.textSecondary,
                                  height: 1.4,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.trace.developerMode)
                      _headerAction(
                        semanticsLabel: 'Todo 편집 상태 확인',
                        icon: Icons.bug_report_rounded,
                        onPressed: _showDeveloperStatus,
                      ),
                    _headerAction(
                      semanticsLabel: 'Todo 편집 닫기',
                      icon: Icons.close_rounded,
                      onPressed: _cancel,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Divider(height: 1, color: tokens.borderStrong),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      AnimatedSwitcher(
                        duration: _reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 160),
                        child: Text(
                          '${_items.length}/30',
                          key: ValueKey<int>(_items.length),
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: tokens.textSecondary,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                      const Spacer(),
                      CommonButton(
                        label: 'Todo 추가',
                        icon: Icons.add_rounded,
                        onPressed: _items.length >= 30 ? null : _add,
                        variant: CommonButtonVariant.secondary,
                        haptic: CommonHaptic.selection,
                        minHeight: 38,
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: tokens.borderSubtle),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: _reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: _items.isEmpty
                        ? _emptyState(context)
                        : ReorderableListView.builder(
                            key: const ValueKey<String>('todo-list'),
                            physics: const ClampingScrollPhysics(),
                            buildDefaultDragHandles: false,
                            itemCount: _items.length,
                            onReorder: _reorder,
                            itemBuilder: _todoRow,
                          ),
                  ),
                ),
                Divider(height: 1, color: tokens.borderSubtle),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: CommonButton(
                        label: '취소',
                        onPressed: _cancel,
                        variant: CommonButtonVariant.secondary,
                        expand: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: CommonButton(
                        label: '적용',
                        icon: Icons.check_rounded,
                        onPressed: _apply,
                        haptic: CommonHaptic.medium,
                        expand: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RuleTodoDraft {
  const _RuleTodoDraft({
    required this.id,
    required this.controller,
  });

  final String id;
  final TextEditingController controller;
}
