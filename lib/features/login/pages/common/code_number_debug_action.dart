import 'package:flutter/material.dart';

import '../../../../features/selector/application/dev_auth.dart';
import '../../../../shared/auth/account_code_diagnostics.dart';
import '../../debug/login_debug_trace.dart';

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
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final colorScheme = Theme.of(context).colorScheme;
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
              ? Semantics(
                  key: ValueKey<String>('login-debug-$scope-on'),
                  button: true,
                  label: title,
                  child: Material(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => LoginDebugTrace.showStatusDialog(
                        context,
                        scope: scope,
                        title: title,
                        additionalDebugPrintCode:
                            AccountCodeDiagnostics.debugPrintCode(
                          scope: scope,
                        ),
                      ),
                      child: const SizedBox(
                        width: 40,
                        height: 40,
                        child: Center(
                          child: Icon(
                            Icons.bug_report_rounded,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              : SizedBox.shrink(
                  key: ValueKey<String>('login-debug-$scope-off'),
                ),
        );
      },
    );
  }
}
