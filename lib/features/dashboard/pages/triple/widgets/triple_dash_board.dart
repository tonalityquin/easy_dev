import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../app/init/db_connection_status_section.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../../../../shared/page/widget/navigation/triple_top_navigation.dart';
import '../../../sheets/triple/triple_hq_dash_board_page.dart';

class TripleDashBoard extends StatelessWidget {
  const TripleDashBoard({super.key});

  static const String _screenTagAsset = 'assets/images/pelican_text.png';
  static const Size _screenTagSize = Size(104, 38);

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final overlayStyle = tokens.isDark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle.copyWith(
        statusBarColor: tokens.surface,
        systemNavigationBarColor: tokens.canvas,
        systemNavigationBarDividerColor: tokens.borderSubtle,
      ),
      child: PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: tokens.canvas,
          appBar: AppBar(
            title: const TripleTopNavigation(usePromptUi: true),
            centerTitle: true,
            backgroundColor: tokens.surface,
            foregroundColor: tokens.textPrimary,
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: tokens.transparent,
            shape: Border(
              bottom: BorderSide(color: tokens.borderSubtle),
            ),
            flexibleSpace: SafeArea(
              child: Stack(
                children: [
                  IgnorePointer(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12, top: 5),
                        child: PromptAnimatedReveal(
                          offset: const Offset(-0.04, 0),
                          child: SizedBox(
                            width: _screenTagSize.width,
                            height: _screenTagSize.height,
                            child: Image.asset(
                              _screenTagAsset,
                              fit: BoxFit.contain,
                              alignment: Alignment.centerLeft,
                              color: tokens.textSecondary,
                              colorBlendMode: BlendMode.srcIn,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  IgnorePointer(
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: EdgeInsets.only(right: 12, top: 8, bottom: 8),
                        child: SizedBox(
                          height: kToolbarHeight - 8,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: 132),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: DbConnectionStatusAppBarSection(
                                liveLabel: 'live DB',
                                storageLabel: '스토리지 DB',
                                spacing: 4,
                                usePromptUi: true,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          body: const TripleHqDashBoardPage(),
        ),
      ),
    );
  }
}
