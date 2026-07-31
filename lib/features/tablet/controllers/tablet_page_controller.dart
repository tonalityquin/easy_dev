import 'package:flutter/material.dart';

import '../../../app/init/logout_helper.dart';
import '../../../design_system/common_ui/common_ui_components.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../pages/widgets/tablet_common_components.dart';

class TabletPageController extends StatelessWidget {
  const TabletPageController({super.key});

  @override
  Widget build(BuildContext context) {
    return CommonUiScope(
      child: Builder(
        builder: (context) {
          final tokens = CommonUiTheme.of(context);
          final text = Theme.of(context).textTheme;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TabletCommonPanel(
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
                              BorderRadius.circular(CommonUiShapes.pill),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    CommonAnimatedReveal(
                      child: CommonButton(
                        label: '로그아웃',
                        icon: Icons.logout_rounded,
                        variant: CommonButtonVariant.destructive,
                        expand: true,
                        haptic: CommonHaptic.medium,
                        onPressed: () => _logout(context),
                      ),
                    ),
                    const Spacer(),
                    CommonAnimatedReveal(
                      delay: const Duration(milliseconds: 70),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.surfaceOverlay,
                          borderRadius:
                              BorderRadius.circular(CommonUiShapes.card),
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
      useCommonUi: true,
    );
  }
}
