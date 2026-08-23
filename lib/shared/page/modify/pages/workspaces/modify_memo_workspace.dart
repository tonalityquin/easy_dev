import 'package:flutter/material.dart';

import '../../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../../design_system/common_ui/common_ui_theme.dart';

class ModifyMemoWorkspace extends StatefulWidget {
  const ModifyMemoWorkspace({
    super.key,
    required this.controller,
    required this.originalValue,
    required this.committedValue,
    required this.statusResolving,
    required this.statusError,
    required this.onRetry,
    required this.onApplied,
    required this.onPendingChanged,
    required this.onExit,
    this.onDebug,
  });

  final TextEditingController controller;
  final String originalValue;
  final String committedValue;
  final bool statusResolving;
  final String? statusError;
  final Future<void> Function() onRetry;
  final ValueChanged<String> onApplied;
  final ValueChanged<bool> onPendingChanged;
  final VoidCallback onExit;
  final ValueChanged<String>? onDebug;

  @override
  State<ModifyMemoWorkspace> createState() => _ModifyMemoWorkspaceState();
}

class _ModifyMemoWorkspaceState extends State<ModifyMemoWorkspace> {
  bool get _pending => widget.controller.text != widget.committedValue;

  void _debug(String message) {
    widget.onDebug?.call(message);
    debugPrint('[ModifyMemoWorkspace] $message');
  }

  void _changed(String value) {
    widget.onPendingChanged(_pending);
    _debug('memo=draft_changed length=${value.length} pending=$_pending');
    setState(() {});
  }

  void _clear() {
    widget.controller.clear();
    widget.onPendingChanged(_pending);
    _debug('memo=draft_cleared pending=$_pending');
    setState(() {});
  }

  void _apply() {
    final value = widget.controller.text;
    widget.onApplied(value);
    widget.onPendingChanged(false);
    _debug('memo=applied length=${value.trim().length}');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
            child: Row(
              children: [
                CommonIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: '차량 정보로',
                  size: 36,
                  iconSize: 18,
                  onPressed: widget.onExit,
                ),
                const SizedBox(width: 6),
                Icon(Icons.notes_rounded, color: tokens.accent, size: 21),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '상태 메모',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: tokens.textPrimary,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '메모 변경값은 적용 후 최종 수정 완료에서 저장됩니다.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: tokens.textSecondary,
                              height: 1.3,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: tokens.borderSubtle),
          Expanded(
            child: AnimatedSwitcher(
              duration:
                  reduceMotion ? Duration.zero : const Duration(milliseconds: 160),
              child: widget.statusResolving
                  ? Center(
                      key: const ValueKey<String>('resolving'),
                      child: CircularProgressIndicator(color: tokens.accent),
                    )
                  : widget.statusError != null
                      ? Center(
                          key: const ValueKey<String>('error'),
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  color: tokens.warning,
                                  size: 34,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  '상태 정보를 확인하지 못했습니다.',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: tokens.textPrimary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                                const SizedBox(height: 12),
                                CommonButton(
                                  label: '다시 시도',
                                  icon: Icons.refresh_rounded,
                                  onPressed: widget.onRetry,
                                ),
                              ],
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          key: const ValueKey<String>('editor'),
                          physics: const ClampingScrollPhysics(),
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (widget.committedValue.trim().isNotEmpty) ...[
                                Text(
                                  '현재 메모',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(
                                        color: tokens.textSecondary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.all(11),
                                  decoration: BoxDecoration(
                                    color: tokens.surfaceOverlay,
                                    borderRadius: BorderRadius.circular(
                                      CommonUiShapes.control,
                                    ),
                                    border: Border.all(color: tokens.borderSubtle),
                                  ),
                                  child: Text(
                                    widget.committedValue,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: tokens.textPrimary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                              ],
                              Text(
                                '메모',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      color: tokens.textSecondary,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: widget.controller,
                                maxLength: 20,
                                minLines: 4,
                                maxLines: 7,
                                decoration: const InputDecoration(
                                  prefixIcon: Icon(Icons.notes_rounded),
                                ),
                                onChanged: _changed,
                              ),
                              const SizedBox(height: 8),
                              AnimatedSwitcher(
                                duration: reduceMotion
                                    ? Duration.zero
                                    : const Duration(milliseconds: 160),
                                child: _MemoStateBanner(
                                  key: ValueKey<String>(
                                    '${widget.controller.text}|${widget.committedValue}',
                                  ),
                                  originalValue: widget.originalValue,
                                  committedValue: widget.committedValue,
                                  draftValue: widget.controller.text,
                                ),
                              ),
                            ],
                          ),
                        ),
            ),
          ),
          if (!widget.statusResolving && widget.statusError == null)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: BoxDecoration(
                color: tokens.surfaceRaised,
                border: Border(top: BorderSide(color: tokens.borderSubtle)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: CommonButton(
                      label: '비우기',
                      icon: Icons.clear_rounded,
                      variant: CommonButtonVariant.secondary,
                      expand: true,
                      onPressed: _clear,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: CommonButton(
                      label: '적용',
                      icon: Icons.check_rounded,
                      expand: true,
                      onPressed: _pending ? _apply : null,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MemoStateBanner extends StatelessWidget {
  const _MemoStateBanner({
    super.key,
    required this.originalValue,
    required this.committedValue,
    required this.draftValue,
  });

  final String originalValue;
  final String committedValue;
  final String draftValue;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final original = originalValue.trim();
    final draft = draftValue.trim();
    final pending = draftValue != committedValue;
    final deletion = original.isNotEmpty && draft.isEmpty;
    final changedFromOriginal = draft != original;
    final title = deletion
        ? '삭제 예정'
        : pending
            ? '적용 대기'
            : changedFromOriginal
                ? '변경 적용됨'
                : '변경 없음';
    final accent = deletion
        ? tokens.danger
        : pending
            ? tokens.warning
            : changedFromOriginal
                ? tokens.info
                : tokens.iconSecondary;
    final background = deletion
        ? tokens.dangerContainer
        : pending
            ? tokens.warningContainer
            : changedFromOriginal
                ? tokens.infoContainer
                : tokens.surfaceOverlay;
    final foreground = deletion
        ? tokens.onDangerContainer
        : pending
            ? tokens.onWarningContainer
            : changedFromOriginal
                ? tokens.onInfoContainer
                : tokens.textSecondary;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(CommonUiShapes.control),
        border: Border.all(color: accent.withOpacity(.4)),
      ),
      child: Row(
        children: [
          Icon(
            deletion
                ? Icons.delete_sweep_rounded
                : pending
                    ? Icons.pending_actions_rounded
                    : changedFromOriginal
                        ? Icons.check_circle_outline_rounded
                        : Icons.notes_rounded,
            color: accent,
            size: 19,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
