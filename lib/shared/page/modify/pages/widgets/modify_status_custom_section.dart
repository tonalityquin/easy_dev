import 'package:flutter/material.dart';

import '../../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_theme.dart';

class ModifyStatusCustomSection extends StatelessWidget {
  const ModifyStatusCustomSection({
    super.key,
    required this.originalCustomStatus,
    required this.changed,
    required this.deletionPending,
    required this.onClear,
  });

  final String originalCustomStatus;
  final bool changed;
  final bool deletionPending;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 220);
    final hasOriginalMemo = originalCustomStatus.trim().isNotEmpty;

    if (!hasOriginalMemo && !changed) {
      return const SizedBox.shrink();
    }

    final background = deletionPending
        ? tokens.dangerContainer
        : changed
            ? tokens.warningContainer
            : tokens.infoContainer;
    final foreground = deletionPending
        ? tokens.onDangerContainer
        : changed
            ? tokens.onWarningContainer
            : tokens.onInfoContainer;
    final accent = deletionPending
        ? tokens.danger
        : changed
            ? tokens.warning
            : tokens.info;

    return AnimatedContainer(
      duration: duration,
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(PromptUiShapes.control),
        border: Border.all(color: accent.withOpacity(.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedSwitcher(
            duration: duration,
            child: Icon(
              deletionPending
                  ? Icons.delete_sweep_rounded
                  : changed
                      ? Icons.edit_note_rounded
                      : Icons.history_rounded,
              key: ValueKey<String>(
                deletionPending ? 'delete' : changed ? 'changed' : 'original',
              ),
              color: accent,
              size: 21,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  deletionPending
                      ? '상태 메모 삭제 예정'
                      : changed
                          ? '상태 메모 수정됨'
                          : '기존 상태 메모',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 5),
                Text(
                  deletionPending
                      ? '수정 완료를 누르면 차량 문서와 상태 문서에서 함께 반영됩니다.'
                      : hasOriginalMemo
                          ? originalCustomStatus.trim()
                          : '기존 상태 메모 없음',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: foreground,
                        height: 1.4,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          PromptIconButton(
            icon: Icons.clear_rounded,
            tooltip: '상태 메모 비우기',
            destructive: true,
            haptic: PromptHaptic.selection,
            onPressed: onClear,
          ),
        ],
      ),
    );
  }
}
