import 'package:flutter/material.dart';

import '../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../design_system/prompt_ui/prompt_ui_theme.dart';

class PlateRemoveDialog extends StatelessWidget {
  const PlateRemoveDialog({
    super.key,
    required this.onConfirm,
  });

  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

    return PromptDialogFrame(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: tokens.dangerContainer,
                    borderRadius:
                        BorderRadius.circular(PromptUiShapes.control),
                    border: Border.all(
                      color: tokens.danger.withOpacity(
                        tokens.isDark ? 0.58 : 0.36,
                      ),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.delete_outline_rounded,
                    color: tokens.danger,
                    size: 25,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '삭제 확인',
                    style: textTheme.titleMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: tokens.surfaceOverlay,
                borderRadius: BorderRadius.circular(PromptUiShapes.control),
                border: Border.all(color: tokens.borderSubtle),
              ),
              child: Text(
                '정말로 삭제하시겠습니까?',
                style: textTheme.bodyMedium?.copyWith(
                  color: tokens.textSecondary,
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: PromptButton(
                    label: '취소',
                    onPressed: () => Navigator.of(context).pop(false),
                    variant: PromptButtonVariant.tertiary,
                    expand: true,
                    haptic: PromptHaptic.selection,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PromptButton(
                    label: '삭제',
                    icon: Icons.delete_outline_rounded,
                    onPressed: onConfirm,
                    variant: PromptButtonVariant.destructive,
                    expand: true,
                    haptic: PromptHaptic.medium,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
