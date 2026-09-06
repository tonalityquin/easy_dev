import 'package:flutter/material.dart';

import '../../../design_system/common_ui/common_ui_side_dock.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import 'faq_side_dock.dart';

class FaqPage extends StatelessWidget {
  const FaqPage({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Scaffold(
      backgroundColor: tokens.canvas,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: const FaqSideDockContent(
                side: CommonSideDockSide.right,
                source: 'route_fallback',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
