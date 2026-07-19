import 'package:flutter/material.dart';

import '../../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_theme.dart';

class ModifyStatusCustomSection extends StatelessWidget {
  const ModifyStatusCustomSection({
    super.key,
    required this.customStatus,
    required this.onDelete,
  });

  final String customStatus;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    return PromptAnimatedReveal(
      delay: const Duration(milliseconds: 80),
      offset: const Offset(0, .025),
      child: Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tokens.warningContainer,
          borderRadius: BorderRadius.circular(PromptUiShapes.control),
          border: Border.all(
            color: tokens.warning.withOpacity(tokens.isDark ? .58 : .36),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline_rounded,
              color: tokens.warning,
              size: 21,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '자동 불러온 상태 메모',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: tokens.onWarningContainer,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    customStatus,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: tokens.onWarningContainer,
                          height: 1.4,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            PromptIconButton(
              icon: Icons.clear_rounded,
              tooltip: '자동 메모 지우기',
              destructive: true,
              haptic: PromptHaptic.selection,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
