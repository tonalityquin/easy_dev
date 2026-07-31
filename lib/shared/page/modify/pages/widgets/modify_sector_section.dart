import 'package:flutter/material.dart';

import '../../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../../design_system/common_ui/common_ui_theme.dart';
import '../common_modify_ui.dart';

class ModifySectorSection extends StatelessWidget {
  const ModifySectorSection({
    super.key,
    required this.sectorName,
    required this.isBusy,
    required this.onPressed,
  });

  final String? sectorName;
  final bool isBusy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final displayName = sectorName?.trim().isNotEmpty == true
        ? sectorName!.trim()
        : '선택되지 않음';
    final selected = sectorName?.trim().isNotEmpty == true;

    return CommonAnimatedReveal(
      child: CommonModifySectionCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const CommonModifySectionTitle(
              icon: Icons.location_city_rounded,
              title: '방문 구역',
              subtitle: '현재 차량의 방문 구역을 확인하고 변경합니다.',
            ),
            const SizedBox(height: 12),
            Material(
              color: tokens.transparent,
              borderRadius: BorderRadius.circular(CommonUiShapes.control),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: isBusy ? null : onPressed,
                child: AnimatedContainer(
                  duration:
                      reduceMotion ? Duration.zero : CommonUiMotion.selection,
                  curve: CommonUiMotion.standard,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? tokens.surfaceSelected
                        : tokens.surfaceOverlay,
                    borderRadius:
                        BorderRadius.circular(CommonUiShapes.control),
                    border: Border.all(
                      color: selected ? tokens.accent : tokens.borderSubtle,
                      width: selected ? 1.5 : 1,
                    ),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: tokens.accent.withOpacity(
                                tokens.isDark ? .18 : .1,
                              ),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : const [],
                  ),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: reduceMotion
                            ? Duration.zero
                            : CommonUiMotion.selection,
                        curve: CommonUiMotion.standard,
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: selected
                              ? tokens.accentContainer
                              : tokens.surfaceRaised,
                          borderRadius:
                              BorderRadius.circular(CommonUiShapes.control),
                          border: Border.all(
                            color: selected
                                ? tokens.accent.withOpacity(
                                    tokens.isDark ? .54 : .36,
                                  )
                                : tokens.borderSubtle,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: AnimatedSwitcher(
                          duration: reduceMotion
                              ? Duration.zero
                              : CommonUiMotion.selection,
                          child: isBusy
                              ? SizedBox(
                                  key: const ValueKey('sector_busy'),
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: tokens.accent,
                                  ),
                                )
                              : Icon(
                                  selected
                                      ? Icons.check_circle_rounded
                                      : Icons.location_city_outlined,
                                  key: ValueKey<bool>(selected),
                                  color: selected
                                      ? tokens.onAccentContainer
                                      : tokens.iconSecondary,
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '현재 방문 구역',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    color: tokens.textSecondary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 3),
                            AnimatedSwitcher(
                              duration: reduceMotion
                                  ? Duration.zero
                                  : CommonUiMotion.selection,
                              switchInCurve: CommonUiMotion.enter,
                              switchOutCurve: CommonUiMotion.exit,
                              transitionBuilder: (child, animation) {
                                final offset = Tween<Offset>(
                                  begin: const Offset(0, .12),
                                  end: Offset.zero,
                                ).animate(animation);
                                return FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: offset,
                                    child: child,
                                  ),
                                );
                              },
                              child: Text(
                                displayName,
                                key: ValueKey<String>(displayName),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(
                                      color: tokens.textPrimary,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      AnimatedRotation(
                        turns: isBusy ? .5 : 0,
                        duration: reduceMotion
                            ? Duration.zero
                            : CommonUiMotion.selection,
                        curve: CommonUiMotion.standard,
                        child: Icon(
                          isBusy
                              ? Icons.sync_rounded
                              : Icons.chevron_right_rounded,
                          color: tokens.iconSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
