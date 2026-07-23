import 'package:flutter/material.dart';

import '../../../app/init/logout_helper.dart';
import '../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../pages/widgets/tablet_prompt_components.dart';

class TabletPageController extends StatelessWidget {
  const TabletPageController({super.key});

  @override
  Widget build(BuildContext context) {
    return PromptUiScope(
      child: Builder(
        builder: (context) {
          final tokens = PromptUiTheme.of(context);
          final text = Theme.of(context).textTheme;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TabletPromptPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: tokens.handle,
                          borderRadius:
                              BorderRadius.circular(PromptUiShapes.pill),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    PromptAnimatedReveal(
                      child: PromptButton(
                        label: '로그아웃',
                        icon: Icons.logout_rounded,
                        variant: PromptButtonVariant.destructive,
                        expand: true,
                        haptic: PromptHaptic.medium,
                        onPressed: () => _logout(context),
                      ),
                    ),
                    const Spacer(),
                    PromptAnimatedReveal(
                      delay: const Duration(milliseconds: 70),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.surfaceOverlay,
                          borderRadius:
                              BorderRadius.circular(PromptUiShapes.card),
                          border: Border.all(color: tokens.borderSubtle),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Icon(
                              Icons.dashboard_customize_outlined,
                              size: 18,
                              color: tokens.iconSecondary,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                '왼쪽 영역(추가 컨텐츠 배치 가능)',
                                textAlign: TextAlign.center,
                                style: text.bodyMedium?.copyWith(
                                  color: tokens.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    await LogoutHelper.logoutAndGoToLogin(
      context,
      checkWorking: true,
      delay: const Duration(seconds: 1),
      usePromptUi: true,
    );
  }
}
