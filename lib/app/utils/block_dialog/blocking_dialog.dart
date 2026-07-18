import 'package:flutter/material.dart';

import '../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../init/app_navigator.dart';

Future<T> runWithBlockingDialog<T>({
  required BuildContext context,
  required Future<T> Function() task,
  String message = '처리 중입니다...',
  bool usePromptUi = false,
}) async {
  if (usePromptUi) {
    final tokens = PromptUiTheme.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: tokens.scrim,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: PromptUiScope(
            child: PromptDialogFrame(
              child: _PromptBlockingContent(message: message),
            ),
          ),
        );
      },
    );
  } else {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.8),
                ),
                const SizedBox(width: 16),
                Flexible(
                  child: Text(
                    message,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  try {
    final result = await task();
    return result;
  } finally {
    final nav = AppNavigator.nav;
    if (nav?.canPop() ?? false) {
      nav!.pop();
    } else if (context.mounted) {
      final rootNavigator = Navigator.of(context, rootNavigator: true);
      if (rootNavigator.canPop()) {
        rootNavigator.pop();
      }
    }
  }
}

class _PromptBlockingContent extends StatelessWidget {
  const _PromptBlockingContent({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final text = Theme.of(context).textTheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: tokens.accentContainer,
              borderRadius: BorderRadius.circular(PromptUiShapes.control),
              border: Border.all(
                color: tokens.accent.withOpacity(
                  tokens.isDark ? 0.58 : 0.36,
                ),
              ),
            ),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: tokens.accent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Flexible(
            child: Text(
              message,
              style: text.bodyLarge?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
