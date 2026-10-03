import 'package:flutter/material.dart';

import '../../../../design_system/common_ui/common_ui_theme.dart';

class WorkManualPageCard extends StatelessWidget {
  const WorkManualPageCard({
    super.key,
    required this.text,
    required this.pageNumber,
    required this.totalPages,
    required this.compact,
  });

  final String text;
  final int pageNumber;
  final int totalPages;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final theme = Theme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final bodyStyle = (compact
            ? theme.textTheme.bodyMedium
            : theme.textTheme.bodyLarge)
        ?.copyWith(
      color: tokens.textPrimary,
      fontWeight: FontWeight.w500,
      height: 1.62,
    );

    return AnimatedContainer(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
      curve: CommonUiMotion.standard,
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(compact ? 18 : 24),
        border: Border.all(color: tokens.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: tokens.shadow,
            blurRadius: compact ? 14 : 22,
            offset: Offset(0, compact ? 6 : 10),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 14 : 20,
          compact ? 12 : 16,
          compact ? 14 : 20,
          compact ? 14 : 18,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: AnimatedSwitcher(
                duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
                switchInCurve: CommonUiMotion.enter,
                switchOutCurve: CommonUiMotion.exit,
                transitionBuilder: (child, animation) {
                  if (reduceMotion) return child;
                  final curved = CurvedAnimation(
                    parent: animation,
                    curve: CommonUiMotion.enter,
                    reverseCurve: CommonUiMotion.exit,
                  );
                  return FadeTransition(
                    opacity: curved,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: .96, end: 1).animate(curved),
                      child: child,
                    ),
                  );
                },
                child: Container(
                  key: ValueKey<String>('$pageNumber/$totalPages'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.accentContainer,
                    borderRadius: BorderRadius.circular(CommonUiShapes.pill),
                    border: Border.all(
                      color: tokens.accent.withOpacity(tokens.isDark ? .62 : .42),
                    ),
                  ),
                  child: Text(
                    '${pageNumber.toString().padLeft(2, '0')} / ${totalPages.toString().padLeft(2, '0')}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: tokens.onAccentContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: compact ? 12 : 16),
            Expanded(
              child: SingleChildScrollView(
                key: PageStorageKey<String>('work_manual_page_scroll_$pageNumber'),
                physics: const ClampingScrollPhysics(),
                child: SelectableText(
                  text,
                  textAlign: TextAlign.start,
                  style: bodyStyle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
