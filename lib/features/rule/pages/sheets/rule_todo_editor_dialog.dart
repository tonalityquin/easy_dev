import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../shared/secondary/widgets/ops_console_widgets.dart';

class RuleTodoEditorResult {
  const RuleTodoEditorResult.apply(this.text) : delete = false;
  const RuleTodoEditorResult.delete()
      : text = '',
        delete = true;

  final String text;
  final bool delete;
}

class RuleTodoEditorDialog extends StatefulWidget {
  const RuleTodoEditorDialog({
    super.key,
    required this.initialText,
    required this.canDelete,
    required this.trace,
  });

  final String initialText;
  final bool canDelete;
  final DeveloperOperationTrace trace;

  @override
  State<RuleTodoEditorDialog> createState() => _RuleTodoEditorDialogState();
}

class _RuleTodoEditorDialogState extends State<RuleTodoEditorDialog> {
  late final TextEditingController _controller;
  bool _submitted = false;
  bool _reduceMotion = false;

  String get _error {
    final value = _controller.text.trim();
    if (value.isEmpty) return 'Todo 내용을 입력해 주세요.';
    if (value.length > 120) return 'Todo 내용은 120자 이하로 입력해 주세요.';
    return '';
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    widget.trace.log(
      'Todo 편집 Dialog 시작 mode=${widget.canDelete ? 'edit' : 'create'} initialLength=${widget.initialText.length}',
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _apply() {
    setState(() => _submitted = true);
    final error = _error;
    if (error.isNotEmpty) {
      widget.trace.log('Todo 편집 validation 실패 reason=$error');
      HapticFeedback.mediumImpact();
      return;
    }
    final value = _controller.text.trim();
    widget.trace.log('Todo 편집 적용 length=${value.length}');
    Navigator.of(context, rootNavigator: true).pop(
      RuleTodoEditorResult.apply(value),
    );
  }

  void _delete() {
    if (!widget.canDelete) return;
    widget.trace.log('Todo 편집 삭제 요청');
    HapticFeedback.mediumImpact();
    Navigator.of(context, rootNavigator: true).pop(
      const RuleTodoEditorResult.delete(),
    );
  }

  void _cancel() {
    widget.trace.log('Todo 편집 취소');
    Navigator.of(context, rootNavigator: true).pop();
  }

  Future<void> _showDeveloperStatus() async {
    widget.trace.log('Todo 편집 개발자 상태 요청');
    await widget.trace.showSnapshotStatusDialog(
      context,
      title: 'Todo 편집 로그',
      description: '현재 Todo 편집 동작의 debugPrint 코드를 확인하고 복사할 수 있습니다.',
      failure: _submitted && _error.isNotEmpty,
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

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Material(
      color: tokens.surfaceRaised,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.canDelete ? 'Todo 수정' : 'Todo 추가',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
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
              AnimatedSwitcher(
                duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
                switchInCurve: CommonUiMotion.enter,
                switchOutCurve: CommonUiMotion.exit,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(.02, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: TextField(
                  key: ValueKey<bool>(_submitted),
                  controller: _controller,
                  autofocus: true,
                  maxLength: 120,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _apply(),
                  decoration: opsInputDecoration(
                    context,
                    label: 'Todo 내용',
                    prefixIcon: const Icon(Icons.checklist_rounded),
                    errorText: _submitted && _error.isNotEmpty ? _error : null,
                  ).copyWith(counterText: '${_controller.text.length}/120'),
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  if (widget.canDelete) ...[
                    Expanded(
                      child: CommonButton(
                        label: '삭제',
                        icon: Icons.delete_outline_rounded,
                        onPressed: _delete,
                        variant: CommonButtonVariant.destructive,
                        haptic: CommonHaptic.medium,
                        expand: true,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: CommonButton(
                      label: '취소',
                      onPressed: _cancel,
                      variant: CommonButtonVariant.secondary,
                      expand: true,
                    ),
                  ),
                  const SizedBox(width: 8),
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
    );
  }
}
