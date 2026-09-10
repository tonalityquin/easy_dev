import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../shared/secondary/widgets/ops_console_widgets.dart';

class RuleContentEditorDialog extends StatefulWidget {
  const RuleContentEditorDialog({
    super.key,
    required this.initialContent,
    required this.trace,
  });

  final String initialContent;
  final DeveloperOperationTrace trace;

  @override
  State<RuleContentEditorDialog> createState() =>
      _RuleContentEditorDialogState();
}

class _RuleContentEditorDialogState extends State<RuleContentEditorDialog> {
  late final TextEditingController _controller;
  bool _submitted = false;
  bool _reduceMotion = false;

  String get _error {
    final value = _controller.text.trim();
    if (value.isEmpty) return '업무 안내문을 입력해 주세요.';
    if (value.length > 4000) return '업무 안내문은 4000자 이하로 입력해 주세요.';
    return '';
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
    widget.trace.log(
      '업무 안내문 편집 Dialog 시작 initialLength=${widget.initialContent.length}',
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
      widget.trace.log('업무 안내문 편집 validation 실패 reason=$error');
      HapticFeedback.mediumImpact();
      return;
    }
    final value = _controller.text.trim();
    widget.trace.log('업무 안내문 편집 적용 length=${value.length}');
    Navigator.of(context, rootNavigator: true).pop(value);
  }

  void _cancel() {
    widget.trace.log('업무 안내문 편집 취소');
    Navigator.of(context, rootNavigator: true).pop();
  }

  Future<void> _showDeveloperStatus() async {
    widget.trace.log('업무 안내문 편집 개발자 상태 요청');
    await widget.trace.showSnapshotStatusDialog(
      context,
      title: '업무 안내문 편집 로그',
      description: '현재 업무 안내문 편집 동작의 debugPrint 코드를 확인하고 복사할 수 있습니다.',
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
                      '업무 안내문',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  if (widget.trace.developerMode)
                    _headerAction(
                      semanticsLabel: '업무 안내문 편집 상태 확인',
                      icon: Icons.bug_report_rounded,
                      onPressed: _showDeveloperStatus,
                    ),
                  _headerAction(
                    semanticsLabel: '업무 안내문 편집 닫기',
                    icon: Icons.close_rounded,
                    onPressed: _cancel,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: AnimatedSwitcher(
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
                    expands: true,
                    maxLines: null,
                    minLines: null,
                    maxLength: 4000,
                    keyboardType: TextInputType.multiline,
                    textAlignVertical: TextAlignVertical.top,
                    onChanged: (_) => setState(() {}),
                    decoration: opsInputDecoration(
                      context,
                      label: '업무 안내문',
                      prefixIcon: const Icon(Icons.article_rounded),
                      errorText: _submitted && _error.isNotEmpty ? _error : null,
                    ).copyWith(counterText: '${_controller.text.length}/4000'),
                  ),
                ),
              ),
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
    );
  }
}
