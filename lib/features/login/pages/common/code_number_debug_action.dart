import 'package:flutter/material.dart';

import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../features/selector/application/dev_auth.dart';
import '../../../../shared/auth/account_code_diagnostics.dart';

class CodeNumberDebugAction extends StatelessWidget {
  const CodeNumberDebugAction({
    super.key,
    required this.scope,
    required this.title,
  });

  final String scope;
  final String title;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return ValueListenableBuilder<bool>(
      valueListenable: DevAuth.devModeEnabled,
      builder: (context, enabled, _) {
        return AnimatedSwitcher(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            );
          },
          child: enabled
              ? CommonIconButton(
                  key: const ValueKey<String>('code-number-debug-on'),
                  icon: Icons.bug_report_rounded,
                  tooltip: '코드번호 로그인 로그',
                  onPressed: () => AccountCodeDiagnostics.showStatusDialog(
                    context,
                    scope: scope,
                    title: title,
                  ),
                  haptic: CommonHaptic.selection,
                  size: 40,
                  iconSize: 20,
                )
              : const SizedBox.shrink(
                  key: ValueKey<String>('code-number-debug-off'),
                ),
        );
      },
    );
  }
}
