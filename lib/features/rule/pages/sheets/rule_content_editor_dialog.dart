import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';

class RuleContentEditorDialog extends StatelessWidget {
  const RuleContentEditorDialog({
    super.key,
    required this.initialContent,
    required this.trace,
  });

  final String initialContent;
  final DeveloperOperationTrace trace;

  @override
  Widget build(BuildContext context) {
    return _RuleLongTextEditorDialog(
      title: '업무 안내문',
      description: '업무 중 반복해서 확인할 운영 안내 내용을 관리합니다.',
      initialValue: initialContent,
      maxLength: 4000,
      icon: Icons.article_rounded,
      trace: trace,
    );
  }
}

class _RuleLongTextEditorDialog extends StatefulWidget {
  const _RuleLongTextEditorDialog({
    required this.title,
    required this.description,
    required this.initialValue,
    required this.maxLength,
    required this.icon,
    required this.trace,
  });

  final String title;
  final String description;
  final String initialValue;
  final int maxLength;
  final IconData icon;
  final DeveloperOperationTrace trace;

  @override
  State<_RuleLongTextEditorDialog> createState() =>
      _RuleLongTextEditorDialogState();
}

class _RuleLongTextEditorDialogState
    extends State<_RuleLongTextEditorDialog> {
  late final TextEditingController _controller;
  bool _submitted = false;
  bool _reduceMotion = false;

  String get _error {
    final value = _controller.text.trim();
    if (value.length > widget.maxLength) {
      return '${widget.title}은 ${widget.maxLength}자 이하로 입력해 주세요.';
    }
    return '';
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    widget.trace.log(
      '${widget.title} 편집 Dialog 시작 initialLength=${widget.initialValue.length} editorStyle=flat_document',
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
      widget.trace.log('${widget.title} 편집 validation 실패 reason=$error');
      HapticFeedback.mediumImpact();
      return;
    }
    final value = _controller.text.trim();
    widget.trace.log(
      '${widget.title} 편집 적용 length=${value.length} empty=${value.isEmpty}',
    );
    HapticFeedback.selectionClick();
    Navigator.of(context, rootNavigator: true).pop(value);
  }

  void _cancel() {
    widget.trace.log(
      '${widget.title} 편집 취소 currentLength=${_controller.text.trim().length}',
    );
    Navigator.of(context, rootNavigator: true).pop();
  }

  Future<void> _showDeveloperStatus() async {
    widget.trace.log(
      '${widget.title} 편집 개발자 상태 요청 length=${_controller.text.trim().length} submitted=$_submitted',
    );
    await widget.trace.showSnapshotStatusDialog(
      context,
      title: '${widget.title} 편집 상태',
      description: '현재 편집 상태의 debugPrint 코드를 확인하고 복사할 수 있습니다.',
      failure: _submitted && _error.isNotEmpty,
    );
  }

  Widget _headerAction({
    required String semanticsLabel,
    required IconData icon,
    required VoidCallback? onPressed,
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
      contentPadding: EdgeInsets.fromLTRB(0, 14, 0, 14),
      counterText: '',
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final media = MediaQuery.of(context);
    final availableHeight =
        media.size.height - media.padding.vertical - media.viewInsets.bottom - 48;
    final dialogHeight = availableHeight.clamp(0.0, 680.0).toDouble();
    final error = _submitted ? _error : '';

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
        constraints: const BoxConstraints(maxWidth: 640),
        child: SizedBox(
          width: 640,
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
                      child: Icon(widget.icon, size: 22, color: tokens.accent),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
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
                            widget.description,
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
                        semanticsLabel: '${widget.title} 편집 상태 확인',
                        icon: Icons.bug_report_rounded,
                        onPressed: _showDeveloperStatus,
                      ),
                    _headerAction(
                      semanticsLabel: '${widget.title} 편집 닫기',
                      icon: Icons.close_rounded,
                      onPressed: _cancel,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Divider(height: 1, color: tokens.borderStrong),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    expands: true,
                    maxLines: null,
                    minLines: null,
                    maxLength: widget.maxLength,
                    maxLengthEnforcement: MaxLengthEnforcement.enforced,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    textAlignVertical: TextAlignVertical.top,
                    onTapOutside: (_) => FocusScope.of(context).unfocus(),
                    onChanged: (_) => setState(() {}),
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: tokens.textPrimary,
                          height: 1.58,
                          fontWeight: FontWeight.w500,
                        ),
                    decoration: _flatDecoration(),
                  ),
                ),
                Divider(height: 1, color: tokens.borderSubtle),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      _controller.text.trim().isEmpty ? '미사용' : '입력 중',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: _controller.text.trim().isEmpty
                                ? tokens.textSecondary
                                : tokens.success,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const Spacer(),
                    Text(
                      '${_controller.text.length}/${widget.maxLength}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: tokens.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: _reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 170),
                  curve: Curves.easeOutCubic,
                  child: error.isEmpty
                      ? const SizedBox(height: 10)
                      : Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 2),
                          child: Text(
                            error,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: tokens.danger,
                                      fontWeight: FontWeight.w700,
                                    ),
                          ),
                        ),
                ),
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
