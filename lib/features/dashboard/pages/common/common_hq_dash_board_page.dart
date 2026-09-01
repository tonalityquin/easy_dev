import 'package:flutter/material.dart';

import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../calendar/presentation/headquarter_calendar_card.dart';
import '../../../headquarter/application/headquarter_dashboard_context.dart';

class CommonHqDashBoardPage extends StatelessWidget {
  const CommonHqDashBoardPage({
    super.key,
    required this.screenName,
    required this.modeKey,
  });

  final String screenName;
  final String modeKey;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final normalizedMode = HeadquarterDashboardContext.normalizeModeKey(modeKey);
    final effectiveMode = normalizedMode.isEmpty
        ? HeadquarterDashboardContext.modeKeyFromScreen(screenName)
        : normalizedMode;

    debugPrint(
      '[HQ_DASHBOARD][${DateTime.now().toIso8601String()}] screen=$screenName mode=$effectiveMode layout=fixed calendar=direct verticalScroll=false modeTrigger=removed contextPublisher=${effectiveMode.isEmpty ? 'none' : 'scope'} additionalFirebaseRead=0 additionalFirebaseWrite=0',
    );

    final content = ColoredBox(
      color: tokens.canvas,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: SizedBox.expand(
            child: CommonAnimatedReveal(
              child: HeadquarterCalendarCard(
                useCommonUi: true,
                showAccountEntry: true,
                fillViewport: true,
              ),
            ),
          ),
        ),
      ),
    );
    if (effectiveMode.isEmpty) return content;
    return HeadquarterDashboardContextScope(
      modeKey: effectiveMode,
      source: 'common_hq_dashboard:$screenName',
      child: content,
    );
  }
}
