import 'package:flutter/material.dart';

import '../../design_system/common_ui/common_ui_components.dart';
import '../../design_system/common_ui/common_ui_theme.dart';
import 'app_exit_service.dart';

class LogoutCompletionExitDialog {
  LogoutCompletionExitDialog._();

  static Future<void> show(
    BuildContext context, {
    bool useCommonUi = true,
    Future<void> Function()? onExit,
  }) async {
    if (!context.mounted) return;
    debugPrint('[LOGOUT-EXIT] logoutCompleteDialogShown=true');
    await showCommonDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: _LogoutCompletionExitBody(
            useCommonUi: useCommonUi,
            onExit: onExit,
          ),
        );
      },
    );
  }
}

class _LogoutCompletionExitBody extends StatelessWidget {
  const _LogoutCompletionExitBody({
    required this.useCommonUi,
    required this.onExit,
  });

  final bool useCommonUi;
  final Future<void> Function()? onExit;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: tokens.dangerContainer,
                shape: BoxShape.circle,
                border: Border.all(
                  color: tokens.danger.withOpacity(
                    tokens.isDark ? 0.56 : 0.36,
                  ),
                ),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.power_settings_new_rounded,
                size: 26,
                color: tokens.danger,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '앱을 종료합니다.',
              textAlign: TextAlign.center,
              style: text.titleMedium?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 22),
            CommonButton(
              label: '앱 종료',
              icon: Icons.power_settings_new_rounded,
              variant: CommonButtonVariant.destructive,
              haptic: CommonHaptic.medium,
              expand: true,
              semanticsLabel: '앱 종료',
              onPressed: () async {
                debugPrint('[LOGOUT-EXIT] exitButtonPressed=true');
                final exitAction = onExit;
                if (exitAction != null) {
                  await exitAction();
                  return;
                }
                await AppExitService.exitApp(
                  context,
                  useCommonUi: useCommonUi,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
